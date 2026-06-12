// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Runtime coverage for the additive pull-based `iterator()` / `Iterator.next`
//! added in phase 7d. One representative alias per family is constructed, its
//! iterator drained, and the yielded sequence asserted to match the family's
//! existing `forEach` / `toSlice` (order + contents).
//!
//! For families whose iteration order is deterministic (array-backed insertion
//! order, tree in-order) the exact sequence is asserted. For hash-ordered
//! families (arbitrary order) the multiset of yielded items is asserted by
//! sorting, plus the yielded count is asserted to equal `len()`.
//!
//! These tests also serve a second purpose: the `object/` generics are exposed
//! through `object.zig` as un-instantiated generic *functions*, so
//! `refAllDecls` does not force their methods to compile. Calling `iterator()`
//! here on concrete object instantiations forces those iterators to be analyzed.

const std = @import("std");
const testing = std.testing;
const root = @import("root.zig");

const arraylist = root.arraylist;
const stack = root.stack;
const deque = root.deque;
const priority_queue = root.priority_queue;
const hashset = root.hashset;
const hashmap = root.hashmap;
const treeset = root.treeset;
const treemap = root.treemap;
const bag = root.bag;
const multimap = root.multimap;
const immutable = root.immutable;
const object = root.object;
const interval = root.interval;
const bitset = root.bitset;

fn sortI32(slice: []i32) void {
    std.mem.sort(i32, slice, {}, struct {
        fn lt(_: void, a: i32, b: i32) bool {
            return a < b;
        }
    }.lt);
}

fn sortI64(slice: []i64) void {
    std.mem.sort(i64, slice, {}, struct {
        fn lt(_: void, a: i64, b: i64) bool {
            return a < b;
        }
    }.lt);
}

// ---------------------------------------------------------------------------
// Array-backed (insertion order) — exact sequence asserted.
// ---------------------------------------------------------------------------

test "ArrayList.iterator yields elements in insertion order" {
    const a = testing.allocator;
    var list = arraylist.I32ArrayList.init(a);
    defer list.deinit();
    try list.push(10);
    try list.push(20);
    try list.push(30);

    var it = list.iterator();
    try testing.expectEqual(@as(?i32, 10), it.next());
    try testing.expectEqual(@as(?i32, 20), it.next());
    try testing.expectEqual(@as(?i32, 30), it.next());
    try testing.expectEqual(@as(?i32, null), it.next());

    // Matches toSlice exactly.
    const sl = list.toSlice();
    var it2 = list.iterator();
    for (sl) |expected| try testing.expectEqual(@as(?i32, expected), it2.next());
    try testing.expectEqual(@as(?i32, null), it2.next());
}

test "ArrayStack.iterator yields bottom-to-top, matching forEach" {
    const a = testing.allocator;
    var s = stack.I32ArrayStack.init(a);
    defer s.deinit();
    try s.push(1);
    try s.push(2);
    try s.push(3);

    const sl = s.toSlice(); // bottom-to-top
    var it = s.iterator();
    for (sl) |expected| try testing.expectEqual(@as(?i32, expected), it.next());
    try testing.expectEqual(@as(?i32, null), it.next());
}

test "ArrayDeque.iterator yields front-to-back" {
    const a = testing.allocator;
    var d = deque.I32ArrayDeque.init(a);
    defer d.deinit();
    try d.addLast(2);
    try d.addLast(3);
    try d.addFirst(1); // [1,2,3]

    const sl = d.slice();
    var it = d.iterator();
    for (sl) |expected| try testing.expectEqual(@as(?i32, expected), it.next());
    try testing.expectEqual(@as(?i32, null), it.next());
}

test "PriorityQueue.iterator yields internal heap-array order (== slice)" {
    const a = testing.allocator;
    var q = priority_queue.I32PriorityQueue.init(a);
    defer q.deinit();
    try q.push(5);
    try q.push(1);
    try q.push(3);

    const sl = q.slice();
    var it = q.iterator();
    var i: usize = 0;
    while (it.next()) |v| : (i += 1) {
        try testing.expectEqual(sl[i], v);
    }
    try testing.expectEqual(sl.len, i);
}

// ---------------------------------------------------------------------------
// Hash-ordered (arbitrary) — multiset + count asserted.
// ---------------------------------------------------------------------------

