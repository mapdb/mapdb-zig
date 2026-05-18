// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Immutable pair of (`i8`, `bool`).
pub const I8BoolPair = struct {
    first: i8,
    second: bool,

    pub fn new(first: i8, second: bool) I8BoolPair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: I8BoolPair) i8 {
        return self.first;
    }

    pub fn two(self: I8BoolPair) bool {
        return self.second;
    }

    pub fn swap(self: I8BoolPair) BoolI8Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: I8BoolPair, other: I8BoolPair) bool {
        return (self.first == other.first) and (self.second == other.second);
    }

    pub fn format(self: I8BoolPair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const BoolI8Pair = @import("bool_i8_pair.zig").BoolI8Pair;

test "I8BoolPair: one and two" {
    const p = I8BoolPair.new(1, false);
    try std.testing.expectEqual(1, p.one());
    try std.testing.expectEqual(false, p.two());
}

test "I8BoolPair: eql" {
    const p1 = I8BoolPair.new(1, false);
    const p2 = I8BoolPair.new(1, false);
    const p3 = I8BoolPair.new(2, true);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
