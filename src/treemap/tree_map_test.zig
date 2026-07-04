// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Tests for the generic tree map type.
//!
//! Zig only type-checks generic methods that are *referenced*. Collapsing the
//! 64 per-type tree map wrappers into one `TreeMap(K, V)` generic means an
//! unreferenced method on an unexercised instantiation would never be compiled
//! — a silent coverage collapse. Two mechanisms counter this:
//!   1. `refAllDeclsRecursive` over every named alias forces every method on
//!      every instantiation to be compiled.
//!   2. Parameterized runtime tests exercise the full 8x8 type axis
//!      behaviourally, replacing the deleted embedded per-file tests.

const std = @import("std");
const agg = @import("treemap.zig");
const Range = @import("../range.zig").Range;

const TreeMap = agg.TreeMap;

// ---------------------------------------------------------------------------
// Force-compile every method on every instantiation.
// ---------------------------------------------------------------------------

const all_alias_types = [_]type{
    agg.BoolBoolTreeMap, agg.BoolCharTreeMap, agg.BoolF32TreeMap, agg.BoolF64TreeMap, agg.BoolI8TreeMap, agg.BoolI16TreeMap, agg.BoolI32TreeMap, agg.BoolI64TreeMap,
    agg.CharBoolTreeMap, agg.CharCharTreeMap, agg.CharF32TreeMap, agg.CharF64TreeMap, agg.CharI8TreeMap, agg.CharI16TreeMap, agg.CharI32TreeMap, agg.CharI64TreeMap,
    agg.F32BoolTreeMap,  agg.F32CharTreeMap,  agg.F32F32TreeMap,  agg.F32F64TreeMap,  agg.F32I8TreeMap,  agg.F32I16TreeMap,  agg.F32I32TreeMap,  agg.F32I64TreeMap,
    agg.F64BoolTreeMap,  agg.F64CharTreeMap,  agg.F64F32TreeMap,  agg.F64F64TreeMap,  agg.F64I8TreeMap,  agg.F64I16TreeMap,  agg.F64I32TreeMap,  agg.F64I64TreeMap,
    agg.I8BoolTreeMap,   agg.I8CharTreeMap,   agg.I8F32TreeMap,   agg.I8F64TreeMap,   agg.I8I8TreeMap,   agg.I8I16TreeMap,   agg.I8I32TreeMap,   agg.I8I64TreeMap,
    agg.I16BoolTreeMap,  agg.I16CharTreeMap,  agg.I16F32TreeMap,  agg.I16F64TreeMap,  agg.I16I8TreeMap,  agg.I16I16TreeMap,  agg.I16I32TreeMap,  agg.I16I64TreeMap,
    agg.I32BoolTreeMap,  agg.I32CharTreeMap,  agg.I32F32TreeMap,  agg.I32F64TreeMap,  agg.I32I8TreeMap,  agg.I32I16TreeMap,  agg.I32I32TreeMap,  agg.I32I64TreeMap,
    agg.I64BoolTreeMap,  agg.I64CharTreeMap,  agg.I64F32TreeMap,  agg.I64F64TreeMap,  agg.I64I8TreeMap,  agg.I64I16TreeMap,  agg.I64I32TreeMap,  agg.I64I64TreeMap,
};

test "refAllDeclsRecursive forces every method on every instantiation to compile" {
    inline for (all_alias_types) |T| {
        std.testing.refAllDeclsRecursive(T);
    }
}

// ---------------------------------------------------------------------------
// Parameterized runtime coverage across the full 8x8 type axis.
// ---------------------------------------------------------------------------

const type_axis = [_]type{ bool, u21, f32, f64, i8, i16, i32, i64 };

/// Two distinct sample values of type `T`, returned in ascending key order
/// (`lo` sorts before `hi` under the canonical comparator). `bool` only has two
/// inhabitants, so they are forced distinct here.
fn samples(comptime T: type) [2]T {
    return switch (@typeInfo(T)) {
        .bool => .{ false, true },
        .float => .{ 1.5, 2.5 },
        .int => .{ 1, 2 },
        else => unreachable,
    };
}

