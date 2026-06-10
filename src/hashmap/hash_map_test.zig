// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Tests for the generic `HashMap(K, V)` / `HashBiMap(K, V)`.
//!
//! Zig only type-checks generic methods that are *referenced*. Collapsing the
//! ~128 per-type wrappers into two generics means an unreferenced method on an
//! unexercised (K, V) would never be compiled — a silent coverage collapse.
//! Two mechanisms counter this:
//!   1. `refAllDeclsRecursive` over every named alias forces every method on
//!      every (K, V) instantiation to be compiled.
//!   2. Parameterized runtime tests exercise the full type axis behaviourally,
//!      replacing the deleted embedded per-file tests.

const std = @import("std");
const agg = @import("hashmap.zig");
const HashMap = agg.HashMap;
const HashBiMap = agg.HashBiMap;

// ---------------------------------------------------------------------------
// Force-compile every method on every (K, V) instantiation.
// ---------------------------------------------------------------------------

const all_alias_types = [_]type{
    agg.BoolBoolHashMap,   agg.BoolCharHashMap,   agg.BoolF32HashMap,   agg.BoolF64HashMap,
    agg.BoolI8HashMap,     agg.BoolI16HashMap,    agg.BoolI32HashMap,   agg.BoolI64HashMap,
    agg.CharBoolHashMap,   agg.CharCharHashMap,   agg.CharF32HashMap,   agg.CharF64HashMap,
    agg.CharI8HashMap,     agg.CharI16HashMap,    agg.CharI32HashMap,   agg.CharI64HashMap,
    agg.F32BoolHashMap,    agg.F32CharHashMap,    agg.F32F32HashMap,    agg.F32F64HashMap,
    agg.F32I8HashMap,      agg.F32I16HashMap,     agg.F32I32HashMap,    agg.F32I64HashMap,
    agg.F64BoolHashMap,    agg.F64CharHashMap,    agg.F64F32HashMap,    agg.F64F64HashMap,
    agg.F64I8HashMap,      agg.F64I16HashMap,     agg.F64I32HashMap,    agg.F64I64HashMap,
    agg.I8BoolHashMap,     agg.I8CharHashMap,     agg.I8F32HashMap,     agg.I8F64HashMap,
    agg.I8I8HashMap,       agg.I8I16HashMap,      agg.I8I32HashMap,     agg.I8I64HashMap,
    agg.I16BoolHashMap,    agg.I16CharHashMap,    agg.I16F32HashMap,    agg.I16F64HashMap,
    agg.I16I8HashMap,      agg.I16I16HashMap,     agg.I16I32HashMap,    agg.I16I64HashMap,
    agg.I32BoolHashMap,    agg.I32CharHashMap,    agg.I32F32HashMap,    agg.I32F64HashMap,
    agg.I32I8HashMap,      agg.I32I16HashMap,     agg.I32I32HashMap,    agg.I32I64HashMap,
    agg.I64BoolHashMap,    agg.I64CharHashMap,    agg.I64F32HashMap,    agg.I64F64HashMap,
    agg.I64I8HashMap,      agg.I64I16HashMap,     agg.I64I32HashMap,    agg.I64I64HashMap,
    agg.BoolBoolHashBiMap, agg.BoolCharHashBiMap, agg.BoolF32HashBiMap, agg.BoolF64HashBiMap,
    agg.BoolI8HashBiMap,   agg.BoolI16HashBiMap,  agg.BoolI32HashBiMap, agg.BoolI64HashBiMap,
    agg.CharBoolHashBiMap, agg.CharCharHashBiMap, agg.CharF32HashBiMap, agg.CharF64HashBiMap,
    agg.CharI8HashBiMap,   agg.CharI16HashBiMap,  agg.CharI32HashBiMap, agg.CharI64HashBiMap,
    agg.F32BoolHashBiMap,  agg.F32CharHashBiMap,  agg.F32F32HashBiMap,  agg.F32F64HashBiMap,
    agg.F32I8HashBiMap,    agg.F32I16HashBiMap,   agg.F32I32HashBiMap,  agg.F32I64HashBiMap,
    agg.F64BoolHashBiMap,  agg.F64CharHashBiMap,  agg.F64F32HashBiMap,  agg.F64F64HashBiMap,
    agg.F64I8HashBiMap,    agg.F64I16HashBiMap,   agg.F64I32HashBiMap,  agg.F64I64HashBiMap,
    agg.I8BoolHashBiMap,   agg.I8CharHashBiMap,   agg.I8F32HashBiMap,   agg.I8F64HashBiMap,
    agg.I8I8HashBiMap,     agg.I8I16HashBiMap,    agg.I8I32HashBiMap,   agg.I8I64HashBiMap,
    agg.I16BoolHashBiMap,  agg.I16CharHashBiMap,  agg.I16F32HashBiMap,  agg.I16F64HashBiMap,
    agg.I16I8HashBiMap,    agg.I16I16HashBiMap,   agg.I16I32HashBiMap,  agg.I16I64HashBiMap,
    agg.I32BoolHashBiMap,  agg.I32CharHashBiMap,  agg.I32F32HashBiMap,  agg.I32F64HashBiMap,
    agg.I32I8HashBiMap,    agg.I32I16HashBiMap,   agg.I32I32HashBiMap,  agg.I32I64HashBiMap,
    agg.I64BoolHashBiMap,  agg.I64CharHashBiMap,  agg.I64F32HashBiMap,  agg.I64F64HashBiMap,
    agg.I64I8HashBiMap,    agg.I64I16HashBiMap,   agg.I64I32HashBiMap,  agg.I64I64HashBiMap,
};

