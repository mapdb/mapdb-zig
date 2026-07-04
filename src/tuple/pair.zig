// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

const std = @import("std");

/// Bit-aware equality for a pair member of type `T`.
///
/// Float members (`f32`/`f64`) compare by reinterpreting to the same-width
/// unsigned integer so that `-0.0`/`+0.0` stay distinct and NaN payloads
/// compare by exact bits — matching the original per-type wrappers, whose
/// float `eql` used `@as(uN, @bitCast(x)) == @as(uN, @bitCast(y))`. Non-float
/// members use plain `==`.
fn memberEql(comptime T: type, a: T, b: T) bool {
    return switch (@typeInfo(T)) {
        .float => switch (T) {
            f32 => @as(u32, @bitCast(a)) == @as(u32, @bitCast(b)),
            f64 => @as(u64, @bitCast(a)) == @as(u64, @bitCast(b)),
            else => @compileError("unsupported float member type: " ++ @typeName(T)),
        },
        else => a == b,
    };
}

/// Immutable pair of (`A`, `B`).
///
/// Single-source generic replacing the 64 per-type `<K><V>Pair` wrappers. The
/// public surface is identical to those wrappers: `first`/`second` fields and
/// `new`/`one`/`two`/`swap`/`eql`/`format`.
///
/// `swap()` returns the transposed type `Pair(B, A)`. Thanks to Zig's comptime
/// memoization, `Pair(B, A)` resolves to the same cached type as the
/// aggregator's `<V><K>Pair` alias, so `p.swap()` has exactly the transposed
/// named type a caller expects.
///
/// `eql` is bit-aware for float members (NaN/±0 distinguished by exact bits),
/// matching the original wrappers.
pub fn Pair(comptime A: type, comptime B: type) type {
    return struct {
        first: A,
        second: B,

        const Self = @This();

        pub fn new(first: A, second: B) Self {
            return .{ .first = first, .second = second };
        }

        pub fn one(self: Self) A {
            return self.first;
        }

        pub fn two(self: Self) B {
            return self.second;
        }

        /// Returns the transposed pair `Pair(B, A)` with fields swapped.
        pub fn swap(self: Self) Pair(B, A) {
            return .{ .first = self.second, .second = self.first };
        }

        pub fn eql(self: Self, other: Self) bool {
            return memberEql(A, self.first, other.first) and memberEql(B, self.second, other.second);
        }

        pub fn format(self: Self, writer: anytype) !void {
            try writer.print("({}, {})", .{ self.first, self.second });
        }
    };
}
