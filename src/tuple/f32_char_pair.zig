// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Immutable pair of (`f32`, `u21`).
pub const F32CharPair = struct {
    first: f32,
    second: u21,

    pub fn new(first: f32, second: u21) F32CharPair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: F32CharPair) f32 {
        return self.first;
    }

    pub fn two(self: F32CharPair) u21 {
        return self.second;
    }

    pub fn swap(self: F32CharPair) CharF32Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: F32CharPair, other: F32CharPair) bool {
        return (@as(u32, @bitCast(self.first)) == @as(u32, @bitCast(other.first))) and (self.second == other.second);
    }

    pub fn format(self: F32CharPair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const CharF32Pair = @import("char_f32_pair.zig").CharF32Pair;

test "F32CharPair: one and two" {
    const p = F32CharPair.new(1.0, 'b');
    try std.testing.expectEqual(1.0, p.one());
    try std.testing.expectEqual('b', p.two());
}

test "F32CharPair: eql" {
    const p1 = F32CharPair.new(1.0, 'b');
    const p2 = F32CharPair.new(1.0, 'b');
    const p3 = F32CharPair.new(2.0, 'a');
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
