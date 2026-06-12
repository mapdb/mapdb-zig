// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Runtime coverage for the additive pull-based `mutIterator()` / `MutIterator`
//! added as a SEPARATE interface from the canonical immutable `iterator()`
//! (2026-06-12 decision). `mutIterator()` exists ONLY on the safe surfaces
//! where in-place mutation cannot corrupt structure invariants:
//!
//!   * list / stack / deque (primitive + object) — yields `*T` element pointers.
//!   * mutable hash maps / tree maps / linked / strategy maps (primitive +
//!     object) — yields `{ key, value_ptr: *V }`; the key is yielded BY VALUE
//!     so it cannot be mutated in place (that would break hashing/ordering).
//!
//! Sets, bags, tree sets, bi-maps, priority queues, multimaps and the set-like
//! `BitSet` have NO `mutIterator()` (their element/key is identity); the
//! exclusion is documented at each such *mutable* family's `iterator()`
//! definition. The immutable families are excluded by construction (no mutation
//! API at all). We assert the ABSENCE of `mutIterator` on the excluded families
//! and its PRESENCE on every safe surface via `@hasDecl` at the bottom of this
//! file.
//!
//! Each test mutates through the yielded pointer and then verifies the
//! container observes the new values. For maps we additionally verify the KEY
//! set and lookups are unaffected (keys are never exposed mutably). Float tests
//! write distinct NaN/zero bit patterns and assert the exact bit pattern is
//! observed (raw-bit identity, per the project's float contract).

const std = @import("std");
const testing = std.testing;
const root = @import("root.zig");

const arraylist = root.arraylist;
const stack = root.stack;
const deque = root.deque;
const hashmap = root.hashmap;
const treemap = root.treemap;
const object = root.object;

fn sortI32(slice: []i32) void {
    std.mem.sort(i32, slice, {}, struct {
        fn lt(_: void, a: i32, b: i32) bool {
            return a < b;
        }
    }.lt);
}

// ---------------------------------------------------------------------------
// List / stack / deque (primitive) — `*T` element pointers, exact order.
// Parameterized over a representative integer and float element axis so the
// pointer-write path is exercised for both bit-copyable scalar kinds.
// ---------------------------------------------------------------------------

test "ArrayList.mutIterator: writes through *T are observed in order" {
    const a = testing.allocator;
    var list = arraylist.I32ArrayList.init(a);
    defer list.deinit();
    try list.push(10);
    try list.push(20);
    try list.push(30);

    // Double every element in place.
    var it = list.mutIterator();
    while (it.next()) |p| p.* *= 2;

    try testing.expectEqualSlices(i32, &[_]i32{ 20, 40, 60 }, list.toSlice());

    // Pointers are stable across the same backing: a second pass sees the writes.
    var it2 = list.mutIterator();
    var idx: usize = 0;
    const want = [_]i32{ 20, 40, 60 };
    while (it2.next()) |p| : (idx += 1) try testing.expectEqual(want[idx], p.*);
    try testing.expectEqual(@as(usize, 3), idx);
}

test "ArrayList(f32).mutIterator: distinct NaN/zero bit patterns survive intact" {
    const a = testing.allocator;
    var list = arraylist.F32ArrayList.init(a);
    defer list.deinit();
    try list.push(1.0);
    try list.push(2.0);
    try list.push(3.0);

    // Overwrite with values whose raw bit pattern must be preserved exactly:
    // a quiet NaN with a payload, -0.0, and +Inf.
    const qnan: f32 = @bitCast(@as(u32, 0x7FC0_1234));
    const neg_zero: f32 = -0.0;
    const pos_inf: f32 = std.math.inf(f32);
    const writes = [_]f32{ qnan, neg_zero, pos_inf };
    var it = list.mutIterator();
    var i: usize = 0;
    while (it.next()) |p| : (i += 1) p.* = writes[i];

    const sl = list.toSlice();
    try testing.expectEqual(@as(u32, 0x7FC0_1234), @as(u32, @bitCast(sl[0])));
    try testing.expectEqual(@as(u32, 0x8000_0000), @as(u32, @bitCast(sl[1]))); // -0.0
    try testing.expectEqual(@as(u32, @bitCast(pos_inf)), @as(u32, @bitCast(sl[2])));
}

test "ArrayStack.mutIterator: writes through *T are observed bottom-to-top" {
    const a = testing.allocator;
    var s = stack.I32ArrayStack.init(a);
    defer s.deinit();
    try s.push(1);
    try s.push(2);
    try s.push(3);

    var it = s.mutIterator();
    while (it.next()) |p| p.* += 100;

    try testing.expectEqualSlices(i32, &[_]i32{ 101, 102, 103 }, s.toSlice());
    // Peek (top) reflects the mutation.
    try testing.expectEqual(@as(?i32, 103), s.peek());
}

