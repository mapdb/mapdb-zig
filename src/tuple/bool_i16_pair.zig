// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Immutable pair of (`bool`, `i16`).
pub const BoolI16Pair = struct {
    first: bool,
    second: i16,

    pub fn new(first: bool, second: i16) BoolI16Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: BoolI16Pair) bool {
        return self.first;
    }

    pub fn two(self: BoolI16Pair) i16 {
        return self.second;
    }

    pub fn swap(self: BoolI16Pair) I16BoolPair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: BoolI16Pair, other: BoolI16Pair) bool {
        return (self.first == other.first) and (self.second == other.second);
    }

    pub fn format(self: BoolI16Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const I16BoolPair = @import("i16_bool_pair.zig").I16BoolPair;

test "BoolI16Pair: one and two" {
    const p = BoolI16Pair.new(true, 2);
    try std.testing.expectEqual(true, p.one());
    try std.testing.expectEqual(2, p.two());
}

test "BoolI16Pair: eql" {
    const p1 = BoolI16Pair.new(true, 2);
    const p2 = BoolI16Pair.new(true, 2);
    const p3 = BoolI16Pair.new(false, 1);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
