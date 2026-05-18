// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Immutable pair of (`i32`, `i16`).
pub const I32I16Pair = struct {
    first: i32,
    second: i16,

    pub fn new(first: i32, second: i16) I32I16Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: I32I16Pair) i32 {
        return self.first;
    }

    pub fn two(self: I32I16Pair) i16 {
        return self.second;
    }

    pub fn swap(self: I32I16Pair) I16I32Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: I32I16Pair, other: I32I16Pair) bool {
        return (self.first == other.first) and (self.second == other.second);
    }

    pub fn format(self: I32I16Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const I16I32Pair = @import("i16_i32_pair.zig").I16I32Pair;

test "I32I16Pair: one and two" {
    const p = I32I16Pair.new(1, 2);
    try std.testing.expectEqual(1, p.one());
    try std.testing.expectEqual(2, p.two());
}

test "I32I16Pair: eql" {
    const p1 = I32I16Pair.new(1, 2);
    const p2 = I32I16Pair.new(1, 2);
    const p3 = I32I16Pair.new(2, 1);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
