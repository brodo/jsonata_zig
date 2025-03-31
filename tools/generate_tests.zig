const std = @import("std");
const json = std.json;
const testing = std.testing;

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
        \\const testing = std.testing;
        \\
        \\const jsonata = @import("root.zig");
        \\
    , .{});

    { // Build Dataset Hashmap
        const datasets = try get_datasets(arena);
        try out_txt.writer().print(
            \\const datasets =[_]struct{{[]const u8, []const u8}}{{
            \\
        , .{});

        var dataset_iterator = datasets.iterator();
        while (dataset_iterator.next()) |entry| {
            const name = entry.key_ptr.*;
            const content = entry.value_ptr.*;
            var lines = std.mem.splitAny(u8, content, "\n");
            var str_builder = std.ArrayList(u8).init(arena);
            while (lines.next()) |line| {
                try std.fmt.format(str_builder.writer(), "\\\\      {s}\n", .{line});
            }
            try out_txt.writer().print(
                \\  .{{
                \\      "{s}",
                \\{s}
                \\  }},
                \\
            , .{ name, str_builder.items });
        }
        try out_txt.writer().print(
            \\}};
            \\
            \\const dataset_map = std.StaticStringMap([]const u8).initComptime(datasets);
            \\
        , .{});
    }
    const groups = try get_groups(arena);
    { // Build Test Info Hashmap
        try out_txt.writer().print(
            \\
            \\const tests = [_]struct{{[]const u8, []const u8}}{{
        , .{});
        var iterator = groups.json.iterator();
        while (iterator.next()) |test_entry| {
            var lines = std.mem.splitAny(u8, test_entry.value_ptr.*, "\n");
            var str_builder = std.ArrayList(u8).init(arena);
            while (lines.next()) |line| {
                try std.fmt.format(str_builder.writer(), "\\\\      {s}\n", .{line});
            }
            try out_txt.writer().print(
                \\  .{{
                \\      "{s}",
                \\{s}
                \\  }},
            , .{ test_entry.key_ptr.*, str_builder.items });
        }
        try out_txt.writer().print(
            \\}};
            \\const test_map = std.StaticStringMap([]const u8).initComptime(tests);
        , .{});
    }

    { // Build JSONATA expression Hashmap
        try out_txt.writer().print(
            \\
            \\const jsonata_expressions = [_]struct{{[]const u8, []const u8}}{{
        , .{});
        var iterator = groups.jsonata.iterator();
        while (iterator.next()) |entry| {
            var lines = std.mem.splitAny(u8, entry.value_ptr.*, "\n");
            var str_builder = std.ArrayList(u8).init(arena);
            while (lines.next()) |line| {
                try std.fmt.format(str_builder.writer(), "\\\\      {s}\n", .{line});
            }
            try out_txt.writer().print(
                \\  .{{
                \\      "{s}",
                \\{s},
                \\  }},
            , .{ entry.key_ptr.*, str_builder.items });
        }
        try out_txt.writer().print(
            \\}};
            \\const expression_map = std.StaticStringMap([]const u8).initComptime(jsonata_expressions);
            \\
            \\const TestData = struct {{expr: [] const u8, data: ?json.Value, result: ?json.Value}};
            \\
            \\
            \\fn test_data_for_json(test_json: json.Value, name: []const u8, alloc: std.mem.Allocator ) !TestData {{
            \\  const expr = if (test_json.object.get("expr")) | e | e.string else blk: {{
            \\       const expr_file = test_json.object.get("expr-file").?;
            \\       if(std.meta.activeTag(expr_file) != .string) {{
            \\           @panic("no expr, and no expr file!");
            \\       }}
            \\       var full_name = std.ArrayList(u8).init(alloc);
            \\       defer full_name.deinit();
            \\       try full_name.writer().print("{{s}}/{{s}}",
            \\           .{{std.fs.path.dirname(name).?, std.fs.path.stem(expr_file.string)}});
            \\       break :blk expression_map.get(full_name.items).?;
            \\   }};
            \\
            \\   const data : ?json.Value = if (test_json.object.get("data")) | d | d else blk: {{
            \\       const data_set = test_json.object.get("dataset").?;
            \\       if(std.meta.activeTag(data_set) != .string) {{
            \\           break :blk null; // This is stupid, but such test cases exist in the repo.
            \\       }}
            \\       const ds_str = dataset_map.get(data_set.string).?;
            \\       const ds_json = try json.parseFromSlice(json.Value, alloc, ds_str, .{{}});
            \\       defer ds_json.deinit();
            \\       break :blk ds_json.value;
            \\   }};
            \\   const result = test_json.object.get("result");
            \\   return .{{.expr= expr, .data= data, .result= result}};
            \\}}
            \\
            \\fn test_data_for_name(name: []const u8, alloc: std.mem.Allocator) !std.ArrayList(TestData) {{
            \\  const json_str = test_map.get(name).?;
            \\  const test_json = try json.parseFromSlice(json.Value, alloc, json_str, .{{}});
            \\  defer test_json.deinit();
            \\  var out = std.ArrayList(TestData).init(alloc);
            \\  switch (test_json.value) {{
            \\      .object => {{
            \\         try out.append(try test_data_for_json(test_json.value, name, alloc));
            \\      }},
            \\      .array => {{
            \\          for (test_json.value.array.items) | test_case | {{
            \\              try out.append(try test_data_for_json(test_case, name, alloc));
            \\          }}
            \\      }},
            \\      else => {{
            \\          std.debug.print("not object or arrray!\n",.{{}});
            \\      }},
            \\  }}
            \\  return out;
            \\}}
        , .{});
    }

    {
        // Build tests
        var iterator = groups.json.iterator();
        while (iterator.next()) |entry| {
            const name = entry.key_ptr.*;
            try out_txt.writer().print(
                \\test "{s}" {{
                \\  const test_data_arr = try test_data_for_name("{s}", testing.allocator);
                \\  defer test_data_arr.deinit();
                \\  for ( test_data_arr.items) | test_data | {{
                \\      try testing.expectEqual(test_data.result, jsonata.evaluate(test_data.expr, test_data.data));
                \\  }}
                \\}}
            , .{name, name});
        }
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
            var file = try test_dir.openFile(file_info.name, .{});
            defer file.close();
            const content = try file.readToEndAlloc(alloc, 1024 * 1204);

            const file_extension = std.fs.path.extension(file_info.name);
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
        const content = try file.readToEndAlloc(alloc, 1024 * 1204);
        const dataset_name = try alloc.dupe(u8, std.fs.path.stem(entry.name));
        try string_hash_map.put(dataset_name, content);
    }
    return string_hash_map;
}

test "get_groups" {
    var area = std.heap.ArenaAllocator.init(testing.allocator);
    defer area.deinit();
    var groups = try get_groups(area.allocator());
    try testing.expect(groups.json.count() > 0);
    try testing.expect(groups.jsonata.count() > 0);
}

test "get_datasets" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var datasets = try get_datasets(arena.allocator());
    try testing.expectEqual(28, datasets.count());
    try testing.expect(datasets.contains("library"));
    try testing.expect(datasets.contains("dataset11"));
}

test "example_test" {
    const json_str =
        \\{
        \\  "expr": "[]",
        \\  "dataset": "dataset5",
        \\  "bindings": {},
        \\  "result": []
        \\}
    ;
    const test_json = try json.parseFromSlice(json.Value, testing.allocator, json_str, .{});
    defer test_json.deinit();
    // const expr = test_json.value.array.

    // var data : json.Value =  if (test_json.value.object.get("data")) | d | d else {
    //     const data_set = test_json.value.object.get("dataset").?.string;
    //     datsets.get(data_set);
    // };

}
