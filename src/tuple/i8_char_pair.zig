
const std = @import("std");

/// Immutable pair of (`i8`, `u21`).
pub const I8CharPair = struct {
    first: i8,
    second: u21,

    pub fn new(first: i8, second: u21) I8CharPair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: I8CharPair) i8 {
        return self.first;
    }

    pub fn two(self: I8CharPair) u21 {
        return self.second;
    }

    pub fn swap(self: I8CharPair) CharI8Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: I8CharPair, other: I8CharPair) bool {
        return (self.first == other.first) and (self.second == other.second);
    }

    pub fn format(self: I8CharPair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const CharI8Pair = @import("char_i8_pair.zig").CharI8Pair;

test "I8CharPair: one and two" {
    const p = I8CharPair.new(1, 'b');
    try std.testing.expectEqual(1, p.one());
    try std.testing.expectEqual('b', p.two());
}

test "I8CharPair: eql" {
    const p1 = I8CharPair.new(1, 'b');
    const p2 = I8CharPair.new(1, 'b');
    const p3 = I8CharPair.new(2, 'a');
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
