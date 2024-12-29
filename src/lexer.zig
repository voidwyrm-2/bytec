const std = @import("std");
const ArrayList = std.ArrayList;
const AllocatorError = std.mem.Allocator.Error;
const tokens_lib = @import("tokens.zig");
const Token = tokens_lib.Token;

const LexerError = error{ IllegalCharacter, UnterminatedString, InvalidEscapeCharacter } || AllocatorError;

pub const Lexer = struct {
    text: []const u8,
    idx: i64 = -1,
    col: u64 = 0,
    ln: usize = 0,
    cchar: ?u8 = null,
    alloc: std.mem.Allocator,
    fn advance(self: *Lexer) void {
        self.idx += 1;
        self.col += 1;
        if (self.idx < self.text.len) {
            self.cchar = self.text[@intCast(self.idx)];
        } else {
            self.cchar = null;
        }

        if (self.cchar == '\n') {
            self.ln += 1;
            self.col = 1;
        }
    }

    fn isNumber(ch: u8) bool {
        return ch >= '0' and ch <= '9';
    }

    fn collectNumber(self: *Lexer) LexerError!Token {
        const start: u32 = @intCast(self.col);
        const startln: u32 = @intCast(self.ln);
        var prevCol: u64 = 0;
        var str = ArrayList(u8).init(self.alloc);

        while (self.cchar != null and Lexer.isNumber(self.cchar.?)) {
            try str.append(self.cchar.?);
            prevCol = self.col;
            self.advance();
        }

        return Token.init(.Number, str.items, start, @intCast(if (self.col - 1 == 0) prevCol else self.col - 1), startln);
    }

    fn collectString(self: *Lexer) LexerError!Token {
        const start: u32 = @intCast(self.col);
        const startln: u32 = @intCast(self.ln);
        var str = ArrayList(u8).init(self.alloc);
        var escaped = false;

        self.advance();

        while (self.cchar != null and self.cchar != '"') {
            if (escaped) {
                try str.append(switch (self.cchar.?) {
                    '\\', '\'', '"' => self.cchar.?,
                    'n' => '\n',
                    't' => '\t',
                    'r' => '\r',
                    'v' => 11,
                    'f' => 12,
                    'a' => 7,
                    '0' => 0,
                    else => {
                        return error.InvalidEscapeCharacter;
                    },
                });
                escaped = false;
            } else if (self.cchar == '\\') {
                escaped = true;
            } else {
                try str.append(self.cchar.?);
            }
            self.advance();
        }

        if (self.cchar != '"') {
            self.col = start;
            self.ln = startln;
            return error.UnterminatedString;
        }

        self.advance();

        return Token.init(.String, str.items, start, @intCast(self.col - 1), startln);
    }

    pub fn getErrorMsg(self: Lexer, kind: LexerError) ![]u8 {
        const reason = switch (kind) {
            LexerError.IllegalCharacter => try std.fmt.allocPrint(self.alloc, "illegal character '{c}'", .{self.cchar.?}),
            LexerError.UnterminatedString => try std.fmt.allocPrint(self.alloc, "unterminated string literal", .{}),
            LexerError.InvalidEscapeCharacter => try std.fmt.allocPrint(self.alloc, "invalid escape sequence character '{c}'", .{self.cchar.?}),
            else => unreachable,
        };
        return try std.fmt.allocPrint(self.alloc, "error on line {d}, {d}: {s}", .{ self.ln, self.col, reason });
    }

    pub fn lex(self: *Lexer) LexerError![]Token {
        var tokens = ArrayList(Token).init(self.alloc);

        while (self.cchar != null) {
            switch (self.cchar.?) {
                ' ', '\n', '\t' => self.advance(),
                '#' => {
                    while (self.cchar != null and self.cchar != '\n') self.advance();
                },
                '(' => {
                    try tokens.append(Token.init(.OpParen, "(", @intCast(self.col), @intCast(self.col), @intCast(self.ln)));
                    self.advance();
                },
                ')' => {
                    try tokens.append(Token.init(.CloseParen, ")", @intCast(self.col), @intCast(self.col), @intCast(self.ln)));
                    self.advance();
                },
                '"' => try tokens.append(try self.collectString()),
                else => {
                    if (Lexer.isNumber(self.cchar.?)) {
                        try tokens.append(try self.collectNumber());
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