test "HashSet.iterator yields every element exactly once (arbitrary order)" {
    const a = testing.allocator;
    var set = try hashset.I32HashSet.init(a);
    defer set.deinit();
    const elems = [_]i32{ 7, 11, 13, 17, 19 };
    for (elems) |e| _ = try set.add(e);

    var got = std.ArrayListUnmanaged(i32){};
    defer got.deinit(a);
    var it = set.iterator();
    while (it.next()) |v| try got.append(a, v);

    try testing.expectEqual(set.len(), got.items.len);
    sortI32(got.items);
    var expected = elems;
    sortI32(&expected);
    try testing.expectEqualSlices(i32, &expected, got.items);
}

test "HashMap.iterator yields every entry exactly once (arbitrary order)" {
    const a = testing.allocator;
    var map = try hashmap.I32I64HashMap.init(a);
    defer map.deinit();
    _ = try map.put(1, 100);
    _ = try map.put(2, 200);
    _ = try map.put(3, 300);

    var keys = std.ArrayListUnmanaged(i32){};
    defer keys.deinit(a);
    var it = map.iterator();
    var count: usize = 0;
    while (it.next()) |entry| {
        // Each yielded entry's value must agree with get(key).
        try testing.expectEqual(@as(?i64, @as(i64, entry.key) * 100), map.get(entry.key));
        try testing.expectEqual(@as(i64, @as(i64, entry.key) * 100), entry.value);
        try keys.append(a, entry.key);
        count += 1;
    }
    try testing.expectEqual(map.len(), count);
    sortI32(keys.items);
    try testing.expectEqualSlices(i32, &[_]i32{ 1, 2, 3 }, keys.items);
}

test "HashBiMap.iterator yields forward entries exactly once" {
    const a = testing.allocator;
    var m = try hashmap.I32I64HashBiMap.init(a);
    defer m.deinit();
    _ = try m.put(1, 10);
    _ = try m.put(2, 20);

    var count: usize = 0;
    var it = m.iterator();
    while (it.next()) |entry| {
        try testing.expectEqual(@as(?i64, entry.value), m.get(entry.key));
        count += 1;
    }
    try testing.expectEqual(m.len(), count);
}

test "HashBag.iterator yields each element repeated by occurrence count" {
    const a = testing.allocator;
    var b = try bag.I32HashBag.init(a);
    defer b.deinit();
    try b.add(5);
    try b.add(5);
    try b.add(5);
    try b.add(7);

    // Drain iterator into a sorted slice; compare with toSlice (also all
    // occurrences, but arbitrary order) sorted.
    var got = std.ArrayListUnmanaged(i32){};
    defer got.deinit(a);
    var it = b.iterator();
    while (it.next()) |v| try got.append(a, v);

    try testing.expectEqual(b.totalSize(), got.items.len);
    const expected = try b.toSlice(a);
    defer a.free(expected);
    sortI32(got.items);
    const exp = try a.dupe(i32, expected);
    defer a.free(exp);
    sortI32(exp);
    try testing.expectEqualSlices(i32, exp, got.items);
}

// ---------------------------------------------------------------------------
// Tree-backed (sorted in-order) — exact sequence asserted.
// ---------------------------------------------------------------------------

test "TreeSet.iterator yields ascending sorted order" {
    const a = testing.allocator;
    var s = treeset.I32TreeSet.init(a);
    defer s.deinit();
    _ = try s.add(30);
    _ = try s.add(10);
    _ = try s.add(20);
    _ = try s.add(10); // dup ignored

    const sl = try s.toSlice(a); // sorted
    defer a.free(sl);
    var it = s.iterator();
    for (sl) |expected| try testing.expectEqual(@as(?i32, expected), it.next());
    try testing.expectEqual(@as(?i32, null), it.next());
    try testing.expectEqualSlices(i32, &[_]i32{ 10, 20, 30 }, sl);
}

test "TreeMap.iterator yields entries in ascending key order" {
    const a = testing.allocator;
    var m = treemap.I32I64TreeMap.init(a);
    defer m.deinit();
    _ = try m.put(3, 300);
    _ = try m.put(1, 100);
    _ = try m.put(2, 200);

    const keys = m.keysSlice(); // sorted
    var it = m.iterator();
    for (keys) |k| {
        const entry = it.next() orelse return error.TestUnexpectedNull;
        try testing.expectEqual(k, entry.key);
        try testing.expectEqual(@as(i64, @as(i64, k) * 100), entry.value);
    }
    try testing.expect(it.next() == null);
}

