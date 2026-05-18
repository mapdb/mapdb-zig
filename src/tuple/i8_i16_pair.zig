// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Immutable pair of (`i8`, `i16`).
pub const I8I16Pair = struct {
    first: i8,
    second: i16,

    pub fn new(first: i8, second: i16) I8I16Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: I8I16Pair) i8 {
        return self.first;
    }

    pub fn two(self: I8I16Pair) i16 {
        return self.second;
    }

    pub fn swap(self: I8I16Pair) I16I8Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: I8I16Pair, other: I8I16Pair) bool {
        return (self.first == other.first) and (self.second == other.second);
    }

    pub fn format(self: I8I16Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const I16I8Pair = @import("i16_i8_pair.zig").I16I8Pair;

test "I8I16Pair: one and two" {
    const p = I8I16Pair.new(1, 2);
    try std.testing.expectEqual(1, p.one());
    try std.testing.expectEqual(2, p.two());
}

test "I8I16Pair: eql" {
    const p1 = I8I16Pair.new(1, 2);
    const p2 = I8I16Pair.new(1, 2);
    const p3 = I8I16Pair.new(2, 1);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
