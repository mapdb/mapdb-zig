
const std = @import("std");

/// Immutable pair of (`i64`, `i8`).
pub const I64I8Pair = struct {
    first: i64,
    second: i8,

    pub fn new(first: i64, second: i8) I64I8Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: I64I8Pair) i64 {
        return self.first;
    }

    pub fn two(self: I64I8Pair) i8 {
        return self.second;
    }

    pub fn swap(self: I64I8Pair) I8I64Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: I64I8Pair, other: I64I8Pair) bool {
        return (self.first == other.first) and (self.second == other.second);
    }

    pub fn format(self: I64I8Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const I8I64Pair = @import("i8_i64_pair.zig").I8I64Pair;

test "I64I8Pair: one and two" {
    const p = I64I8Pair.new(1, 2);
    try std.testing.expectEqual(1, p.one());
    try std.testing.expectEqual(2, p.two());
}

test "I64I8Pair: eql" {
    const p1 = I64I8Pair.new(1, 2);
    const p2 = I64I8Pair.new(1, 2);
    const p3 = I64I8Pair.new(2, 1);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
