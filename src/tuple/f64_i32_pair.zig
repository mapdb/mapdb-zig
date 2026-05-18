
const std = @import("std");

/// Immutable pair of (`f64`, `i32`).
pub const F64I32Pair = struct {
    first: f64,
    second: i32,

    pub fn new(first: f64, second: i32) F64I32Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: F64I32Pair) f64 {
        return self.first;
    }

    pub fn two(self: F64I32Pair) i32 {
        return self.second;
    }

    pub fn swap(self: F64I32Pair) I32F64Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: F64I32Pair, other: F64I32Pair) bool {
        return (@as(u64, @bitCast(self.first)) == @as(u64, @bitCast(other.first))) and (self.second == other.second);
    }

    pub fn format(self: F64I32Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const I32F64Pair = @import("i32_f64_pair.zig").I32F64Pair;

test "F64I32Pair: one and two" {
    const p = F64I32Pair.new(1.0, 2);
    try std.testing.expectEqual(1.0, p.one());
    try std.testing.expectEqual(2, p.two());
}

test "F64I32Pair: eql" {
    const p1 = F64I32Pair.new(1.0, 2);
    const p2 = F64I32Pair.new(1.0, 2);
    const p3 = F64I32Pair.new(2.0, 1);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
