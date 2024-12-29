const std = @import("std");
const ArrayList = std.ArrayList;
const AllocatorError = std.mem.Allocator.Error;
const tokens_lib = @import("tokens.zig");
const Token = tokens_lib.Token;
const TokenType = tokens_lib.TokenType;

const GeneratorError = error{ OutOfBounds, UnexpectedToken } || AllocatorError || std.fmt.ParseIntError;

fn expandString(list: *ArrayList(u8), str: []const u8) GeneratorError!void {
    for (str) |c| {
        try list.append(c);
    }
}

pub const Generator = struct {
    tokens: []Token,
    idx: i64,
    alloc: std.mem.Allocator,
    errString: []u8,
    fn next(self: *Generator) Token {
        self.idx += 1;
        return if (self.idx < self.tokens.len) self.tokens[@intCast(self.idx)] else Token.none();
    }
    fn peek(self: *Generator) Token {
        return if (self.idx + 1 < self.tokens.len) self.tokens[@intCast(self.idx + 1)] else Token.none();
    }
    fn convertNumber(self: *Generator, t: Token, bound: bool) GeneratorError!u64 {
        const n = try std.fmt.parseInt(u64, t.lit, 10);
        if (n > 255 and bound) {
            self.errString = try std.fmt.allocPrint(self.alloc, "'{d}' is not in the valid range of 0-255", .{n});
            return error.OutOfBounds;
        }
        return n;
    }
    pub fn generate(self: *Generator) GeneratorError![]u8 {
        var bytes = ArrayList(u8).init(self.alloc);
        var t = self.next();

        while (t.kind != TokenType.None) {
            switch (t.kind) {
                .Number => {
                    try bytes.append(@intCast(try self.convertNumber(t, true)));
                    t = self.next();
                },
                .String => {
                    try expandString(&bytes, t.lit);
                    t = self.next();
                },
                .OpParen => {
                    const num = self.next();
                    //std.debug.print("{s}\n", .{try num.str()});
                    if (num.kind != TokenType.Number) {
                        self.errString = if (num.kind == TokenType.None)
                            return try std.fmt.allocPrint(self.alloc, "expected number, but found EOL", .{})
                        else
                            return try std.fmt.allocPrint(self.alloc, "expected number, but found '{s}'", .{num.lit});

                        return error.UnexpectedToken;
                    }

                    const numValue = try self.convertNumber(num, false);

                    const paren = self.next();
                    //std.debug.print("{s}\n", .{try paren.str()});
                    if (paren.kind != TokenType.CloseParen) {
                        self.errString = if (num.kind == TokenType.None)
                            try std.fmt.allocPrint(self.alloc, "expected ')', but found EOL", .{})
                        else
                            try std.fmt.allocPrint(self.alloc, "expected ')', but found '{s}'", .{paren.lit});
                        return error.UnexpectedToken;
                    }

                    const stringOrNum = self.next();
                    //std.debug.print("{s}\n", .{try stringOrNum.str()});
                    switch (stringOrNum.kind) {
                        .String => {
                            for (0..numValue) |_| {
                                try expandString(&bytes, stringOrNum.lit);
                            }
                        },
                        .Number => {
                            const repNum: u8 = @intCast(try self.convertNumber(stringOrNum, true));
                            for (0..numValue) |_| {
                                try bytes.append(repNum);
                            }
                        },
                        else => {
                            self.errString = if (num.kind == TokenType.None)
                                return try std.fmt.allocPrint(self.alloc, "expected a string or number, but found EOL", .{})
                            else
                                try std.fmt.allocPrint(self.alloc, "expected a string or number, but found '{s}'", .{stringOrNum.lit});
                            return error.UnexpectedToken;
                        },
                    }

                    t = self.next();
                },
                else => {
                    self.errString = try std.fmt.allocPrint(self.alloc, "unexpected token '{any}'", .{t.kind});
                    return error.UnexpectedToken;
                },
            }
        }

        return bytes.items;
    }
    pub fn init(alloc: std.mem.Allocator, tokens: []Token) Generator {
        return Generator{ .alloc = alloc, .tokens = tokens, .idx = -1, .errString = "" };
    }
};
