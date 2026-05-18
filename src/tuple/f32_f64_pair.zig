// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Immutable pair of (`f32`, `f64`).
pub const F32F64Pair = struct {
    first: f32,
    second: f64,

    pub fn new(first: f32, second: f64) F32F64Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: F32F64Pair) f32 {
        return self.first;
    }

    pub fn two(self: F32F64Pair) f64 {
        return self.second;
    }

    pub fn swap(self: F32F64Pair) F64F32Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: F32F64Pair, other: F32F64Pair) bool {
        return (@as(u32, @bitCast(self.first)) == @as(u32, @bitCast(other.first))) and (@as(u64, @bitCast(self.second)) == @as(u64, @bitCast(other.second)));
    }

    pub fn format(self: F32F64Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const F64F32Pair = @import("f64_f32_pair.zig").F64F32Pair;

test "F32F64Pair: one and two" {
    const p = F32F64Pair.new(1.0, 2.0);
    try std.testing.expectEqual(1.0, p.one());
    try std.testing.expectEqual(2.0, p.two());
}

test "F32F64Pair: eql" {
    const p1 = F32F64Pair.new(1.0, 2.0);
    const p2 = F32F64Pair.new(1.0, 2.0);
    const p3 = F32F64Pair.new(2.0, 1.0);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
