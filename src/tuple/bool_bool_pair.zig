
const std = @import("std");

/// Immutable pair of (`bool`, `bool`).
pub const BoolBoolPair = struct {
    first: bool,
    second: bool,

    pub fn new(first: bool, second: bool) BoolBoolPair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: BoolBoolPair) bool {
        return self.first;
    }

    pub fn two(self: BoolBoolPair) bool {
        return self.second;
    }

    pub fn swap(self: BoolBoolPair) BoolBoolPair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: BoolBoolPair, other: BoolBoolPair) bool {
        return (self.first == other.first) and (self.second == other.second);
    }

    pub fn format(self: BoolBoolPair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

// Self-pair: swap returns same type

test "BoolBoolPair: one and two" {
    const p = BoolBoolPair.new(true, false);
    try std.testing.expectEqual(true, p.one());
    try std.testing.expectEqual(false, p.two());
}

test "BoolBoolPair: eql" {
    const p1 = BoolBoolPair.new(true, false);
    const p2 = BoolBoolPair.new(true, false);
    const p3 = BoolBoolPair.new(false, true);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
