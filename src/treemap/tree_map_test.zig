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
            try std.testing.expectEqual(@as(usize, 2), m.size());
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
            _ = m.put(ks[1], vs[1]);
            _ = m.put(ks[0], vs[0]);

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
            const rk = m.rangeKeys(ks[0], ks[1]);
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
            _ = a.withKeyValue(ks[0], vs[0]).withKeyValue(ks[1], vs[1]);
            try std.testing.expectEqual(@as(usize, 2), a.size());

            // Insertion-order independence of eql (TreeMap is always sorted).
            var b = TreeMap(K, V).init(std.testing.allocator);
            defer b.deinit();
            _ = b.put(ks[1], vs[1]);
            _ = b.put(ks[0], vs[0]);
            try std.testing.expect(a.eql(&b));

            // withoutKey drops an entry.
            _ = a.withoutKey(ks[0]);
            try std.testing.expect(!a.containsKey(ks[0]));
            try std.testing.expect(!a.eql(&b));

            // count predicate over b (matches everything).
            const total = b.count(struct {
                fn f(_: K, _: V) bool {
                    return true;
                }
            }.f);
            try std.testing.expectEqual(@as(usize, 2), total);
            try std.testing.expect(b.anySatisfy(struct {
                fn f(_: K, _: V) bool {
                    return true;
                }
            }.f));
            try std.testing.expect(b.allSatisfy(struct {
                fn f(_: K, _: V) bool {
                    return true;
                }
            }.f));
            try std.testing.expect(b.noneSatisfy(struct {
                fn f(_: K, _: V) bool {
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
    _ = m.put(nan, 7);
    _ = m.put(0.0, 100);
    _ = m.put(-0.0, 200);
    _ = m.put(1.0, 1);
    _ = m.put(-1.0, -1);
    _ = m.put(pinf, 9);
    _ = m.put(ninf, 8);

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
    _ = m.put(nan, 1);
    _ = m.put(-0.0, 2);
    _ = m.put(0.0, 3);
    try std.testing.expectEqual(@as(usize, 3), m.len());
    const keys = m.keysSlice();
    try std.testing.expect(keys[0] == 0.0 and std.math.signbit(keys[0])); // -0.0
    try std.testing.expect(keys[1] == 0.0 and !std.math.signbit(keys[1])); // +0.0
    try std.testing.expect(std.math.isNan(keys[2]));
}

test "TreeMap(i32, f32) value: eql uses exact-bit float equality (-0 != +0)" {
    var a = TreeMap(i32, f32).init(std.testing.allocator);
    defer a.deinit();
    _ = a.put(1, 0.0);

    var b = TreeMap(i32, f32).init(std.testing.allocator);
    defer b.deinit();
    _ = b.put(1, -0.0);

    // 0.0 == -0.0 numerically, but their bits differ -> eql must report unequal.
    try std.testing.expect(!a.eql(&b));

    // Identical bits -> equal.
    var c = TreeMap(i32, f32).init(std.testing.allocator);
    defer c.deinit();
    _ = c.put(1, 0.0);
    try std.testing.expect(a.eql(&c));

    // NaN with identical bits compares equal under bit-equality.
    const nan = std.math.nan(f32);
    var d = TreeMap(i32, f32).init(std.testing.allocator);
    defer d.deinit();
    _ = d.put(1, nan);
    var e = TreeMap(i32, f32).init(std.testing.allocator);
    defer e.deinit();
    _ = e.put(1, nan);
    try std.testing.expect(d.eql(&e));
}

test "TreeMap(bool, i32) key: false sorts before true" {
    var m = TreeMap(bool, i32).init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 10);
    _ = m.put(false, 20);
    const keys = m.keysSlice();
    try std.testing.expectEqual(false, keys[0]);
    try std.testing.expectEqual(true, keys[1]);
    try std.testing.expect(m.min().?.key == false);
    try std.testing.expect(m.max().?.key == true);
}

test "TreeMap(char, i32) key: u21 natural order" {
    var m = TreeMap(u21, i32).init(std.testing.allocator);
    defer m.deinit();
    _ = m.put('z', 1);
    _ = m.put('a', 2);
    _ = m.put('m', 3);
    const keys = m.keysSlice();
    try std.testing.expectEqual(@as(u21, 'a'), keys[0]);
    try std.testing.expectEqual(@as(u21, 'm'), keys[1]);
    try std.testing.expectEqual(@as(u21, 'z'), keys[2]);
}
