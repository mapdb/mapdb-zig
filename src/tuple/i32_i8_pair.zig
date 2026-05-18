// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Immutable pair of (`i32`, `i8`).
pub const I32I8Pair = struct {
    first: i32,
    second: i8,

    pub fn new(first: i32, second: i8) I32I8Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: I32I8Pair) i32 {
        return self.first;
    }

    pub fn two(self: I32I8Pair) i8 {
        return self.second;
    }

    pub fn swap(self: I32I8Pair) I8I32Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: I32I8Pair, other: I32I8Pair) bool {
        return (self.first == other.first) and (self.second == other.second);
    }

    pub fn format(self: I32I8Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const I8I32Pair = @import("i8_i32_pair.zig").I8I32Pair;

test "I32I8Pair: one and two" {
    const p = I32I8Pair.new(1, 2);
    try std.testing.expectEqual(1, p.one());
    try std.testing.expectEqual(2, p.two());
}

test "I32I8Pair: eql" {
    const p1 = I32I8Pair.new(1, 2);
    const p2 = I32I8Pair.new(1, 2);
    const p3 = I32I8Pair.new(2, 1);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
