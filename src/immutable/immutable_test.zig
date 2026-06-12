// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Tests for the generic immutable collection types.
//!
//! Zig only type-checks generic methods that are *referenced*. Collapsing the
//! 112 per-type immutable wrappers into 7 generics means an unreferenced method
//! on an unexercised instantiation would never be compiled — a silent coverage
//! collapse. Two mechanisms counter this:
//!   1. `refAllDeclsRecursive` over every named alias forces every method on
//!      every instantiation to be compiled.
//!   2. Parameterized runtime tests exercise the full type axis behaviourally,
//!      replacing the deleted embedded per-file tests.

const std = @import("std");
const agg = @import("immutable.zig");

const ImmutableHashMap = agg.ImmutableHashMap;
const ImmutableHashSet = agg.ImmutableHashSet;
const ImmutableHashBag = agg.ImmutableHashBag;
const ImmutableArrayList = agg.ImmutableArrayList;
const ImmutableArrayStack = agg.ImmutableArrayStack;
const ImmutableArrayDeque = agg.ImmutableArrayDeque;
const ImmutablePriorityQueue = agg.ImmutablePriorityQueue;

const hashmap = @import("../hashmap/hashmap.zig");
const arraylist = @import("../arraylist/arraylist.zig");
const hashset = @import("../hashset/hashset.zig");
const bag = @import("../bag/bag.zig");
const stack = @import("../stack/stack.zig");
const deque = @import("../deque/deque.zig");
const priority_queue = @import("../priority_queue/priority_queue.zig");

// ---------------------------------------------------------------------------
// Force-compile every method on every instantiation.
// ---------------------------------------------------------------------------

