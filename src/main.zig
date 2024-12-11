const std = @import("std");
const fs = std.fs;
const tokens = @import("tokens.zig");
const Lexer = @import("lexer.zig").Lexer;
const Generator = @import("generator.zig").Generator;

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("expected 'bytec <input file> [output file]'\n", .{});
        return 1;
    }

    const input = args[1];
    const output = if (args.len > 2) args[2] else "out.bin";

    const dir = std.fs.cwd();

    const maxSize = std.math.maxInt(usize);
    const data = dir.readFileAlloc(allocator, input, maxSize) catch |err| switch (err) {
        std.posix.OpenError.FileNotFound => {
            std.debug.print("file '{s}' does not exist\n", .{input});
            return 1;
        },
        else => return err,
    };
    defer allocator.free(data);

    var lexer = Lexer.init(std.heap.page_allocator, data);
    const toks = try lexer.lex();

    var generator = Generator.init(std.heap.page_allocator, toks);
    const bytes = try generator.generate();

    var f = try dir.createFile(output, .{});

    try f.writeAll(bytes);

    return 0;
}