test "TreeMap: parameterized put/get/containsKey/getOrDefault/remove/clear" {
    inline for (type_axis) |K| {
        inline for (type_axis) |V| {
            const ks = samples(K);
            const vs = samples(V);

            var m = TreeMap(K, V).init(std.testing.allocator);
            defer m.deinit();

            try std.testing.expect(m.isEmpty());
            try std.testing.expectEqual(@as(?V, null), m.put(ks[0], vs[0]));
            try std.testing.expectEqual(@as(?V, null), m.put(ks[1], vs[1]));
            try std.testing.expectEqual(@as(usize, 2), m.len());
            try std.testing.expectEqual(@as(usize, 2), m.len());
            try std.testing.expect(!m.isEmpty());

            // Overwrite returns old value.
            try std.testing.expectEqual(@as(?V, vs[0]), m.put(ks[0], vs[1]));
            try std.testing.expectEqual(@as(?V, vs[1]), m.get(ks[0]));

            try std.testing.expect(m.containsKey(ks[0]));
            try std.testing.expect(m.containsKey(ks[1]));
            try std.testing.expectEqual(vs[1], m.getOrDefault(ks[0], vs[0]));

            // remove a present key returns its value; absent key returns null.
            try std.testing.expectEqual(@as(?V, vs[1]), m.remove(ks[0]));
            try std.testing.expect(!m.containsKey(ks[0]));
            try std.testing.expectEqual(@as(usize, 1), m.len());

            m.clear();
            try std.testing.expect(m.isEmpty());
            try std.testing.expectEqual(@as(usize, 0), m.len());
        }
    }
}

test "TreeMap: parameterized sorted iteration, min, max, range, navigation" {
    inline for (type_axis) |K| {
        inline for (type_axis) |V| {
            const ks = samples(K);
            const vs = samples(V);

            var m = TreeMap(K, V).init(std.testing.allocator);
            defer m.deinit();

            // Insert in reverse key order; tree must store them sorted.
            _ = try m.put(ks[1], vs[1]);
            _ = try m.put(ks[0], vs[0]);

            const keys = m.keysSlice();
            try std.testing.expectEqual(@as(usize, 2), keys.len);
            try std.testing.expect(keys[0] == ks[0]); // lo sorts first
            try std.testing.expect(keys[1] == ks[1]);

            const vals = m.valuesSlice();
            try std.testing.expect(vals[0] == vs[0]);
            try std.testing.expect(vals[1] == vs[1]);

            const mn = m.min().?;
            try std.testing.expect(mn.key == ks[0]);
            const mx = m.max().?;
            try std.testing.expect(mx.key == ks[1]);

            // ceiling(lo) == lo entry; floor(hi) == hi entry.
            try std.testing.expect(m.ceiling(ks[0]).?.key == ks[0]);
            try std.testing.expect(m.floor(ks[1]).?.key == ks[1]);

            // rangeKeys over [lo, hi] returns both keys in order.
            const rk = m.rangeKeysSlice(ks[0], ks[1]);
            try std.testing.expectEqual(@as(usize, 2), rk.len);
            try std.testing.expect(rk[0] == ks[0]);
            try std.testing.expect(rk[1] == ks[1]);
        }
    }
}

