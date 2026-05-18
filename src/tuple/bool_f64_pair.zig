
const std = @import("std");

/// Immutable pair of (`bool`, `f64`).
pub const BoolF64Pair = struct {
    first: bool,
    second: f64,

    pub fn new(first: bool, second: f64) BoolF64Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: BoolF64Pair) bool {
        return self.first;
    }

    pub fn two(self: BoolF64Pair) f64 {
        return self.second;
    }

    pub fn swap(self: BoolF64Pair) F64BoolPair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: BoolF64Pair, other: BoolF64Pair) bool {
        return (self.first == other.first) and (@as(u64, @bitCast(self.second)) == @as(u64, @bitCast(other.second)));
    }

    pub fn format(self: BoolF64Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const F64BoolPair = @import("f64_bool_pair.zig").F64BoolPair;

test "BoolF64Pair: one and two" {
    const p = BoolF64Pair.new(true, 2.0);
    try std.testing.expectEqual(true, p.one());
    try std.testing.expectEqual(2.0, p.two());
}

test "BoolF64Pair: eql" {
    const p1 = BoolF64Pair.new(true, 2.0);
    const p2 = BoolF64Pair.new(true, 2.0);
    const p3 = BoolF64Pair.new(false, 1.0);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