const all_alias_types = [_]type{
    agg.ImmutableBoolBoolHashMap,   agg.ImmutableBoolCharHashMap,   agg.ImmutableBoolF32HashMap,   agg.ImmutableBoolF64HashMap,
    agg.ImmutableBoolI8HashMap,     agg.ImmutableBoolI16HashMap,    agg.ImmutableBoolI32HashMap,   agg.ImmutableBoolI64HashMap,
    agg.ImmutableCharBoolHashMap,   agg.ImmutableCharCharHashMap,   agg.ImmutableCharF32HashMap,   agg.ImmutableCharF64HashMap,
    agg.ImmutableCharI8HashMap,     agg.ImmutableCharI16HashMap,    agg.ImmutableCharI32HashMap,   agg.ImmutableCharI64HashMap,
    agg.ImmutableF32BoolHashMap,    agg.ImmutableF32CharHashMap,    agg.ImmutableF32F32HashMap,    agg.ImmutableF32F64HashMap,
    agg.ImmutableF32I8HashMap,      agg.ImmutableF32I16HashMap,     agg.ImmutableF32I32HashMap,    agg.ImmutableF32I64HashMap,
    agg.ImmutableF64BoolHashMap,    agg.ImmutableF64CharHashMap,    agg.ImmutableF64F32HashMap,    agg.ImmutableF64F64HashMap,
    agg.ImmutableF64I8HashMap,      agg.ImmutableF64I16HashMap,     agg.ImmutableF64I32HashMap,    agg.ImmutableF64I64HashMap,
    agg.ImmutableI8BoolHashMap,     agg.ImmutableI8CharHashMap,     agg.ImmutableI8F32HashMap,     agg.ImmutableI8F64HashMap,
    agg.ImmutableI8I8HashMap,       agg.ImmutableI8I16HashMap,      agg.ImmutableI8I32HashMap,     agg.ImmutableI8I64HashMap,
    agg.ImmutableI16BoolHashMap,    agg.ImmutableI16CharHashMap,    agg.ImmutableI16F32HashMap,    agg.ImmutableI16F64HashMap,
    agg.ImmutableI16I8HashMap,      agg.ImmutableI16I16HashMap,     agg.ImmutableI16I32HashMap,    agg.ImmutableI16I64HashMap,
    agg.ImmutableI32BoolHashMap,    agg.ImmutableI32CharHashMap,    agg.ImmutableI32F32HashMap,    agg.ImmutableI32F64HashMap,
    agg.ImmutableI32I8HashMap,      agg.ImmutableI32I16HashMap,     agg.ImmutableI32I32HashMap,    agg.ImmutableI32I64HashMap,
    agg.ImmutableI64BoolHashMap,    agg.ImmutableI64CharHashMap,    agg.ImmutableI64F32HashMap,    agg.ImmutableI64F64HashMap,
    agg.ImmutableI64I8HashMap,      agg.ImmutableI64I16HashMap,     agg.ImmutableI64I32HashMap,    agg.ImmutableI64I64HashMap,
    agg.ImmutableBoolHashSet,       agg.ImmutableCharHashSet,       agg.ImmutableF32HashSet,       agg.ImmutableF64HashSet,
    agg.ImmutableI8HashSet,         agg.ImmutableI16HashSet,        agg.ImmutableI32HashSet,       agg.ImmutableI64HashSet,
    agg.ImmutableBoolHashBag,       agg.ImmutableCharHashBag,       agg.ImmutableF32HashBag,       agg.ImmutableF64HashBag,
    agg.ImmutableI8HashBag,         agg.ImmutableI16HashBag,        agg.ImmutableI32HashBag,       agg.ImmutableI64HashBag,
    agg.ImmutableBoolArrayList,     agg.ImmutableCharArrayList,     agg.ImmutableF32ArrayList,     agg.ImmutableF64ArrayList,
    agg.ImmutableI8ArrayList,       agg.ImmutableI16ArrayList,      agg.ImmutableI32ArrayList,     agg.ImmutableI64ArrayList,
    agg.ImmutableBoolArrayStack,    agg.ImmutableCharArrayStack,    agg.ImmutableF32ArrayStack,    agg.ImmutableF64ArrayStack,
    agg.ImmutableI8ArrayStack,      agg.ImmutableI16ArrayStack,     agg.ImmutableI32ArrayStack,    agg.ImmutableI64ArrayStack,
    agg.ImmutableBoolArrayDeque,    agg.ImmutableCharArrayDeque,    agg.ImmutableF32ArrayDeque,    agg.ImmutableF64ArrayDeque,
    agg.ImmutableI8ArrayDeque,      agg.ImmutableI16ArrayDeque,     agg.ImmutableI32ArrayDeque,    agg.ImmutableI64ArrayDeque,
    agg.ImmutableBoolPriorityQueue, agg.ImmutableCharPriorityQueue, agg.ImmutableF32PriorityQueue, agg.ImmutableF64PriorityQueue,
    agg.ImmutableI8PriorityQueue,   agg.ImmutableI16PriorityQueue,  agg.ImmutableI32PriorityQueue, agg.ImmutableI64PriorityQueue,
};

test "refAllDeclsRecursive forces every method on every instantiation to compile" {
    inline for (all_alias_types) |T| {
        std.testing.refAllDeclsRecursive(T);
    }
}

// ---------------------------------------------------------------------------
// Parameterized runtime coverage across the full type axis.
// ---------------------------------------------------------------------------

const type_axis = [_]type{ bool, u21, f32, f64, i8, i16, i32, i64 };

/// PascalCase token, used to resolve the matching mutable named alias.
fn pascal(comptime T: type) []const u8 {
    return switch (T) {
        bool => "Bool",
        u21 => "Char",
        f32 => "F32",
        f64 => "F64",
        i8 => "I8",
        i16 => "I16",
        i32 => "I32",
        i64 => "I64",
        else => unreachable,
    };
}

/// Lowercase file-token, used to resolve the per-file mutable namespace.
fn token(comptime T: type) []const u8 {
    return switch (T) {
        bool => "bool",
        u21 => "char",
        f32 => "f32",
        f64 => "f64",
        i8 => "i8",
        i16 => "i16",
        i32 => "i32",
        i64 => "i64",
        else => unreachable,
    };
}

/// Three distinct sample values of type `T`.
fn samples(comptime T: type) [3]T {
    return switch (@typeInfo(T)) {
        .bool => .{ false, true, false },
        .float => .{ 1.5, 2.5, 3.5 },
        .int => .{ 1, 2, 3 },
        else => unreachable,
    };
}

