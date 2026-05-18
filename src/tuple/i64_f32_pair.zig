// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Immutable pair of (`i64`, `f32`).
pub const I64F32Pair = struct {
    first: i64,
    second: f32,

    pub fn new(first: i64, second: f32) I64F32Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: I64F32Pair) i64 {
        return self.first;
    }

    pub fn two(self: I64F32Pair) f32 {
        return self.second;
    }

    pub fn swap(self: I64F32Pair) F32I64Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: I64F32Pair, other: I64F32Pair) bool {
        return (self.first == other.first) and (@as(u32, @bitCast(self.second)) == @as(u32, @bitCast(other.second)));
    }

    pub fn format(self: I64F32Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const F32I64Pair = @import("f32_i64_pair.zig").F32I64Pair;

test "I64F32Pair: one and two" {
    const p = I64F32Pair.new(1, 2.0);
    try std.testing.expectEqual(1, p.one());
    try std.testing.expectEqual(2.0, p.two());
}

test "I64F32Pair: eql" {
    const p1 = I64F32Pair.new(1, 2.0);
    const p2 = I64F32Pair.new(1, 2.0);
    const p3 = I64F32Pair.new(2, 1.0);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
