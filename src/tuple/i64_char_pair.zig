// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Immutable pair of (`i64`, `u21`).
pub const I64CharPair = struct {
    first: i64,
    second: u21,

    pub fn new(first: i64, second: u21) I64CharPair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: I64CharPair) i64 {
        return self.first;
    }

    pub fn two(self: I64CharPair) u21 {
        return self.second;
    }

    pub fn swap(self: I64CharPair) CharI64Pair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: I64CharPair, other: I64CharPair) bool {
        return (self.first == other.first) and (self.second == other.second);
    }

    pub fn format(self: I64CharPair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const CharI64Pair = @import("char_i64_pair.zig").CharI64Pair;

test "I64CharPair: one and two" {
    const p = I64CharPair.new(1, 'b');
    try std.testing.expectEqual(1, p.one());
    try std.testing.expectEqual('b', p.two());
}

test "I64CharPair: eql" {
    const p1 = I64CharPair.new(1, 'b');
    const p2 = I64CharPair.new(1, 'b');
    const p3 = I64CharPair.new(2, 'a');
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