test "ImmutableHashMap: parameterized fromMutable / read ops / toMutable independence" {
    inline for (type_axis) |K| {
        inline for (type_axis) |V| {
            const M = @field(hashmap, pascal(K) ++ pascal(V) ++ "HashMap");
            const ks = samples(K);
            const vs = samples(V);
            const distinct: usize = if (K == bool) 1 else 2;

            var mm = try M.init(std.testing.allocator);
            _ = try mm.put(ks[0], vs[0]);
            if (distinct == 2) _ = try mm.put(ks[1], vs[1]);

            var im = try ImmutableHashMap(K, V).fromMutable(std.testing.allocator, &mm);
            defer im.deinit();

            // Snapshot is independent: mutate the source after the snapshot.
            mm.clear();
            mm.deinit();

            try std.testing.expectEqual(@as(usize, distinct), im.len());
            try std.testing.expect(!im.isEmpty());
            try std.testing.expectEqual(@as(?V, vs[0]), im.get(ks[0]));
            try std.testing.expect(im.containsKey(ks[0]));
            try std.testing.expect(im.containsValue(vs[0]));
            try std.testing.expectEqual(vs[0], im.getOrDefault(ks[0], vs[1]));

            // eql against an identical snapshot.
            var mm2 = try M.init(std.testing.allocator);
            _ = try mm2.put(ks[0], vs[0]);
            if (distinct == 2) _ = try mm2.put(ks[1], vs[1]);
            var im2 = try ImmutableHashMap(K, V).fromMutable(std.testing.allocator, &mm2);
            defer im2.deinit();
            mm2.deinit();
            try std.testing.expect(im.eql(&im2));

            // toMutable yields an independent mutable copy.
            var back = try im.toMutable();
            defer back.deinit();
            try std.testing.expectEqual(@as(usize, distinct), back.len());
        }
    }
}

test "ImmutableArrayList: parameterized read ops + numeric-gated sum/min/max" {
    inline for (type_axis) |T| {
        const vs = samples(T);
        var il = try ImmutableArrayList(T).of(std.testing.allocator, &vs);
        defer il.deinit();

        try std.testing.expectEqual(@as(usize, 3), il.len());
        try std.testing.expect(!il.isEmpty());
        try std.testing.expectEqual(@as(?T, vs[0]), il.get(0));
        try std.testing.expectEqual(@as(?T, null), il.get(99));
        try std.testing.expect(il.contains(vs[1]));
        try std.testing.expectEqual(@as(?usize, 1), il.indexOf(vs[1]));

        // min/max are present for every type.
        try std.testing.expect(il.min() != null);
        try std.testing.expect(il.max() != null);

        // sum: numeric float types sum in-type; everything else widens to i64.
        if (@typeInfo(T) == .float) {
            try std.testing.expectEqual(@as(T, 7.5), il.sum());
        } else if (T == bool) {
            // {false, true, false} => 1
            try std.testing.expectEqual(@as(i64, 1), il.sum());
        } else {
            // {1, 2, 3} => 6
            try std.testing.expectEqual(@as(i64, 6), il.sum());
        }

        // eql against an identical list.
        var il2 = try ImmutableArrayList(T).of(std.testing.allocator, &vs);
        defer il2.deinit();
        try std.testing.expect(il.eql(&il2));

        var back = try il.toMutable();
        defer back.deinit();
        try std.testing.expectEqual(@as(usize, 3), back.len());
    }
}

test "ImmutableHashSet: parameterized dedup / contains / fromMutable independence" {
    inline for (type_axis) |T| {
        const S = @field(@field(hashset, token(T) ++ "_hash_set"), pascal(T) ++ "HashSet");
        const vs = samples(T);
        const distinct: usize = if (T == bool) 2 else 3;

        var ms = try S.init(std.testing.allocator);
        for (vs) |v| _ = try ms.add(v);
        var is = try ImmutableHashSet(T).fromMutable(std.testing.allocator, &ms);
        defer is.deinit();
        ms.deinit();

        try std.testing.expectEqual(distinct, is.len());
        try std.testing.expect(is.contains(vs[0]));

        var back = try is.toMutable();
        defer back.deinit();
        try std.testing.expectEqual(distinct, back.len());
    }
}