test "ArrayDeque.mutIterator: writes through *T are observed front-to-back" {
    const a = testing.allocator;
    var d = deque.I32ArrayDeque.init(a);
    defer d.deinit();
    try d.addLast(2);
    try d.addLast(3);
    try d.addFirst(1); // [1,2,3]

    var it = d.mutIterator();
    while (it.next()) |p| p.* = -p.*;

    try testing.expectEqualSlices(i32, &[_]i32{ -1, -2, -3 }, d.slice());
}

// ---------------------------------------------------------------------------
// Hash map / tree map (primitive) — `{ key, value_ptr }`. Mutating values must
// be observed via get(); keys and the key-set must be untouched.
// ---------------------------------------------------------------------------

test "HashMap.mutIterator: value writes observed via get(); keys unaffected" {
    const a = testing.allocator;
    var map = try hashmap.I32I64HashMap.init(a);
    defer map.deinit();
    _ = try map.put(1, 100);
    _ = try map.put(2, 200);
    _ = try map.put(3, 300);

    // Negate every value in place through value_ptr.
    var it = map.mutIterator();
    var seen: usize = 0;
    while (it.next()) |e| {
        e.value_ptr.* = -e.value_ptr.*;
        seen += 1;
    }
    try testing.expectEqual(map.len(), seen);

    // Values updated; keys (and key-set) intact: lookups still resolve and the
    // map size is unchanged.
    try testing.expectEqual(@as(?i64, -100), map.get(1));
    try testing.expectEqual(@as(?i64, -200), map.get(2));
    try testing.expectEqual(@as(?i64, -300), map.get(3));
    try testing.expectEqual(@as(usize, 3), map.len());
    try testing.expect(map.containsKey(1) and map.containsKey(2) and map.containsKey(3));
}

test "HashMap(f64 value).mutIterator: NaN-payload value writes keep raw bits" {
    const a = testing.allocator;
    var map = try hashmap.I32F64HashMap.init(a);
    defer map.deinit();
    _ = try map.put(7, 1.0);
    _ = try map.put(8, 2.0);

    const payload: u64 = 0x7FF8_0000_0000_0042;
    var it = map.mutIterator();
    while (it.next()) |e| {
        if (e.key == 7) e.value_ptr.* = @bitCast(payload);
    }

    const got = map.get(7) orelse return error.TestUnexpectedNull;
    try testing.expectEqual(payload, @as(u64, @bitCast(got)));
    // Key 8 (and its value) untouched; lookup by the NaN-valued key still works
    // because the KEY is an i32, never the mutated value.
    try testing.expectEqual(@as(?f64, 2.0), map.get(8));
    try testing.expectEqual(@as(usize, 2), map.len());
}

test "TreeMap.mutIterator: value writes observed in ascending key order; keys intact" {
    const a = testing.allocator;
    var m = treemap.I32I64TreeMap.init(a);
    defer m.deinit();
    _ = try m.put(3, 300);
    _ = try m.put(1, 100);
    _ = try m.put(2, 200);

    // Iterate in ascending key order, asserting order, and rewrite each value.
    var it = m.mutIterator();
    var prev: ?i32 = null;
    while (it.next()) |e| {
        if (prev) |p| try testing.expect(e.key > p);
        prev = e.key;
        e.value_ptr.* += 1;
    }

    try testing.expectEqual(@as(?i64, 101), m.get(1));
    try testing.expectEqual(@as(?i64, 201), m.get(2));
    try testing.expectEqual(@as(?i64, 301), m.get(3));
    // Key ordering preserved.
    try testing.expectEqualSlices(i32, &[_]i32{ 1, 2, 3 }, m.keysSlice());
}

// ---------------------------------------------------------------------------
// Object (generic) safe surfaces. These calls also force the object
// `mutIterator` methods to compile (refAllDecls does not instantiate them).
// ---------------------------------------------------------------------------

test "object.ArrayList.mutIterator: writes through *T observed" {
    const a = testing.allocator;
    var list = object.ArrayList(i32).init(a);
    defer list.deinit();
    try list.push(7);
    try list.push(8);
    try list.push(9);
    var it = list.mutIterator();
    while (it.next()) |p| p.* *= 10;
    var ck = list.iterator();
    try testing.expectEqual(@as(?i32, 70), ck.next());
    try testing.expectEqual(@as(?i32, 80), ck.next());
    try testing.expectEqual(@as(?i32, 90), ck.next());
    try testing.expectEqual(@as(?i32, null), ck.next());
}

