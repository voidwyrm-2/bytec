const std = @import("std");
const ArrayList = std.ArrayList;
const AllocatorError = std.mem.Allocator.Error;
const tokens_lib = @import("tokens.zig");
const TokenTypes = tokens_lib.TokenTypes;
const Token = tokens_lib.Token;

const LexerError = error{ IllegalCharacter, UnterminatedString, InvalidEscapeCharacter } || AllocatorError;

pub const Lexer = struct {
    text: []const u8,
    idx: i64 = -1,
    ln: usize = 0,
    cchar: ?u8 = null,
    alloc: std.mem.Allocator,
    fn advance(self: *Lexer) void {
        self.idx += 1;
        if (self.idx < self.text.len) {
            self.cchar = self.text[@intCast(self.idx)];
        } else {
            self.cchar = null;
        }

        if (self.cchar == '\n') {
            self.ln += 1;
        }
    }

    fn isNumber(ch: u8) bool {
        return ch >= '0' and ch <= '9';
    }

    fn collectNumber(self: *Lexer) LexerError!Token {
        const start: u32 = @intCast(self.idx);
        const startln: u32 = @intCast(self.ln);
        var str = ArrayList(u8).init(self.alloc);

        while (self.cchar != null and Lexer.isNumber(self.cchar.?)) {
            try str.append(self.cchar.?);
            self.advance();
        }

        return Token.init(str.items, start, @intCast(self.idx - 1), startln);
    }

    pub fn lex(self: *Lexer) LexerError![]Token {
        var tokens = ArrayList(Token).init(self.alloc);

        while (self.cchar != null) {
            switch (self.cchar.?) {
                ' ', '\n', '\t' => self.advance(),
                '#' => {
                    while (self.cchar != null and self.cchar != '\n') self.advance();
                },
                else => {
                    if (Lexer.isNumber(self.cchar.?)) {
                        try tokens.append(try self.collectNumber());
                        self.advance();
                    } else {
                        return error.IllegalCharacter;
                    }
                },
            }
        }

        return tokens.items;
    }

    pub fn init(alloc: std.mem.Allocator, text: []const u8) Lexer {
        var l = Lexer{ .alloc = alloc, .text = text };
        l.advance();
        return l;
    }
};