test "TreeBag.iterator yields each element by occurrence in sorted order" {
    const a = testing.allocator;
    var b = bag.I32TreeBag.init(a);
    defer b.deinit();
    try b.add(3);
    try b.add(1);
    try b.add(1);
    try b.add(2);

    const sl = try b.toSlice(a); // sorted, with duplicates: [1,1,2,3]
    defer a.free(sl);
    var it = b.iterator();
    for (sl) |expected| try testing.expectEqual(@as(?i32, expected), it.next());
    try testing.expectEqual(@as(?i32, null), it.next());
    try testing.expectEqualSlices(i32, &[_]i32{ 1, 1, 2, 3 }, sl);
}

// ---------------------------------------------------------------------------
// Multimaps — one entry per (key, value), matching forEach.
// ---------------------------------------------------------------------------

test "ListMultimap.iterator yields one entry per (key, value)" {
    const a = testing.allocator;
    var m = multimap.I32I64ListMultimap.init(a);
    defer m.deinit();
    try m.put(1, 10);
    try m.put(1, 11);
    try m.put(2, 20);

    var count: usize = 0;
    var it = m.iterator();
    while (it.next()) |entry| {
        try testing.expect(m.containsKeyValue(entry.key, entry.value));
        count += 1;
    }
    try testing.expectEqual(m.size(), count);
    try testing.expectEqual(@as(usize, 3), count);
}

test "SetMultimap.iterator yields one entry per (key, value)" {
    const a = testing.allocator;
    var m = multimap.I32I64SetMultimap.init(a);
    defer m.deinit();
    try m.put(1, 10);
    try m.put(1, 10); // dup dropped
    try m.put(1, 11);
    try m.put(2, 20);

    var count: usize = 0;
    var it = m.iterator();
    while (it.next()) |entry| {
        try testing.expect(m.containsKeyValue(entry.key, entry.value));
        count += 1;
    }
    try testing.expectEqual(m.size(), count);
    try testing.expectEqual(@as(usize, 3), count);
}

// ---------------------------------------------------------------------------
// Immutable variants — delegate to the snapshot's storage.
// ---------------------------------------------------------------------------

test "ImmutableArrayList.iterator yields insertion order" {
    const a = testing.allocator;
    var imm = try immutable.ImmutableI32ArrayList.of(a, &[_]i32{ 4, 5, 6 });
    defer imm.deinit();
    var it = imm.iterator();
    try testing.expectEqual(@as(?i32, 4), it.next());
    try testing.expectEqual(@as(?i32, 5), it.next());
    try testing.expectEqual(@as(?i32, 6), it.next());
    try testing.expectEqual(@as(?i32, null), it.next());
}

test "ImmutableHashSet.iterator yields every element once" {
    const a = testing.allocator;
    var imm = try immutable.ImmutableI32HashSet.of(a, &[_]i32{ 1, 2, 3, 2 });
    defer imm.deinit();
    var got = std.ArrayListUnmanaged(i32){};
    defer got.deinit(a);
    var it = imm.iterator();
    while (it.next()) |v| try got.append(a, v);
    try testing.expectEqual(imm.len(), got.items.len);
    sortI32(got.items);
    try testing.expectEqualSlices(i32, &[_]i32{ 1, 2, 3 }, got.items);
}

test "ImmutableHashMap.iterator yields every entry once" {
    const a = testing.allocator;
    var mut = try hashmap.I32I64HashMap.init(a);
    defer mut.deinit();
    _ = try mut.put(1, 10);
    _ = try mut.put(2, 20);
    var imm = try mut.toImmutable();
    defer imm.deinit();

    var count: usize = 0;
    var it = imm.iterator();
    while (it.next()) |entry| {
        try testing.expectEqual(@as(?i64, entry.value), imm.get(entry.key));
        count += 1;
    }
    try testing.expectEqual(imm.len(), count);
}

