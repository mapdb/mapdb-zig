
const std = @import("std");

/// Immutable pair of (`i16`, `i64`).
pub const I16I64Pair = struct {
    first: i16,
    second: i64,

    pub fn new(first: i16, second: i64) I16I64Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: I16I64Pair) i16 {
        return self.first;
    }

    pub fn two(self: I16I64Pair) i64 {
        return self.second;
    }

    pub fn swap(self: I16I64Pair) I64I16Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: I16I64Pair, other: I16I64Pair) bool {
        return (self.first == other.first) and (self.second == other.second);
    }

    pub fn format(self: I16I64Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const I64I16Pair = @import("i64_i16_pair.zig").I64I16Pair;

test "I16I64Pair: one and two" {
    const p = I16I64Pair.new(1, 2);
    try std.testing.expectEqual(1, p.one());
    try std.testing.expectEqual(2, p.two());
}

test "I16I64Pair: eql" {
    const p1 = I16I64Pair.new(1, 2);
    const p2 = I16I64Pair.new(1, 2);
    const p3 = I16I64Pair.new(2, 1);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
