// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Immutable pair of (`f32`, `i16`).
pub const F32I16Pair = struct {
    first: f32,
    second: i16,

    pub fn new(first: f32, second: i16) F32I16Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: F32I16Pair) f32 {
        return self.first;
    }

    pub fn two(self: F32I16Pair) i16 {
        return self.second;
    }

    pub fn swap(self: F32I16Pair) I16F32Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: F32I16Pair, other: F32I16Pair) bool {
        return (@as(u32, @bitCast(self.first)) == @as(u32, @bitCast(other.first))) and (self.second == other.second);
    }

    pub fn format(self: F32I16Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const I16F32Pair = @import("i16_f32_pair.zig").I16F32Pair;

test "F32I16Pair: one and two" {
    const p = F32I16Pair.new(1.0, 2);
    try std.testing.expectEqual(1.0, p.one());
    try std.testing.expectEqual(2, p.two());
}

test "F32I16Pair: eql" {
    const p1 = F32I16Pair.new(1.0, 2);
    const p2 = F32I16Pair.new(1.0, 2);
    const p3 = F32I16Pair.new(2.0, 1);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
