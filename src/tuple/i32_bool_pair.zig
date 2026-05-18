// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Immutable pair of (`i32`, `bool`).
pub const I32BoolPair = struct {
    first: i32,
    second: bool,

    pub fn new(first: i32, second: bool) I32BoolPair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: I32BoolPair) i32 {
        return self.first;
    }

    pub fn two(self: I32BoolPair) bool {
        return self.second;
    }

    pub fn swap(self: I32BoolPair) BoolI32Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: I32BoolPair, other: I32BoolPair) bool {
        return (self.first == other.first) and (self.second == other.second);
    }

    pub fn format(self: I32BoolPair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const BoolI32Pair = @import("bool_i32_pair.zig").BoolI32Pair;

test "I32BoolPair: one and two" {
    const p = I32BoolPair.new(1, false);
    try std.testing.expectEqual(1, p.one());
    try std.testing.expectEqual(false, p.two());
}

test "I32BoolPair: eql" {
    const p1 = I32BoolPair.new(1, false);
    const p2 = I32BoolPair.new(1, false);
    const p3 = I32BoolPair.new(2, true);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
