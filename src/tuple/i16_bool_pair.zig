// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Immutable pair of (`i16`, `bool`).
pub const I16BoolPair = struct {
    first: i16,
    second: bool,

    pub fn new(first: i16, second: bool) I16BoolPair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: I16BoolPair) i16 {
        return self.first;
    }

    pub fn two(self: I16BoolPair) bool {
        return self.second;
    }

    pub fn swap(self: I16BoolPair) BoolI16Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: I16BoolPair, other: I16BoolPair) bool {
        return (self.first == other.first) and (self.second == other.second);
    }

    pub fn format(self: I16BoolPair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const BoolI16Pair = @import("bool_i16_pair.zig").BoolI16Pair;

test "I16BoolPair: one and two" {
    const p = I16BoolPair.new(1, false);
    try std.testing.expectEqual(1, p.one());
    try std.testing.expectEqual(false, p.two());
}

test "I16BoolPair: eql" {
    const p1 = I16BoolPair.new(1, false);
    const p2 = I16BoolPair.new(1, false);
    const p3 = I16BoolPair.new(2, true);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
