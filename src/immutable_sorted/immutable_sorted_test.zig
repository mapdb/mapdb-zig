// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Native tests for the compact immutable sorted map / set. These cover the
//! obligations the cross-language JSON suite cannot express (construction
//! traps, snapshot independence, iterator key-order pairing with NON-monotonic
//! values, signed-edge nav/rank/select + range brackets, round-trip identity).
//! Mirrors `mapdb-rust/src/immutable_sorted/tests.rs`. No leaks: every test
//! uses `std.testing.allocator` and frees owned slices.

const std = @import("std");
const testing = std.testing;

const mod = @import("immutable_sorted.zig");
const ImmutableSortedMap = mod.ImmutableSortedMap;
const ImmutableSortedSet = mod.ImmutableSortedSet;
const Map = mod.ImmutableI32I32SortedMap;
const Set = mod.ImmutableI32SortedSet;

const range_mod = @import("../range.zig");
const I32Range = range_mod.I32Range;

const min_i32 = std.math.minInt(i32);
const max_i32 = std.math.maxInt(i32);

// ── Construction traps (native-only; RESERVED expect_panic) ──────────
//
// Zig's in-process test runner cannot intercept @panic (same convention as
// Range/Interval trap tests). The construction traps are pinned by inspection
// — fromSorted uses always-on @panic (every build profile) — and these tests
// pin the VALID neighbours so a regression loosening the strictly-ascending /
// length-mismatch guard stays visible.

test "trap: unsorted / duplicate / length-mismatch verified out of process" {
    // The VALID boundary cases that must NOT trap:
    var sorted = try Map.fromSorted(testing.allocator, &.{ 10, 20, 30 }, &.{ 1, 2, 3 });
    defer sorted.deinit();
    try testing.expectEqual(@as(usize, 3), sorted.len());

    var single = try Map.fromSorted(testing.allocator, &.{7}, &.{700});
    defer single.deinit();
    try testing.expectEqual(@as(?i32, 700), single.get(7));

    var empty = try Map.fromSorted(testing.allocator, &.{}, &.{});
    defer empty.deinit();
    try testing.expect(empty.isEmpty());

    var set_sorted = try Set.fromSorted(testing.allocator, &.{ 10, 20, 30 });
    defer set_sorted.deinit();
    try testing.expectEqual(@as(usize, 3), set_sorted.len());

    // The following trap via always-on @panic in fromSorted (verified out of
    // process; the test runner cannot intercept @panic):
    //   Map.fromSorted(&{10,30,20}, &{1,3,2})  -> out-of-order
    //   Map.fromSorted(&{10,20,20}, &{1,2,3})  -> duplicate key
    //   Map.fromSorted(&{10,20,30}, &{1,2})    -> keys/values length mismatch
    //   Set.fromSorted(&{10,30,20})            -> out-of-order
    //   Set.fromSorted(&{10,20,20})            -> duplicate
}

// ── Empty + single (valid, not a trap) ───────────────────────────────

test "empty map is valid and all absence" {
    var m = try Map.fromSorted(testing.allocator, &.{}, &.{});
    defer m.deinit();
    try testing.expectEqual(@as(usize, 0), m.len());
    try testing.expect(m.isEmpty());
    try testing.expectEqual(@as(?i32, null), m.get(5));
    try testing.expect(!m.containsKey(5));
    try testing.expectEqual(@as(?i32, null), m.firstKey());
    try testing.expectEqual(@as(?i32, null), m.lastKey());
    try testing.expectEqual(@as(?i32, null), m.floorKey(5));
    try testing.expectEqual(@as(?i32, null), m.ceilingKey(5));
    try testing.expectEqual(@as(?i32, null), m.lowerKey(5));
    try testing.expectEqual(@as(?i32, null), m.higherKey(5));
    try testing.expectEqual(@as(usize, 0), m.rank(5));
    try testing.expectEqual(@as(?i32, null), m.selectKey(0));
    try testing.expectEqual(@as(usize, 0), m.keysSlice().len);

    const dk = try m.descendingKeys(testing.allocator);
    defer testing.allocator.free(dk);
    try testing.expectEqual(@as(usize, 0), dk.len);

    const rk = try m.rangeKeys(I32Range.all(), testing.allocator);
    defer testing.allocator.free(rk);
    try testing.expectEqual(@as(usize, 0), rk.len);
}

