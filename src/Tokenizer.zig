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
        star,
        eq,
        lparen,
        rparen,
        lsquare,
        rsquare,
        string,
        ref,
        identifier,
        number,

        pub fn lexeme(self: Tag) ?[]const u8 {
            return switch (self) {
                .invalid,
                .string,
                .ref,
                .identifier,
                .number,
                => null,
                .dollar => "$",
                .dot => ".",
                .comma => ",",
                .star => "*",
                .eq => "=",
                .lparen => "(",
                .rparen => ")",
                .lsquare => "[",
                .rsquare => "]",
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
    ref,
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
                '`' => {
                    state = .ref;
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
                '*' => {
                    self.idx += 1;
                    res.tag = .star;
                    res.loc.end = self.idx;
                    break;
                },
                '=' => {
                    self.idx += 1;
                    res.tag = .eq;
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
                '[' => {
                    self.idx += 1;
                    res.tag = .lsquare;
                    res.loc.end = self.idx;
                    break;
                },
                ']' => {
                    self.idx += 1;
                    res.tag = .rsquare;
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
            .ref => switch (c) {
                0 => {
                    res.tag = .invalid;
                    res.loc.end = self.idx;
                    break;
                },
                '`' => {
                    self.idx += 1;
                    res.tag = .ref;
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
    const Case = struct {
        code: []const u8,
        expected: []const Token.Tag,
    };
    const cases: []const Case = &.{
        .{ .code = "Surname", .expected = &.{
            .identifier,
        } },
        .{ .code = "Address.City", .expected = &.{
            .identifier,
            .dot,
            .identifier,
        } },
        .{ .code = "Phone[type='mobile']", .expected = &.{
            .identifier,
            .lsquare,
            .identifier,
            .eq,
            .string,
            .rsquare,
        } },
        .{ .code = "Address.*", .expected = &.{
            .identifier,
            .dot,
            .star,
        } },
        .{ .code = "Other.`Over 18 ?`", .expected = &.{
            .identifier,
            .dot,
            .ref,
        } },
        .{ .code = "$[0].ref", .expected = &.{
            .dollar,
            .lsquare,
            .number,
            .rsquare,
            .dot,
            .identifier,
        } },
        .{ .code = "Phone[type='mobile']", .expected = &.{
            .identifier,
            .lsquare,
            .identifier,
            .eq,
            .string,
            .rsquare,
        } },
    };

    for (cases) |case| {
        // std.debug.print("Case: {s}\n", .{case.code});

        var it: Tokenizer = .{};
        for (case.expected) |ex| {
            errdefer std.debug.print("{any}\n", .{it});

            const t = it.next(case.code) orelse return error.Null;
            try std.testing.expectEqual(ex, t.tag);
            const src = case.code[t.loc.start..t.loc.end];
            // std.debug.print(".{s} => `{s}`\n", .{ @tagName(t.tag), src });
            if (t.tag.lexeme()) |l| {
                try std.testing.expectEqualStrings(l, src);
            }
        }

        try std.testing.expectEqual(@as(?Token, null), it.next(case.code));
    }
}

test "strings" {
    const cases =
        \\"arst"
        \\"arst"
        \\"ba\"nana1"
        \\"ba\'nana2"
        \\'ba\'nana3'
        \\'ba\"nana4'
        \\'b1a\''
        \\"b2a\""
        \\"b3a\'"
        \\"b4a\\"
        \\"b5a\\\\"
        \\"b6a\\\\\\"
        \\'ba\\"nana5'
    .*;
    var cases_it = std.mem.tokenizeScalar(u8, &cases, '\n');
    while (cases_it.next()) |case| {
        errdefer std.debug.print("Case: {s}\n", .{case});

        var it: Tokenizer = .{};
        errdefer std.debug.print("Tokenizer idx: {}\n", .{it.idx});
        const t = it.next(case) orelse return error.Null;
        const src = case[t.loc.start..t.loc.end];
        errdefer std.debug.print(".{s} => `{s}`\n", .{ @tagName(t.tag), src });
        try std.testing.expectEqual(@as(Token.Tag, .string), t.tag);
        try std.testing.expectEqual(@as(?Token, null), it.next(case));
    }
}
