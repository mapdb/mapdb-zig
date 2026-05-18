// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Immutable pair of (`i64`, `i16`).
pub const I64I16Pair = struct {
    first: i64,
    second: i16,

    pub fn new(first: i64, second: i16) I64I16Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: I64I16Pair) i64 {
        return self.first;
    }

    pub fn two(self: I64I16Pair) i16 {
        return self.second;
    }

    pub fn swap(self: I64I16Pair) I16I64Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: I64I16Pair, other: I64I16Pair) bool {
        return (self.first == other.first) and (self.second == other.second);
    }

    pub fn format(self: I64I16Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const I16I64Pair = @import("i16_i64_pair.zig").I16I64Pair;

test "I64I16Pair: one and two" {
    const p = I64I16Pair.new(1, 2);
    try std.testing.expectEqual(1, p.one());
    try std.testing.expectEqual(2, p.two());
}

test "I64I16Pair: eql" {
    const p1 = I64I16Pair.new(1, 2);
    const p2 = I64I16Pair.new(1, 2);
    const p3 = I64I16Pair.new(2, 1);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