test "object.ArrayStack.mutIterator: writes through *T observed" {
    const a = testing.allocator;
    var s = object.ArrayStack(i32).init(a);
    defer s.deinit();
    try s.push(1);
    try s.push(2);
    var it = s.mutIterator();
    while (it.next()) |p| p.* += 5;
    var ck = s.iterator();
    try testing.expectEqual(@as(?i32, 6), ck.next());
    try testing.expectEqual(@as(?i32, 7), ck.next());
    try testing.expectEqual(@as(?i32, null), ck.next());
}

test "object.HashMap.mutIterator: value writes observed; keys unaffected" {
    const a = testing.allocator;
    var m = object.HashMap(i32, i64).init(a);
    defer m.deinit();
    _ = try m.put(1, 10);
    _ = try m.put(2, 20);
    var it = m.mutIterator();
    while (it.next()) |e| e.value_ptr.* *= 3;
    try testing.expectEqual(@as(?i64, 30), m.get(1));
    try testing.expectEqual(@as(?i64, 60), m.get(2));
    try testing.expectEqual(@as(usize, 2), m.len());
}

test "object.TreeMap.mutIterator: ascending-key value writes; keys intact" {
    const a = testing.allocator;
    var m = object.TreeMap(i32, i64).init(a, object.naturalComparator(i32));
    defer m.deinit();
    _ = try m.put(30, 3);
    _ = try m.put(10, 1);
    _ = try m.put(20, 2);
    var it = m.mutIterator();
    var prev: ?i32 = null;
    while (it.next()) |e| {
        if (prev) |p| try testing.expect(e.key > p);
        prev = e.key;
        e.value_ptr.* += 100;
    }
    try testing.expectEqual(@as(?i64, 101), m.get(10));
    try testing.expectEqual(@as(?i64, 102), m.get(20));
    try testing.expectEqual(@as(?i64, 103), m.get(30));
}

test "object.LinkedHashMap.mutIterator: insertion-order value writes" {
    const a = testing.allocator;
    var m = object.LinkedHashMap(i32, i64).init(a);
    defer m.deinit();
    _ = try m.put(3, 30);
    _ = try m.put(1, 10);
    _ = try m.put(2, 20);
    var it = m.mutIterator();
    // Insertion order is 3,1,2; tag values by order to prove the order.
    var order: i64 = 0;
    while (it.next()) |e| {
        e.value_ptr.* = order;
        order += 1;
    }
    try testing.expectEqual(@as(?i64, 0), m.get(3));
    try testing.expectEqual(@as(?i64, 1), m.get(1));
    try testing.expectEqual(@as(?i64, 2), m.get(2));
}

fn hashI32(x: i32) u64 {
    return @as(u64, @bitCast(@as(i64, x)));
}
fn eqlI32(a: i32, b: i32) bool {
    return a == b;
}

test "object.HashMapWithStrategy.mutIterator: value writes observed; keys intact" {
    const a = testing.allocator;
    const strat = object.HashingStrategy(i32){ .hashFn = &hashI32, .eqlFn = &eqlI32 };
    var m = object.HashMapWithStrategy(i32, i64).init(a, strat);
    defer m.deinit();
    _ = try m.put(1, 10);
    _ = try m.put(2, 20);
    var it = m.mutIterator();
    while (it.next()) |e| e.value_ptr.* += 1;
    try testing.expectEqual(@as(?i64, 11), m.get(1));
    try testing.expectEqual(@as(?i64, 21), m.get(2));
    try testing.expectEqual(@as(usize, 2), m.len());
}

// ---------------------------------------------------------------------------
// Stress: RB-tree object map mutIterator survives churn, mutates every value,
// and leaves the key ordering and key-set intact.
// ---------------------------------------------------------------------------

test "object.TreeMap.mutIterator survives churn; bulk value rewrite keeps keys" {
    const a = testing.allocator;
    var m = object.TreeMap(i32, i64).init(a, object.naturalComparator(i32));
    defer m.deinit();
    var prng = std.Random.DefaultPrng.init(0xFEEDBEEF);
    const rand = prng.random();

    var expected = std.AutoHashMapUnmanaged(i32, void){};
    defer expected.deinit(a);

    var op: usize = 0;
    while (op < 3000) : (op += 1) {
        const key = rand.intRangeAtMost(i32, -300, 300);
        if (rand.boolean()) {
            _ = try m.put(key, 0);
            try expected.put(a, key, {});
        } else {
            _ = m.remove(key);
            _ = expected.remove(key);
        }
    }

    // Rewrite every value to key*2 through the mutable iterator, asserting
    // ascending key order throughout.
    var it = m.mutIterator();
    var prev: ?i32 = null;
    var count: usize = 0;
    while (it.next()) |e| {
        if (prev) |p| try testing.expect(e.key > p);
        prev = e.key;
        e.value_ptr.* = @as(i64, e.key) * 2;
        count += 1;
    }
    try testing.expectEqual(expected.count(), count);
    try testing.expectEqual(m.len(), count);

    // Verify every present key now maps to key*2 and the key-set is unchanged.
    var ek = expected.keyIterator();
    while (ek.next()) |kp| {
        try testing.expectEqual(@as(?i64, @as(i64, kp.*) * 2), m.get(kp.*));
    }
}

