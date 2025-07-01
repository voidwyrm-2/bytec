const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;

const Self = @This();

pub const LexerError = error{
    IllegalCharacter,
    UnterminatedStringLiteral,
    InvalidEscapeCharacter,
};

pub const TokenType = enum {
    none,
    number,
    string,
    paren_open,
    paren_close,

    pub fn fromChar(ch: u8) ?TokenType {
        return switch (ch) {
            '(' => .paren_open,
            ')' => .paren_close,
            else => null,
        };
    }
};

pub const Token = struct {
    kind: TokenType,
    lit: []const u8,
    col: usize,
    ln: usize,

    pub fn init(kind: TokenType, lit: []const u8, col: usize, ln: usize) Token {
        return .{
            .kind = kind,
            .lit = lit,
            .col = col,
            .ln = ln,
        };
    }

    pub fn simple(kind: TokenType, lit: []const u8) Token {
        return Token.init(kind, lit, 0, 0);
    }

    pub fn errf(self: Token, allocator: Allocator, comptime fmt: []const u8, args: anytype) ![]const u8 {
        const msg = try std.fmt.allocPrint(allocator, fmt, args);

        return try std.fmt.allocPrint(allocator, "Error on line {d}, col {d}: {s}", .{ self.ln, self.col, msg });
    }

    pub fn str(self: Token, allocator: Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "<{any}, `{s}`, {d}, {d}>", .{ self.kind, self.lit, self.col, self.ln });
    }
};

const string_delimiter = '"';

parent_allocator: Allocator,
arena: *ArenaAllocator,
allocator: Allocator,
text: []const u8,
err_string: []const u8 = "",
ch: ?u8,
idx: usize = 0,
col: usize = 1,
ln: usize = 1,

fn isNumber(ch: u8) bool {
    return ch >= '0' and '9' >= ch;
}

fn isIdent(ch: u8) bool {
    return (ch >= 'a' and 'z' >= ch) or (ch >= 'A' and 'Z' >= ch) or isNumber(ch) or ch == '_';
}

pub fn init(allocator: Allocator, text: []const u8) !Self {
    var l: Self = .{
        .parent_allocator = allocator,
        .arena = try allocator.create(ArenaAllocator),
        .allocator = undefined,
        .text = text,
        .ch = if (text.len > 0) text[0] else null,
    };

    l.arena.* = ArenaAllocator.init(allocator);
    l.allocator = l.arena.allocator();

    return l;
}

pub fn deinit(self: *Self) void {
    _ = self.arena.reset(.free_all);
    self.parent_allocator.destroy(self.arena);
}

fn errf(self: *Self, comptime fmt: []const u8, args: anytype) !void {
    const token = Token.init(.none, "", self.col, self.ln);
    self.err_string = try token.errf(self.allocator, fmt, args);
}

fn err(self: *Self, str: []const u8) void {
    self.err_string = str;
}

fn advance(self: *Self) void {
    self.idx += 1;
    self.col += 1;

    self.ch = if (self.idx < self.text.len) self.text[self.idx] else null;

    if (self.ch) |ch| {
        if (ch == '\n') {
            self.ln += 1;
            self.col = 0;
        }
    }
}

fn skipComment(self: *Self) void {
    while (self.ch != null and self.ch != '\n') {
        self.advance();
    }
}

fn collectString(self: *Self) !Token {
    const start = self.col;
    const startln = self.ln;
    var lit = ArrayList(u8).init(self.allocator);

    var escaped = false;

    self.advance();

    while (self.ch) |ch| {
        if (ch == '\n') {
            break;
        } else if (escaped) {
            const char = switch (ch) {
                '\\', '\'', '"' => ch,
                'n' => '\n',
                't' => '\t',
                'a' => 7,
                '0' => 0,
                else => {
                    try self.errf("invalid escape character '{c}'", .{ch});
                    return error.InvalidEscapeCharacter;
                },
            };

            try lit.append(char);
            escaped = false;
        } else if (ch == '\\') {
            escaped = true;
        } else if (ch == string_delimiter) {
            break;
        } else {
            try lit.append(ch);
        }
        self.advance();
    }

    if (self.ch != string_delimiter) {
        const token = Token.init(.number, "", start, startln);
        self.err_string = try token.errf(self.allocator, "unterminated string literal", .{});
        return error.UnterminatedStringLiteral;
    }

    self.advance();

    return Token.init(.string, lit.items, start, startln);
}

fn collectNumber(self: *Self) !Token {
    const start = self.col;
    const startln = self.ln;
    var lit = ArrayList(u8).init(self.allocator);

    while (self.ch) |ch| {
        if (!Self.isNumber(ch))
            break;

        try lit.append(ch);

        self.advance();
    }

    return Token.init(.number, lit.items, start, startln);
}

fn collectIdent(self: *Self, kind: TokenType) !Token {
    const start = self.col;
    const startln = self.ln;
    var lit = ArrayList(u8).init(self.allocator);

    while (self.ch) |ch| {
        if (!Self.isIdent(ch))
            break;

        try lit.append(ch);

        self.advance();
    }

    return Token.init(kind, lit.items, start, startln);
}

pub fn lex(self: *Self) ![]Token {
    var tokens = ArrayList(Token).init(self.allocator);

    while (self.ch) |ch| {
        switch (ch) {
            ' ', '\t', '\n' => self.advance(),
            '#' => self.skipComment(),
            string_delimiter => try tokens.append(try self.collectString()),
            else => if (TokenType.fromChar(ch)) |kind| {
                try tokens.append(Token.init(kind, "", self.col, self.ln));
                self.advance();
            } else if (isNumber(ch)) {
                try tokens.append(try self.collectNumber());
            } else {
                try self.errf("illegal character '{c}'", .{ch});
                return error.IllegalCharacter;
            },
        }
    }

    return tokens.items;
}
