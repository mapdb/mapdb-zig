// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Immutable pair of (`u21`, `u21`).
pub const CharCharPair = struct {
    first: u21,
    second: u21,

    pub fn new(first: u21, second: u21) CharCharPair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: CharCharPair) u21 {
        return self.first;
    }

    pub fn two(self: CharCharPair) u21 {
        return self.second;
    }

    pub fn swap(self: CharCharPair) CharCharPair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: CharCharPair, other: CharCharPair) bool {
        return (self.first == other.first) and (self.second == other.second);
    }

    pub fn format(self: CharCharPair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

// Self-pair: swap returns same type

test "CharCharPair: one and two" {
    const p = CharCharPair.new('a', 'b');
    try std.testing.expectEqual('a', p.one());
    try std.testing.expectEqual('b', p.two());
}

test "CharCharPair: eql" {
    const p1 = CharCharPair.new('a', 'b');
    const p2 = CharCharPair.new('a', 'b');
    const p3 = CharCharPair.new('b', 'a');
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