test "refAllDeclsRecursive forces every method on every (K,V) to compile" {
    inline for (all_alias_types) |T| {
        std.testing.refAllDeclsRecursive(T);
    }
}

// ---------------------------------------------------------------------------
// Parameterized runtime coverage across the full type axis.
// ---------------------------------------------------------------------------

const type_axis = [_]type{ bool, u21, f32, f64, i8, i16, i32, i64 };

/// Two distinct sample values of type `T`, used as keys/values in the
/// parameterized tests.
fn samples(comptime T: type) [2]T {
    return switch (@typeInfo(T)) {
        .bool => .{ false, true },
        .float => .{ 1.5, 2.5 },
        .int => .{ 1, 2 },
        else => unreachable,
    };
}

test "HashMap: parameterized put/get/remove/contains/size/clear/iterate over full axis" {
    inline for (type_axis) |K| {
        inline for (type_axis) |V| {
            const M = HashMap(K, V);
            var m = M.init(std.testing.allocator);
            defer m.deinit();

            const ks = samples(K);
            const vs = samples(V);

            // bool keys collapse two distinct sample keys; cap insertions so we
            // never assert "2 entries" for a key type with only one usable slot.
            const distinct_keys: usize = if (K == bool) 1 else 2;

            _ = m.put(ks[0], vs[0]);
            if (distinct_keys == 2) _ = m.put(ks[1], vs[1]);

            try std.testing.expectEqual(@as(?V, vs[0]), m.get(ks[0]));
            try std.testing.expect(m.containsKey(ks[0]));
            try std.testing.expectEqual(@as(usize, distinct_keys), m.size());
            try std.testing.expectEqual(@as(usize, distinct_keys), m.len());
            try std.testing.expectEqual(vs[0], m.getOrDefault(ks[0], vs[1]));

            // getOrDefault for an absent key (only meaningful when keys differ).
            if (distinct_keys == 2) {
                _ = m.remove(ks[1]);
                try std.testing.expectEqual(vs[1], m.getOrDefault(ks[1], vs[1]));
                try std.testing.expect(!m.containsKey(ks[1]));
            }

            // overwrite returns old value
            const old = m.put(ks[0], vs[1]);
            try std.testing.expectEqual(@as(?V, vs[0]), old);
            try std.testing.expectEqual(@as(?V, vs[1]), m.get(ks[0]));

            // remove returns old value
            const removed = m.remove(ks[0]);
            try std.testing.expectEqual(@as(?V, vs[1]), removed);
            try std.testing.expect(!m.containsKey(ks[0]));

            // select / reject over a freshly populated map
            _ = m.put(ks[0], vs[0]);
            if (distinct_keys == 2) _ = m.put(ks[1], vs[1]);
            const keep_all = struct {
                fn f(_: K, _: V) bool {
                    return true;
                }
            }.f;
            const drop_all = struct {
                fn f(_: K, _: V) bool {
                    return true;
                }
            }.f;
            var sel = m.select(keep_all);
            defer sel.deinit();
            try std.testing.expectEqual(@as(usize, distinct_keys), sel.len());
            var rej = m.reject(drop_all);
            defer rej.deinit();
            try std.testing.expectEqual(@as(usize, 0), rej.len());

            // count via iteration helper
            const counter = struct {
                fn f(_: K, _: V) bool {
                    return true;
                }
            }.f;
            try std.testing.expectEqual(distinct_keys, m.count(counter));

            m.clear();
            try std.testing.expect(m.isEmpty());
        }
    }
}

test "HashBiMap: parameterized forward+reverse round-trip over full axis" {
    inline for (type_axis) |K| {
        inline for (type_axis) |V| {
            const B = HashBiMap(K, V);
            var m = B.init(std.testing.allocator);
            defer m.deinit();

            const ks = samples(K);
            const vs = samples(V);
            const distinct: usize = if (K == bool or V == bool) 1 else 2;

            _ = m.put(ks[0], vs[0]);
            if (distinct == 2) _ = m.put(ks[1], vs[1]);

            // forward + reverse lookups
            try std.testing.expectEqual(@as(?V, vs[0]), m.get(ks[0]));
            try std.testing.expectEqual(@as(?K, ks[0]), m.getKey(vs[0]));
            try std.testing.expect(m.containsKey(ks[0]));
            try std.testing.expect(m.containsValue(vs[0]));
            try std.testing.expectEqual(@as(usize, distinct), m.len());

            // removeValue cleans up the forward side too
            if (distinct == 2) {
                const ok = m.removeValue(vs[1]);
                try std.testing.expectEqual(@as(?K, ks[1]), ok);
                try std.testing.expect(!m.containsKey(ks[1]));
                try std.testing.expect(!m.containsValue(vs[1]));
            }

            // inverse swaps key/value type and content
            var inv = m.inverse();
            defer inv.deinit();
            try std.testing.expectEqual(@as(?K, ks[0]), inv.get(vs[0]));

            m.clear();
            try std.testing.expect(m.isEmpty());
        }
    }
}

