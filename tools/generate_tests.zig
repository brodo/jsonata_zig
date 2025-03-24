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

fn get_datasets(alloc: std.mem.Allocator) !std.StringArrayHashMap(std.json.Value) {
    var test_suite_dir = try std.fs.cwd().openDir("test-suite/datasets", .{});
    defer test_suite_dir.close();
    var iter = test_suite_dir.iterate();
    var string_hash_map = std.StringArrayHashMap(std.json.Value).init(alloc);
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        var file = try test_suite_dir.openFile(entry.name, .{});
        defer file.close();
        const file_content = try file.readToEndAlloc(alloc, 1024 * 1024);
        defer alloc.free(file_content);
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, alloc, file_content, .{});
        const dataset_name = try alloc.alloc(u8, entry.name.len - 5);
        @memcpy(dataset_name, entry.name[0 .. entry.name.len - 5]);
        try string_hash_map.put(dataset_name, parsed);
    }
    return string_hash_map;
}

const Test = struct { name: []u8, definition: std.json.Value };

fn get_groups(alloc: std.mem.Allocator) !std.StringArrayHashMap(std.ArrayList(Test)) {
    var group_dir = try std.fs.cwd().openDir("test-suite/groups", .{});
    defer group_dir.close();
    var g_iter = group_dir.iterate();
    var result_hm = std.StringArrayHashMap(std.ArrayList(Test)).init(alloc);

    while (try g_iter.next()) |dir_info| {
        std.debug.print("dir: {s}\n", .{dir_info.name});
        if (dir_info.kind != .directory) continue;
        var test_dir = try group_dir.openDir(dir_info.name, .{});
        defer test_dir.close();
        var t_iter = test_dir.iterate();
        var test_list = std.ArrayList(Test).init(alloc);
        while (try t_iter.next()) |file_info| {
            std.debug.print("file: {s}\n", .{file_info.name});

            if (file_info.kind != .file or !std.mem.eql(u8, file_info.name[0 .. file_info.name.len - 4], "json")) continue;
            // todo: also add .jsonata files!
            var file = try test_dir.openFile(file_info.name, .{});
            defer file.close();
            const file_content = try file.readToEndAlloc(alloc, 1024 * 1024);
            defer alloc.free(file_content);
            const parsed = try std.json.parseFromSliceLeaky(std.json.Value, alloc, file_content, .{});
            const case_name = try alloc.alloc(u8, file_info.name.len - 5);
            @memcpy(case_name, file_info.name[0 .. file_info.name.len - 5]);
            try test_list.append(.{ .name = case_name, .definition = parsed });
        }
        try result_hm.put(dir_info.name, test_list);
    }
    return result_hm;
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}

test "get_groups" {
    var area = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer area.deinit();
    var groups = try get_groups(area.allocator());
    try std.testing.expectEqual(100, groups.count());
}

test "get_datasets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var datasets = try get_datasets(arena.allocator());
    try std.testing.expectEqual(28, datasets.count());
    try std.testing.expect(datasets.contains("library"));
    try std.testing.expect(datasets.contains("dataset11"));
}
