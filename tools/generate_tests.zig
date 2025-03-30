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
        \\const json = std.json;
        \\
    , .{});

    { // Build Dataset Hashmap
        const datasets = try get_datasets(arena);
        try out_txt.writer().print(
            \\const datasets = blk: {{
            \\  var arena_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            \\  defer arena_alloc.deinit();
            \\  const arr = [_]struct{{[]const u8, json.Value}}{{
            \\
        , .{});

        var dataset_iterator = datasets.iterator();
        while (dataset_iterator.next()) |entry| {
            const name = entry.key_ptr.*;
            const content = entry.value_ptr.*;
            var lines = std.mem.splitAny(u8, content, "\n");
            var str_builder = std.ArrayList(u8).init(arena);
            while (lines.next()) |line| {
                try std.fmt.format(str_builder.writer(), "\\\\            {s}\n", .{line});
            }
            try out_txt.writer().print(
                \\      .{{
                \\          "{s}",
                \\          json.parseFromSlice(std.json.Value, arena_alloc.allocator(),
                \\{s}
                \\          , .{{}}).?
                \\      }},
                \\
            , .{ name, str_builder.items });
        }
        try out_txt.writer().print(
            \\  }};
            \\  break :blk arr;
            \\}};
            \\
            \\const dataset_map = std.StaticStringMap(json.Value).initComptime(datasets);
            \\
        , .{});
    }
    const groups = try get_groups(arena);
    { // Build Test Info Hashmap
        try out_txt.writer().print(
            \\
            \\const tests = blk: {{
            \\  var arena_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            \\  defer arena_alloc.deinit();
            \\  const arr = [_]struct{{[]const u8, json.Value}}{{
        , .{});
        var iterator = groups.json.iterator();
        while (iterator.next()) |test_entry| {
            var lines = std.mem.splitAny(u8, test_entry.value_ptr.*, "\n");
            var str_builder = std.ArrayList(u8).init(arena);
            while (lines.next()) |line| {
                try std.fmt.format(str_builder.writer(), "\\\\            {s}\n", .{line});
            }
            try out_txt.writer().print(
                \\      .{{
                \\          "{s}",
                \\          json.parseFromSlice(std.json.Value, arena_alloc.allocator(),
                \\{s}
                \\          , .{{}}).?,
                \\      }},
            , .{ test_entry.key_ptr.*, str_builder.items });
        }
        try out_txt.writer().print(
            \\      }};
            \\  break :blk arr;
            \\}};
            \\const test_map = std.StaticStringMap(json.Value).initComptime(tests);
        , .{});
    }

    { // Build JSONATA expression Hashmap
        try out_txt.writer().print(
            \\
            \\const jsonata_expressions = blk: {{
            \\  var arena_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            \\  defer arena_alloc.deinit();
            \\  const arr = [].{{
        , .{});
        var iterator = groups.jsonata.iterator();
        while (iterator.next()) |entry| {
            var lines = std.mem.splitAny(u8, entry.value_ptr.*, "\n");
            var str_builder = std.ArrayList(u8).init(arena);
            while (lines.next()) |line| {
                try std.fmt.format(str_builder.writer(), "\\\\            {s}\n", .{line});
            }
            try out_txt.writer().print(
                \\      .{{
                \\          "{s}",
                \\{s},
                \\      }},
            , .{ entry.key_ptr.*, str_builder.items });
        }
        try out_txt.writer().print(
            \\      }};
            \\  break :blk arr;
            \\}};
        , .{});
    }

    try output_file.writeAll(out_txt.items);
    return std.process.cleanExit();
}

// name is file path without extension
const TestNames = struct { json: std.StringArrayHashMap([]const u8), jsonata: std.StringArrayHashMap([]const u8) };

fn get_groups(alloc: std.mem.Allocator) !TestNames {
    var group_dir = try std.fs.cwd().openDir("test-suite/groups", .{});
    defer group_dir.close();
    var g_iter = group_dir.iterate();
    var json_map = std.StringArrayHashMap([]const u8).init(alloc);
    var jsonata_map = std.StringArrayHashMap([]const u8).init(alloc);
    while (try g_iter.next()) |dir_info| {
        if (dir_info.kind != .directory) continue;
        var test_dir = try group_dir.openDir(dir_info.name, .{});
        defer test_dir.close();
        const dir_name = try alloc.dupe(u8, dir_info.name);
        var t_iter = test_dir.iterate();
        while (try t_iter.next()) |file_info| {
            if (file_info.kind != .file) continue;
            const test_name = std.fs.path.stem(file_info.name);
            const complete_test_name = try alloc.alloc(u8, dir_name.len + test_name.len + 1);
            _ = try std.fmt.bufPrint(complete_test_name, "{s}/{s}", .{ dir_name, test_name });
            const file_extension = std.fs.path.extension(file_info.name);
            var file = try test_dir.openFile(file_info.name, .{});
            defer file.close();
            const content = try file.readToEndAlloc(alloc, 1024*1204);

            if (std.mem.eql(u8, ".json", file_extension)) {
                try json_map.put(complete_test_name, content);
                continue;
            }
            if (std.mem.eql(u8, ".jsonata", file_extension)) {
                try jsonata_map.put(complete_test_name, content);
                continue;
            }
        }
    }
    return .{ .json = json_map, .jsonata = jsonata_map };
}

fn get_datasets(alloc: std.mem.Allocator) !std.StringArrayHashMap([]const u8) {
    const dataset_root = "test-suite/datasets";
    var dataset_dir = try std.fs.cwd().openDir(dataset_root, .{});
    defer dataset_dir.close();
    var string_hash_map = std.StringArrayHashMap([]const u8).init(alloc);
    var iter = dataset_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        var file = try dataset_dir.openFile(entry.name, .{});
        defer file.close();
        const content = try file.readToEndAlloc(alloc, 1024*1204);
        const dataset_name = try alloc.dupe(u8, std.fs.path.stem(entry.name));
        try string_hash_map.put(dataset_name, content);
    }
    return string_hash_map;
}

test "get_groups" {
    var area = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer area.deinit();
    var groups = try get_groups(area.allocator());
    try std.testing.expect(groups.json.count() > 0);
    try std.testing.expect(groups.jsonata.count() > 0);
}

test "get_datasets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var datasets = try get_datasets(arena.allocator());
    try std.testing.expectEqual(28, datasets.count());
    try std.testing.expect(datasets.contains("library"));
    try std.testing.expect(datasets.contains("dataset11"));
}
