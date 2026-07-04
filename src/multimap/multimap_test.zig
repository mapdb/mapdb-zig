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
            try m.put(ks[0], vs[0]);
            try m.put(ks[0], vs[1]);
            try m.put(ks[0], vs[0]); // duplicate pair -> list keeps 2 copies of vs[0]
            try m.put(ks[1], vs[1]);

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
            try m.put(ks[0], vs[0]);
            try m.put(ks[0], vs[1]);
            try m.put(ks[0], vs[0]); // duplicate pair -> dropped
            try m.put(ks[1], vs[1]);

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
    try m.put(nan, 1);
    try m.put(0.0, 100);
    try m.put(-0.0, 200);
    // Three bit-distinct keys -> three distinct buckets.
    try std.testing.expectEqual(@as(usize, 3), m.keysCount());
    try std.testing.expectEqual(@as(usize, 1), m.getCount(nan));
    try std.testing.expectEqual(@as(usize, 1), m.getCount(0.0));
    try std.testing.expectEqual(@as(usize, 1), m.getCount(-0.0));
    try std.testing.expectEqual(@as(i32, 1), m.get(nan)[0]);
    try std.testing.expectEqual(@as(i32, 100), m.get(0.0)[0]);
    try std.testing.expectEqual(@as(i32, 200), m.get(-0.0)[0]);
    // uniqueKeys round-trips float keys back to f32 bit patterns.
    const keys = try m.uniqueKeys(std.testing.allocator);
    defer std.testing.allocator.free(keys);
    try std.testing.expectEqual(@as(usize, 3), keys.len);
}

test "SetMultimap(i32, f32) value: bit-aware dedup keeps +0.0 and -0.0 distinct" {
    var m = SetMultimap(i32, f32).init(std.testing.allocator);
    defer m.deinit();
    try m.put(7, 0.0);
    try m.put(7, -0.0); // distinct bits -> kept
    try m.put(7, 0.0); // exact bit duplicate -> dropped
    try std.testing.expectEqual(@as(usize, 2), m.getCount(7));
    try std.testing.expect(m.containsKeyValue(7, 0.0));
    try std.testing.expect(m.containsKeyValue(7, -0.0));

    // NaN with identical bits dedups to a single entry.
    const nan = std.math.nan(f32);
    var n = SetMultimap(i32, f32).init(std.testing.allocator);
    defer n.deinit();
    try n.put(1, nan);
    try n.put(1, nan);
    try std.testing.expectEqual(@as(usize, 1), n.getCount(1));
}

test "SetMultimap(f32, f32): float key and float value both bit-canonicalized" {
    var m = SetMultimap(f32, f32).init(std.testing.allocator);
    defer m.deinit();
    try m.put(0.0, 0.0);
    try m.put(-0.0, 0.0); // distinct key -> new bucket
    try m.put(0.0, -0.0); // distinct value under existing key -> kept
    try m.put(0.0, 0.0); // bit-duplicate pair -> dropped
    try std.testing.expectEqual(@as(usize, 2), m.keysCount());
    try std.testing.expectEqual(@as(usize, 2), m.getCount(0.0));
    try std.testing.expectEqual(@as(usize, 1), m.getCount(-0.0));
}

