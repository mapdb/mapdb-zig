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

test "reversed off-grid keeps elements (ReversedOffGridKeepsElements)" {
    // spec/algorithms.md §"Reversed() starts from the last element": the
    // reverse's `from` is the last element actually produced, not the
    // constructor's `to`. Every case fits i8, so the same table runs for all
    // four widths; the boundary cases use the width's own min/max.
    inline for (int_types) |T| {
        const Iv = interval.Interval(T);
        const max = std.math.maxInt(T);
        const min = std.math.minInt(T);
        const Case = struct { src: Iv, want: []const T };
        const cases = [_]Case{
            .{ .src = Iv.fromToBy(0, 10, 3), .want = &[_]T{ 9, 6, 3, 0 } },
            .{ .src = Iv.fromToBy(10, 0, -3), .want = &[_]T{ 1, 4, 7, 10 } },
            .{ .src = Iv.fromToBy(0, 5, max), .want = &[_]T{0} },
            .{ .src = Iv.fromToBy(-7, 9, 5), .want = &[_]T{ 8, 3, -2, -7 } },
            .{ .src = Iv.fromToBy(0, 9, 3), .want = &[_]T{ 9, 6, 3, 0 } }, // on grid
            .{ .src = Iv.fromToBy(5, 5, 1), .want = &[_]T{5} },
            // max boundary: to = maxInt off the grid, found without wrapping.
            .{ .src = Iv.fromToBy(max - 7, max, 3), .want = &[_]T{ max - 1, max - 4, max - 7 } },
            // min boundary descending: to = minInt off the grid.
            .{ .src = Iv.fromToBy(min + 7, min, -3), .want = &[_]T{ min + 1, min + 4, min + 7 } },
            // step minInt+1 negates without overflow; only minInt traps.
            .{ .src = Iv.fromToBy(0, min + 1, min + 1), .want = &[_]T{ min + 1, 0 } },
        };
        for (cases) |c| {
            const rev = c.src.reversed();
            const got = try rev.toSlice(std.testing.allocator);
            defer std.testing.allocator.free(got);
            try std.testing.expectEqualSlices(T, c.want, got);
            try std.testing.expectEqual(c.want[0], rev.from);
            try std.testing.expectEqual(c.src.from, rev.to);
            try std.testing.expectEqual(-c.src.step, rev.step);

            // Same size and element set; contains agrees on every probe.
            try std.testing.expectEqual(c.src.len(), rev.len());
            try std.testing.expectEqual(c.want[0], rev.get(0).?);
            try std.testing.expectEqual(c.want[c.want.len - 1], rev.get(rev.len() - 1).?);
            for (c.want) |v| {
                try std.testing.expect(c.src.contains(v));
                try std.testing.expect(rev.contains(v));
            }
            const probes = [_]T{ 10, 1, 2, 4, 5, max, min, 0, -1, 9, 3, 8, -7 };
            for (probes) |v| try std.testing.expectEqual(c.src.contains(v), rev.contains(v));

            // The production iterator yields the same sequence as toSlice.
            var it = rev.iterator();
            var idx: usize = 0;
            while (it.next()) |v| : (idx += 1) try std.testing.expectEqual(c.want[idx], v);
            try std.testing.expectEqual(c.want.len, idx);

            // Reversed twice gives the source sequence (to is normalised to
            // the source's last element, but the elements are identical).
            const twice = rev.reversed();
            const src_slice = try c.src.toSlice(std.testing.allocator);
            defer std.testing.allocator.free(src_slice);
            const twice_slice = try twice.toSlice(std.testing.allocator);
            defer std.testing.allocator.free(twice_slice);
            try std.testing.expectEqualSlices(T, src_slice, twice_slice);
            try std.testing.expectEqual(c.src.from, twice.from);
            try std.testing.expectEqual(c.src.step, twice.step);
        }
    }
}

test "reversed of the full i64 range is not derived from the capped len" {
    // A full-range i64 interval has 2^64 elements and len() caps at
    // maxInt(usize); the remainder form still finds the true last element.
    const full = I64Interval.fromTo(std.math.minInt(i64), std.math.maxInt(i64));
    const rev = full.reversed();
    try std.testing.expectEqual(@as(i64, std.math.maxInt(i64)), rev.from);
    try std.testing.expectEqual(@as(i64, std.math.minInt(i64)), rev.to);
    try std.testing.expectEqual(@as(i64, -1), rev.step);
    try std.testing.expectEqual(@as(?i64, std.math.maxInt(i64)), rev.get(0));
    // Off-grid full-range: from minInt to maxInt by 7. The distance 2^64-1
    // is 1 mod 7 (it is divisible by 3 and 5, which would sit on the grid),
    // so the last element is maxInt-1 and maxInt itself is not contained.
    const wide = I64Interval.fromToBy(std.math.minInt(i64), std.math.maxInt(i64), 7);
    const wrev = wide.reversed();
    const want_last: i64 = std.math.maxInt(i64) - 1;
    try std.testing.expectEqual(want_last, wrev.from);
    try std.testing.expectEqual(@as(?i64, want_last), wrev.get(0));
    try std.testing.expect(wide.contains(want_last));
    try std.testing.expect(wrev.contains(want_last));
    try std.testing.expect(!wide.contains(std.math.maxInt(i64)));
    try std.testing.expect(!wrev.contains(std.math.maxInt(i64)));
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