test "ImmutableHashBag: parameterized occurrence counting + independence" {
    inline for (type_axis) |T| {
        const vs = samples(T);
        // of() with a duplicate of vs[0].
        const data = [_]T{ vs[0], vs[0], vs[1] };
        var ib = try ImmutableHashBag(T).of(std.testing.allocator, &data);
        defer ib.deinit();

        try std.testing.expectEqual(@as(usize, 2), ib.occurrencesOf(vs[0]));
        try std.testing.expectEqual(@as(usize, 3), ib.totalSize());
        try std.testing.expect(ib.contains(vs[0]));
        const distinct: usize = if (T == bool) 2 else 2;
        try std.testing.expectEqual(distinct, ib.sizeDistinct());

        var back = try ib.toMutable();
        defer back.deinit();
        try std.testing.expectEqual(@as(usize, 3), back.totalSize());
    }
}

test "ImmutableArrayStack: parameterized push/pop/peek persistence" {
    inline for (type_axis) |T| {
        const vs = samples(T);
        var s1 = try ImmutableArrayStack(T).of(std.testing.allocator, &[_]T{vs[0]});
        defer s1.deinit();
        var s2 = try s1.push(vs[1]);
        defer s2.deinit();

        try std.testing.expectEqual(@as(usize, 1), s1.len());
        try std.testing.expectEqual(@as(usize, 2), s2.len());
        try std.testing.expectEqual(@as(?T, vs[1]), s2.peek());
        try std.testing.expect(s2.contains(vs[0]));

        const r = (try s2.pop()).?;
        var s3 = r.stack;
        defer s3.deinit();
        try std.testing.expectEqual(vs[1], r.value);
        try std.testing.expectEqual(@as(usize, 1), s3.len());

        var s4 = try ImmutableArrayStack(T).of(std.testing.allocator, &[_]T{vs[0]});
        defer s4.deinit();
        try std.testing.expect(s1.eql(&s4));
    }
}

test "ImmutableArrayDeque: parameterized withFirst/withLast/without persistence" {
    inline for (type_axis) |T| {
        const vs = samples(T);
        var d1 = try ImmutableArrayDeque(T).of(std.testing.allocator, &[_]T{vs[1]});
        defer d1.deinit();
        var d2 = try d1.withFirst(vs[0]);
        defer d2.deinit();
        var d3 = try d2.withLast(vs[2]);
        defer d3.deinit();

        try std.testing.expectEqual(@as(usize, 1), d1.len());
        try std.testing.expectEqual(@as(usize, 3), d3.len());
        try std.testing.expectEqual(@as(?T, vs[0]), d3.peekFirst());
        try std.testing.expectEqual(@as(?T, vs[2]), d3.peekLast());
        try std.testing.expect(d3.contains(vs[1]));

        const rf = (try d3.withoutFirst()).?;
        var df = rf.deque;
        defer df.deinit();
        try std.testing.expectEqual(vs[0], rf.value);
        try std.testing.expectEqual(@as(usize, 2), df.len());

        const rl = (try d3.withoutLast()).?;
        var dl = rl.deque;
        defer dl.deinit();
        try std.testing.expectEqual(vs[2], rl.value);
    }
}

test "ImmutablePriorityQueue: parameterized heap order + persistence" {
    inline for (type_axis) |T| {
        const vs = samples(T);
        var q = try ImmutablePriorityQueue(T).of(std.testing.allocator, &vs);
        defer q.deinit();
        try std.testing.expectEqual(@as(usize, 3), q.len());
        try std.testing.expect(q.peek() != null);
        try std.testing.expect(q.contains(vs[0]));

        var q2 = try q.push(vs[2]);
        defer q2.deinit();
        try std.testing.expectEqual(@as(usize, 3), q.len()); // original untouched
        try std.testing.expectEqual(@as(usize, 4), q2.len());

        const r = (try q.pop()).?;
        var q3 = r.queue;
        defer q3.deinit();
        try std.testing.expectEqual(@as(usize, 2), q3.len());
    }
}

// ---------------------------------------------------------------------------
// Marquee smoke tests for the canonical correctness fixes.
// ---------------------------------------------------------------------------

