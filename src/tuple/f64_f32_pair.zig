
const std = @import("std");

/// Immutable pair of (`f64`, `f32`).
pub const F64F32Pair = struct {
    first: f64,
    second: f32,

    pub fn new(first: f64, second: f32) F64F32Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: F64F32Pair) f64 {
        return self.first;
    }

    pub fn two(self: F64F32Pair) f32 {
        return self.second;
    }

    pub fn swap(self: F64F32Pair) F32F64Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: F64F32Pair, other: F64F32Pair) bool {
        return (@as(u64, @bitCast(self.first)) == @as(u64, @bitCast(other.first))) and (@as(u32, @bitCast(self.second)) == @as(u32, @bitCast(other.second)));
    }

    pub fn format(self: F64F32Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const F32F64Pair = @import("f32_f64_pair.zig").F32F64Pair;

test "F64F32Pair: one and two" {
    const p = F64F32Pair.new(1.0, 2.0);
    try std.testing.expectEqual(1.0, p.one());
    try std.testing.expectEqual(2.0, p.two());
}

test "F64F32Pair: eql" {
    const p1 = F64F32Pair.new(1.0, 2.0);
    const p2 = F64F32Pair.new(1.0, 2.0);
    const p3 = F64F32Pair.new(2.0, 1.0);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
