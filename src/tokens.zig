const std = @import("std");

pub const TokenType = enum { None, Number, String, OpParen, CloseParen };

pub const Token = struct {
    kind: TokenType,
    lit: []const u8,
    start: u64,
    end: u64,
    ln: u64,
    pub fn str(self: Token) std.fmt.AllocPrintError![]u8 {
        return try std.fmt.allocPrint(std.heap.page_allocator, "Token[{any}, {s}, {d}..{d}, {d}]", .{ self.kind, self.lit, self.start, self.end, self.ln });
    }
    pub fn init(kind: TokenType, lit: []const u8, start: u32, end: u32, ln: u32) Token {
        return .{ .kind = kind, .lit = lit, .start = start, .end = end, .ln = ln };
    }
    pub fn none() Token {
        return .{ .kind = .None, .lit = "", .start = 0, .end = 0, .ln = 0 };
    }
};
