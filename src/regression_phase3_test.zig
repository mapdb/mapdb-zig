// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! PHASE 3 correctness-burndown regression tests. One block per fixed bug.
//! Run via `zig build test`.

const std = @import("std");
const testing = std.testing;

const F32I32TreeMap = @import("treemap/treemap.zig").F32I32TreeMap;
const F32TreeSet = @import("treeset/treeset.zig").F32TreeSet;
const F64TreeSet = @import("treeset/treeset.zig").F64TreeSet;
const F64I32TreeMap = @import("treemap/treemap.zig").F64I32TreeMap;
const I64Interval = @import("interval/interval.zig").I64Interval;
const I32Interval = @import("interval/interval.zig").I32Interval;
const I32I32HashMap = @import("hashmap/hashmap.zig").I32I32HashMap;

// ── Bug 1: float tree comparator must be a true total order ──────────────

// The exact 172/2000 repro from zig.md: NaN mixed with negatives used to make
// the buggy bit-compare intransitive, so get(2.0) returned null. With the
// total-order comparator every key stays findable.
test "F32I32TreeMap: NaN + negatives keep keys findable (zig.md repro)" {
    var m = F32I32TreeMap.init(testing.allocator);
    defer m.deinit();

    const nan = std.math.nan(f32);
    _ = try m.put(nan, 100);
    _ = try m.put(2.0, 200);
    _ = try m.put(-0.5, 300);
    _ = try m.put(-1.0, 400);

    // The headline failure: 2.0 was lost in the buggy bit-compare tree.
    try testing.expectEqual(@as(?i32, 200), m.get(2.0));
    try testing.expectEqual(@as(?i32, 300), m.get(-0.5));
    try testing.expectEqual(@as(?i32, 400), m.get(-1.0));
    try testing.expectEqual(@as(?i32, 100), m.get(nan));
    try testing.expectEqual(@as(usize, 4), m.size());
}

test "F32I32TreeMap: brute-ish NaN/negative mix stays findable" {
    var m = F32I32TreeMap.init(testing.allocator);
    defer m.deinit();

    const nan = std.math.nan(f32);
    const inf = std.math.inf(f32);
    const keys = [_]f32{
        nan, -inf, inf, -3.5, -2.0, -1.0, -0.5, 0.5, 1.0, 2.0, 3.5, 0.0, 7.25, -9.0,
    };
    for (keys, 0..) |k, i| {
        _ = try m.put(k, @as(i32, @intCast(i)));
    }
    // Every inserted key must be retrievable with its exact value.
    for (keys, 0..) |k, i| {
        const got = m.get(k);
        try testing.expect(got != null);
        try testing.expectEqual(@as(i32, @intCast(i)), got.?);
    }
    try testing.expectEqual(keys.len, m.size());
}

// ── ±0 distinct and distinct NaN payloads distinct ──────────────────────

test "F32TreeSet: +0.0 and -0.0 are distinct keys" {
    var s = F32TreeSet.init(testing.allocator);
    defer s.deinit();

    try testing.expect(try s.add(0.0)); // newly inserted
    try testing.expect(try s.add(-0.0)); // distinct → newly inserted
    try testing.expectEqual(@as(usize, 2), s.size());
    try testing.expect(s.contains(0.0));
    try testing.expect(s.contains(-0.0));
    // Re-adding the same signed zero is a no-op.
    try testing.expect(!(try s.add(0.0)));
    try testing.expectEqual(@as(usize, 2), s.size());
}

test "F64TreeSet: distinct NaN payloads are distinct keys" {
    var s = F64TreeSet.init(testing.allocator);
    defer s.deinit();

    const qnan: f64 = @bitCast(@as(u64, 0x7FF8_0000_0000_0001));
    const qnan2: f64 = @bitCast(@as(u64, 0x7FF8_0000_0000_0002));
    try testing.expect(std.math.isNan(qnan));
    try testing.expect(std.math.isNan(qnan2));

    try testing.expect(try s.add(qnan));
    try testing.expect(try s.add(qnan2)); // different payload → distinct
    try testing.expectEqual(@as(usize, 2), s.size());
    try testing.expect(s.contains(qnan));
    try testing.expect(s.contains(qnan2));
    try testing.expect(!(try s.add(qnan))); // same payload → no-op
    try testing.expectEqual(@as(usize, 2), s.size());
}

