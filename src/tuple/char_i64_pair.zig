// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Immutable pair of (`u21`, `i64`).
pub const CharI64Pair = struct {
    first: u21,
    second: i64,

    pub fn new(first: u21, second: i64) CharI64Pair {
        return .{ .first = first, .second = second };
    }

    pub fn one(self: CharI64Pair) u21 {
        return self.first;
    }

    pub fn two(self: CharI64Pair) i64 {
        return self.second;
    }

    pub fn swap(self: CharI64Pair) I64CharPair {
        return .{ .first = self.second, .second = self.first };
    }

    pub fn eql(self: CharI64Pair, other: CharI64Pair) bool {
        return (self.first == other.first) and (self.second == other.second);
    }

    pub fn format(self: CharI64Pair, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "({}, {})", .{ self.first, self.second });
    }
};

const I64CharPair = @import("i64_char_pair.zig").I64CharPair;

test "CharI64Pair: one and two" {
    const p = CharI64Pair.new('a', 2);
    try std.testing.expectEqual('a', p.one());
    try std.testing.expectEqual(2, p.two());
}

test "CharI64Pair: eql" {
    const p1 = CharI64Pair.new('a', 2);
    const p2 = CharI64Pair.new('a', 2);
    const p3 = CharI64Pair.new('b', 1);
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}
