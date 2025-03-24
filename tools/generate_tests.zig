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


const ds_formatter = std.fs.path.fmtJoin(&[_][]const u8{ "test-suite", "datasets" });
fn get_datasets(alloc: std.mem.Allocator) !std.StringArrayHashMap(std.json.Value) {
    var dataset_path = std.ArrayList(u8).init(alloc);
    defer dataset_path.deinit();
    try dataset_path.writer().print("{s}", .{ds_formatter});
    var test_suite_dir = try std.fs.cwd().openDir(dataset_path.items, .{});
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


const group_formatter = std.fs.path.fmtJoin(&[_][]const u8{ "test-suite", "groups" });
fn get_groups(alloc: std.mem.Allocator) !void {
    var group_path = std.ArrayList(u8).init(alloc);
    defer group_path.deinit();
    try group_path.writer().print("{s}", .{group_formatter});
    var group_dir = try std.fs.cwd().openDir(group_path.items, .{});
    defer group_dir.close();
    var iter = group_dir.iterate();
    while (try iter.next()) |entry| {
        std.debug.print("name: {s}\n", .{entry.name});
        if (entry.kind != .directory) continue;

    }
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}

test "get_groups" {
    var area = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer area.deinit();
    try get_groups(area.allocator());
}

test "get_datasets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var datasets = try get_datasets(arena.allocator());
    try std.testing.expectEqual(28, datasets.count());
    try std.testing.expect(datasets.contains("library"));
    try std.testing.expect(datasets.contains("dataset11"));
}
