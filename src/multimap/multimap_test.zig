// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Tests for the generic multimap types.
//!
//! Zig only type-checks generic methods that are *referenced*. Collapsing the
//! 128 per-type multimap wrappers into 2 generics means an unreferenced method
//! on an unexercised instantiation would never be compiled — a silent coverage
//! collapse. Two mechanisms counter this:
//!   1. `refAllDeclsRecursive` over every named alias forces every method on
//!      every instantiation to be compiled.
//!   2. Parameterized runtime tests exercise the full 8x8 type axis (for both
//!      shapes) behaviourally, replacing the deleted embedded per-file tests.

const std = @import("std");
const agg = @import("multimap.zig");

const ListMultimap = agg.ListMultimap;
const SetMultimap = agg.SetMultimap;

// ---------------------------------------------------------------------------
// Force-compile every method on every instantiation.
// ---------------------------------------------------------------------------

const all_alias_types = [_]type{
    // List multimaps
    agg.BoolBoolListMultimap, agg.BoolCharListMultimap, agg.BoolF32ListMultimap, agg.BoolF64ListMultimap, agg.BoolI8ListMultimap, agg.BoolI16ListMultimap, agg.BoolI32ListMultimap, agg.BoolI64ListMultimap,
    agg.CharBoolListMultimap, agg.CharCharListMultimap, agg.CharF32ListMultimap, agg.CharF64ListMultimap, agg.CharI8ListMultimap, agg.CharI16ListMultimap, agg.CharI32ListMultimap, agg.CharI64ListMultimap,
    agg.F32BoolListMultimap,  agg.F32CharListMultimap,  agg.F32F32ListMultimap,  agg.F32F64ListMultimap,  agg.F32I8ListMultimap,  agg.F32I16ListMultimap,  agg.F32I32ListMultimap,  agg.F32I64ListMultimap,
    agg.F64BoolListMultimap,  agg.F64CharListMultimap,  agg.F64F32ListMultimap,  agg.F64F64ListMultimap,  agg.F64I8ListMultimap,  agg.F64I16ListMultimap,  agg.F64I32ListMultimap,  agg.F64I64ListMultimap,
    agg.I8BoolListMultimap,   agg.I8CharListMultimap,   agg.I8F32ListMultimap,   agg.I8F64ListMultimap,   agg.I8I8ListMultimap,   agg.I8I16ListMultimap,   agg.I8I32ListMultimap,   agg.I8I64ListMultimap,
    agg.I16BoolListMultimap,  agg.I16CharListMultimap,  agg.I16F32ListMultimap,  agg.I16F64ListMultimap,  agg.I16I8ListMultimap,  agg.I16I16ListMultimap,  agg.I16I32ListMultimap,  agg.I16I64ListMultimap,
    agg.I32BoolListMultimap,  agg.I32CharListMultimap,  agg.I32F32ListMultimap,  agg.I32F64ListMultimap,  agg.I32I8ListMultimap,  agg.I32I16ListMultimap,  agg.I32I32ListMultimap,  agg.I32I64ListMultimap,
    agg.I64BoolListMultimap,  agg.I64CharListMultimap,  agg.I64F32ListMultimap,  agg.I64F64ListMultimap,  agg.I64I8ListMultimap,  agg.I64I16ListMultimap,  agg.I64I32ListMultimap,  agg.I64I64ListMultimap,
    // Set multimaps
    agg.BoolBoolSetMultimap,  agg.BoolCharSetMultimap,  agg.BoolF32SetMultimap,  agg.BoolF64SetMultimap,  agg.BoolI8SetMultimap,  agg.BoolI16SetMultimap,  agg.BoolI32SetMultimap,  agg.BoolI64SetMultimap,
    agg.CharBoolSetMultimap,  agg.CharCharSetMultimap,  agg.CharF32SetMultimap,  agg.CharF64SetMultimap,  agg.CharI8SetMultimap,  agg.CharI16SetMultimap,  agg.CharI32SetMultimap,  agg.CharI64SetMultimap,
    agg.F32BoolSetMultimap,   agg.F32CharSetMultimap,   agg.F32F32SetMultimap,   agg.F32F64SetMultimap,   agg.F32I8SetMultimap,   agg.F32I16SetMultimap,   agg.F32I32SetMultimap,   agg.F32I64SetMultimap,
    agg.F64BoolSetMultimap,   agg.F64CharSetMultimap,   agg.F64F32SetMultimap,   agg.F64F64SetMultimap,   agg.F64I8SetMultimap,   agg.F64I16SetMultimap,   agg.F64I32SetMultimap,   agg.F64I64SetMultimap,
    agg.I8BoolSetMultimap,    agg.I8CharSetMultimap,    agg.I8F32SetMultimap,    agg.I8F64SetMultimap,    agg.I8I8SetMultimap,    agg.I8I16SetMultimap,    agg.I8I32SetMultimap,    agg.I8I64SetMultimap,
    agg.I16BoolSetMultimap,   agg.I16CharSetMultimap,   agg.I16F32SetMultimap,   agg.I16F64SetMultimap,   agg.I16I8SetMultimap,   agg.I16I16SetMultimap,   agg.I16I32SetMultimap,   agg.I16I64SetMultimap,
    agg.I32BoolSetMultimap,   agg.I32CharSetMultimap,   agg.I32F32SetMultimap,   agg.I32F64SetMultimap,   agg.I32I8SetMultimap,   agg.I32I16SetMultimap,   agg.I32I32SetMultimap,   agg.I32I64SetMultimap,
    agg.I64BoolSetMultimap,   agg.I64CharSetMultimap,   agg.I64F32SetMultimap,   agg.I64F64SetMultimap,   agg.I64I8SetMultimap,   agg.I64I16SetMultimap,   agg.I64I32SetMultimap,   agg.I64I64SetMultimap,
};

