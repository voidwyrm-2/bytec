const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Lexer = @import("Lexer.zig");
const Token = Lexer.Token;
const TokenType = Lexer.TokenType;

const Self = @This();

const Error = error{
    UnexpectedToken,
    UnexpectedEOL,
};

const ParseResult = struct {
    initial: usize,
    added: usize,
};

allocator: Allocator,
buf: ArrayList(u8),
err_string: []const u8 = "",
idx: usize,
tokens: []const Token,

pub fn init(allocator: Allocator, tokens: []const Token) !Self {
    return .{
        .allocator = allocator,
        .buf = ArrayList(u8).init(allocator),
        .idx = 0,
        .tokens = tokens,
    };
}

pub fn deinit(self: *Self) void {
    self.buf.deinit();

    //if (self.err_string.len > 0)
    //    self.allocator.free(self.err_string);
}

pub fn parse(self: *Self) ![]u8 {
    _ = try self.innerParse(self.tokens.len);
    return self.buf.items;
}

fn errf(self: *Self, comptime fmt: []const u8, args: anytype) !void {
    self.err_string = try self.tokens[self.idx].errf(self.allocator, fmt, args);
}

fn expectKind(self: *Self, expected: TokenType, offset: usize) !void {
    const actual = self.peek(offset);

    const anchor = self.tokens[self.tokens.len - 1];

    if (actual) |a| {
        if (a.kind != expected) {
            self.err_string = try anchor.errf(
                self.allocator,
                "expected '{s}', but found '{s}' instead",
                .{ @tagName(expected), @tagName(a.kind) },
            );

            return error.UnexpectedToken;
        }
    } else {
        self.err_string = try anchor.errf(
            self.allocator,
            "expected '{s}', but found EOL instead",
            .{@tagName(expected)},
        );

        return error.UnexpectedEOL;
    }
}

fn peek(self: *Self, by: usize) ?Token {
    return if (self.idx + by < self.tokens.len)
        self.tokens[self.idx + by]
    else
        null;
}

fn innerParse(self: *Self, limit: usize) !ParseResult {
    const initial_bytes = self.buf.items.len;
    var bytes: usize = 0;

    var mut_limit = limit;

    while (self.idx < self.tokens.len) {
        const cur = self.tokens[self.idx];

        switch (cur.kind) {
            .number => {
                // TODO: make this support any integer size
                const n = try std.fmt.parseInt(u8, cur.lit, 0);
                try self.buf.append(n);
                bytes += 1;
                self.idx += 1;
            },
            .string => {
                try self.buf.appendSlice(cur.lit);
                bytes += cur.lit.len;
                self.idx += 1;
            },
            .paren_open => {
                try self.expectKind(.number, 1);
                try self.expectKind(.paren_close, 2);

                self.idx += 3;

                const amount = try std.fmt.parseInt(usize, self.tokens[self.idx - 2].lit, 0);

                const sl = try self.innerParse(1);

                const copy = try self.allocator.alloc(u8, sl.added);
                defer self.allocator.free(copy);

                @memcpy(copy, self.buf.items[sl.initial .. sl.initial + sl.added]);

                for (0..amount) |_|
                    try self.buf.appendSlice(copy);
            },
            else => {
                try self.errf("unexpected token '{s}'", .{cur.lit});
                return error.UnexpectedToken;
            },
        }

        mut_limit -= 1;

        if (mut_limit == 0)
            break;
    }

    return .{
        .initial = initial_bytes,
        .added = bytes,
    };
}
