const std = @import("std");

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);

    if (args.len != 2) fatal("wrong number of arguments", .{});

    const output_file_path = args[1];

    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        fatal("unable to open '{s}': {s}", .{ output_file_path, @errorName(err) });
    };
    defer output_file.close();

    try output_file.writeAll(
        \\const std = @import("std");
        \\const testing = std.testing;
        \\
        \\test "failing to add" {
        \\  try testing.expect(3 + 8 == 11);
        \\}
    );
    return std.process.cleanExit();
}

const formatter = std.fs.path.fmtJoin(&[_][]const u8{ "test-suite", "datasets" });
fn get_datasets(alloc: std.mem.Allocator) std.StringArrayHashMap(std.json.Value) {
    var dataset_path = std.ArrayList(u8).init(alloc);
    defer dataset_path.deinit();
    dataset_path.writer().print("{s}", .{formatter}) catch |err| {
        fatal("unable to create path: {s}", .{@errorName(err)});
    };
    var test_suite_dir = std.fs.cwd().openDir(dataset_path.items, .{}) catch |err| {
        fatal("unable to open '{s}': {s}", .{ dataset_path.items, @errorName(err) });
    };
    defer test_suite_dir.close();
    var iter = test_suite_dir.iterate();
    var string_hash_map = std.StringArrayHashMap(std.json.Value).init(alloc);
    while (iter.next()) |maybe_entry| {
        const entry = maybe_entry orelse break;
        if (entry.kind == .file) {
            var file = test_suite_dir.openFile(entry.name, .{}) catch |err| {
                fatal("unable to open '{s}': {s}", .{ dataset_path.items, @errorName(err) });
            };
            defer file.close();
            const file_content = file.readToEndAlloc(alloc, 1024 * 1024) catch |err| {
                fatal("unable to read '{s}': {s}", .{ entry.name, @errorName(err) });
            };
            defer alloc.free(file_content);
            const parsed = std.json.parseFromSliceLeaky(std.json.Value, alloc, file_content, .{}) catch |err| {
                fatal("unable to parse '{s}': {s}", .{ entry.name, @errorName(err) });
            };
            const dataset_name = alloc.alloc(u8, entry.name.len-5) catch |err | {
                fatal("error allocating: {any}", .{err});
            };
            @memcpy(dataset_name, entry.name[0..entry.name.len-5]);
            string_hash_map.put(dataset_name, parsed) catch |err| {
                fatal("unable to alloc: {any}", .{err});
            };
        }
    } else |err| {
        fatal("error iterating: {s}", .{@errorName(err)});
    }
    return string_hash_map;
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}

test "get_datasets should return datasets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    var datasets = get_datasets(arena.allocator());
    defer arena.deinit();
    try std.testing.expectEqual(28, datasets.count());
    try std.testing.expect(datasets.contains("library"));
    try std.testing.expect(datasets.contains("dataset11"));
}