test "ListMultimap(i32, i32): eql, select/reject, fluent withKeyValue" {
    var a = ListMultimap(i32, i32).init(std.testing.allocator);
    defer a.deinit();
    _ = try a.withKeyValue(1, 1);
    _ = try a.withKeyValue(1, 2);
    _ = try a.withKeyValue(2, 3);
    try std.testing.expectEqual(@as(usize, 3), a.size());

    var b = ListMultimap(i32, i32).init(std.testing.allocator);
    defer b.deinit();
    try b.put(1, 1);
    try b.put(1, 2);
    try b.put(2, 3);
    try std.testing.expect(a.eql(&b));

    var ctx: u8 = 0;
    var sel = try a.select(&ctx, struct {
        fn f(_: *anyopaque, _: i32, v: i32) bool {
            return v > 1;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expectEqual(@as(usize, 2), sel.size());
    var rej = try a.reject(&ctx, struct {
        fn f(_: *anyopaque, _: i32, v: i32) bool {
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

// Scaled KEY-IDENTITY stress test, NOT a hash-distribution test. The multimaps
// back onto std.AutoHashMap, whose bucket distribution is not observable and
// whose collisions are functionally invisible, so distribution quality cannot
// be asserted behaviourally. What IS observable — and what the cross-language
// validator only checks at 8 keys — is that a large family of keys sharing
// identical low 32 bits and differing only in the high 32 bits (the family that
// would collapse under a low-bits-only hash) each survives as a distinct,
// correctly-valued entry through the AutoHashMap resize path.
fn highBitKey(i: i64) i64 {
    return (i << 32) | 1; // 1, 2^32+1, 2*2^32+1, ...
}

test "ListMultimap(i64, i32): high-32-bit-varying key family stays distinct at scale" {
    const N: i64 = 5000;
    var m = ListMultimap(i64, i32).init(std.testing.allocator);
    defer m.deinit();
    var i: i64 = 0;
    while (i < N) : (i += 1) try m.put(highBitKey(i), @intCast(i));
    try std.testing.expectEqual(@as(usize, @intCast(N)), m.keysCount());
    i = 0;
    while (i < N) : (i += 1) {
        const key = highBitKey(i);
        try std.testing.expect(m.containsKey(key));
        const vals = m.get(key);
        try std.testing.expectEqual(@as(usize, 1), vals.len);
        try std.testing.expectEqual(@as(i32, @intCast(i)), vals[0]);
    }
    try std.testing.expect(!m.containsKey(highBitKey(N)));
}

test "SetMultimap(i64, i32): high-32-bit-varying key family stays distinct at scale" {
    const N: i64 = 5000;
    var m = SetMultimap(i64, i32).init(std.testing.allocator);
    defer m.deinit();
    var i: i64 = 0;
    while (i < N) : (i += 1) try m.put(highBitKey(i), @intCast(i));
    try std.testing.expectEqual(@as(usize, @intCast(N)), m.keysCount());
    i = 0;
    while (i < N) : (i += 1) {
        const key = highBitKey(i);
        try std.testing.expect(m.containsKey(key));
        const vals = m.get(key);
        try std.testing.expectEqual(@as(usize, 1), vals.len);
        try std.testing.expectEqual(@as(i32, @intCast(i)), vals[0]);
    }
    try std.testing.expect(!m.containsKey(highBitKey(N)));
}

// ---------------------------------------------------------------------------
// F5: a failed put must not leave an observable empty key entry.
// ---------------------------------------------------------------------------

test "ListMultimap put rolls back new key on append OOM (F5)" {
    var fail_index: usize = 0;
    while (fail_index < 64) : (fail_index += 1) {
        var failing = std.testing.FailingAllocator.init(
            std.testing.allocator,
            .{ .fail_index = fail_index },
        );
        var m = ListMultimap(i32, i32).init(failing.allocator());
        defer m.deinit();
        // Populate one existing key so we exercise the new-key path separately.
        m.put(1, 10) catch {};
        // Attempt to add a brand-new key. On OOM the key must not appear, and
        // total_size must equal the summed per-key counts.
        m.put(2, 20) catch |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expect(!m.containsKey(2));
        };
        // Invariant: total_size == sum of get(key).len over all keys.
        var it = m.inner.iterator();
        var summed: usize = 0;
        while (it.next()) |e| summed += e.value_ptr.items.len;
        try std.testing.expectEqual(summed, m.size());
    }
}

test "SetMultimap put rolls back new key on append OOM (F5)" {
    var fail_index: usize = 0;
    while (fail_index < 64) : (fail_index += 1) {
        var failing = std.testing.FailingAllocator.init(
            std.testing.allocator,
            .{ .fail_index = fail_index },
        );
        var m = SetMultimap(i32, i32).init(failing.allocator());
        defer m.deinit();
        m.put(1, 10) catch {};
        m.put(2, 20) catch |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expect(!m.containsKey(2));
        };
        var it = m.inner.iterator();
        var summed: usize = 0;
        while (it.next()) |e| summed += e.value_ptr.items.len;
        try std.testing.expectEqual(summed, m.size());
    }
}
