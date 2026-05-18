
const std = @import("std");

/// Immutable pair of (`i16`, `f32`).
pub const I16F32Pair = struct {
    first: i16,
    second: f32,

    pub fn new(first: i16, second: f32) I16F32Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: I16F32Pair) i16 {
        return self.first;
    }

    pub fn two(self: I16F32Pair) f32 {
        return self.second;
    }

    pub fn swap(self: I16F32Pair) F32I16Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: I16F32Pair, other: I16F32Pair) bool {
        return (self.first == other.first) and (@as(u32, @bitCast(self.second)) == @as(u32, @bitCast(other.second)));
    }

    pub fn format(self: I16F32Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const F32I16Pair = @import("f32_i16_pair.zig").F32I16Pair;

test "I16F32Pair: one and two" {
    const p = I16F32Pair.new(1, 2.0);
    try std.testing.expectEqual(1, p.one());
    try std.testing.expectEqual(2.0, p.two());
}

test "I16F32Pair: eql" {
    const p1 = I16F32Pair.new(1, 2.0);
    const p2 = I16F32Pair.new(1, 2.0);
    const p3 = I16F32Pair.new(2, 1.0);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