test "ImmutableHashBag.iterator yields each element by occurrence" {
    const a = testing.allocator;
    var imm = try immutable.ImmutableI32HashBag.of(a, &[_]i32{ 9, 9, 8 });
    defer imm.deinit();
    var got = std.ArrayListUnmanaged(i32){};
    defer got.deinit(a);
    var it = imm.iterator();
    while (it.next()) |v| try got.append(a, v);
    try testing.expectEqual(imm.totalSize(), got.items.len);
    sortI32(got.items);
    try testing.expectEqualSlices(i32, &[_]i32{ 8, 9, 9 }, got.items);
}

// ---------------------------------------------------------------------------
// Object (generic-over-arbitrary-T) variants. These calls also force the
// object iterators to compile (refAllDecls does not instantiate them).
// ---------------------------------------------------------------------------

test "object.ArrayList.iterator yields insertion order" {
    const a = testing.allocator;
    var list = object.ArrayList(i32).init(a);
    defer list.deinit();
    try list.push(7);
    try list.push(8);
    try list.push(9);
    var it = list.iterator();
    try testing.expectEqual(@as(?i32, 7), it.next());
    try testing.expectEqual(@as(?i32, 8), it.next());
    try testing.expectEqual(@as(?i32, 9), it.next());
    try testing.expectEqual(@as(?i32, null), it.next());
}

test "object.ArrayStack.iterator yields bottom-to-top" {
    const a = testing.allocator;
    var s = object.ArrayStack(i32).init(a);
    defer s.deinit();
    try s.push(1);
    try s.push(2);
    var it = s.iterator();
    try testing.expectEqual(@as(?i32, 1), it.next());
    try testing.expectEqual(@as(?i32, 2), it.next());
    try testing.expectEqual(@as(?i32, null), it.next());
}

test "object.HashMap.iterator yields every entry once" {
    const a = testing.allocator;
    var m = object.HashMap(i32, i64).init(a);
    defer m.deinit();
    _ = try m.put(1, 10);
    _ = try m.put(2, 20);
    var count: usize = 0;
    var it = m.iterator();
    while (it.next()) |entry| {
        try testing.expectEqual(@as(?i64, entry.value), m.get(entry.key));
        count += 1;
    }
    try testing.expectEqual(m.len(), count);
}

test "object.HashSet.iterator yields every element once" {
    const a = testing.allocator;
    var s = object.HashSet(i32).init(a);
    defer s.deinit();
    _ = try s.add(3);
    _ = try s.add(4);
    var count: usize = 0;
    var it = s.iterator();
    while (it.next()) |v| {
        try testing.expect(s.contains(v));
        count += 1;
    }
    try testing.expectEqual(s.len(), count);
}

test "object.HashBag.iterator yields each element repeated by occurrence count" {
    const a = testing.allocator;
    var b = object.HashBag(i32).init(a);
    defer b.deinit();
    try b.add(5);
    try b.add(5);
    try b.add(6);
    var fives: usize = 0;
    var sixes: usize = 0;
    var total: usize = 0;
    var it = b.iterator();
    while (it.next()) |v| {
        switch (v) {
            5 => fives += 1,
            6 => sixes += 1,
            else => return error.UnexpectedValue,
        }
        total += 1;
    }
    try testing.expectEqual(@as(usize, 2), fives);
    try testing.expectEqual(@as(usize, 1), sixes);
    try testing.expectEqual(b.len(), total);
}

test "object.HashBiMap.iterator yields forward entries once" {
    const a = testing.allocator;
    var m = object.HashBiMap(i32, i64).init(a);
    defer m.deinit();
    _ = try m.put(1, 10);
    _ = try m.put(2, 20);
    var count: usize = 0;
    var it = m.iterator();
    while (it.next()) |entry| {
        try testing.expectEqual(@as(?i64, entry.value), m.get(entry.key));
        count += 1;
    }
    try testing.expectEqual(m.len(), count);
}

test "object.LinkedHashMap.iterator yields insertion order" {
    const a = testing.allocator;
    var m = object.LinkedHashMap(i32, i64).init(a);
    defer m.deinit();
    _ = try m.put(3, 30);
    _ = try m.put(1, 10);
    _ = try m.put(2, 20);
    var it = m.iterator();
    var e = it.next().?;
    try testing.expectEqual(@as(i32, 3), e.key);
    e = it.next().?;
    try testing.expectEqual(@as(i32, 1), e.key);
    e = it.next().?;
    try testing.expectEqual(@as(i32, 2), e.key);
    try testing.expect(it.next() == null);
}

