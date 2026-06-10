// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! IEEE 754 totalOrder comparators for float keys in sorted/searched
//! collections.
//!
//! `std.math.order` traps or returns `.gt` for NaN, and a raw unsigned bit
//! compare is *not* a total order when NaN coexists with negative floats
//! (NaN's bit pattern sorts below every negative but above every positive,
//! which is intransitive and silently loses keys in a tree's binary search).
//!
//! The canonical fix is the IEEE 754 totalOrder construction — reinterpret
//! the bits as a same-width SIGNED integer, then for negative values flip all
//! bits except the sign bit (logical >>1 of the arithmetic-shifted sign bit),
//! then compare the transformed integers as signed. This is bit-identical to
//! Rust's `f32::total_cmp` / `f64::total_cmp`.
//!
//! The resulting order is:
//!   -NaN < -Inf < neg < -0.0 < +0.0 < pos < +Inf < +NaN
//! with distinct NaN payloads and ±0 staying distinct.
//!
//! See mapdb-collection-spec/spec/algorithms.md §"Float ordering for tree
//! collections".

const std = @import("std");

/// IEEE 754 totalOrder comparator on `f32`. Matches Rust's `f32::total_cmp`.
pub fn totalCmpF32(a: f32, b: f32) std.math.Order {
    var ai: i32 = @bitCast(a);
    var bi: i32 = @bitCast(b);
    ai ^= @as(i32, @bitCast(@as(u32, @bitCast(ai >> 31)) >> 1));
    bi ^= @as(i32, @bitCast(@as(u32, @bitCast(bi >> 31)) >> 1));
    return std.math.order(ai, bi);
}

/// IEEE 754 totalOrder comparator on `f64`. Matches Rust's `f64::total_cmp`.
pub fn totalCmpF64(a: f64, b: f64) std.math.Order {
    var ai: i64 = @bitCast(a);
    var bi: i64 = @bitCast(b);
    ai ^= @as(i64, @bitCast(@as(u64, @bitCast(ai >> 63)) >> 1));
    bi ^= @as(i64, @bitCast(@as(u64, @bitCast(bi >> 63)) >> 1));
    return std.math.order(ai, bi);
}

/// Generic totalOrder comparator for `f32` or `f64`. Dispatches at comptime
/// to the appropriate fixed-width implementation above.
pub fn totalCmp(comptime T: type) fn (T, T) std.math.Order {
    return switch (T) {
        f32 => totalCmpF32,
        f64 => totalCmpF64,
        else => @compileError("float_order.totalCmp only supports f32/f64, got " ++ @typeName(T)),
    };
}

test "totalCmpF32 is a total order: -NaN < -Inf < neg < -0 < +0 < pos < +Inf < +NaN" {
    const neg_nan: f32 = -std.math.nan(f32);
    const neg_inf: f32 = -std.math.inf(f32);
    const neg: f32 = -1.0;
    const neg_zero: f32 = -0.0;
    const pos_zero: f32 = 0.0;
    const pos: f32 = 1.0;
    const pos_inf: f32 = std.math.inf(f32);
    const pos_nan: f32 = std.math.nan(f32);

    try std.testing.expectEqual(std.math.Order.lt, totalCmpF32(neg_nan, neg_inf));
    try std.testing.expectEqual(std.math.Order.lt, totalCmpF32(neg_inf, neg));
    try std.testing.expectEqual(std.math.Order.lt, totalCmpF32(neg, neg_zero));
    try std.testing.expectEqual(std.math.Order.lt, totalCmpF32(neg_zero, pos_zero));
    try std.testing.expectEqual(std.math.Order.lt, totalCmpF32(pos_zero, pos));
    try std.testing.expectEqual(std.math.Order.lt, totalCmpF32(pos, pos_inf));
    try std.testing.expectEqual(std.math.Order.lt, totalCmpF32(pos_inf, pos_nan));

    // The intransitivity-trigger from the review: NaN vs a negative.
    const nan: f32 = std.math.nan(f32);
    try std.testing.expectEqual(std.math.Order.gt, totalCmpF32(nan, neg));
    try std.testing.expectEqual(std.math.Order.gt, totalCmpF32(nan, pos));
}

test "totalCmpF64 ordering and ±0 distinct" {
    const neg_zero: f64 = -0.0;
    const pos_zero: f64 = 0.0;
    try std.testing.expectEqual(std.math.Order.lt, totalCmpF64(neg_zero, pos_zero));
    try std.testing.expectEqual(std.math.Order.eq, totalCmpF64(pos_zero, pos_zero));
    try std.testing.expectEqual(std.math.Order.gt, totalCmpF64(std.math.nan(f64), -1.0));
}

test "totalCmp generic dispatch" {
    try std.testing.expectEqual(std.math.Order.lt, totalCmp(f32)(1.0, 2.0));
    try std.testing.expectEqual(std.math.Order.lt, totalCmp(f64)(1.0, 2.0));
}
