const std = @import("std");
const json = std.json;

const Interpreter = @import("Interpreter.zig");

pub fn evaluate(expr: []const u8, data: ?json.Value) ?json.Value {
    const interpreter : Interpreter =.{};
    return interpreter.evaluate(expr, data);
}