// ---------------------------------------------------------------------------
// Marquee smoke tests for the canonical correctness fixes.
// ---------------------------------------------------------------------------

test "I32I32HashMap: put/get/remove/size/sumOfValues/addToValue" {
    var m = agg.I32I32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 10);
    _ = m.put(2, 20);
    _ = m.put(3, 30);
    try std.testing.expectEqual(@as(?i32, 10), m.get(1));
    try std.testing.expectEqual(@as(usize, 3), m.size());
    try std.testing.expectEqual(@as(i64, 60), m.sumOfValues());
    try std.testing.expectEqual(@as(i32, 15), m.addToValue(1, 5));
    try std.testing.expectEqual(@as(?i32, 20), m.remove(2));
    try std.testing.expect(!m.containsKey(2));
}

test "F32I32HashMap: NaN key and +/-0 key distinctness" {
    var m = agg.F32I32HashMap.init(std.testing.allocator);
    defer m.deinit();

    const nan = std.math.nan(f32);
    _ = m.put(nan, 1);
    // A NaN key must be retrievable by an identical-bit NaN (NaN-aware keyEql).
    try std.testing.expectEqual(@as(?i32, 1), m.get(nan));

    // +0.0 and -0.0 are distinct keys under total-order key equality.
    _ = m.put(0.0, 100);
    _ = m.put(-0.0, 200);
    try std.testing.expectEqual(@as(?i32, 100), m.get(0.0));
    try std.testing.expectEqual(@as(?i32, 200), m.get(-0.0));
    try std.testing.expectEqual(@as(usize, 3), m.size());
}

test "F32F32HashMap: eql uses bit equality for float values" {
    var a = agg.F32F32HashMap.init(std.testing.allocator);
    defer a.deinit();
    var b = agg.F32F32HashMap.init(std.testing.allocator);
    defer b.deinit();
    const nan = std.math.nan(f32);
    _ = a.put(1.0, nan);
    _ = b.put(1.0, nan);
    // identical NaN bits => equal
    try std.testing.expect(a.eql(&b));

    var c = agg.F32F32HashMap.init(std.testing.allocator);
    defer c.deinit();
    _ = c.put(1.0, 0.0);
    var d = agg.F32F32HashMap.init(std.testing.allocator);
    defer d.deinit();
    _ = d.put(1.0, -0.0);
    // +0.0 vs -0.0 differ in bits => not equal
    try std.testing.expect(!c.eql(&d));
}

test "I64I32HashMap: high-bit-fold spread {1, 2^32+1} do not collide" {
    var m = agg.I64I32HashMap.init(std.testing.allocator);
    defer m.deinit();
    const a: i64 = 1;
    const b: i64 = (@as(i64, 1) << 32) + 1; // 2^32 + 1, differs from `a` only in the high 32 bits
    _ = m.put(a, 111);
    _ = m.put(b, 222);
    try std.testing.expectEqual(@as(usize, 2), m.size());
    try std.testing.expectEqual(@as(?i32, 111), m.get(a));
    try std.testing.expectEqual(@as(?i32, 222), m.get(b));
}

test "I32F64HashMap: float-value sumOfValues and addToValue add (not wrap)" {
    var m = agg.I32F64HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1.5);
    _ = m.put(2, 2.5);
    try std.testing.expectEqual(@as(f64, 4.0), m.sumOfValues());
    try std.testing.expectEqual(@as(f64, 3.0), m.addToValue(1, 1.5));
}

test "I32I32HashBiMap: inverse returns swapped-type map" {
    var m = agg.I32I32HashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 100);
    var inv = m.inverse();
    defer inv.deinit();
    try std.testing.expectEqual(@as(?i32, 1), inv.get(100));
    // inverse() type is HashBiMap(V, K); for symmetric (i32,i32) it is the
    // same named alias.
    try std.testing.expectEqual(agg.I32I32HashBiMap, @TypeOf(inv));
}

test "I32F32HashBiMap: inverse returns F32I32HashBiMap (transposed type)" {
    var m = agg.I32F32HashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(7, 1.25);
    var inv = m.inverse();
    defer inv.deinit();
    try std.testing.expectEqual(agg.F32I32HashBiMap, @TypeOf(inv));
    try std.testing.expectEqual(@as(?i32, 7), inv.get(1.25));
}