test "refAllDeclsRecursive forces every method on every instantiation to compile" {
    inline for (all_alias_types) |T| {
        std.testing.refAllDeclsRecursive(T);
    }
}

// ---------------------------------------------------------------------------
// Parameterized runtime coverage across the full 8x8 type axis, both shapes.
// ---------------------------------------------------------------------------

const type_axis = [_]type{ bool, u21, f32, f64, i8, i16, i32, i64 };

/// Two distinct sample values of type `T` (`bool` only has two inhabitants,
/// so they are forced distinct here).
fn samples(comptime T: type) [2]T {
    return switch (@typeInfo(T)) {
        .bool => .{ false, true },
        .float => .{ 1.5, 2.5 },
        .int => .{ 1, 2 },
        else => unreachable,
    };
}

test "ListMultimap: parameterized put/get/getCount/contains/remove/clear (list keeps dups)" {
    inline for (type_axis) |K| {
        inline for (type_axis) |V| {
            const ks = samples(K);
            const vs = samples(V);

            var m = ListMultimap(K, V).init(std.testing.allocator);
            defer m.deinit();

            // Two values under one key, plus a duplicate (k0,v0): list keeps it.
            m.put(ks[0], vs[0]);
            m.put(ks[0], vs[1]);
            m.put(ks[0], vs[0]); // duplicate pair -> list keeps 2 copies of vs[0]
            m.put(ks[1], vs[1]);

            // (k0,v0) appears twice, (k0,v1) once => 3 values under k0.
            try std.testing.expectEqual(@as(usize, 3), m.getCount(ks[0]));
            try std.testing.expectEqual(@as(usize, 1), m.getCount(ks[1]));
            try std.testing.expectEqual(@as(usize, 4), m.size());
            try std.testing.expectEqual(@as(usize, 4), m.len());
            try std.testing.expectEqual(@as(usize, 2), m.keysCount());
            try std.testing.expect(!m.isEmpty());

            try std.testing.expectEqual(@as(usize, 3), m.get(ks[0]).len);
            try std.testing.expect(m.containsKey(ks[0]));
            try std.testing.expect(m.containsKeyValue(ks[0], vs[0]));
            try std.testing.expect(m.containsKeyValue(ks[0], vs[1]));
            try std.testing.expect(!m.containsKeyValue(ks[1], vs[0]));

            const removed = m.removeAll(ks[0]);
            try std.testing.expectEqual(@as(usize, 3), removed);
            try std.testing.expect(!m.containsKey(ks[0]));
            try std.testing.expectEqual(@as(usize, 1), m.size());

            m.clear();
            try std.testing.expect(m.isEmpty());
            try std.testing.expectEqual(@as(usize, 0), m.size());
            try std.testing.expectEqual(@as(usize, 0), m.keysCount());
        }
    }
}

test "SetMultimap: parameterized put/get/getCount/contains/remove/clear (set dedups)" {
    inline for (type_axis) |K| {
        inline for (type_axis) |V| {
            const ks = samples(K);
            const vs = samples(V);

            var m = SetMultimap(K, V).init(std.testing.allocator);
            defer m.deinit();

            // Same (k0,v0) twice: set keeps exactly 1.
            m.put(ks[0], vs[0]);
            m.put(ks[0], vs[1]);
            m.put(ks[0], vs[0]); // duplicate pair -> dropped
            m.put(ks[1], vs[1]);

            try std.testing.expectEqual(@as(usize, 2), m.getCount(ks[0]));
            try std.testing.expectEqual(@as(usize, 1), m.getCount(ks[1]));
            try std.testing.expectEqual(@as(usize, 3), m.size());
            try std.testing.expectEqual(@as(usize, 3), m.len());
            try std.testing.expectEqual(@as(usize, 2), m.keysCount());
            try std.testing.expect(!m.isEmpty());

            try std.testing.expectEqual(@as(usize, 2), m.get(ks[0]).len);
            try std.testing.expect(m.containsKey(ks[0]));
            try std.testing.expect(m.containsKeyValue(ks[0], vs[0]));
            try std.testing.expect(m.containsKeyValue(ks[0], vs[1]));
            try std.testing.expect(!m.containsKeyValue(ks[1], vs[0]));

            const removed = m.removeAll(ks[0]);
            try std.testing.expectEqual(@as(usize, 2), removed);
            try std.testing.expect(!m.containsKey(ks[0]));
            try std.testing.expectEqual(@as(usize, 1), m.size());

            m.clear();
            try std.testing.expect(m.isEmpty());
            try std.testing.expectEqual(@as(usize, 0), m.size());
            try std.testing.expectEqual(@as(usize, 0), m.keysCount());
        }
    }
}