test "TreeMap: parameterized functional ops, fluent API, eql" {
    inline for (type_axis) |K| {
        inline for (type_axis) |V| {
            const ks = samples(K);
            const vs = samples(V);

            var a = TreeMap(K, V).init(std.testing.allocator);
            defer a.deinit();
            _ = try a.withKeyValue(ks[0], vs[0]);
            _ = try a.withKeyValue(ks[1], vs[1]);
            try std.testing.expectEqual(@as(usize, 2), a.len());

            // Insertion-order independence of eql (TreeMap is always sorted).
            var b = TreeMap(K, V).init(std.testing.allocator);
            defer b.deinit();
            _ = try b.put(ks[1], vs[1]);
            _ = try b.put(ks[0], vs[0]);
            try std.testing.expect(a.eql(&b));

            // withoutKey drops an entry.
            _ = a.withoutKey(ks[0]);
            try std.testing.expect(!a.containsKey(ks[0]));
            try std.testing.expect(!a.eql(&b));

            // count predicate over b (matches everything).
            const total = b.count({}, struct {
                fn f(_: void, _: K, _: V) bool {
                    return true;
                }
            }.f);
            try std.testing.expectEqual(@as(usize, 2), total);
            try std.testing.expect(b.anySatisfy({}, struct {
                fn f(_: void, _: K, _: V) bool {
                    return true;
                }
            }.f));
            try std.testing.expect(b.allSatisfy({}, struct {
                fn f(_: void, _: K, _: V) bool {
                    return true;
                }
            }.f));
            try std.testing.expect(b.noneSatisfy({}, struct {
                fn f(_: void, _: K, _: V) bool {
                    return false;
                }
            }.f));
        }
    }
}

test "TreeMap: ensureUnusedCapacity propagates allocator error" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var m = TreeMap(i32, i32).init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(1024));
}

// ---------------------------------------------------------------------------
// Marquee tests for the canonical correctness behavior.
// ---------------------------------------------------------------------------

test "TreeMap(f32, i32) key: IEEE 754 total order — NaN at the end, -0 vs +0 distinct" {
    var m = TreeMap(f32, i32).init(std.testing.allocator);
    defer m.deinit();
    const nan = std.math.nan(f32);
    const ninf = -std.math.inf(f32);
    const pinf = std.math.inf(f32);

    // Insert in a deliberately scrambled order.
    _ = try m.put(nan, 7);
    _ = try m.put(0.0, 100);
    _ = try m.put(-0.0, 200);
    _ = try m.put(1.0, 1);
    _ = try m.put(-1.0, -1);
    _ = try m.put(pinf, 9);
    _ = try m.put(ninf, 8);

    // -0.0 and +0.0 are bit-distinct keys: both retained.
    try std.testing.expectEqual(@as(usize, 7), m.len());

    // Canonical total order: -Inf < -1 < -0.0 < +0.0 < 1 < +Inf < +NaN.
    const keys = m.keysSlice();
    try std.testing.expect(keys[0] == ninf);
    try std.testing.expect(keys[1] == -1.0);
    // keys[2] is -0.0, keys[3] is +0.0 — distinguish by sign bit.
    try std.testing.expect(keys[2] == 0.0 and std.math.signbit(keys[2]));
    try std.testing.expect(keys[3] == 0.0 and !std.math.signbit(keys[3]));
    try std.testing.expect(keys[4] == 1.0);
    try std.testing.expect(keys[5] == pinf);
    try std.testing.expect(std.math.isNan(keys[6])); // NaN sorts to the very end

    try std.testing.expectEqual(@as(?i32, 200), m.get(-0.0));
    try std.testing.expectEqual(@as(?i32, 100), m.get(0.0));
    try std.testing.expectEqual(@as(?i32, 7), m.get(nan));

    // min/max reflect the total order, not raw float compare.
    try std.testing.expect(m.min().?.key == ninf);
    try std.testing.expect(std.math.isNan(m.max().?.key));
}

test "TreeMap(f64, i32) key: NaN/-0/+0 total order on f64 width" {
    var m = TreeMap(f64, i32).init(std.testing.allocator);
    defer m.deinit();
    const nan = std.math.nan(f64);
    _ = try m.put(nan, 1);
    _ = try m.put(-0.0, 2);
    _ = try m.put(0.0, 3);
    try std.testing.expectEqual(@as(usize, 3), m.len());
    const keys = m.keysSlice();
    try std.testing.expect(keys[0] == 0.0 and std.math.signbit(keys[0])); // -0.0
    try std.testing.expect(keys[1] == 0.0 and !std.math.signbit(keys[1])); // +0.0
    try std.testing.expect(std.math.isNan(keys[2]));
}

