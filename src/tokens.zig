const std = @import("std");

pub const Token = struct {
    lit: []const u8,
    start: u64,
    end: u64,
    ln: u64,
    pub fn str(self: Token) std.fmt.AllocPrintError![]u8 {
        return try std.fmt.allocPrint(std.heap.page_allocator, "Token[{s}, {d}..{d}, {d}]\n", .{ self.type, self.lit, self.start, self.end, self.ln });
    }
    pub fn init(lit: []const u8, start: u32, end: u32, ln: u32) Token {
        return .{ .lit = lit, .start = start, .end = end, .ln = ln };
    }
    pub fn empty() Token {
        return .{ .lit = "", .start = 0, .end = 0, .ln = 0 };
    }
};