test "empty set is valid" {
    var s = try Set.fromSorted(testing.allocator, &.{});
    defer s.deinit();
    try testing.expect(s.isEmpty());
    try testing.expectEqual(@as(?i32, null), s.first());
    try testing.expectEqual(@as(?i32, null), s.floor(0));
    try testing.expectEqual(@as(usize, 0), s.rank(0));
    try testing.expectEqual(@as(?i32, null), s.select(0));
}

test "single element is valid" {
    var m = try Map.fromSorted(testing.allocator, &.{7}, &.{700});
    defer m.deinit();
    try testing.expectEqual(@as(?i32, 700), m.get(7));
    try testing.expectEqual(@as(?i32, 7), m.floorKey(7));
    try testing.expectEqual(@as(?i32, 7), m.ceilingKey(7));
    try testing.expectEqual(@as(?i32, null), m.lowerKey(7));
    try testing.expectEqual(@as(?i32, null), m.higherKey(7));
    try testing.expectEqual(@as(usize, 0), m.rank(6));
    try testing.expectEqual(@as(usize, 0), m.rank(7));
    try testing.expectEqual(@as(usize, 1), m.rank(8));
    try testing.expectEqual(@as(?i32, 7), m.selectKey(0));
    try testing.expectEqual(@as(?i32, null), m.selectKey(1));
}

// ── values() / entries() key-order pairing (native-only obligation) ──

test "values and entries pair with keys, not value-sorted" {
    // Deliberately NON-monotonic values; a port that sorts values
    // independently would mis-pair. keys {10,20,30}; values {300,100,200}.
    var m = try Map.fromSorted(testing.allocator, &.{ 10, 20, 30 }, &.{ 300, 100, 200 });
    defer m.deinit();

    const keys = m.keysSlice();
    const values = m.valuesSlice();
    try testing.expectEqualSlices(i32, &.{ 10, 20, 30 }, keys);
    try testing.expectEqualSlices(i32, &.{ 300, 100, 200 }, values); // NOT [100,200,300]

    // Zip-and-assert: values[i] is the value of keys[i].
    for (keys, values) |k, v| {
        try testing.expectEqual(@as(?i32, v), m.get(k));
    }

    // entries() pairing via descendingEntries / selectEntry.
    try testing.expectEqual(@as(?i32, 300), m.get(10));
    try testing.expectEqual(@as(?i32, 100), m.get(20));
    try testing.expectEqual(@as(?i32, 200), m.get(30));

    const e1 = m.selectEntry(1).?;
    try testing.expectEqual(@as(i32, 20), e1.key);
    try testing.expectEqual(@as(i32, 100), e1.value);

    // Ascending entries() carries the same key-order pairing (NOT value-sorted).
    const ents = try m.entries(testing.allocator);
    defer testing.allocator.free(ents);
    try testing.expectEqual(@as(usize, 3), ents.len);
    try testing.expectEqual(@as(i32, 10), ents[0].key);
    try testing.expectEqual(@as(i32, 300), ents[0].value);
    try testing.expectEqual(@as(i32, 20), ents[1].key);
    try testing.expectEqual(@as(i32, 100), ents[1].value);
    try testing.expectEqual(@as(i32, 30), ents[2].key);
    try testing.expectEqual(@as(i32, 200), ents[2].value);
}

// ── Snapshot independence from a mutated source buffer ───────────────

