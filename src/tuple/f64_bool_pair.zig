// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Immutable pair of (`f64`, `bool`).
pub const F64BoolPair = struct {
    first: f64,
    second: bool,

    pub fn new(first: f64, second: bool) F64BoolPair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: F64BoolPair) f64 {
        return self.first;
    }

    pub fn two(self: F64BoolPair) bool {
        return self.second;
    }

    pub fn swap(self: F64BoolPair) BoolF64Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: F64BoolPair, other: F64BoolPair) bool {
        return (@as(u64, @bitCast(self.first)) == @as(u64, @bitCast(other.first))) and (self.second == other.second);
    }

    pub fn format(self: F64BoolPair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const BoolF64Pair = @import("bool_f64_pair.zig").BoolF64Pair;

test "F64BoolPair: one and two" {
    const p = F64BoolPair.new(1.0, false);
    try std.testing.expectEqual(1.0, p.one());
    try std.testing.expectEqual(false, p.two());
}

test "F64BoolPair: eql" {
    const p1 = F64BoolPair.new(1.0, false);
    const p2 = F64BoolPair.new(1.0, false);
    const p3 = F64BoolPair.new(2.0, true);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
