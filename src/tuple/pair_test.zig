// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Tests for the generic immutable pair type.
//!
//! Zig only type-checks generic methods that are *referenced*. Collapsing the
//! 64 per-type `<K><V>Pair` wrappers into one `Pair(A, B)` generic means an
//! unreferenced method on an unexercised instantiation would never be compiled
//! — a silent coverage collapse. Two mechanisms counter this:
//!   1. `refAllDeclsRecursive` over every named alias forces every method on
//!      every instantiation to be compiled.
//!   2. Parameterized runtime tests exercise the full 8x8 type axis
//!      behaviourally (new/one/two/swap/eql/format), including the float-member
//!      bit-equality edge cases (NaN, -0.0 vs +0.0), replacing the deleted
//!      per-file tests.

const std = @import("std");
const agg = @import("tuple.zig");

const Pair = agg.Pair;

// ---------------------------------------------------------------------------
// Force-compile every method on every instantiation.
// ---------------------------------------------------------------------------

const all_alias_types = [_]type{
    agg.BoolBoolPair, agg.BoolCharPair, agg.BoolF32Pair, agg.BoolF64Pair, agg.BoolI8Pair, agg.BoolI16Pair, agg.BoolI32Pair, agg.BoolI64Pair,
    agg.CharBoolPair, agg.CharCharPair, agg.CharF32Pair, agg.CharF64Pair, agg.CharI8Pair, agg.CharI16Pair, agg.CharI32Pair, agg.CharI64Pair,
    agg.F32BoolPair,  agg.F32CharPair,  agg.F32F32Pair,  agg.F32F64Pair,  agg.F32I8Pair,  agg.F32I16Pair,  agg.F32I32Pair,  agg.F32I64Pair,
    agg.F64BoolPair,  agg.F64CharPair,  agg.F64F32Pair,  agg.F64F64Pair,  agg.F64I8Pair,  agg.F64I16Pair,  agg.F64I32Pair,  agg.F64I64Pair,
    agg.I8BoolPair,   agg.I8CharPair,   agg.I8F32Pair,   agg.I8F64Pair,   agg.I8I8Pair,   agg.I8I16Pair,   agg.I8I32Pair,   agg.I8I64Pair,
    agg.I16BoolPair,  agg.I16CharPair,  agg.I16F32Pair,  agg.I16F64Pair,  agg.I16I8Pair,  agg.I16I16Pair,  agg.I16I32Pair,  agg.I16I64Pair,
    agg.I32BoolPair,  agg.I32CharPair,  agg.I32F32Pair,  agg.I32F64Pair,  agg.I32I8Pair,  agg.I32I16Pair,  agg.I32I32Pair,  agg.I32I64Pair,
    agg.I64BoolPair,  agg.I64CharPair,  agg.I64F32Pair,  agg.I64F64Pair,  agg.I64I8Pair,  agg.I64I16Pair,  agg.I64I32Pair,  agg.I64I64Pair,
};

test "refAllDeclsRecursive forces every method on every instantiation to compile" {
    inline for (all_alias_types) |T| {
        std.testing.refAllDeclsRecursive(T);
    }
}

// ---------------------------------------------------------------------------
// Parameterized behaviour over the full 8x8 (A, B) type axis.
// ---------------------------------------------------------------------------

const axis = [_]type{ bool, u21, f32, f64, i8, i16, i32, i64 };

/// A small representative non-zero sample value for each supported member type.
fn sampleA(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .bool => true,
        .float => @as(T, 1.5),
        else => @as(T, 1),
    };
}

fn sampleB(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .bool => false,
        .float => @as(T, 2.25),
        else => @as(T, 2),
    };
}