test "construction takes an independent snapshot (map)" {
    var keys = [_]i32{ 10, 20, 30 };
    var values = [_]i32{ 100, 200, 300 };
    var m = try Map.fromSorted(testing.allocator, &keys, &values);
    defer m.deinit();

    // Mutate the caller's source buffers AFTER construction.
    keys[0] = 999;
    values[1] = -1;

    // The built map is unaffected.
    try testing.expectEqual(@as(usize, 3), m.len());
    try testing.expectEqual(@as(?i32, 100), m.get(10));
    try testing.expectEqual(@as(?i32, 200), m.get(20));
    try testing.expectEqual(@as(?i32, 10), m.firstKey());
    try testing.expect(!m.containsKey(999));
}

test "construction takes an independent snapshot (set)" {
    var elems = [_]i32{ 1, 2, 3 };
    var s = try Set.fromSorted(testing.allocator, &elems);
    defer s.deinit();
    elems[0] = 99;
    try testing.expectEqual(@as(usize, 3), s.len());
    try testing.expect(s.contains(1));
    try testing.expect(!s.contains(99));
}

// ── select(rank(k)) == k round-trip identity ─────────────────────────

test "select(rank(k)) round-trip identity" {
    const keys = [_]i32{ -100, -1, 0, 1, 42, 1000 };
    var m = try Map.fromSorted(testing.allocator, &keys, &.{ 1, 2, 3, 4, 5, 6 });
    defer m.deinit();
    for (keys) |k| {
        const r = m.rank(k);
        try testing.expectEqual(@as(?i32, k), m.selectKey(r));
        try testing.expectEqual(r, m.rank(m.selectKey(r).?));
    }
    // rank on absent keys is the lower-bound index.
    try testing.expectEqual(@as(usize, 0), m.rank(-101));
    try testing.expectEqual(@as(usize, 5), m.rank(500));
    try testing.expectEqual(@as(usize, 6), m.rank(100_000));
}

// ── Sortedness / parallel-array invariants post-build ────────────────

test "stored arrays are strictly ascending and aligned" {
    var m = try Map.fromSorted(testing.allocator, &.{ 10, 20, 30, 40, 50 }, &.{ 1, 2, 3, 4, 5 });
    defer m.deinit();
    const keys = m.keysSlice();
    var i: usize = 1;
    while (i < keys.len) : (i += 1) {
        try testing.expect(keys[i - 1] < keys[i]);
    }
    for (keys, 0..) |k, idx| {
        try testing.expectEqual(m.selectEntry(idx).?.value, m.get(k).?);
    }
}

// ── Signed extremes (INT_MIN / INT_MAX) ──────────────────────────────

test "signed extremes lookup / nav / rank / select" {
    const keys = [_]i32{ min_i32, -1, 0, 1, max_i32 };
    var m = try Map.fromSorted(testing.allocator, &keys, &.{ 10, 20, 30, 40, 50 });
    defer m.deinit();

    try testing.expectEqual(@as(?i32, 10), m.get(min_i32));
    try testing.expectEqual(@as(?i32, 50), m.get(max_i32));

    try testing.expectEqual(@as(?i32, min_i32), m.floorKey(min_i32));
    try testing.expectEqual(@as(?i32, null), m.lowerKey(min_i32));
    try testing.expectEqual(@as(?i32, 0), m.higherKey(-1));
    try testing.expectEqual(@as(?i32, max_i32), m.ceilingKey(max_i32));
    try testing.expectEqual(@as(?i32, null), m.higherKey(max_i32));

    try testing.expectEqual(@as(usize, 2), m.rank(0));
    try testing.expectEqual(@as(usize, 0), m.rank(min_i32));
    try testing.expectEqual(@as(usize, 4), m.rank(max_i32));
    try testing.expectEqual(@as(?i32, min_i32), m.selectKey(0));
    try testing.expectEqual(@as(?i32, max_i32), m.selectKey(4));
    try testing.expectEqual(@as(?i32, null), m.selectKey(5));

    const dk = try m.descendingKeys(testing.allocator);
    defer testing.allocator.free(dk);
    try testing.expectEqualSlices(i32, &.{ max_i32, 1, 0, -1, min_i32 }, dk);
}

