// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Immutable pair of (`u21`, `i16`).
pub const CharI16Pair = struct {
    first: u21,
    second: i16,

    pub fn new(first: u21, second: i16) CharI16Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: CharI16Pair) u21 {
        return self.first;
    }

    pub fn two(self: CharI16Pair) i16 {
        return self.second;
    }

    pub fn swap(self: CharI16Pair) I16CharPair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: CharI16Pair, other: CharI16Pair) bool {
        return (self.first == other.first) and (self.second == other.second);
    }

    pub fn format(self: CharI16Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const I16CharPair = @import("i16_char_pair.zig").I16CharPair;

test "CharI16Pair: one and two" {
    const p = CharI16Pair.new('a', 2);
    try std.testing.expectEqual('a', p.one());
    try std.testing.expectEqual(2, p.two());
}

test "CharI16Pair: eql" {
    const p1 = CharI16Pair.new('a', 2);
    const p2 = CharI16Pair.new('a', 2);
    const p3 = CharI16Pair.new('b', 1);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