test "TreeMap(i32, f32) value: eql uses exact-bit float equality (-0 != +0)" {
    var a = TreeMap(i32, f32).init(std.testing.allocator);
    defer a.deinit();
    _ = try a.put(1, 0.0);

    var b = TreeMap(i32, f32).init(std.testing.allocator);
    defer b.deinit();
    _ = try b.put(1, -0.0);

    // 0.0 == -0.0 numerically, but their bits differ -> eql must report unequal.
    try std.testing.expect(!a.eql(&b));

    // Identical bits -> equal.
    var c = TreeMap(i32, f32).init(std.testing.allocator);
    defer c.deinit();
    _ = try c.put(1, 0.0);
    try std.testing.expect(a.eql(&c));

    // NaN with identical bits compares equal under bit-equality.
    const nan = std.math.nan(f32);
    var d = TreeMap(i32, f32).init(std.testing.allocator);
    defer d.deinit();
    _ = try d.put(1, nan);
    var e = TreeMap(i32, f32).init(std.testing.allocator);
    defer e.deinit();
    _ = try e.put(1, nan);
    try std.testing.expect(d.eql(&e));
}

test "TreeMap(bool, i32) key: false sorts before true" {
    var m = TreeMap(bool, i32).init(std.testing.allocator);
    defer m.deinit();
    _ = try m.put(true, 10);
    _ = try m.put(false, 20);
    const keys = m.keysSlice();
    try std.testing.expectEqual(false, keys[0]);
    try std.testing.expectEqual(true, keys[1]);
    try std.testing.expect(m.min().?.key == false);
    try std.testing.expect(m.max().?.key == true);
}

test "TreeMap(char, i32) key: u21 natural order" {
    var m = TreeMap(u21, i32).init(std.testing.allocator);
    defer m.deinit();
    _ = try m.put('z', 1);
    _ = try m.put('a', 2);
    _ = try m.put('m', 3);
    const keys = m.keysSlice();
    try std.testing.expectEqual(@as(u21, 'a'), keys[0]);
    try std.testing.expectEqual(@as(u21, 'm'), keys[1]);
    try std.testing.expectEqual(@as(u21, 'z'), keys[2]);
}

// ---------------------------------------------------------------------------
// NavigableMap surface (mirrors mapdb-rust/src/object/treemap.rs tests).
// ---------------------------------------------------------------------------

const I32Map = TreeMap(i32, i32);
const I32Range = Range(i32);

fn mapOf(allocator: std.mem.Allocator, keys: []const i32) !I32Map {
    var m = I32Map.init(allocator);
    for (keys) |k| _ = try m.put(k, k *% 10);
    return m;
}

test "TreeMap nav: floor/ceiling/lower/higher strictness + entry forms" {
    var m = try mapOf(std.testing.allocator, &.{ 10, 20, 30 });
    defer m.deinit();
    try std.testing.expectEqual(@as(?i32, 20), m.floorKey(25));
    try std.testing.expectEqual(@as(?i32, 30), m.ceilingKey(25));
    try std.testing.expectEqual(@as(?i32, 10), m.floorKey(10)); // inclusive
    try std.testing.expectEqual(@as(?i32, null), m.lowerKey(10)); // strict
    try std.testing.expectEqual(@as(?i32, null), m.higherKey(30)); // strict
    try std.testing.expectEqual(@as(?i32, 10), m.ceilingKey(5));
    try std.testing.expectEqual(@as(?i32, 20), m.lowerKey(25));
    try std.testing.expectEqual(@as(?i32, 30), m.higherKey(25));
    // entry forms carry value = key*10.
    const fe = m.floorEntry(25).?;
    try std.testing.expectEqual(@as(i32, 20), fe.key);
    try std.testing.expectEqual(@as(i32, 200), fe.value);
    const ce = m.ceilingEntry(25).?;
    try std.testing.expectEqual(@as(i32, 30), ce.key);
    try std.testing.expectEqual(@as(i32, 300), ce.value);
    try std.testing.expectEqual(@as(i32, 10), m.firstKey().?);
    try std.testing.expectEqual(@as(i32, 30), m.lastKey().?);
    try std.testing.expectEqual(@as(i32, 100), m.firstEntry().?.value);
    try std.testing.expectEqual(@as(i32, 300), m.lastEntry().?.value);
}