test "range brackets at signed extremes do not overflow" {
    const keys = [_]i32{ min_i32, -1, 0, 1, max_i32 };
    var m = try Map.fromSorted(testing.allocator, &keys, &.{ 10, 20, 30, 40, 50 });
    defer m.deinit();

    {
        // greater_than(MIN) excludes MIN, no MIN-1.
        const r = try m.rangeKeys(I32Range.greaterThan(min_i32), testing.allocator);
        defer testing.allocator.free(r);
        try testing.expectEqualSlices(i32, &.{ -1, 0, 1, max_i32 }, r);
    }
    {
        // less_than(MAX) excludes MAX, no MAX+1.
        const r = try m.rangeKeys(I32Range.lessThan(max_i32), testing.allocator);
        defer testing.allocator.free(r);
        try testing.expectEqualSlices(i32, &.{ min_i32, -1, 0, 1 }, r);
    }
    {
        const r = try m.rangeKeys(I32Range.closed(min_i32, max_i32), testing.allocator);
        defer testing.allocator.free(r);
        try testing.expectEqualSlices(i32, &.{ min_i32, -1, 0, 1, max_i32 }, r);
    }
    {
        const r = try m.rangeKeys(I32Range.singleton(max_i32), testing.allocator);
        defer testing.allocator.free(r);
        try testing.expectEqualSlices(i32, &.{max_i32}, r);
    }
}

// ── Range membership == range.contains (discrete-empty is NOT an error) ─

test "open range over adjacent ints is empty, not error" {
    var m = try Map.fromSorted(testing.allocator, &.{ 1, 2 }, &.{ 10, 20 });
    defer m.deinit();
    {
        const r = try m.rangeKeys(I32Range.open(1, 2), testing.allocator);
        defer testing.allocator.free(r);
        try testing.expectEqual(@as(usize, 0), r.len);
    }
    {
        const r = try m.rangeKeys(I32Range.closedOpen(5, 5), testing.allocator);
        defer testing.allocator.free(r);
        try testing.expectEqual(@as(usize, 0), r.len);
    }
}

test "range query contiguous slice + entries + descending" {
    var keys: [10]i32 = undefined;
    var vals: [10]i32 = undefined;
    for (0..10) |i| {
        keys[i] = @intCast((i + 1) * 10);
        vals[i] = keys[i] * 10;
    }
    var m = try Map.fromSorted(testing.allocator, &keys, &vals);
    defer m.deinit();

    {
        const r = try m.rangeKeys(I32Range.closedOpen(30, 70), testing.allocator);
        defer testing.allocator.free(r);
        try testing.expectEqualSlices(i32, &.{ 30, 40, 50, 60 }, r);
    }
    {
        const r = try m.descendingRangeKeys(I32Range.closedOpen(30, 70), testing.allocator);
        defer testing.allocator.free(r);
        try testing.expectEqualSlices(i32, &.{ 60, 50, 40, 30 }, r);
    }
    {
        const r = try m.rangeEntries(I32Range.closed(40, 50), testing.allocator);
        defer testing.allocator.free(r);
        try testing.expectEqual(@as(usize, 2), r.len);
        try testing.expectEqual(@as(i32, 40), r[0].key);
        try testing.expectEqual(@as(i32, 400), r[0].value);
        try testing.expectEqual(@as(i32, 50), r[1].key);
        try testing.expectEqual(@as(i32, 500), r[1].value);
    }
    {
        const r = try m.rangeKeys(I32Range.atLeast(80), testing.allocator);
        defer testing.allocator.free(r);
        try testing.expectEqualSlices(i32, &.{ 80, 90, 100 }, r);
    }
    {
        const r = try m.rangeKeys(I32Range.atMost(30), testing.allocator);
        defer testing.allocator.free(r);
        try testing.expectEqualSlices(i32, &.{ 10, 20, 30 }, r);
    }
    {
        const r = try m.rangeKeys(I32Range.all(), testing.allocator);
        defer testing.allocator.free(r);
        try testing.expectEqual(@as(usize, 10), r.len);
    }
}