test "object.LinkedHashSet.iterator yields insertion order" {
    const a = testing.allocator;
    var s = object.LinkedHashSet(i32).init(a);
    defer s.deinit();
    _ = try s.add(9);
    _ = try s.add(7);
    _ = try s.add(8);
    var it = s.iterator();
    try testing.expectEqual(@as(?i32, 9), it.next());
    try testing.expectEqual(@as(?i32, 7), it.next());
    try testing.expectEqual(@as(?i32, 8), it.next());
    try testing.expectEqual(@as(?i32, null), it.next());
}

test "object.TreeMap.iterator yields ascending key order" {
    const a = testing.allocator;
    var m = object.TreeMap(i32, i64).init(a, object.naturalComparator(i32));
    defer m.deinit();
    _ = try m.put(30, 3);
    _ = try m.put(10, 1);
    _ = try m.put(20, 2);
    var it = m.iterator();
    var e = it.next().?;
    try testing.expectEqual(@as(i32, 10), e.key);
    try testing.expectEqual(@as(i64, 1), e.value);
    e = it.next().?;
    try testing.expectEqual(@as(i32, 20), e.key);
    e = it.next().?;
    try testing.expectEqual(@as(i32, 30), e.key);
    try testing.expect(it.next() == null);
}

test "object.TreeSet.iterator yields ascending order" {
    const a = testing.allocator;
    var s = object.TreeSet(i32).init(a, object.naturalComparator(i32));
    defer s.deinit();
    _ = try s.add(30);
    _ = try s.add(10);
    _ = try s.add(20);
    var it = s.iterator();
    try testing.expectEqual(@as(?i32, 10), it.next());
    try testing.expectEqual(@as(?i32, 20), it.next());
    try testing.expectEqual(@as(?i32, 30), it.next());
    try testing.expectEqual(@as(?i32, null), it.next());
}

// The object RB-tree iterators (TreeMap/TreeSet) are the first consumers to
// walk the tree by its parent pointers for in-order traversal, so they must
// survive the rotations and re-links of many inserts and deletes — not just a
// handful of ascending keys. Stress with a deterministic pseudo-random churn
// and assert iteration is strictly ascending and matches len() throughout.
test "object.TreeSet.iterator survives randomized insert/remove churn" {
    const a = testing.allocator;
    var s = object.TreeSet(i32).init(a, object.naturalComparator(i32));
    defer s.deinit();
    var prng = std.Random.DefaultPrng.init(0xC0FFEE);
    const rand = prng.random();

    var present = std.AutoHashMapUnmanaged(i32, void){};
    defer present.deinit(a);

    var op: usize = 0;
    while (op < 4000) : (op += 1) {
        const key = rand.intRangeAtMost(i32, -500, 500);
        if (rand.boolean()) {
            if (try s.add(key)) try present.put(a, key, {});
        } else {
            if (s.remove(key)) _ = present.remove(key);
        }
    }

    try testing.expectEqual(present.count(), s.len());
    var it = s.iterator();
    var count: usize = 0;
    var prev: ?i32 = null;
    while (it.next()) |v| {
        if (prev) |p| try testing.expect(v > p); // strictly ascending, no dups
        try testing.expect(present.contains(v));
        prev = v;
        count += 1;
    }
    try testing.expectEqual(s.len(), count);
}

test "object.TreeMap.iterator survives randomized insert/remove churn" {
    const a = testing.allocator;
    var m = object.TreeMap(i32, i64).init(a, object.naturalComparator(i32));
    defer m.deinit();
    var prng = std.Random.DefaultPrng.init(0xBADF00D);
    const rand = prng.random();

    var expected = std.AutoHashMapUnmanaged(i32, i64){};
    defer expected.deinit(a);

    var op: usize = 0;
    while (op < 4000) : (op += 1) {
        const key = rand.intRangeAtMost(i32, -500, 500);
        if (rand.boolean()) {
            const value: i64 = @as(i64, key) * 7;
            _ = try m.put(key, value);
            try expected.put(a, key, value);
        } else {
            _ = m.remove(key);
            _ = expected.remove(key);
        }
    }

    try testing.expectEqual(expected.count(), m.len());
    var it = m.iterator();
    var count: usize = 0;
    var prev: ?i32 = null;
    while (it.next()) |e| {
        if (prev) |p| try testing.expect(e.key > p); // strictly ascending keys
        try testing.expectEqual(expected.get(e.key), @as(?i64, e.value));
        prev = e.key;
        count += 1;
    }
    try testing.expectEqual(m.len(), count);
}

