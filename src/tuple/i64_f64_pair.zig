
const std = @import("std");

/// Immutable pair of (`i64`, `f64`).
pub const I64F64Pair = struct {
    first: i64,
    second: f64,

    pub fn new(first: i64, second: f64) I64F64Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: I64F64Pair) i64 {
        return self.first;
    }

    pub fn two(self: I64F64Pair) f64 {
        return self.second;
    }

    pub fn swap(self: I64F64Pair) F64I64Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: I64F64Pair, other: I64F64Pair) bool {
        return (self.first == other.first) and (@as(u64, @bitCast(self.second)) == @as(u64, @bitCast(other.second)));
    }

    pub fn format(self: I64F64Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const F64I64Pair = @import("f64_i64_pair.zig").F64I64Pair;

test "I64F64Pair: one and two" {
    const p = I64F64Pair.new(1, 2.0);
    try std.testing.expectEqual(1, p.one());
    try std.testing.expectEqual(2.0, p.two());
}

test "I64F64Pair: eql" {
    const p1 = I64F64Pair.new(1, 2.0);
    const p2 = I64F64Pair.new(1, 2.0);
    const p3 = I64F64Pair.new(2, 1.0);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
