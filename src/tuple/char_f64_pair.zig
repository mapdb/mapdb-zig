
const std = @import("std");

/// Immutable pair of (`u21`, `f64`).
pub const CharF64Pair = struct {
    first: u21,
    second: f64,

    pub fn new(first: u21, second: f64) CharF64Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: CharF64Pair) u21 {
        return self.first;
    }

    pub fn two(self: CharF64Pair) f64 {
        return self.second;
    }

    pub fn swap(self: CharF64Pair) F64CharPair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: CharF64Pair, other: CharF64Pair) bool {
        return (self.first == other.first) and (@as(u64, @bitCast(self.second)) == @as(u64, @bitCast(other.second)));
    }

    pub fn format(self: CharF64Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const F64CharPair = @import("f64_char_pair.zig").F64CharPair;

test "CharF64Pair: one and two" {
    const p = CharF64Pair.new('a', 2.0);
    try std.testing.expectEqual('a', p.one());
    try std.testing.expectEqual(2.0, p.two());
}

test "CharF64Pair: eql" {
    const p1 = CharF64Pair.new('a', 2.0);
    const p2 = CharF64Pair.new('a', 2.0);
    const p3 = CharF64Pair.new('b', 1.0);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
