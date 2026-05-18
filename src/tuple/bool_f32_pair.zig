
const std = @import("std");

/// Immutable pair of (`bool`, `f32`).
pub const BoolF32Pair = struct {
    first: bool,
    second: f32,

    pub fn new(first: bool, second: f32) BoolF32Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: BoolF32Pair) bool {
        return self.first;
    }

    pub fn two(self: BoolF32Pair) f32 {
        return self.second;
    }

    pub fn swap(self: BoolF32Pair) F32BoolPair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: BoolF32Pair, other: BoolF32Pair) bool {
        return (self.first == other.first) and (@as(u32, @bitCast(self.second)) == @as(u32, @bitCast(other.second)));
    }

    pub fn format(self: BoolF32Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const F32BoolPair = @import("f32_bool_pair.zig").F32BoolPair;

test "BoolF32Pair: one and two" {
    const p = BoolF32Pair.new(true, 2.0);
    try std.testing.expectEqual(true, p.one());
    try std.testing.expectEqual(2.0, p.two());
}

test "BoolF32Pair: eql" {
    const p1 = BoolF32Pair.new(true, 2.0);
    const p2 = BoolF32Pair.new(true, 2.0);
    const p3 = BoolF32Pair.new(false, 1.0);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
