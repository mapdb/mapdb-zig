// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Immutable pair of (`i64`, `bool`).
pub const I64BoolPair = struct {
    first: i64,
    second: bool,

    pub fn new(first: i64, second: bool) I64BoolPair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: I64BoolPair) i64 {
        return self.first;
    }

    pub fn two(self: I64BoolPair) bool {
        return self.second;
    }

    pub fn swap(self: I64BoolPair) BoolI64Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: I64BoolPair, other: I64BoolPair) bool {
        return (self.first == other.first) and (self.second == other.second);
    }

    pub fn format(self: I64BoolPair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const BoolI64Pair = @import("bool_i64_pair.zig").BoolI64Pair;

test "I64BoolPair: one and two" {
    const p = I64BoolPair.new(1, false);
    try std.testing.expectEqual(1, p.one());
    try std.testing.expectEqual(false, p.two());
}

test "I64BoolPair: eql" {
    const p1 = I64BoolPair.new(1, false);
    const p2 = I64BoolPair.new(1, false);
    const p3 = I64BoolPair.new(2, true);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
