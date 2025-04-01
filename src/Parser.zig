const Parser = @This();

const std = @import("std");
const Tokenizer = @import("Tokenizer.zig");

it: Tokenizer = .{},
state: State = .start,
call_depth: u32 = 0, // 0 = not in a call
previous_segment_end: u32 = 0, // used for call

const State = enum {
    start,
    extend_path,
    // Error state
    syntax,
};

pub const Node = struct {
    tag: Tag,
    loc: Tokenizer.Token.Loc,

    pub const Tag = enum {
        path,
        syntax_error,
    };
};

pub fn next(p: *Parser, code: []const u8) ?Node {
    if (p.it.idx == code.len) {
        const in_terminal_state =  p.state == .extend_path;
        if (in_terminal_state) return null;
        return p.syntaxError(.{
            .start = p.it.idx,
            .end = p.it.idx,
        });
    }
    var path: Node = .{
        .tag = .path,
        .loc = undefined,
    };

    var path_starts_at_global = false;
    var dotted_path = false;

    while (p.it.next(code)) |tok| switch (p.state) {
        .syntax => unreachable,
        .start => switch (tok.tag) {
            .dollar, .identifier, .star => {
                p.state = .extend_path;
                path.loc.end = tok.loc.end;
                path_starts_at_global = true;
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
                path.loc.end = id_tok.?.loc.end;
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

    path.loc.end = code_len;
    if (path.loc.len() == 0) return null;
    return path;
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

    var p: Parser = .{};

    for (expected) |ex| {
        const actual = p.next(case).?;
        try std.testing.expectEqual(ex, actual.tag);
    }
    try std.testing.expectEqual(@as(?Node, null), p.next(case));
}