// ---------------------------------------------------------------------------
// Marquee smoke tests for the canonical correctness behavior.
// ---------------------------------------------------------------------------

test "ListMultimap(f32, i32) key: NaN and ±0 distinctness" {
    var m = ListMultimap(f32, i32).init(std.testing.allocator);
    defer m.deinit();
    const nan = std.math.nan(f32);
    m.put(nan, 1);
    m.put(0.0, 100);
    m.put(-0.0, 200);
    // Three bit-distinct keys -> three distinct buckets.
    try std.testing.expectEqual(@as(usize, 3), m.keysCount());
    try std.testing.expectEqual(@as(usize, 1), m.getCount(nan));
    try std.testing.expectEqual(@as(usize, 1), m.getCount(0.0));
    try std.testing.expectEqual(@as(usize, 1), m.getCount(-0.0));
    try std.testing.expectEqual(@as(i32, 1), m.get(nan)[0]);
    try std.testing.expectEqual(@as(i32, 100), m.get(0.0)[0]);
    try std.testing.expectEqual(@as(i32, 200), m.get(-0.0)[0]);
    // uniqueKeys round-trips float keys back to f32 bit patterns.
    const keys = m.uniqueKeys(std.testing.allocator);
    defer std.testing.allocator.free(keys);
    try std.testing.expectEqual(@as(usize, 3), keys.len);
}

test "SetMultimap(i32, f32) value: bit-aware dedup keeps +0.0 and -0.0 distinct" {
    var m = SetMultimap(i32, f32).init(std.testing.allocator);
    defer m.deinit();
    m.put(7, 0.0);
    m.put(7, -0.0); // distinct bits -> kept
    m.put(7, 0.0); // exact bit duplicate -> dropped
    try std.testing.expectEqual(@as(usize, 2), m.getCount(7));
    try std.testing.expect(m.containsKeyValue(7, 0.0));
    try std.testing.expect(m.containsKeyValue(7, -0.0));

    // NaN with identical bits dedups to a single entry.
    const nan = std.math.nan(f32);
    var n = SetMultimap(i32, f32).init(std.testing.allocator);
    defer n.deinit();
    n.put(1, nan);
    n.put(1, nan);
    try std.testing.expectEqual(@as(usize, 1), n.getCount(1));
}

test "SetMultimap(f32, f32): float key and float value both bit-canonicalized" {
    var m = SetMultimap(f32, f32).init(std.testing.allocator);
    defer m.deinit();
    m.put(0.0, 0.0);
    m.put(-0.0, 0.0); // distinct key -> new bucket
    m.put(0.0, -0.0); // distinct value under existing key -> kept
    m.put(0.0, 0.0); // bit-duplicate pair -> dropped
    try std.testing.expectEqual(@as(usize, 2), m.keysCount());
    try std.testing.expectEqual(@as(usize, 2), m.getCount(0.0));
    try std.testing.expectEqual(@as(usize, 1), m.getCount(-0.0));
}

test "ListMultimap(i32, i32): eql, select/reject, fluent withKeyValue" {
    var a = ListMultimap(i32, i32).init(std.testing.allocator);
    defer a.deinit();
    _ = a.withKeyValue(1, 1).withKeyValue(1, 2).withKeyValue(2, 3);
    try std.testing.expectEqual(@as(usize, 3), a.size());

    var b = ListMultimap(i32, i32).init(std.testing.allocator);
    defer b.deinit();
    b.put(1, 1);
    b.put(1, 2);
    b.put(2, 3);
    try std.testing.expect(a.eql(&b));

    var sel = a.select(struct {
        fn f(_: i32, v: i32) bool {
            return v > 1;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expectEqual(@as(usize, 2), sel.size());
    var rej = a.reject(struct {
        fn f(_: i32, v: i32) bool {
            return v > 1;
        }
    }.f);
    defer rej.deinit();
    try std.testing.expectEqual(@as(usize, 1), rej.size());
}

test "ListMultimap(i32, i32): ensureUnusedCapacity propagates allocator error" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var m = ListMultimap(i32, i32).init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(1024));
}