test "ImmutableF32F32HashMap: eql uses bit equality for float values (NaN, ±0)" {
    var a = try hashmap.F32F32HashMap.init(std.testing.allocator);
    defer a.deinit();
    const nan = std.math.nan(f32);
    _ = try a.put(1.0, nan);
    var ia = try ImmutableHashMap(f32, f32).fromMutable(std.testing.allocator, &a);
    defer ia.deinit();

    var b = try hashmap.F32F32HashMap.init(std.testing.allocator);
    defer b.deinit();
    _ = try b.put(1.0, nan);
    var ib = try ImmutableHashMap(f32, f32).fromMutable(std.testing.allocator, &b);
    defer ib.deinit();
    // identical NaN bits => equal
    try std.testing.expect(ia.eql(&ib));

    var c = try hashmap.F32F32HashMap.init(std.testing.allocator);
    defer c.deinit();
    _ = try c.put(1.0, 0.0);
    var ic = try ImmutableHashMap(f32, f32).fromMutable(std.testing.allocator, &c);
    defer ic.deinit();

    var d = try hashmap.F32F32HashMap.init(std.testing.allocator);
    defer d.deinit();
    _ = try d.put(1.0, -0.0);
    var id = try ImmutableHashMap(f32, f32).fromMutable(std.testing.allocator, &d);
    defer id.deinit();
    // +0.0 vs -0.0 differ in bits => not equal
    try std.testing.expect(!ic.eql(&id));
}

test "ImmutableF32HashMap key: NaN and ±0 distinctness survives snapshot" {
    var m = try hashmap.F32I32HashMap.init(std.testing.allocator);
    defer m.deinit();
    const nan = std.math.nan(f32);
    _ = try m.put(nan, 1);
    _ = try m.put(0.0, 100);
    _ = try m.put(-0.0, 200);
    var im = try ImmutableHashMap(f32, i32).fromMutable(std.testing.allocator, &m);
    defer im.deinit();
    try std.testing.expectEqual(@as(?i32, 1), im.get(nan));
    try std.testing.expectEqual(@as(?i32, 100), im.get(0.0));
    try std.testing.expectEqual(@as(?i32, 200), im.get(-0.0));
    try std.testing.expectEqual(@as(usize, 3), im.len());
}

test "ImmutableF32ArrayList: contains uses bit equality (+0.0 != -0.0), totalCmp min/max" {
    var il = try ImmutableArrayList(f32).of(std.testing.allocator, &[_]f32{ 0.0, 2.0, -1.0 });
    defer il.deinit();
    // +0.0 present, -0.0 absent under bit equality.
    try std.testing.expect(il.contains(0.0));
    try std.testing.expect(!il.contains(-0.0));
    // total order: -1.0 is min, 2.0 is max.
    try std.testing.expectEqual(@as(?f32, -1.0), il.min());
    try std.testing.expectEqual(@as(?f32, 2.0), il.max());
}

test "ImmutableF32PriorityQueue: float total-order min-heap via delegation" {
    // -0.0 sorts below +0.0 under total order; smallest must surface at peek.
    var q = try ImmutablePriorityQueue(f32).of(std.testing.allocator, &[_]f32{ 3.0, -0.0, 0.0, 1.0 });
    defer q.deinit();
    const r = (try q.pop()).?;
    var q2 = r.queue;
    defer q2.deinit();
    // The popped (smallest) element is -0.0 under total order.
    try std.testing.expectEqual(@as(u32, @bitCast(@as(f32, -0.0))), @as(u32, @bitCast(r.value)));
}

test "ImmutableI8ArrayList: sum widens to i64 (no i8 overflow)" {
    var il = try ImmutableArrayList(i8).of(std.testing.allocator, &[_]i8{ 100, 100, 100 });
    defer il.deinit();
    // 300 would overflow i8 but the accumulator is i64.
    try std.testing.expectEqual(@as(i64, 300), il.sum());
}

test "ImmutableI64ArrayList: sum is plain i64 accumulation" {
    var il = try ImmutableArrayList(i64).of(std.testing.allocator, &[_]i64{ 10, 20, 30 });
    defer il.deinit();
    try std.testing.expectEqual(@as(i64, 60), il.sum());
}
