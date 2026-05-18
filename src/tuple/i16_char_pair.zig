
const std = @import("std");

/// Immutable pair of (`i16`, `u21`).
pub const I16CharPair = struct {
    first: i16,
    second: u21,

    pub fn new(first: i16, second: u21) I16CharPair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: I16CharPair) i16 {
        return self.first;
    }

    pub fn two(self: I16CharPair) u21 {
        return self.second;
    }

    pub fn swap(self: I16CharPair) CharI16Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: I16CharPair, other: I16CharPair) bool {
        return (self.first == other.first) and (self.second == other.second);
    }

    pub fn format(self: I16CharPair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const CharI16Pair = @import("char_i16_pair.zig").CharI16Pair;

test "I16CharPair: one and two" {
    const p = I16CharPair.new(1, 'b');
    try std.testing.expectEqual(1, p.one());
    try std.testing.expectEqual('b', p.two());
}

test "I16CharPair: eql" {
    const p1 = I16CharPair.new(1, 'b');
    const p2 = I16CharPair.new(1, 'b');
    const p3 = I16CharPair.new(2, 'a');
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
