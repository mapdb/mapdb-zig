
const std = @import("std");

/// Immutable pair of (`f64`, `u21`).
pub const F64CharPair = struct {
    first: f64,
    second: u21,

    pub fn new(first: f64, second: u21) F64CharPair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: F64CharPair) f64 {
        return self.first;
    }

    pub fn two(self: F64CharPair) u21 {
        return self.second;
    }

    pub fn swap(self: F64CharPair) CharF64Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: F64CharPair, other: F64CharPair) bool {
        return (@as(u64, @bitCast(self.first)) == @as(u64, @bitCast(other.first))) and (self.second == other.second);
    }

    pub fn format(self: F64CharPair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const CharF64Pair = @import("char_f64_pair.zig").CharF64Pair;

test "F64CharPair: one and two" {
    const p = F64CharPair.new(1.0, 'b');
    try std.testing.expectEqual(1.0, p.one());
    try std.testing.expectEqual('b', p.two());
}

test "F64CharPair: eql" {
    const p1 = F64CharPair.new(1.0, 'b');
    const p2 = F64CharPair.new(1.0, 'b');
    const p3 = F64CharPair.new(2.0, 'a');
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
