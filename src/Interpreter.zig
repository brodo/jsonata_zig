const Iterpreter = @This();

const std = @import("std");
const json = @import("json");
const Parser = @import("Parser.zig");

current: ?.json.Value = null,

pub fn evaluate(expr: []const u8, _: ?json.Value) ?json.Value {
    var parser: Parser = .{};
    while (parser.next(expr)) |node| {
        switch (node.tag) {
            .path => @panic("todo"),
            .syntax_error => std.debug.panic("Syntax error at {any}", .{node.loc}),
        }
    }
}