// ---------------------------------------------------------------------------
// Negative coverage: the excluded families must NOT expose `mutIterator`.
// `@hasDecl` is a compile-time check, so this is a static guard that the
// safe-surface restriction holds (and a reviewer-visible contract).
// ---------------------------------------------------------------------------

test "excluded families do not expose mutIterator (static guard)" {
    const immutable = root.immutable;

    // --- EXCLUDED: element/key is identity (or value is a key / heap-ordered /
    //     a nested collection) — no in-place mutation surface is offered. ---
    // Primitive sets / bags / tree sets / bi-map / priority queue / multimaps.
    try testing.expect(!@hasDecl(root.hashset.I32HashSet, "mutIterator"));
    try testing.expect(!@hasDecl(root.treeset.I32TreeSet, "mutIterator"));
    try testing.expect(!@hasDecl(root.bag.I32HashBag, "mutIterator"));
    try testing.expect(!@hasDecl(root.bag.I32TreeBag, "mutIterator"));
    try testing.expect(!@hasDecl(root.hashmap.I32I64HashBiMap, "mutIterator"));
    try testing.expect(!@hasDecl(root.priority_queue.I32PriorityQueue, "mutIterator"));
    try testing.expect(!@hasDecl(root.multimap.I32I64ListMultimap, "mutIterator"));
    try testing.expect(!@hasDecl(root.multimap.I32I64SetMultimap, "mutIterator"));
    // Set-like BitSet.
    try testing.expect(!@hasDecl(root.bitset.bit_set.BitSet, "mutIterator"));
    // Object generics — every set/bag/bimap variant, including the linked and
    // strategy sets.
    try testing.expect(!@hasDecl(object.HashSet(i32), "mutIterator"));
    try testing.expect(!@hasDecl(object.TreeSet(i32), "mutIterator"));
    try testing.expect(!@hasDecl(object.LinkedHashSet(i32), "mutIterator"));
    try testing.expect(!@hasDecl(object.HashSetWithStrategy(i32), "mutIterator"));
    try testing.expect(!@hasDecl(object.HashBag(i32), "mutIterator"));
    try testing.expect(!@hasDecl(object.HashBiMap(i32, i64), "mutIterator"));
    // Immutable families are excluded by construction (no mutation API at all);
    // spot-check a representative list/map/set/bag.
    try testing.expect(!@hasDecl(immutable.ImmutableI32ArrayList, "mutIterator"));
    try testing.expect(!@hasDecl(immutable.ImmutableI32I64HashMap, "mutIterator"));
    try testing.expect(!@hasDecl(immutable.ImmutableI32HashSet, "mutIterator"));
    try testing.expect(!@hasDecl(immutable.ImmutableI32HashBag, "mutIterator"));

    // --- SAFE SURFACES: must expose mutIterator (positive half). ---
    // Primitive list / stack / deque.
    try testing.expect(@hasDecl(root.arraylist.I32ArrayList, "mutIterator"));
    try testing.expect(@hasDecl(root.stack.I32ArrayStack, "mutIterator"));
    try testing.expect(@hasDecl(root.deque.I32ArrayDeque, "mutIterator"));
    // Primitive mutable hash / tree maps.
    try testing.expect(@hasDecl(root.hashmap.I32I64HashMap, "mutIterator"));
    try testing.expect(@hasDecl(root.treemap.I32I64TreeMap, "mutIterator"));
    // Object list / stack and every mutable map variant.
    try testing.expect(@hasDecl(object.ArrayList(i32), "mutIterator"));
    try testing.expect(@hasDecl(object.ArrayStack(i32), "mutIterator"));
    try testing.expect(@hasDecl(object.HashMap(i32, i64), "mutIterator"));
    try testing.expect(@hasDecl(object.TreeMap(i32, i64), "mutIterator"));
    try testing.expect(@hasDecl(object.LinkedHashMap(i32, i64), "mutIterator"));
    try testing.expect(@hasDecl(object.HashMapWithStrategy(i32, i64), "mutIterator"));
}
