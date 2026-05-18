
const std = @import("std");

/// Immutable pair of (`f64`, `i64`).
pub const F64I64Pair = struct {
    first: f64,
    second: i64,

    pub fn new(first: f64, second: i64) F64I64Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: F64I64Pair) f64 {
        return self.first;
    }

    pub fn two(self: F64I64Pair) i64 {
        return self.second;
    }

    pub fn swap(self: F64I64Pair) I64F64Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: F64I64Pair, other: F64I64Pair) bool {
        return (@as(u64, @bitCast(self.first)) == @as(u64, @bitCast(other.first))) and (self.second == other.second);
    }

    pub fn format(self: F64I64Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const I64F64Pair = @import("i64_f64_pair.zig").I64F64Pair;

test "F64I64Pair: one and two" {
    const p = F64I64Pair.new(1.0, 2);
    try std.testing.expectEqual(1.0, p.one());
    try std.testing.expectEqual(2, p.two());
}

test "F64I64Pair: eql" {
    const p1 = F64I64Pair.new(1.0, 2);
    const p2 = F64I64Pair.new(1.0, 2);
    const p3 = F64I64Pair.new(2.0, 1);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
