const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // This creates a "module", which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Every executable or library we compile will be based on one or more modules.
    const lib_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Now, we will create a static library based on the module we created above.
    // This creates a `std.Build.Step.Compile`, which is the build step responsible
    // for actually invoking the compiler.
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "jsonata_zig",
        .root_module = lib_mod,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const gen_tests = b.addExecutable(.{
        .name = "generate_tests",
        .root_source_file = b.path("tools/generate_tests.zig"),
        .target = b.graph.host,
    });

    const gen_tests_step = b.addRunArtifact(gen_tests);
    const output = gen_tests_step.addOutputFileArg("test_suite.zig");
    lib_mod.addAnonymousImport("test_suite", .{ .root_source_file = output });
    add_tests_files(b, lib_mod) catch |err| {
        std.debug.panic("could not add test suite files to lib module: {any}", .{err});
    };

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}

fn add_tests_files(b: *std.Build, module: *std.Build.Module) !void {
    // get datasets
    const dataset_root = "test-suite/datasets";
    var test_suite_dir = try std.fs.cwd().openDir(dataset_root, .{});
    defer test_suite_dir.close();
    var iter = test_suite_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        var buf = [_]u8{0} ** 100;
        const path = try std.fmt.bufPrint(&buf, "{s}/{s}", .{ dataset_root, entry.name });
        const name = std.fs.path.stem(entry.name);
        module.addAnonymousImport(name, .{ .root_source_file = b.path(path) });
    }

    // get groups
    const group_root = "test-suite/groups";
    var group_dir = try std.fs.cwd().openDir(group_root, .{});
    defer group_dir.close();
    var g_iter = group_dir.iterate();
    while (try g_iter.next()) |dir_info| {
        if (dir_info.kind != .directory) continue;
        var test_dir = try group_dir.openDir(dir_info.name, .{});
        defer test_dir.close();
        var t_iter = test_dir.iterate();
        while (try t_iter.next()) |file_info| {
            if (file_info.kind != .file) continue;
            var name_buf = [_]u8{0} ** 100;
            const complete_test_name = try std.fmt.bufPrint(&name_buf, "{s}/{s}", .{ dir_info.name, std.fs.path.stem(file_info.name) });
            var path_buf = [_]u8{0} ** 100;
            const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}/{s}", .{ group_root, dir_info.name, file_info.name });
            module.addAnonymousImport(complete_test_name, .{ .root_source_file = b.path(path) });
        }
    }
}