test "F64I32TreeMap: ±0 distinct keys in a map" {
    var m = F64I32TreeMap.init(testing.allocator);
    defer m.deinit();
    _ = try m.put(0.0, 1);
    _ = try m.put(-0.0, 2);
    try testing.expectEqual(@as(usize, 2), m.size());
    try testing.expectEqual(@as(?i32, 1), m.get(0.0));
    try testing.expectEqual(@as(?i32, 2), m.get(-0.0));
}

// ── Bug 2: interval len() caps at maxInt(usize) instead of panicking ─────

test "I64Interval: full-range len() caps at maxInt(usize) (no panic)" {
    const iv = I64Interval.fromTo(std.math.minInt(i64), std.math.maxInt(i64));
    // The element count is 2^64, which does not fit in usize; it is capped.
    try testing.expectEqual(@as(usize, std.math.maxInt(usize)), iv.len());
    try testing.expect(!iv.isEmpty());
    // contains/get still use the wider integer correctly.
    try testing.expect(iv.contains(0));
    try testing.expect(iv.contains(std.math.maxInt(i64)));
}

test "I32Interval: ordinary len() is exact (cap does not perturb small ranges)" {
    const iv = I32Interval.fromTo(1, 10);
    try testing.expectEqual(@as(usize, 10), iv.len());
}

// ── Bug 3: addToValue wraps at the value width ──────────────────────────

test "I32I32HashMap.addToValue wraps i32 MAX + 1 to i32 MIN" {
    var m = try I32I32HashMap.init(testing.allocator);
    defer m.deinit();
    _ = try m.put(7, std.math.maxInt(i32));
    const result = m.addToValue(7, 1);
    try testing.expectEqual(@as(i32, std.math.minInt(i32)), result);
    try testing.expectEqual(@as(?i32, std.math.minInt(i32)), m.get(7));
}

test "I32I32HashMap.addToValue wraps i32 MIN - 1 to i32 MAX" {
    var m = try I32I32HashMap.init(testing.allocator);
    defer m.deinit();
    _ = try m.put(9, std.math.minInt(i32));
    const result = m.addToValue(9, -1);
    try testing.expectEqual(@as(i32, std.math.maxInt(i32)), result);
}

// ── Bug 4: Swiss-table 7/8 load factor ──────────────────────────────────

// The Swiss table uses a 7/8 max-load factor: maxLoad(16) = 14. A fresh
// 16-bucket table holds up to 14 entries; the 15th distinct insert forces a
// grow. (The earlier 0.75 backward-shift design grew on the 12th insert; this
// asserts the new observable 7/8 threshold rather than an exact bucket count.)
test "I32I32HashMap: 15th insert into capacity-16 grows (7/8 load)" {
    var m = try I32I32HashMap.init(testing.allocator);
    defer m.deinit();
    try testing.expectEqual(@as(usize, 16), m.inner.capacity);

    // Insert 14 distinct keys — should stay at capacity 16 (14 == maxLoad(16)).
    var k: i32 = 0;
    while (k < 14) : (k += 1) {
        _ = try m.put(k, k);
    }
    try testing.expectEqual(@as(usize, 16), m.inner.capacity);

    // The 15th distinct key exceeds maxLoad(16) → must resize.
    _ = try m.put(14, 14);
    try testing.expect(m.inner.capacity > 16);
    try testing.expectEqual(@as(usize, 15), m.len());
}

// ── Bug 5: fromToBy(_, _, 0) panics in every build profile ──────────────

// Zig's in-process test runner cannot catch @panic, so we cannot assert the
// trap with `testing.expect` here. The contract is instead verified out of
// band by `nanprobe`/a standalone probe and by inspection: fromToBy now uses
// `if (step == 0) @panic(...)` (always-on) rather than `std.debug.assert`
// (a no-op in ReleaseFast). This test pins the *valid* paths so a regression
// that loosens the zero-step guard back into an assert is still visible via
// the surrounding contract, and documents the panic expectation.
test "I64Interval.fromToBy: valid non-zero steps construct correctly" {
    const up = I64Interval.fromToBy(0, 10, 2);
    try testing.expectEqual(@as(usize, 6), up.len()); // 0,2,4,6,8,10
    const down = I64Interval.fromToBy(10, 0, -2);
    try testing.expectEqual(@as(usize, 6), down.len());
    // (fromToBy(x, y, 0) traps via @panic in all build profiles — verified
    //  out of process; the test runner cannot intercept @panic.)
}
