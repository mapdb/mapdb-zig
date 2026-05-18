
const std = @import("std");

/// Immutable pair of (`f32`, `i32`).
pub const F32I32Pair = struct {
    first: f32,
    second: i32,

    pub fn new(first: f32, second: i32) F32I32Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: F32I32Pair) f32 {
        return self.first;
    }

    pub fn two(self: F32I32Pair) i32 {
        return self.second;
    }

    pub fn swap(self: F32I32Pair) I32F32Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: F32I32Pair, other: F32I32Pair) bool {
        return (@as(u32, @bitCast(self.first)) == @as(u32, @bitCast(other.first))) and (self.second == other.second);
    }

    pub fn format(self: F32I32Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const I32F32Pair = @import("i32_f32_pair.zig").I32F32Pair;

test "F32I32Pair: one and two" {
    const p = F32I32Pair.new(1.0, 2);
    try std.testing.expectEqual(1.0, p.one());
    try std.testing.expectEqual(2, p.two());
}

test "F32I32Pair: eql" {
    const p1 = F32I32Pair.new(1.0, 2);
    const p2 = F32I32Pair.new(1.0, 2);
    const p3 = F32I32Pair.new(2.0, 1);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
