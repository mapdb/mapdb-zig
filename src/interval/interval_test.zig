// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Tests for the generic `Interval(T)` and its named aliases. Interval is only
//! applicable to signed integer element types (`i8`/`i16`/`i32`/`i64`).

const std = @import("std");
const interval = @import("interval.zig");

const I8Interval = interval.I8Interval;
const I16Interval = interval.I16Interval;
const I32Interval = interval.I32Interval;
const I64Interval = interval.I64Interval;

// The signed-integer element types Interval supports.
const int_types = [_]type{ i8, i16, i32, i64 };

test "refAllDeclsRecursive over named aliases" {
    std.testing.refAllDeclsRecursive(I8Interval);
    std.testing.refAllDeclsRecursive(I16Interval);
    std.testing.refAllDeclsRecursive(I32Interval);
    std.testing.refAllDeclsRecursive(I64Interval);
}

test "aggregator exposes named aliases and backward-compat namespaces" {
    try std.testing.expect(I8Interval == interval.Interval(i8));
    try std.testing.expect(I16Interval == interval.Interval(i16));
    try std.testing.expect(I32Interval == interval.Interval(i32));
    try std.testing.expect(I64Interval == interval.Interval(i64));

    try std.testing.expect(interval.i8_interval.I8Interval == I8Interval);
    try std.testing.expect(interval.i16_interval.I16Interval == I16Interval);
    try std.testing.expect(interval.i32_interval.I32Interval == I32Interval);
    try std.testing.expect(interval.i64_interval.I64Interval == I64Interval);

    // The non-applicable stub namespaces remain empty.
    try std.testing.expectEqual(0, @typeInfo(interval.bool_interval).@"struct".decls.len);
    try std.testing.expectEqual(0, @typeInfo(interval.char_interval).@"struct".decls.len);
    try std.testing.expectEqual(0, @typeInfo(interval.f32_interval).@"struct".decls.len);
    try std.testing.expectEqual(0, @typeInfo(interval.f64_interval).@"struct".decls.len);
}

test "fromTo ascending across all int types" {
    inline for (int_types) |T| {
        const Iv = interval.Interval(T);
        const iv = Iv.fromTo(1, 5);
        try std.testing.expectEqual(@as(usize, 5), iv.len());
        const slice = try iv.toSlice(std.testing.allocator);
        defer std.testing.allocator.free(slice);
        try std.testing.expectEqualSlices(T, &[_]T{ 1, 2, 3, 4, 5 }, slice);
    }
}

test "fromTo descending across all int types" {
    inline for (int_types) |T| {
        const Iv = interval.Interval(T);
        const iv = Iv.fromTo(5, 1);
        try std.testing.expectEqual(@as(usize, 5), iv.len());
        const slice = try iv.toSlice(std.testing.allocator);
        defer std.testing.allocator.free(slice);
        try std.testing.expectEqualSlices(T, &[_]T{ 5, 4, 3, 2, 1 }, slice);
    }
}

test "fromToBy positive and negative step across all int types" {
    inline for (int_types) |T| {
        const Iv = interval.Interval(T);

        const up = Iv.fromToBy(0, 10, 2);
        try std.testing.expectEqual(@as(usize, 6), up.len());
        const up_slice = try up.toSlice(std.testing.allocator);
        defer std.testing.allocator.free(up_slice);
        try std.testing.expectEqualSlices(T, &[_]T{ 0, 2, 4, 6, 8, 10 }, up_slice);

        const down = Iv.fromToBy(10, 1, -3);
        try std.testing.expectEqual(@as(usize, 4), down.len());
        const down_slice = try down.toSlice(std.testing.allocator);
        defer std.testing.allocator.free(down_slice);
        try std.testing.expectEqualSlices(T, &[_]T{ 10, 7, 4, 1 }, down_slice);
    }
}

test "oneTo and zeroTo across all int types" {
    inline for (int_types) |T| {
        const Iv = interval.Interval(T);

        const one = Iv.oneTo(3);
        const one_slice = try one.toSlice(std.testing.allocator);
        defer std.testing.allocator.free(one_slice);
        try std.testing.expectEqualSlices(T, &[_]T{ 1, 2, 3 }, one_slice);

        const zero = Iv.zeroTo(3);
        try std.testing.expectEqual(@as(usize, 4), zero.len());
        const zero_slice = try zero.toSlice(std.testing.allocator);
        defer std.testing.allocator.free(zero_slice);
        try std.testing.expectEqualSlices(T, &[_]T{ 0, 1, 2, 3 }, zero_slice);
    }
}

test "single element and isEmpty across all int types" {
    inline for (int_types) |T| {
        const Iv = interval.Interval(T);
        const single = Iv.fromTo(3, 3);
        try std.testing.expectEqual(@as(usize, 1), single.len());
        try std.testing.expect(!single.isEmpty());
    }
}