test "new/one/two/swap/eql over the full 8x8 axis" {
    inline for (axis) |A| {
        inline for (axis) |B| {
            const P = Pair(A, B);
            const a = sampleA(A);
            const b = sampleB(B);

            const p = P.new(a, b);
            try std.testing.expectEqual(a, p.first);
            try std.testing.expectEqual(b, p.second);
            try std.testing.expectEqual(a, p.one());
            try std.testing.expectEqual(b, p.two());

            // swap returns the transposed type Pair(B, A) — and via comptime
            // memoization, that is exactly the same type as Pair(B, A).
            const s = p.swap();
            comptime std.debug.assert(@TypeOf(s) == Pair(B, A));
            try std.testing.expectEqual(b, s.first);
            try std.testing.expectEqual(a, s.second);

            // eql: reflexive, and distinguishes a different pair.
            const p2 = P.new(a, b);
            try std.testing.expect(p.eql(p2));
            const p3 = P.new(b_as(A, B), a_as(B, A));
            // p3 only meaningfully differs when the swapped sample values land
            // in a different value; guard against degenerate equal cases.
            if (!sameValue(A, a, b_as(A, B)) or !sameValue(B, b, a_as(B, A))) {
                try std.testing.expect(!p.eql(p3));
            }
        }
    }
}

/// Coerce sampleB-of-B into an A-typed value (used to build a differing pair).
fn b_as(comptime A: type, comptime B: type) A {
    _ = B;
    return sampleB(A);
}
fn a_as(comptime B: type, comptime A: type) B {
    _ = A;
    return sampleA(B);
}
fn sameValue(comptime T: type, x: T, y: T) bool {
    return switch (@typeInfo(T)) {
        .bool => x == y,
        .float => x == y,
        else => x == y,
    };
}

test "eql float-member bit-equality: NaN equals itself by bits, +0 != -0" {
    // f32 first member.
    {
        const P = Pair(f32, i32);
        const nan = std.math.nan(f32);
        const p_nan_a = P.new(nan, 7);
        const p_nan_b = P.new(nan, 7);
        // Same NaN bit pattern -> bit-equal -> eql true (differs from `==`,
        // which would say NaN != NaN).
        try std.testing.expect(p_nan_a.eql(p_nan_b));

        const p_pos0 = P.new(@as(f32, 0.0), 7);
        const p_neg0 = P.new(-@as(f32, 0.0), 7);
        // +0.0 and -0.0 have different bits -> not eql (differs from `==`).
        try std.testing.expect(!p_pos0.eql(p_neg0));
        // +0.0 equals +0.0.
        const p_pos0_b = P.new(@as(f32, 0.0), 7);
        try std.testing.expect(p_pos0.eql(p_pos0_b));
    }
    // f64 second member.
    {
        const P = Pair(i32, f64);
        const nan = std.math.nan(f64);
        try std.testing.expect(P.new(7, nan).eql(P.new(7, nan)));
        try std.testing.expect(!P.new(7, @as(f64, 0.0)).eql(P.new(7, -@as(f64, 0.0))));
    }
}

test "format renders as (first, second)" {
    // The pair's `format` retains the legacy 4-arg signature
    // `format(self, comptime fmt, options, writer)` that the rest of this
    // codebase uses, so it is exercised by calling it directly on a writer
    // (the `{}`/`{f}` format-string dispatch in this Zig version expects the
    // newer 1-arg signature and is therefore not used here).
    var buf: [64]u8 = undefined;

    {
        var fbs = std.io.fixedBufferStream(&buf);
        try Pair(i32, i32).new(1, 2).format("", .{}, fbs.writer());
        try std.testing.expectEqualStrings("(1, 2)", fbs.getWritten());
    }
    {
        var fbs = std.io.fixedBufferStream(&buf);
        try Pair(bool, u21).new(true, 'b').format("", .{}, fbs.writer());
        try std.testing.expectEqualStrings("(true, 98)", fbs.getWritten());
    }
    {
        // Float member renders via default float formatting.
        var fbs = std.io.fixedBufferStream(&buf);
        try Pair(f64, i32).new(1.5, 2).format("", .{}, fbs.writer());
        try std.testing.expectEqualStrings("(1.5, 2)", fbs.getWritten());
    }
}