test "TreeMap nav: empty map returns absence for every nav query" {
    var m = try mapOf(std.testing.allocator, &.{});
    defer m.deinit();
    try std.testing.expectEqual(@as(?i32, null), m.floorKey(5));
    try std.testing.expectEqual(@as(?i32, null), m.ceilingKey(5));
    try std.testing.expectEqual(@as(?i32, null), m.lowerKey(5));
    try std.testing.expectEqual(@as(?i32, null), m.higherKey(5));
    try std.testing.expectEqual(@as(?i32, null), m.firstKey());
    try std.testing.expectEqual(@as(?i32, null), m.lastKey());
    try std.testing.expect(m.firstEntry() == null);
    try std.testing.expect(m.floorEntry(5) == null);
}

test "TreeMap nav: signed i32 MIN/MAX + descending keys" {
    var m = try mapOf(std.testing.allocator, &.{ std.math.minInt(i32), -1, 0, 1, std.math.maxInt(i32) });
    defer m.deinit();
    try std.testing.expectEqual(@as(?i32, std.math.minInt(i32)), m.floorKey(std.math.minInt(i32)));
    try std.testing.expectEqual(@as(?i32, null), m.lowerKey(std.math.minInt(i32)));
    try std.testing.expectEqual(@as(?i32, 0), m.higherKey(-1));
    try std.testing.expectEqual(@as(?i32, std.math.maxInt(i32)), m.ceilingKey(std.math.maxInt(i32)));
    try std.testing.expectEqual(@as(?i32, null), m.higherKey(std.math.maxInt(i32)));
    const desc = try m.descendingKeys(std.testing.allocator);
    defer std.testing.allocator.free(desc);
    try std.testing.expectEqualSlices(i32, &.{ std.math.maxInt(i32), 1, 0, -1, std.math.minInt(i32) }, desc);
}

test "TreeMap poll: first/last then empty (does not trap)" {
    var m = try mapOf(std.testing.allocator, &.{ 10, 20, 30 });
    defer m.deinit();
    const f = m.pollFirstEntry().?;
    try std.testing.expectEqual(@as(i32, 10), f.key);
    try std.testing.expectEqual(@as(i32, 100), f.value);
    const l = m.pollLastEntry().?;
    try std.testing.expectEqual(@as(i32, 30), l.key);
    try std.testing.expectEqual(@as(usize, 1), m.len());
    try std.testing.expectEqual(@as(i32, 20), m.pollFirstEntry().?.key);
    try std.testing.expect(m.pollFirstEntry() == null);
    try std.testing.expect(m.pollLastEntry() == null);
}

test "TreeMap poll: single element then empty" {
    var m = try mapOf(std.testing.allocator, &.{});
    defer m.deinit();
    _ = try m.put(7, 700);
    const e = m.pollFirstEntry().?;
    try std.testing.expectEqual(@as(i32, 7), e.key);
    try std.testing.expectEqual(@as(i32, 700), e.value);
    try std.testing.expect(m.pollFirstEntry() == null);
    try std.testing.expect(m.isEmpty());
}

