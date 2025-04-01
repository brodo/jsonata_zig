const Tokenizer = @This();

const std = @import("std");

idx: u32 = 0,
pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: u32,
        end: u32,

        pub fn len(loc: Loc) u32 {
            return loc.end - loc.start;
        }

        pub fn slice(self: Loc, code: []const u8) []const u8 {
            return code[self.start..self.end];
        }

        pub fn unquote(
            self: Loc,
            gpa: std.mem.Allocator,
            code: []const u8,
        ) ![]const u8 {
            const s = code[self.start..self.end];
            const quoteless = s[1 .. s.len - 1];

            for (quoteless) |c| {
                if (c == '\\') break;
            } else {
                return quoteless;
            }

            const quote = s[0];
            var out = std.ArrayList(u8).init(gpa);
            var last = quote;
            var skipped = false;
            for (quoteless) |c| {
                if (c == '\\' and last == '\\' and !skipped) {
                    skipped = true;
                    last = c;
                    continue;
                }
                if (c == quote and last == '\\' and !skipped) {
                    out.items[out.items.len - 1] = quote;
                    last = c;
                    continue;
                }
                try out.append(c);
                skipped = false;
                last = c;
            }
            return try out.toOwnedSlice();
        }
    };

    pub const Tag = enum {
        invalid,
        dollar,
        dot,
        comma,
        lparen,
        rparen,
        string,
        identifier,
        number,

        pub fn lexeme(self: Tag) ?[]const u8 {
            return switch (self) {
                .invalid,
                .string,
                .identifier,
                .number,
                => null,
                .dollar => "$",
                .dot => ".",
                .comma => ",",
                .lparen => "(",
                .rparen => ")",
            };
        }
    };
};

const State = enum {
    invalid,
    start,
    identifier,
    number,
    string,
};

pub fn next(self: *Tokenizer, code: []const u8) ?Token {
    var state: State = .start;
    var res: Token = .{
        .tag = .invalid,
        .loc = .{
            .start = self.idx,
            .end = undefined,
        },
    };
    while (true) : (self.idx += 1) {
        const c = if (self.idx >= code.len) 0 else code[self.idx];

        switch (state) {
            .start => switch (c) {
                else => state = .invalid,
                0 => return null,
                ' ', '\n' => res.loc.start += 1,
                'a'...'z', 'A'...'Z', '_' => {
                    state = .identifier;
                },
                '"', '\'' => {
                    state = .string;
                },
                '0'...'9', '-' => {
                    state = .number;
                },

                '$' => {
                    self.idx += 1;
                    res.tag = .dollar;
                    res.loc.end = self.idx;
                    break;
                },
                ',' => {
                    self.idx += 1;
                    res.tag = .comma;
                    res.loc.end = self.idx;
                    break;
                },
                '.' => {
                    self.idx += 1;
                    res.tag = .dot;
                    res.loc.end = self.idx;
                    break;
                },
                '(' => {
                    self.idx += 1;
                    res.tag = .lparen;
                    res.loc.end = self.idx;
                    break;
                },
                ')' => {
                    self.idx += 1;
                    res.tag = .rparen;
                    res.loc.end = self.idx;
                    break;
                },
            },
            .identifier => switch (c) {
                'a'...'z', 'A'...'Z', '0'...'9', '_', '?', '!' => {},
                else => {
                    res.tag = .identifier;
                    res.loc.end = self.idx;
                    break;
                },
            },
            .string => switch (c) {
                0 => {
                    res.tag = .invalid;
                    res.loc.end = self.idx;
                    break;
                },

                '"', '\'' => if (c == code[res.loc.start] and
                    evenSlashes(code[0..self.idx]))
                {
                    self.idx += 1;
                    res.tag = .string;
                    res.loc.end = self.idx;
                    break;
                },
                else => {},
            },
            .number => switch (c) {
                '0'...'9', '.', '_' => {},
                else => {
                    res.tag = .number;
                    res.loc.end = self.idx;
                    break;
                },
            },
            .invalid => switch (c) {
                'a'...'z',
                'A'...'Z',
                '0'...'9',
                => {},
                else => {
                    res.loc.end = self.idx;
                    break;
                },
            },
        }
    }
    return res;
}

fn evenSlashes(str: []const u8) bool {
    var i = str.len - 1;
    var even = true;
    while (true) : (i -= 1) {
        if (str[i] != '\\') break;
        even = !even;
        if (i == 0) break;
    }
    return even;
}

test "general language" {
    const expected = [_]Token.Tag{.identifier};
    var it: Tokenizer = .{};
    var idx: u32 = 0;
    while (it.next("Test")) |token| {
        try std.testing.expectEqual(expected[idx], token.tag);
        idx += 1;
    }
}
