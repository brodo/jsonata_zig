const Parser = @This();
const Self = @This();
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

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .stack = std.ArrayList(Node).init(allocator), .allocator = allocator };
}

pub fn deinit(p: Self) void {
    p.stack.deinit();
}

pub const Node = struct {
    tag: Tag,
    loc: Tokenizer.Token.Loc,
    infos: ?Infos = null,

    pub const Tag = enum {
        path,
        syntax_error,
    };

    pub const Infos = union(Tag) {
        path: std.ArrayList(Tokenizer.Token),
        syntax_error: void,
    };

    pub fn init(allocator: std.mem.Allocator, tag: Tag, loc: Tokenizer.Token.Loc) Node {
        return switch (tag) {
            .path => .{ .tag = tag, .infos = .{ .path = std.ArrayList(Tokenizer.Token).init(allocator) }, .loc = loc },
            .syntax_error => .{ .tag = tag, .loc = loc},
        };
    }

    pub fn deinit(n: Node) void {
        return switch (n) {
            .path => n.infos.?.path.deinit(),
        };
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
                try p.stack.append(Node.init(p.allocator, .path, tok.loc));
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
                last.loc.end = id_tok.?.loc.end;
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
    last.loc.end = code_len;
    if (last.loc.len() == 0) return null;
    return p.stack.getLast();
}

fn syntaxError(p: *Parser, loc: Tokenizer.Token.Loc) Node {
    p.state = .syntax;
    return .{ .tag = .syntax_error, .loc = loc };
}

test "basics" {
    const case = "Address.City";
    const expected: []const Node.Tag = &.{
        .path,
    };

    var p: Parser = Parser.init(std.testing.allocator);
    defer p.deinit();
    for (expected) |ex| {
        const actual = try p.next(case);
        std.debug.print("node: {any}\n", .{actual.?});
        try std.testing.expectEqual(ex, actual.?.tag);
    }
    try std.testing.expectEqual(@as(?Node, null), p.next(case));

}
