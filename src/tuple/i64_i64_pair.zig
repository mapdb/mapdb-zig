// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Immutable pair of (`i64`, `i64`).
pub const I64I64Pair = struct {
    first: i64,
    second: i64,

    pub fn new(first: i64, second: i64) I64I64Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: I64I64Pair) i64 {
        return self.first;
    }

    pub fn two(self: I64I64Pair) i64 {
        return self.second;
    }

    pub fn swap(self: I64I64Pair) I64I64Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: I64I64Pair, other: I64I64Pair) bool {
        return (self.first == other.first) and (self.second == other.second);
    }

    pub fn format(self: I64I64Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

// Self-pair: swap returns same type

test "I64I64Pair: one and two" {
    const p = I64I64Pair.new(1, 2);
    try std.testing.expectEqual(1, p.one());
    try std.testing.expectEqual(2, p.two());
}

test "I64I64Pair: eql" {
    const p1 = I64I64Pair.new(1, 2);
    const p2 = I64I64Pair.new(1, 2);
    const p3 = I64I64Pair.new(2, 1);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
