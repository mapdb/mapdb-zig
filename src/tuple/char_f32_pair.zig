// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Immutable pair of (`u21`, `f32`).
pub const CharF32Pair = struct {
    first: u21,
    second: f32,

    pub fn new(first: u21, second: f32) CharF32Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: CharF32Pair) u21 {
        return self.first;
    }

    pub fn two(self: CharF32Pair) f32 {
        return self.second;
    }

    pub fn swap(self: CharF32Pair) F32CharPair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: CharF32Pair, other: CharF32Pair) bool {
        return (self.first == other.first) and (@as(u32, @bitCast(self.second)) == @as(u32, @bitCast(other.second)));
    }

    pub fn format(self: CharF32Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const F32CharPair = @import("f32_char_pair.zig").F32CharPair;

test "CharF32Pair: one and two" {
    const p = CharF32Pair.new('a', 2.0);
    try std.testing.expectEqual('a', p.one());
    try std.testing.expectEqual(2.0, p.two());
}

test "CharF32Pair: eql" {
    const p1 = CharF32Pair.new('a', 2.0);
    const p2 = CharF32Pair.new('a', 2.0);
    const p3 = CharF32Pair.new('b', 1.0);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
