const std = @import("std");
const ArrayList = std.ArrayList;
const AllocatorError = std.mem.Allocator.Error;
const tokens_lib = @import("tokens.zig");
const Token = tokens_lib.Token;

const GeneratorError = error{OutOfBounds} || AllocatorError || std.fmt.ParseIntError;

pub const Generator = struct {
    tokens: []Token,
    alloc: std.mem.Allocator,
    pub fn generate(self: *Generator) GeneratorError![]u8 {
        var bytes = ArrayList(u8).init(self.alloc);

        for (self.tokens) |t| {
            const n = try std.fmt.parseInt(u16, t.lit, 10);
            if (n > 255) return error.OutOfBounds;
            try bytes.append(@intCast(n));
        }

        return bytes.items;
    }
    pub fn init(alloc: std.mem.Allocator, tokens: []Token) Generator {
        return Generator{ .alloc = alloc, .tokens = tokens };
    }
};