// ── Large flat-array parity (paging-invariance trivial for a flat array) ─

test "large flat lookup parity" {
    var keys: [10_000]i32 = undefined;
    var vals: [10_000]i32 = undefined;
    for (0..10_000) |i| {
        keys[i] = @intCast(i);
        vals[i] = @intCast(i * 7);
    }
    var m = try Map.fromSorted(testing.allocator, &keys, &vals);
    defer m.deinit();
    try testing.expectEqual(@as(usize, 10_000), m.len());
    for ([_]i32{ 0, 1023, 1024, 1025, 4095, 4096, 4097, 8191, 8192, 9999 }) |probe| {
        try testing.expectEqual(@as(?i32, probe * 7), m.get(probe));
        try testing.expectEqual(@as(usize, @intCast(probe)), m.rank(probe));
        try testing.expectEqual(@as(?i32, probe), m.selectKey(@intCast(probe)));
        try testing.expectEqual(@as(?i32, probe), m.floorKey(probe));
        try testing.expectEqual(@as(?i32, probe), m.ceilingKey(probe));
    }
    try testing.expectEqual(@as(?i32, null), m.get(10_000));
    try testing.expectEqual(@as(usize, 10_000), m.rank(10_000));
    try testing.expectEqual(@as(?i32, null), m.selectKey(10_000));
    const r = try m.rangeKeys(I32Range.closedOpen(4090, 4100), testing.allocator);
    defer testing.allocator.free(r);
    try testing.expectEqual(@as(usize, 10), r.len);
}

// ── Set surface mirrors the map ──────────────────────────────────────

test "set full surface" {
    var s = try Set.fromSorted(testing.allocator, &.{ 10, 20, 30, 40, 50 });
    defer s.deinit();
    try testing.expectEqual(@as(usize, 5), s.len());
    try testing.expect(s.contains(30));
    try testing.expect(!s.contains(25));
    try testing.expectEqual(@as(?i32, 10), s.first());
    try testing.expectEqual(@as(?i32, 50), s.last());
    try testing.expectEqual(@as(?i32, 20), s.floor(25));
    try testing.expectEqual(@as(?i32, 30), s.ceiling(25));
    try testing.expectEqual(@as(?i32, null), s.lower(10));
    try testing.expectEqual(@as(?i32, null), s.higher(50));
    try testing.expectEqual(@as(usize, 2), s.rank(30));
    try testing.expectEqual(@as(?i32, 10), s.select(0));
    try testing.expectEqual(@as(?i32, null), s.select(5));
    try testing.expectEqualSlices(i32, &.{ 10, 20, 30, 40, 50 }, s.elementsSlice());

    const de = try s.descendingElements(testing.allocator);
    defer testing.allocator.free(de);
    try testing.expectEqualSlices(i32, &.{ 50, 40, 30, 20, 10 }, de);

    const re = try s.rangeElements(I32Range.closedOpen(20, 50), testing.allocator);
    defer testing.allocator.free(re);
    try testing.expectEqualSlices(i32, &.{ 20, 30, 40 }, re);

    const dre = try s.descendingRangeElements(I32Range.closedOpen(20, 50), testing.allocator);
    defer testing.allocator.free(dre);
    try testing.expectEqualSlices(i32, &.{ 40, 30, 20 }, dre);
}

// ── Generic over a second type (V != K) exercises the comptime shape ──

test "map with differing key/value types" {
    const M = ImmutableSortedMap(i32, i64);
    var m = try M.fromSorted(testing.allocator, &.{ 1, 2, 3 }, &.{ 100, 200, 300 });
    defer m.deinit();
    try testing.expectEqual(@as(?i64, 200), m.get(2));
    try testing.expectEqual(@as(?i64, null), m.get(9));
    const e = m.lastEntry().?;
    try testing.expectEqual(@as(i32, 3), e.key);
    try testing.expectEqual(@as(i64, 300), e.value);
}

comptime {
    // Force-compile the generic set shape over a second element type.
    _ = ImmutableSortedSet(i64);
}
