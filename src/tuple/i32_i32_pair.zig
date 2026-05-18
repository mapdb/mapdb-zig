
const std = @import("std");

/// Immutable pair of (`i32`, `i32`).
pub const I32I32Pair = struct {
    first: i32,
    second: i32,

    pub fn new(first: i32, second: i32) I32I32Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: I32I32Pair) i32 {
        return self.first;
    }

    pub fn two(self: I32I32Pair) i32 {
        return self.second;
    }

    pub fn swap(self: I32I32Pair) I32I32Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: I32I32Pair, other: I32I32Pair) bool {
        return (self.first == other.first) and (self.second == other.second);
    }

    pub fn format(self: I32I32Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

// Self-pair: swap returns same type

test "I32I32Pair: one and two" {
    const p = I32I32Pair.new(1, 2);
    try std.testing.expectEqual(1, p.one());
    try std.testing.expectEqual(2, p.two());
}

test "I32I32Pair: eql" {
    const p1 = I32I32Pair.new(1, 2);
    const p2 = I32I32Pair.new(1, 2);
    const p3 = I32I32Pair.new(2, 1);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
