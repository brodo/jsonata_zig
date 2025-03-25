const std = @import("std");

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const args = try std.process.argsAlloc(arena);
    if (args.len != 2) {
        std.debug.panic("Please provide the output file name as an argument.", .{});
    }
    const output_file_path = args[1];
    var output_file = try std.fs.cwd().createFile(output_file_path, .{});
    defer output_file.close();
    var out_txt = std.ArrayList(u8).init(arena);
    defer out_txt.deinit();
    try out_txt.writer().print(
        \\const std = @import("std");
        \\const testing = std.testing;
        \\const json = std.json;
        \\const jsonata = @import("root.zig");
        \\
    , .{});

    {
        const datasets = try get_datasets(arena);

        try out_txt.writer().print(
            \\const datasets = blk: {{
            \\  var arena_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            \\  defer arena_alloc.deinit();
            \\  const arr = [].{{
            \\
        , .{});

        var dataset_iterator = datasets.iterator();
        while (dataset_iterator.next()) |entry| {
            const name = entry.key_ptr.*;
            const path = entry.value_ptr.*;
            try out_txt.writer().print(
                \\      .{{ "{s}", json.parseFromSlice(std.json.Value, arena_alloc.allocator(), @embedFile("{s}"), .{{}}).? }},
                \\
            , .{ name, path });
        }
        try out_txt.writer().print(
            \\  }};
            \\  break :blk arr;
            \\}};
            \\
            \\const dataset_map = std.StaticStringMap(json.Value).initComptime(datasets);
        , .{});
    }
    {
        var groups = try get_groups(arena);
        var g_iter = groups.iterator();
        while (g_iter.next()) |group| {
            for (group.value_ptr.items) |test_case| {
                try out_txt.writer().print(
                    \\
                    \\test "{s} - {s}" {{
                    \\  try testing.expect(jsonata.test_me());
                    \\}}
                , .{ group.key_ptr.*, test_case.name });
            }
        }
    }

    try output_file.writeAll(out_txt.items);
    return std.process.cleanExit();
}

const Test = struct { name: []const u8, definition: std.json.Value };

fn get_groups(alloc: std.mem.Allocator) !std.StringArrayHashMap(std.ArrayList(Test)) {
    var group_dir = try std.fs.cwd().openDir("test-suite/groups", .{});
    defer group_dir.close();
    var g_iter = group_dir.iterate();
    var result_hm = std.StringArrayHashMap(std.ArrayList(Test)).init(alloc);

    while (try g_iter.next()) |dir_info| {
        if (dir_info.kind != .directory) continue;
        var test_dir = try group_dir.openDir(dir_info.name, .{});
        defer test_dir.close();
        var t_iter = test_dir.iterate();
        var test_list = std.ArrayList(Test).init(alloc);
        while (try t_iter.next()) |file_info| {
            // std.debug.print("group: '{s}', name: '{s}', ending: {s}\n", .{ dir_info.name, file_info.name, file_info.name[file_info.name.len - 5 ..] });
            if (file_info.kind != .file or !std.mem.eql(u8, std.fs.path.extension(file_info.name), ".json")) continue;
            // todo: also add .jsonata files!
            var file = try test_dir.openFile(file_info.name, .{});
            defer file.close();
            const file_content = try file.readToEndAlloc(alloc, 1024 * 1024);
            const parsed = try std.json.parseFromSliceLeaky(std.json.Value, alloc, file_content, .{});
            const name = try alloc.dupe(u8, std.fs.path.stem(file_info.name));
            try test_list.append(.{ .name = name, .definition = parsed });
        }
        const dir_name = try alloc.dupe(u8, dir_info.name);
        try result_hm.put(dir_name, test_list);
    }
    return result_hm;
}

fn get_datasets(alloc: std.mem.Allocator) !std.StringArrayHashMap([]const u8) {
    const dataset_root = "test-suite/datasets";
    var test_suite_dir = try std.fs.cwd().openDir(dataset_root, .{});
    defer test_suite_dir.close();
    var string_hash_map = std.StringArrayHashMap([]const u8).init(alloc);
    var iter = test_suite_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        var file = try test_suite_dir.openFile(entry.name, .{});
        defer file.close();
        const dataset_name = try alloc.dupe(u8, std.fs.path.stem(entry.name));
        try string_hash_map.put(dataset_name, try std.fs.path.join(alloc, &.{ dataset_root, entry.name }));
    }
    return string_hash_map;
}

test "get_groups" {
    var area = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer area.deinit();
    var groups = try get_groups(area.allocator());
    try std.testing.expectEqual(100, groups.count());
    var iterator = groups.iterator();
    while (iterator.next()) |entry| {
        try std.testing.expect(entry.value_ptr.items.len > 0);
    }
}

test "get_datasets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var datasets = try get_datasets(arena.allocator());
    try std.testing.expectEqual(28, datasets.count());
    try std.testing.expect(datasets.contains("library"));
    try std.testing.expect(datasets.contains("dataset11"));
}