test "TreeMap range: closed_open + descending + entries" {
    var m = try mapOf(std.testing.allocator, &.{ 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 });
    defer m.deinit();
    const rk = try m.rangeKeysIn(I32Range.closedOpen(30, 70), std.testing.allocator);
    defer std.testing.allocator.free(rk);
    try std.testing.expectEqualSlices(i32, &.{ 30, 40, 50, 60 }, rk);
    const rkd = try m.descendingRangeKeys(I32Range.closedOpen(30, 70), std.testing.allocator);
    defer std.testing.allocator.free(rkd);
    try std.testing.expectEqualSlices(i32, &.{ 60, 50, 40, 30 }, rkd);
    const re = try m.rangeEntriesIn(I32Range.closedOpen(30, 50), std.testing.allocator);
    defer std.testing.allocator.free(re);
    try std.testing.expectEqual(@as(usize, 2), re.len);
    try std.testing.expectEqual(@as(i32, 30), re[0].key);
    try std.testing.expectEqual(@as(i32, 300), re[0].value);
    try std.testing.expectEqual(@as(i32, 40), re[1].key);
}

test "TreeMap range: open(1,2) over i32 matches nothing (not cut-empty)" {
    var m = try mapOf(std.testing.allocator, &.{ 1, 2 });
    defer m.deinit();
    const rk = try m.rangeKeysIn(I32Range.open(1, 2), std.testing.allocator);
    defer std.testing.allocator.free(rk);
    try std.testing.expectEqual(@as(usize, 0), rk.len);
    try std.testing.expectEqual(@as(usize, 0), m.removeRange(I32Range.open(1, 2)));
    try std.testing.expectEqual(@as(usize, 2), m.len());
}

test "TreeMap removeRange: count + no-op repeat" {
    var m = try mapOf(std.testing.allocator, &.{ 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 });
    defer m.deinit();
    try std.testing.expectEqual(@as(usize, 4), m.removeRange(I32Range.closedOpen(30, 70)));
    try std.testing.expectEqual(@as(usize, 0), m.removeRange(I32Range.closedOpen(30, 70)));
    try std.testing.expectEqualSlices(i32, &.{ 10, 20, 70, 80, 90, 100 }, m.keysSlice());
}

test "TreeMap subMap: independent materialized snapshot" {
    var m = try mapOf(std.testing.allocator, &.{ 10, 20, 30, 40, 50 });
    defer m.deinit();
    var snap = try m.subMap(I32Range.closed(20, 40), std.testing.allocator);
    defer snap.deinit();
    try std.testing.expectEqualSlices(i32, &.{ 20, 30, 40 }, snap.keysSlice());
    // Mutate snapshot — original unchanged.
    _ = try snap.put(99, 990);
    _ = snap.remove(20);
    try std.testing.expect(m.containsKey(20));
    try std.testing.expect(!m.containsKey(99));
    // Mutate original — snapshot unchanged.
    _ = m.remove(30);
    try std.testing.expect(snap.containsKey(30));
}

test "TreeMap descendingEntries: all entries descending" {
    var m = try mapOf(std.testing.allocator, &.{ 10, 20, 30 });
    defer m.deinit();
    const de = try m.descendingEntries(std.testing.allocator);
    defer std.testing.allocator.free(de);
    try std.testing.expectEqual(@as(usize, 3), de.len);
    try std.testing.expectEqual(@as(i32, 30), de[0].key);
    try std.testing.expectEqual(@as(i32, 300), de[0].value);
    try std.testing.expectEqual(@as(i32, 10), de[2].key);
}

// ---------------------------------------------------------------------------
// Order statistics (rank / select).
// ---------------------------------------------------------------------------

test "TreeMap rank: present and absent keys" {
    var m = try mapOf(std.testing.allocator, &.{ 10, 20, 30, 40, 50 });
    defer m.deinit();
    try std.testing.expectEqual(@as(usize, 0), m.rank(10));
    try std.testing.expectEqual(@as(usize, 2), m.rank(30));
    try std.testing.expectEqual(@as(usize, 4), m.rank(50));
    try std.testing.expectEqual(@as(usize, 0), m.rank(5));
    try std.testing.expectEqual(@as(usize, 2), m.rank(25));
    try std.testing.expectEqual(@as(usize, 5), m.rank(55));
}