fn hashI32(x: i32) u64 {
    return @as(u64, @bitCast(@as(i64, x)));
}
fn eqlI32(a: i32, b: i32) bool {
    return a == b;
}

test "object.HashMapWithStrategy.iterator yields every entry once" {
    const a = testing.allocator;
    const strat = object.HashingStrategy(i32){ .hashFn = &hashI32, .eqlFn = &eqlI32 };
    var m = object.HashMapWithStrategy(i32, i64).init(a, strat);
    defer m.deinit();
    _ = try m.put(1, 10);
    _ = try m.put(2, 20);
    var count: usize = 0;
    var it = m.iterator();
    while (it.next()) |entry| {
        try testing.expectEqual(@as(?i64, entry.value), m.get(entry.key));
        count += 1;
    }
    try testing.expectEqual(m.len(), count);
}

test "object.HashSetWithStrategy.iterator yields every element once" {
    const a = testing.allocator;
    const strat = object.HashingStrategy(i32){ .hashFn = &hashI32, .eqlFn = &eqlI32 };
    var s = object.HashSetWithStrategy(i32).init(a, strat);
    defer s.deinit();
    _ = try s.add(1);
    _ = try s.add(2);
    var count: usize = 0;
    var it = s.iterator();
    while (it.next()) |v| {
        try testing.expect(s.contains(v));
        count += 1;
    }
    try testing.expectEqual(s.len(), count);
}

// ---------------------------------------------------------------------------
// Interval (virtual, no backing storage) — exact ascending sequence asserted.
// ---------------------------------------------------------------------------

test "Interval.iterator yields the same sequence as toSlice" {
    const a = testing.allocator;
    const iv = interval.Interval(i32).fromToBy(2, 10, 2);
    const expected = try iv.toSlice(a);
    defer a.free(expected);
    var got = std.ArrayListUnmanaged(i32){};
    defer got.deinit(a);
    var it = iv.iterator();
    while (it.next()) |v| try got.append(a, v);
    try testing.expectEqualSlices(i32, expected, got.items);
    try testing.expectEqual(iv.len(), got.items.len);
}

test "Interval.iterator yields a descending (negative-step) sequence" {
    const iv = interval.Interval(i32).fromToBy(10, 2, -2);
    var it = iv.iterator();
    inline for ([_]i32{ 10, 8, 6, 4, 2 }) |want| {
        try testing.expectEqual(@as(?i32, want), it.next());
    }
    try testing.expectEqual(@as(?i32, null), it.next());
}

// ---------------------------------------------------------------------------
// BitSet / ImmutableBitSet — ascending set-bit indices, matching toOwnedSlice.
// ---------------------------------------------------------------------------

test "BitSet.iterator yields set bit indices ascending, matching toOwnedSlice" {
    const a = testing.allocator;
    var b = bitset.bit_set.BitSet.init(a);
    defer b.deinit();
    try b.set(3);
    try b.set(65);
    try b.set(200);
    const expected = try b.toOwnedSlice(a);
    defer a.free(expected);
    var got = std.ArrayListUnmanaged(usize){};
    defer got.deinit(a);
    var it = b.iterator();
    while (it.next()) |bit| try got.append(a, bit);
    try testing.expectEqualSlices(usize, expected, got.items);
}

test "ImmutableBitSet.iterator yields set bit indices ascending" {
    const a = testing.allocator;
    var m = bitset.bit_set.BitSet.init(a);
    defer m.deinit();
    try m.set(0);
    try m.set(64);
    try m.set(130);
    var im = try immutable.immutable_bit_set.ImmutableBitSet.fromMutable(a, &m);
    defer im.deinit();
    var got = std.ArrayListUnmanaged(usize){};
    defer got.deinit(a);
    var it = im.iterator();
    while (it.next()) |bit| try got.append(a, bit);
    try testing.expectEqualSlices(usize, &[_]usize{ 0, 64, 130 }, got.items);
    try testing.expectEqual(im.cardinality(), got.items.len);
}

// Silence unused-import warnings for `sortI64` if no test references it.
comptime {
    _ = sortI64;
}
