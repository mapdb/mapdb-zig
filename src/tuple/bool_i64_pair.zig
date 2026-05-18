// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Immutable pair of (`bool`, `i64`).
pub const BoolI64Pair = struct {
    first: bool,
    second: i64,

    pub fn new(first: bool, second: i64) BoolI64Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: BoolI64Pair) bool {
        return self.first;
    }

    pub fn two(self: BoolI64Pair) i64 {
        return self.second;
    }

    pub fn swap(self: BoolI64Pair) I64BoolPair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: BoolI64Pair, other: BoolI64Pair) bool {
        return (self.first == other.first) and (self.second == other.second);
    }

    pub fn format(self: BoolI64Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const I64BoolPair = @import("i64_bool_pair.zig").I64BoolPair;

test "BoolI64Pair: one and two" {
    const p = BoolI64Pair.new(true, 2);
    try std.testing.expectEqual(true, p.one());
    try std.testing.expectEqual(2, p.two());
}

test "BoolI64Pair: eql" {
    const p1 = BoolI64Pair.new(true, 2);
    const p2 = BoolI64Pair.new(true, 2);
    const p3 = BoolI64Pair.new(false, 1);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