test "TreeMap selectKey/selectEntry and round-trip" {
    var m = try mapOf(std.testing.allocator, &.{ 10, 20, 30, 40, 50 });
    defer m.deinit();
    try std.testing.expectEqual(@as(?i32, 10), m.selectKey(0));
    try std.testing.expectEqual(@as(?i32, 30), m.selectKey(2));
    try std.testing.expectEqual(@as(?i32, 50), m.selectKey(4));
    try std.testing.expectEqual(@as(?i32, null), m.selectKey(5));
    try std.testing.expectEqual(@as(?i32, null), m.selectKey(999));
    try std.testing.expectEqual(@as(i32, 10), m.selectEntry(0).?.key);
    try std.testing.expectEqual(@as(i32, 100), m.selectEntry(0).?.value);
    try std.testing.expectEqual(@as(i32, 300), m.selectEntry(2).?.value);
    try std.testing.expect(m.selectEntry(5) == null);
    var i: usize = 0;
    while (i < m.len()) : (i += 1) {
        const k = m.selectKey(i).?;
        try std.testing.expectEqual(i, m.rank(k));
        try std.testing.expectEqual(@as(?i32, k), m.selectKey(m.rank(k)));
    }
    try std.testing.expectEqual(@as(?i32, null), m.selectKey(m.len()));
}

test "TreeMap rank/select: empty, single, signed extremes, after remove" {
    var empty = I32Map.init(std.testing.allocator);
    defer empty.deinit();
    try std.testing.expectEqual(@as(usize, 0), empty.rank(5));
    try std.testing.expectEqual(@as(?i32, null), empty.selectKey(0));

    var single = try mapOf(std.testing.allocator, &.{7});
    defer single.deinit();
    try std.testing.expectEqual(@as(usize, 0), single.rank(6));
    try std.testing.expectEqual(@as(usize, 0), single.rank(7));
    try std.testing.expectEqual(@as(usize, 1), single.rank(8));
    try std.testing.expectEqual(@as(?i32, 7), single.selectKey(0));
    try std.testing.expectEqual(@as(?i32, null), single.selectKey(1));

    var ext = try mapOf(std.testing.allocator, &.{ std.math.minInt(i32), -1, 0, 1, std.math.maxInt(i32) });
    defer ext.deinit();
    try std.testing.expectEqual(@as(usize, 0), ext.rank(std.math.minInt(i32)));
    try std.testing.expectEqual(@as(usize, 2), ext.rank(0));
    try std.testing.expectEqual(@as(usize, 4), ext.rank(std.math.maxInt(i32)));
    try std.testing.expectEqual(@as(?i32, std.math.minInt(i32)), ext.selectKey(0));
    try std.testing.expectEqual(@as(?i32, std.math.maxInt(i32)), ext.selectKey(4));
    try std.testing.expectEqual(@as(?i32, null), ext.selectKey(5));

    var rem = try mapOf(std.testing.allocator, &.{ 10, 20, 30, 40, 50 });
    defer rem.deinit();
    _ = rem.remove(30);
    try std.testing.expectEqual(@as(usize, 2), rem.rank(40));
    try std.testing.expectEqual(@as(usize, 2), rem.rank(35));
    try std.testing.expectEqual(@as(?i32, 40), rem.selectKey(2));
    try std.testing.expectEqual(@as(?i32, null), rem.selectKey(4));
}

// ---------------------------------------------------------------------------
// D11: `{f}` format-string dispatch reaches the 1-arg custom `format` method.
// ---------------------------------------------------------------------------

test "TreeMap: {f} dispatch renders {1=10, 2=20} in sorted key order" {
    var m = TreeMap(i32, i32).init(std.testing.allocator);
    defer m.deinit();
    _ = try m.put(2, 20);
    _ = try m.put(1, 10);
    const out = try std.fmt.allocPrint(std.testing.allocator, "{f}", .{m});
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("{1=10, 2=20}", out);
}
