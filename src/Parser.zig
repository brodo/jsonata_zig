const Parser = @This();
const std = @import("std");
const Tokenizer = @import("Tokenizer.zig");

it: Tokenizer = .{},
state: State = .start,
call_depth: u32 = 0, // 0 = not in a call
previous_segment_end: u32 = 0, // used for call
stack: std.ArrayList(Node),
allocator: std.mem.Allocator,

const State = enum {
    start,
    extend_path,
    // Error state
    syntax,
};

pub fn init(allocator: std.mem.Allocator) Parser {
    return .{ .stack = std.ArrayList(Node).init(allocator), .allocator = allocator };
}

pub fn deinit(p: Parser) void {
    for (p.stack.items) |node| {
        node.deinit();
    }
    p.stack.deinit();
}
pub const Tag = enum {
    path,
    syntax_error,
};

const PathNode = struct {
    loc: Tokenizer.Token.Loc,
    steps: std.ArrayList(Tokenizer.Token),
    fn init(allocator: std.mem.Allocator, loc: Tokenizer.Token.Loc) PathNode {
        return .{ .steps = std.ArrayList(Tokenizer.Token).init(allocator), .loc = loc };
    }
    fn deinit(n: PathNode) void {
        n.steps.deinit();
    }
};

const SyntaxErrorNode = struct {
    loc: Tokenizer.Token.Loc,
};

pub const Node = union(Tag) {
    path: PathNode,
    syntax_error: SyntaxErrorNode,
    fn loc(self: Node) *Tokenizer.Token.Loc {
        return switch (self) {
            .path => |p| @constCast(&p.loc),
            .syntax_error => |e| @constCast(&e.loc),
        };
    }

    fn tag(self: Node) Tag {
        return switch (self) {
            .path => .path,
            .syntax_error => .syntax_error,
        };
    }
    fn deinit(self: Node) void {
        switch (self) {
            .path => |p| p.deinit(),
            else => {},
        }
    }
};

pub fn next(p: *Parser, code: []const u8) !?Node {
    if (p.it.idx == code.len) {
        const in_terminal_state = p.state == .extend_path;
        if (in_terminal_state) return null;
        return p.syntaxError(.{
            .start = p.it.idx,
            .end = p.it.idx,
        });
    }

    var dotted_path = false;

    while (p.it.next(code)) |tok| switch (p.state) {
        .syntax => unreachable,
        .start => switch (tok.tag) {
            .dollar, .identifier, .star => {
                var node = PathNode.init(p.allocator, tok.loc);
                try node.steps.append(tok);
                try p.stack.append(Node{ .path = node });
                p.state = .extend_path;
            },
            else => {
                return p.syntaxError(tok.loc);
            },
        },

        .extend_path => switch (tok.tag) {
            .dot => {
                const id_tok = p.it.next(code);
                if (id_tok == null or id_tok.?.tag != .identifier) {
                    return p.syntaxError(tok.loc);
                }

                p.previous_segment_end = tok.loc.end;
                const last = &p.stack.items[p.stack.items.len - 1];
                try last.path.steps.append(tok);
                last.path.loc.end = id_tok.?.loc.end;
                dotted_path = true;
            },

            else => return p.syntaxError(tok.loc),
        },
    };

    const in_terminal_state = p.state == .extend_path;

    const code_len: u32 = @intCast(code.len);
    if (p.call_depth > 0 or !in_terminal_state) {
        return p.syntaxError(.{
            .start = code_len - 1,
            .end = code_len,
        });
    }
    const last = &p.stack.items[p.stack.items.len - 1];
    last.loc().end = code_len;
    if (last.loc().len() == 0) return null;
    return p.stack.getLast();
}

fn syntaxError(p: *Parser, loc: Tokenizer.Token.Loc) Node {
    p.state = .syntax;
    return .{ .syntax_error = .{ .loc = loc } };
}

test "basics" {
    const case = "Address.City";
    const expected: []const Tag = &.{
        .path,
    };

    var p = Parser.init(std.testing.allocator);
    defer p.deinit();
    for (expected) |ex| {
        const actual = (try p.next(case)).?;
        try std.testing.expectEqual(ex, actual.tag());
    }
    try std.testing.expectEqual(@as(?Node, null), p.next(case));
}