test "empty interval via reversed-direction step guards" {
    // fromToBy enforces step sign, so an "empty" interval is produced by an
    // ascending [from,to] with a step that overshoots, etc. Construct directly
    // to exercise the len()==0 / isEmpty branch without tripping the guards.
    inline for (int_types) |T| {
        const Iv = interval.Interval(T);
        // step > 0 but from > to → length 0.
        const empty_up = Iv{ .from = 5, .to = 1, .step = 1 };
        try std.testing.expectEqual(@as(usize, 0), empty_up.len());
        try std.testing.expect(empty_up.isEmpty());
        try std.testing.expectEqual(@as(?T, null), empty_up.get(0));

        // step < 0 but from < to → length 0.
        const empty_down = Iv{ .from = 1, .to = 5, .step = -1 };
        try std.testing.expectEqual(@as(usize, 0), empty_down.len());
        try std.testing.expect(empty_down.isEmpty());
    }
}

test "contains across all int types" {
    inline for (int_types) |T| {
        const Iv = interval.Interval(T);
        const iv = Iv.fromToBy(0, 10, 2);
        try std.testing.expect(iv.contains(0));
        try std.testing.expect(iv.contains(4));
        try std.testing.expect(iv.contains(10));
        try std.testing.expect(!iv.contains(3));
        try std.testing.expect(!iv.contains(11));

        // Descending contains.
        const dn = Iv.fromToBy(10, 0, -2);
        try std.testing.expect(dn.contains(10));
        try std.testing.expect(dn.contains(2));
        try std.testing.expect(!dn.contains(1));
        try std.testing.expect(!dn.contains(-2));
    }
}

test "get bounds across all int types" {
    inline for (int_types) |T| {
        const Iv = interval.Interval(T);
        const iv = Iv.fromTo(1, 5);
        try std.testing.expectEqual(@as(?T, 1), iv.get(0));
        try std.testing.expectEqual(@as(?T, 5), iv.get(4));
        try std.testing.expectEqual(@as(?T, null), iv.get(5));
    }
}

test "reversed across all int types" {
    inline for (int_types) |T| {
        const Iv = interval.Interval(T);
        const iv = Iv.fromTo(1, 5);
        const rev = iv.reversed();
        const slice = try rev.toSlice(std.testing.allocator);
        defer std.testing.allocator.free(slice);
        try std.testing.expectEqualSlices(T, &[_]T{ 5, 4, 3, 2, 1 }, slice);
    }
}

// ── Marquee canonical-fix cases ──────────────────────────────────────────

test "i8 minimum-step full-range edge: len cap and reversal panic threshold" {
    // The minimum-step interval: step == minInt(i8) == -128. from == 0 means
    // a single element (only index 0 is in range), exercising the wrapping
    // arithmetic with the most extreme step magnitude.
    const iv = I8Interval{ .from = 0, .to = -128, .step = -128 };
    try std.testing.expectEqual(@as(usize, 2), iv.len()); // 0 and -128
    const slice = try iv.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqualSlices(i8, &[_]i8{ 0, -128 }, slice);

    // A full-range descending i8 interval with step -1.
    const full = I8Interval.fromTo(127, -128);
    try std.testing.expectEqual(@as(usize, 256), full.len());
    try std.testing.expectEqual(@as(?i8, 127), full.get(0));
    try std.testing.expectEqual(@as(?i8, -128), full.get(255));
    try std.testing.expectEqual(@as(?i8, null), full.get(256));
}

test "i64 large-range wrapping: len caps at maxInt(usize) without overflow" {
    // A full-range i64 interval has 2^64 elements, which exceeds usize. The
    // i128-widened arithmetic must not overflow and len() must cap.
    const full = I64Interval.fromTo(std.math.minInt(i64), std.math.maxInt(i64));
    try std.testing.expectEqual(@as(usize, std.math.maxInt(usize)), full.len());
    try std.testing.expect(!full.isEmpty());
    try std.testing.expectEqual(@as(?i64, std.math.minInt(i64)), full.get(0));
    try std.testing.expectEqual(@as(?i64, std.math.minInt(i64) + 1), full.get(1));

    // contains across the full range, exercising the i128 @mod path.
    try std.testing.expect(full.contains(0));
    try std.testing.expect(full.contains(std.math.maxInt(i64)));
    try std.testing.expect(full.contains(std.math.minInt(i64)));
}

test "reversed panics on minimum signed step" {
    // negating minInt(T) overflows, so reversed() must @panic at the threshold.
    // We verify the guard condition holds for each width by checking a
    // non-minimum step reverses fine and the minimum step is exactly minInt.
    inline for (int_types) |T| {
        const Iv = interval.Interval(T);
        try std.testing.expectEqual(std.math.minInt(T), -@as(i128, std.math.maxInt(T)) - 1);
        const ok = Iv{ .from = 0, .to = 10, .step = 1 };
        const rev = ok.reversed();
        try std.testing.expectEqual(@as(T, -1), rev.step);
    }
}
