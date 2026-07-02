// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Native tests for the data pump (bulk import) feature across all families.
//!
//! Coverage per the change brief:
//!   * pump-built == N× incremental (iteration order + `eql`);
//!   * zero-rehash / single-allocation at `n = 3·2^k` (hash) and exact-capacity
//!     (sorted array);
//!   * NotSorted / DuplicateKey at first / middle / last positions;
//!   * no-leak on mid-load failure via `std.testing.FailingAllocator`;
//!   * float (NaN / ±0 / ±Inf) and bool axes through the pump path;
//!   * Sink poison / double-create / put-after-create / empty input (ordered);
//!   * bag overflow + BiMap two-sided conflict.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const pump = @import("pump.zig");
const DupPolicy = pump.DupPolicy;

const TreeMap = @import("treemap/tree_map.zig").TreeMap;
const TreeSet = @import("treeset/tree_set.zig").TreeSet;
const TreeBag = @import("bag/tree_bag.zig").TreeBag;
const HashMap = @import("hashmap/hash_map.zig").HashMap;
const HashSet = @import("hashset/hash_set.zig").HashSet;
const HashBag = @import("bag/hash_bag.zig").HashBag;
const HashBiMap = @import("hashmap/hash_bi_map.zig").HashBiMap;
const ListMultimap = @import("multimap/list_multimap.zig").ListMultimap;
const SetMultimap = @import("multimap/set_multimap.zig").SetMultimap;
const BitSet = @import("bitset/bit_set.zig").BitSet;

// ===========================================================================
// TreeMap.fromSorted — happy path, equivalence, single allocation
// ===========================================================================

test "TreeMap.fromSorted: happy path equals sorted put-loop" {
    const a = testing.allocator;
    const keys = [_]i32{ 1, 3, 5, 7, 9 };
    const vals = [_]i64{ 10, 30, 50, 70, 90 };

    var pumped = try TreeMap(i32, i64).fromSorted(a, &keys, &vals, .err);
    defer pumped.deinit();

    var incremental = TreeMap(i32, i64).init(a);
    defer incremental.deinit();
    for (keys, vals) |k, v| _ = try incremental.put(k, v);

    try testing.expect(pumped.eql(&incremental));
    try testing.expectEqualSlices(i32, &keys, pumped.keysSlice());
    try testing.expectEqualSlices(i64, &vals, pumped.valuesSlice());
    try testing.expectEqual(@as(usize, 5), pumped.len());
}

test "TreeMap.fromSorted: single allocation (exact final capacity, no shifts)" {
    const a = testing.allocator;
    var keys: [100]i32 = undefined;
    var vals: [100]i64 = undefined;
    for (0..100) |i| {
        keys[i] = @intCast(i);
        vals[i] = @intCast(i * 2);
    }
    var m = try TreeMap(i32, i64).fromSorted(a, &keys, &vals, .err);
    defer m.deinit();
    // Reserved exactly once for n; capacity holds all n with no realloc/shift.
    try testing.expectEqual(@as(usize, 100), m.len());
    try testing.expect(m.keys.capacity >= 100);
}

test "TreeMap.fromSorted: empty input" {
    const a = testing.allocator;
    var m = try TreeMap(i32, i64).fromSorted(a, &[_]i32{}, &[_]i64{}, .err);
    defer m.deinit();
    try testing.expectEqual(@as(usize, 0), m.len());
    try testing.expect(m.isEmpty());
}

test "TreeMap.fromSorted: NotSorted at first/middle/last positions" {
    const a = testing.allocator;
    // descending right away (positions 0->1)
    try testing.expectError(error.NotSorted, TreeMap(i32, i64).fromSorted(a, &[_]i32{ 5, 1, 2 }, &[_]i64{ 0, 0, 0 }, .err));
    // middle
    try testing.expectError(error.NotSorted, TreeMap(i32, i64).fromSorted(a, &[_]i32{ 1, 2, 1, 3 }, &[_]i64{ 0, 0, 0, 0 }, .err));
    // last
    try testing.expectError(error.NotSorted, TreeMap(i32, i64).fromSorted(a, &[_]i32{ 1, 2, 3, 0 }, &[_]i64{ 0, 0, 0, 0 }, .err));
}

test "TreeMap.fromSorted: DuplicateKey at first/middle/last with policy .err" {
    const a = testing.allocator;
    try testing.expectError(error.DuplicateKey, TreeMap(i32, i64).fromSorted(a, &[_]i32{ 1, 1, 2 }, &[_]i64{ 0, 0, 0 }, .err));
    try testing.expectError(error.DuplicateKey, TreeMap(i32, i64).fromSorted(a, &[_]i32{ 1, 2, 2, 3 }, &[_]i64{ 0, 0, 0, 0 }, .err));
    try testing.expectError(error.DuplicateKey, TreeMap(i32, i64).fromSorted(a, &[_]i32{ 1, 2, 3, 3 }, &[_]i64{ 0, 0, 0, 0 }, .err));
}

test "TreeMap.fromSorted: policy .ignore keeps first of each run" {
    const a = testing.allocator;
    const keys = [_]i32{ 1, 1, 2, 3, 3, 3 };
    const vals = [_]i64{ 100, 999, 200, 300, 888, 777 };
    var m = try TreeMap(i32, i64).fromSorted(a, &keys, &vals, .ignore);
    defer m.deinit();
    try testing.expectEqual(@as(usize, 3), m.len());
    try testing.expectEqual(@as(?i64, 100), m.get(1)); // first wins
    try testing.expectEqual(@as(?i64, 200), m.get(2));
    try testing.expectEqual(@as(?i64, 300), m.get(3));
}

test "TreeMap.fromSorted: no leak on NotSorted mid-load" {
    // testing.allocator detects leaks at teardown; an order error mid-load must
    // free the partial map.
    const a = testing.allocator;
    const r = TreeMap(i32, i64).fromSorted(a, &[_]i32{ 1, 2, 3, 2 }, &[_]i64{ 0, 0, 0, 0 }, .err);
    try testing.expectError(error.NotSorted, r);
}

test "TreeMap.fromSorted: no leak on allocator failure mid-load" {
    var failing = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 1 });
    var keys: [50]i32 = undefined;
    var vals: [50]i64 = undefined;
    for (0..50) |i| {
        keys[i] = @intCast(i);
        vals[i] = @intCast(i);
    }
    const r = TreeMap(i32, i64).fromSorted(failing.allocator(), &keys, &vals, .err);
    try testing.expectError(error.OutOfMemory, r);
    // FailingAllocator + no leak panic on teardown ⇒ errdefer freed the partial.
}

// ===========================================================================
// TreeMap.Sink — poison / double-create / put-after-create / empty
// ===========================================================================

test "TreeMap.Sink: streaming build equals fromSorted" {
    const a = testing.allocator;
    var sink = TreeMap(i32, i64).Sink.init(a, .err);
    errdefer sink.deinit();
    try sink.put(1, 10);
    try sink.put(2, 20);
    try sink.put(3, 30);
    var m = try sink.create();
    defer m.deinit();
    try testing.expectEqual(@as(usize, 3), m.len());
    try testing.expectEqual(@as(?i64, 20), m.get(2));
}

test "TreeMap.Sink: empty create" {
    const a = testing.allocator;
    var sink = TreeMap(i32, i64).Sink.init(a, .err);
    var m = try sink.create();
    defer m.deinit();
    try testing.expect(m.isEmpty());
}

test "TreeMap.Sink: poisoned after NotSorted, put/create fail" {
    const a = testing.allocator;
    var sink = TreeMap(i32, i64).Sink.init(a, .err);
    defer sink.deinit();
    try sink.put(5, 0);
    try testing.expectError(error.NotSorted, sink.put(2, 0));
    // Poisoned: further puts and create both fail.
    try testing.expectError(error.PumpPoisoned, sink.put(9, 0));
    try testing.expectError(error.PumpPoisoned, sink.create());
}

test "TreeMap.Sink: poisoned after DuplicateKey" {
    const a = testing.allocator;
    var sink = TreeMap(i32, i64).Sink.init(a, .err);
    defer sink.deinit();
    try sink.put(1, 0);
    try testing.expectError(error.DuplicateKey, sink.put(1, 0));
    try testing.expectError(error.PumpPoisoned, sink.create());
}

test "TreeMap.Sink: double-create and put-after-create fail" {
    const a = testing.allocator;
    var sink = TreeMap(i32, i64).Sink.init(a, .err);
    try sink.put(1, 10);
    var m = try sink.create();
    defer m.deinit();
    try testing.expectError(error.PumpPoisoned, sink.create()); // double create
    try testing.expectError(error.PumpPoisoned, sink.put(2, 20)); // put after create
}

// ===========================================================================
// Float key axis (NaN / ±0 / ±Inf) through the pump — IEEE total order
// ===========================================================================

test "TreeMap.fromSorted: float keys in IEEE total order (NaN/±0/±Inf)" {
    const a = testing.allocator;
    const nan = std.math.nan(f64);
    const inf = std.math.inf(f64);
    // total order: -Inf < -0.0 < +0.0 < +Inf < NaN
    const keys = [_]f64{ -inf, -0.0, 0.0, inf, nan };
    const vals = [_]i32{ 1, 2, 3, 4, 5 };
    var m = try TreeMap(f64, i32).fromSorted(a, &keys, &vals, .err);
    defer m.deinit();
    try testing.expectEqual(@as(usize, 5), m.len());
    // -0.0 and +0.0 are distinct keys under bit-identity.
    try testing.expectEqual(@as(?i32, 2), m.get(-0.0));
    try testing.expectEqual(@as(?i32, 3), m.get(0.0));

    var incremental = TreeMap(f64, i32).init(a);
    defer incremental.deinit();
    for (keys, vals) |k, v| _ = try incremental.put(k, v);
    try testing.expect(m.eql(&incremental));
}

test "TreeMap.fromSorted: float +0.0 then -0.0 is NotSorted (total order)" {
    const a = testing.allocator;
    // +0.0 sorts AFTER -0.0 in total order, so this descends.
    const r = TreeMap(f64, i32).fromSorted(a, &[_]f64{ 0.0, -0.0 }, &[_]i32{ 0, 0 }, .err);
    try testing.expectError(error.NotSorted, r);
}

// ===========================================================================
// Bool axis
// ===========================================================================

test "TreeMap.fromSorted: bool keys (false < true)" {
    const a = testing.allocator;
    var m = try TreeMap(bool, i32).fromSorted(a, &[_]bool{ false, true }, &[_]i32{ 0, 1 }, .err);
    defer m.deinit();
    try testing.expectEqual(@as(usize, 2), m.len());
    try testing.expectEqual(@as(?i32, 0), m.get(false));
    try testing.expectEqual(@as(?i32, 1), m.get(true));
    // true before false is descending.
    try testing.expectError(error.NotSorted, TreeMap(bool, i32).fromSorted(a, &[_]bool{ true, false }, &[_]i32{ 0, 0 }, .err));
}

test "TreeSet.fromSorted: bool axis" {
    const a = testing.allocator;
    var s = try TreeSet(bool).fromSorted(a, &[_]bool{ false, true }, .err);
    defer s.deinit();
    try testing.expectEqual(@as(usize, 2), s.len());
    try testing.expect(s.contains(false));
    try testing.expect(s.contains(true));
}

// ===========================================================================
// TreeSet.fromSorted (O(n log n) treap) — equivalence + errors
// ===========================================================================

test "TreeSet.fromSorted: equals incremental add (in-order equivalence)" {
    const a = testing.allocator;
    const vals = [_]i32{ -5, -1, 0, 3, 8, 42, 1000 };
    var pumped = try TreeSet(i32).fromSorted(a, &vals, .err);
    defer pumped.deinit();

    var incremental = TreeSet(i32).init(a);
    defer incremental.deinit();
    for (vals) |v| _ = try incremental.add(v);

    try testing.expect(pumped.eql(&incremental));
    const slice = try pumped.toSlice(a);
    defer a.free(slice);
    try testing.expectEqualSlices(i32, &vals, slice);
}

test "TreeSet.fromSorted: NotSorted and DuplicateKey at positions" {
    const a = testing.allocator;
    try testing.expectError(error.NotSorted, TreeSet(i32).fromSorted(a, &[_]i32{ 3, 1 }, .err));
    try testing.expectError(error.NotSorted, TreeSet(i32).fromSorted(a, &[_]i32{ 1, 2, 1 }, .err));
    try testing.expectError(error.DuplicateKey, TreeSet(i32).fromSorted(a, &[_]i32{ 1, 1, 2 }, .err));
    try testing.expectError(error.DuplicateKey, TreeSet(i32).fromSorted(a, &[_]i32{ 1, 2, 2 }, .err));
}

test "TreeSet.fromSorted: policy .ignore collapses dup run" {
    const a = testing.allocator;
    var s = try TreeSet(i32).fromSorted(a, &[_]i32{ 1, 1, 1, 2, 3, 3 }, .ignore);
    defer s.deinit();
    try testing.expectEqual(@as(usize, 3), s.len());
}

test "TreeSet.fromSorted: float NaN/±0/Inf total order through pump" {
    const a = testing.allocator;
    const nan = std.math.nan(f32);
    const inf = std.math.inf(f32);
    const vals = [_]f32{ -inf, -0.0, 0.0, inf, nan };
    var s = try TreeSet(f32).fromSorted(a, &vals, .err);
    defer s.deinit();
    const slice = try s.toSlice(a);
    defer a.free(slice);
    try testing.expectEqual(@as(usize, 5), slice.len);
    // bit-identity: -0.0 and +0.0 both present and distinct.
    try testing.expect(s.contains(-0.0));
    try testing.expect(s.contains(0.0));
}

test "TreeSet.Sink: poison + double-create" {
    const a = testing.allocator;
    var sink = TreeSet(i32).Sink.init(a, .err);
    defer sink.deinit();
    try sink.put(1);
    try sink.put(2);
    try testing.expectError(error.NotSorted, sink.put(1));
    try testing.expectError(error.PumpPoisoned, sink.create());
}

test "TreeSet.fromSorted: no leak on mid-load order error" {
    const a = testing.allocator;
    try testing.expectError(error.NotSorted, TreeSet(i32).fromSorted(a, &[_]i32{ 1, 2, 3, 1 }, .err));
}

// ===========================================================================
// TreeBag.fromSorted — run counting + overflow + errors
// ===========================================================================

test "TreeBag.fromSorted: runs become counts; equals incremental" {
    const a = testing.allocator;
    const vals = [_]i32{ 1, 1, 1, 2, 3, 3 };
    var pumped = try TreeBag(i32).fromSorted(a, &vals);
    defer pumped.deinit();

    var incremental = TreeBag(i32).init(a);
    defer incremental.deinit();
    for (vals) |v| try incremental.add(v);

    try testing.expect(pumped.eql(&incremental));
    try testing.expectEqual(@as(usize, 3), pumped.occurrencesOf(1));
    try testing.expectEqual(@as(usize, 1), pumped.occurrencesOf(2));
    try testing.expectEqual(@as(usize, 2), pumped.occurrencesOf(3));
    try testing.expectEqual(@as(usize, 6), pumped.totalSize());
    try testing.expectEqual(@as(usize, 3), pumped.sizeDistinct());
}

test "TreeBag.fromSorted: NotSorted on descending distinct keys" {
    const a = testing.allocator;
    try testing.expectError(error.NotSorted, TreeBag(i32).fromSorted(a, &[_]i32{ 1, 2, 2, 1 }));
    try testing.expectError(error.NotSorted, TreeBag(i32).fromSorted(a, &[_]i32{ 3, 1 }));
}

test "TreeBag.fromSortedCounts: parallel (value,count); NotSorted; overflow" {
    const a = testing.allocator;
    var b = try TreeBag(i32).fromSortedCounts(a, &[_]i32{ 1, 2, 5 }, &[_]usize{ 2, 3, 1 });
    defer b.deinit();
    try testing.expectEqual(@as(usize, 2), b.occurrencesOf(1));
    try testing.expectEqual(@as(usize, 3), b.occurrencesOf(2));
    try testing.expectEqual(@as(usize, 6), b.totalSize());

    try testing.expectError(error.NotSorted, TreeBag(i32).fromSortedCounts(a, &[_]i32{ 2, 1 }, &[_]usize{ 1, 1 }));

    // overflow: two runs whose counts sum past usize max.
    const big = std.math.maxInt(usize);
    try testing.expectError(error.CountOverflow, TreeBag(i32).fromSortedCounts(a, &[_]i32{ 1, 2 }, &[_]usize{ big, 1 }));
}

// ===========================================================================
// Hash family — bulkLoad / bulkLoadExact, zero rehash, equivalence, dups
// ===========================================================================

fn expectHashMapSlotsEqual(
    pumped: *const HashMap(i32, i64),
    incremental: *const HashMap(i32, i64),
) !void {
    try testing.expectEqual(pumped.inner.capacity, incremental.inner.capacity);
    for (pumped.inner.entries, incremental.inner.entries) |a, b| {
        try testing.expectEqual(a.occupied, b.occupied);
        if (a.occupied) {
            try testing.expectEqual(a.key, b.key);
            try testing.expectEqual(a.value, b.value);
        }
    }
}

fn expectHashSetSlotsEqual(
    pumped: *const HashSet(i32),
    incremental: *const HashSet(i32),
) !void {
    try testing.expectEqual(pumped.inner.capacity, incremental.inner.capacity);
    for (pumped.inner.entries, incremental.inner.entries) |a, b| {
        try testing.expectEqual(a.occupied, b.occupied);
        if (a.occupied) try testing.expectEqual(a.key, b.key);
    }
}

test "HashMap.bulkLoad: equals incremental put-loop" {
    const a = testing.allocator;
    const keys = [_]i32{ 5, 2, 9, 1, 7 };
    const vals = [_]i64{ 50, 20, 90, 10, 70 };
    var pumped = try HashMap(i32, i64).bulkLoad(a, &keys, &vals, .err);
    defer pumped.deinit();

    var incremental = try HashMap(i32, i64).init(a);
    defer incremental.deinit();
    for (keys, vals) |k, v| _ = try incremental.put(k, v);

    try testing.expect(pumped.eql(&incremental));
    try testing.expectEqual(@as(usize, 5), pumped.len());
}

test "HashMap.bulkLoadExact: zero rehash at n = 3*2^k" {
    const a = testing.allocator;
    const ns = [_]usize{ 3, 6, 12, 24, 48 };
    inline for (ns) |n| {
        const expected_cap: usize = switch (n) {
            3, 6 => 16,
            12 => 32,
            24 => 64,
            48 => 128,
            else => unreachable,
        };
        var keys: [n]i32 = undefined;
        var vals: [n]i64 = undefined;
        for (0..n) |i| {
            keys[i] = @intCast(i);
            vals[i] = @intCast(i);
        }
        var m = try HashMap(i32, i64).bulkLoadExact(a, &keys, &vals, n, .err);
        defer m.deinit();
        const cap_after = m.inner.capacity;
        // Insert nothing more; assert every key present and capacity is the
        // single pre-sized power-of-two with NO mid-load growth.
        try testing.expectEqual(n, m.len());
        try testing.expectEqual(cap_after, m.inner.capacity);
        try testing.expectEqual(expected_cap, cap_after);
        // Pre-sized table fits n strictly below the 0.75 load factor.
        try testing.expect(m.len() * 4 < cap_after * 3);
        for (0..n) |i| try testing.expectEqual(@as(?i64, @intCast(i)), m.get(@intCast(i)));
    }
}

test "HashMap.bulkLoadExact: collision-heavy layout matches pre-sized put-loop" {
    const a = testing.allocator;
    const keys = [_]i32{ 0, 16, 32, 48, 64, 80, 96, 112, 1, 17, 33, 49 };
    const vals = [_]i64{ 0, 160, 320, 480, 640, 800, 960, 1120, 10, 170, 330, 490 };
    var pumped = try HashMap(i32, i64).bulkLoadExact(a, &keys, &vals, keys.len, .err);
    defer pumped.deinit();

    var incremental = try HashMap(i32, i64).init(a);
    defer incremental.deinit();
    try incremental.ensureTotalCapacity(keys.len);
    for (keys, vals) |k, v| _ = try incremental.put(k, v);

    try expectHashMapSlotsEqual(&pumped, &incremental);
}

test "HashMap.bulkLoadExact: one table allocation at exact zero-rehash size" {
    var failing = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 1 });
    const keys = [_]i32{ 0, 16, 32, 48, 64, 80, 96, 112, 1, 17, 33, 49 };
    const vals = [_]i64{ 0, 160, 320, 480, 640, 800, 960, 1120, 10, 170, 330, 490 };
    var m = try HashMap(i32, i64).bulkLoadExact(failing.allocator(), &keys, &vals, keys.len, .err);
    defer m.deinit();
    try testing.expectEqual(@as(usize, 32), m.inner.capacity);
    for (keys, vals) |k, v| try testing.expectEqual(@as(?i64, v), m.get(k));
}

test "HashMap.bulkLoadExact: source length, not inserted cardinality, enforces n" {
    const a = testing.allocator;
    try testing.expectError(
        error.TooManyElements,
        HashMap(i32, i64).bulkLoadExact(a, &[_]i32{ 1, 1, 1 }, &[_]i64{ 10, 11, 12 }, 2, .ignore),
    );
}

test "HashMap.bulkLoad: DuplicateKey at first/middle/last" {
    const a = testing.allocator;
    try testing.expectError(error.DuplicateKey, HashMap(i32, i64).bulkLoad(a, &[_]i32{ 1, 1, 2 }, &[_]i64{ 0, 0, 0 }, .err));
    try testing.expectError(error.DuplicateKey, HashMap(i32, i64).bulkLoad(a, &[_]i32{ 1, 2, 2, 3 }, &[_]i64{ 0, 0, 0, 0 }, .err));
    try testing.expectError(error.DuplicateKey, HashMap(i32, i64).bulkLoad(a, &[_]i32{ 1, 2, 3, 3 }, &[_]i64{ 0, 0, 0, 0 }, .err));
}

test "HashMap.bulkLoad: policy .ignore keeps first" {
    const a = testing.allocator;
    var m = try HashMap(i32, i64).bulkLoad(a, &[_]i32{ 1, 1, 2 }, &[_]i64{ 100, 999, 200 }, .ignore);
    defer m.deinit();
    try testing.expectEqual(@as(usize, 2), m.len());
    try testing.expectEqual(@as(?i64, 100), m.get(1));
}

test "HashMap.bulkLoad: float and bool axes" {
    const a = testing.allocator;
    var mf = try HashMap(f32, i32).bulkLoad(a, &[_]f32{ 1.5, 2.5, -0.0 }, &[_]i32{ 1, 2, 3 }, .err);
    defer mf.deinit();
    try testing.expectEqual(@as(?i32, 3), mf.get(-0.0));
    var mb = try HashMap(bool, i32).bulkLoad(a, &[_]bool{ true, false }, &[_]i32{ 1, 0 }, .err);
    defer mb.deinit();
    try testing.expectEqual(@as(?i32, 1), mb.get(true));
}

test "HashMap.bulkLoad: no leak on duplicate error" {
    const a = testing.allocator;
    try testing.expectError(error.DuplicateKey, HashMap(i32, i64).bulkLoad(a, &[_]i32{ 1, 2, 3, 1 }, &[_]i64{ 0, 0, 0, 0 }, .err));
}

test "HashMap.bulkLoad: no leak on allocator failure" {
    var failing = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    const r = HashMap(i32, i64).bulkLoad(failing.allocator(), &[_]i32{ 1, 2 }, &[_]i64{ 0, 0 }, .err);
    try testing.expectError(error.OutOfMemory, r);
}

test "HashSet.bulkLoad / bulkLoadExact: equivalence + zero rehash" {
    const a = testing.allocator;
    const ns = [_]usize{ 3, 6, 12, 24, 48 };
    inline for (ns) |n| {
        const expected_cap: usize = switch (n) {
            3, 6 => 16,
            12 => 32,
            24 => 64,
            48 => 128,
            else => unreachable,
        };
        var vals: [n]i32 = undefined;
        for (0..n) |i| vals[i] = @intCast(i);
        var s = try HashSet(i32).bulkLoadExact(a, &vals, n, .err);
        defer s.deinit();
        const cap_after = s.inner.capacity;
        try testing.expectEqual(n, s.len());
        try testing.expectEqual(cap_after, s.inner.capacity);
        try testing.expectEqual(expected_cap, cap_after);
        for (0..n) |i| try testing.expect(s.contains(@intCast(i)));
    }
    var s2 = try HashSet(i32).bulkLoad(a, &[_]i32{ 5, 1, 5, 3 }, .ignore);
    defer s2.deinit();
    try testing.expectEqual(@as(usize, 3), s2.len());
    try testing.expectError(error.DuplicateKey, HashSet(i32).bulkLoad(a, &[_]i32{ 1, 2, 1 }, .err));
    try testing.expectError(error.TooManyElements, HashSet(i32).bulkLoadExact(a, &[_]i32{ 1, 1, 1 }, 2, .ignore));
}

test "HashSet.bulkLoadExact: collision-heavy layout matches pre-sized add-loop" {
    const a = testing.allocator;
    const vals = [_]i32{ 0, 16, 32, 48, 64, 80, 96, 112, 1, 17, 33, 49 };
    var pumped = try HashSet(i32).bulkLoadExact(a, &vals, vals.len, .err);
    defer pumped.deinit();

    var incremental = try HashSet(i32).init(a);
    defer incremental.deinit();
    try incremental.ensureTotalCapacity(vals.len);
    for (vals) |v| _ = try incremental.add(v);

    try expectHashSetSlotsEqual(&pumped, &incremental);
}

test "HashSet.bulkLoadExact: one table allocation at exact zero-rehash size" {
    var failing = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 1 });
    const vals = [_]i32{ 0, 16, 32, 48, 64, 80, 96, 112, 1, 17, 33, 49 };
    var s = try HashSet(i32).bulkLoadExact(failing.allocator(), &vals, vals.len, .err);
    defer s.deinit();
    try testing.expectEqual(@as(usize, 32), s.inner.capacity);
    for (vals) |v| try testing.expect(s.contains(v));
}

test "HashBag.bulkLoad: flat values count; equals incremental" {
    const a = testing.allocator;
    const vals = [_]i32{ 1, 2, 1, 3, 1, 2 };
    var pumped = try HashBag(i32).bulkLoad(a, &vals);
    defer pumped.deinit();
    var incremental = try HashBag(i32).init(a);
    defer incremental.deinit();
    for (vals) |v| try incremental.add(v);
    try testing.expect(pumped.eql(&incremental));
    try testing.expectEqual(@as(usize, 3), pumped.occurrencesOf(1));
    try testing.expectEqual(@as(usize, 2), pumped.occurrencesOf(2));
}

test "HashBag.bulkLoadCounts: parallel + overflow guard" {
    const a = testing.allocator;
    var b = try HashBag(i32).bulkLoadCounts(a, &[_]i32{ 7, 8 }, &[_]usize{ 4, 5 });
    defer b.deinit();
    try testing.expectEqual(@as(usize, 4), b.occurrencesOf(7));
    try testing.expectEqual(@as(usize, 9), b.totalSize());
    const big = std.math.maxInt(usize);
    try testing.expectError(error.CountOverflow, HashBag(i32).bulkLoadCounts(a, &[_]i32{ 1, 2 }, &[_]usize{ big, 1 }));
}

test "HashBag.bulkLoad: no leak on allocator failure" {
    var failing = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    const r = HashBag(i32).bulkLoad(failing.allocator(), &[_]i32{ 1, 2, 3, 1 });
    try testing.expectError(error.OutOfMemory, r);
}

test "HashBiMap.bulkLoad: bijection + two-sided conflict + no leak" {
    const a = testing.allocator;
    var bm = try HashBiMap(i32, i64).bulkLoad(a, &[_]i32{ 1, 2, 3 }, &[_]i64{ 10, 20, 30 }, .err);
    defer bm.deinit();
    try testing.expectEqual(@as(?i64, 20), bm.get(2));
    try testing.expectEqual(@as(?i32, 3), bm.getKey(30));

    // duplicate KEY
    try testing.expectError(error.DuplicateKey, HashBiMap(i32, i64).bulkLoad(a, &[_]i32{ 1, 1 }, &[_]i64{ 10, 20 }, .err));
    // duplicate VALUE (distinct keys, same value)
    try testing.expectError(error.DuplicateValue, HashBiMap(i32, i64).bulkLoad(a, &[_]i32{ 1, 2 }, &[_]i64{ 10, 10 }, .err));
    // BiMap ignores duplicate policy: duplicate key/value always errors.
    try testing.expectError(error.DuplicateKey, HashBiMap(i32, i64).bulkLoad(a, &[_]i32{ 1, 1 }, &[_]i64{ 10, 10 }, .ignore));
    try testing.expectError(error.DuplicateValue, HashBiMap(i32, i64).bulkLoad(a, &[_]i32{ 1, 2 }, &[_]i64{ 10, 10 }, .ignore));
}

// ===========================================================================
// Multimaps — fromSortedKeys + bulkLoad
// ===========================================================================

test "ListMultimap.fromSortedKeys: grouped, value order preserved; equals put-loop" {
    const a = testing.allocator;
    const keys = [_]i32{ 1, 1, 2, 3, 3, 3 };
    const vals = [_]i32{ 10, 11, 20, 30, 31, 32 };
    var pumped = try ListMultimap(i32, i32).fromSortedKeys(a, &keys, &vals);
    defer pumped.deinit();

    var incremental = ListMultimap(i32, i32).init(a);
    defer incremental.deinit();
    for (keys, vals) |k, v| try incremental.put(k, v);

    try testing.expect(pumped.eql(&incremental));
    try testing.expectEqualSlices(i32, &[_]i32{ 10, 11 }, pumped.get(1));
    try testing.expectEqualSlices(i32, &[_]i32{ 30, 31, 32 }, pumped.get(3));
    try testing.expectEqual(@as(usize, 6), pumped.size());
}

test "ListMultimap.fromSortedKeys: NotSorted on non-grouped/out-of-order keys" {
    const a = testing.allocator;
    try testing.expectError(error.NotSorted, ListMultimap(i32, i32).fromSortedKeys(a, &[_]i32{ 1, 2, 1 }, &[_]i32{ 0, 0, 0 }));
    try testing.expectError(error.NotSorted, ListMultimap(i32, i32).fromSortedKeys(a, &[_]i32{ 3, 1 }, &[_]i32{ 0, 0 }));
}

test "ListMultimap.bulkLoad: any order accumulates" {
    const a = testing.allocator;
    var m = try ListMultimap(i32, i32).bulkLoad(a, &[_]i32{ 3, 1, 3, 2 }, &[_]i32{ 30, 10, 31, 20 });
    defer m.deinit();
    try testing.expectEqual(@as(usize, 2), m.getCount(3));
    try testing.expectEqual(@as(usize, 4), m.size());
}

test "ListMultimap.fromSortedKeyValues: validates value order and preserves duplicates" {
    const a = testing.allocator;
    var m = try ListMultimap(i32, i32).fromSortedKeyValues(a, &[_]i32{ 1, 1, 1, 2 }, &[_]i32{ 10, 10, 11, 20 });
    defer m.deinit();
    try testing.expectEqualSlices(i32, &[_]i32{ 10, 10, 11 }, m.get(1));
    try testing.expectEqual(@as(usize, 4), m.size());
    try testing.expectError(error.NotSorted, ListMultimap(i32, i32).fromSortedKeyValues(a, &[_]i32{ 1, 1, 1 }, &[_]i32{ 2, 1, 2 }));
    try testing.expectError(error.NotSorted, ListMultimap(i32, i32).fromSortedKeyValues(a, &[_]i32{ 1, 2, 1 }, &[_]i32{ 10, 20, 30 }));
    try testing.expectError(error.NotSorted, ListMultimap(i32, i32).fromSortedKeyValues(a, &[_]i32{ 1, 1, 1 }, &[_]i32{ 10, 10, 9 }));
}

test "SetMultimap.fromSortedKeys: dedupes values per key" {
    const a = testing.allocator;
    const keys = [_]i32{ 1, 1, 1, 2 };
    const vals = [_]i32{ 10, 10, 11, 20 };
    var pumped = try SetMultimap(i32, i32).fromSortedKeys(a, &keys, &vals);
    defer pumped.deinit();
    try testing.expectEqual(@as(usize, 2), pumped.getCount(1)); // 10, 11 (dup 10 dropped)
    try testing.expectEqual(@as(usize, 1), pumped.getCount(2));
    try testing.expectEqual(@as(usize, 3), pumped.size());

    var incremental = SetMultimap(i32, i32).init(a);
    defer incremental.deinit();
    for (keys, vals) |k, v| try incremental.put(k, v);
    try testing.expect(pumped.eql(&incremental));
}

test "SetMultimap.fromSortedKeys: NotSorted" {
    const a = testing.allocator;
    try testing.expectError(error.NotSorted, SetMultimap(i32, i32).fromSortedKeys(a, &[_]i32{ 2, 1 }, &[_]i32{ 0, 0 }));
}

test "SetMultimap.fromSortedKeyValues: validates value order and dedupes adjacent values" {
    const a = testing.allocator;
    var m = try SetMultimap(i32, i32).fromSortedKeyValues(a, &[_]i32{ 1, 1, 1, 2 }, &[_]i32{ 10, 10, 11, 20 });
    defer m.deinit();
    try testing.expectEqual(@as(usize, 2), m.getCount(1));
    try testing.expectEqual(@as(usize, 3), m.size());
    try testing.expectError(error.NotSorted, SetMultimap(i32, i32).fromSortedKeyValues(a, &[_]i32{ 1, 1, 1 }, &[_]i32{ 2, 1, 2 }));
    try testing.expectError(error.NotSorted, SetMultimap(i32, i32).fromSortedKeyValues(a, &[_]i32{ 1, 1, 1 }, &[_]i32{ 10, 10, 9 }));
    try testing.expectError(error.NotSorted, SetMultimap(i32, i32).fromSortedKeyValues(a, &[_]i32{ 1, 2, 1 }, &[_]i32{ 10, 20, 30 }));
}

test "Multimap pump paths: no leak on allocator failure" {
    var list_failing = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 1 });
    try testing.expectError(
        error.OutOfMemory,
        ListMultimap(i32, i32).fromSortedKeyValues(list_failing.allocator(), &[_]i32{ 1, 1, 2, 2 }, &[_]i32{ 10, 11, 20, 21 }),
    );

    var set_failing = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 1 });
    try testing.expectError(
        error.OutOfMemory,
        SetMultimap(i32, i32).fromSortedKeyValues(set_failing.allocator(), &[_]i32{ 1, 1, 2, 2 }, &[_]i32{ 10, 11, 20, 21 }),
    );
}

// ===========================================================================
// BitSet.fromIndices
// ===========================================================================

test "BitSet.fromIndices: equals incremental set; single sizing" {
    const a = testing.allocator;
    const idxs = [_]usize{ 1, 5, 64, 200, 5 }; // duplicate harmless
    var pumped = try BitSet.fromIndices(a, &idxs);
    defer pumped.deinit();

    var incremental = BitSet.init(a);
    defer incremental.deinit();
    for (idxs) |i| try incremental.set(i);

    try testing.expect(pumped.eql(&incremental));
    try testing.expectEqual(@as(usize, 4), pumped.cardinality());
    try testing.expect(pumped.get(200));
    try testing.expectEqual(@as(usize, 201), pumped.len());
}

test "BitSet.fromIndices: empty" {
    const a = testing.allocator;
    var b = try BitSet.fromIndices(a, &[_]usize{});
    defer b.deinit();
    try testing.expectEqual(@as(usize, 0), b.cardinality());
    try testing.expectEqual(@as(usize, 0), b.len());
}

test "BitSet.fromIndices: max index is overflow" {
    const a = testing.allocator;
    try testing.expectError(error.Overflow, BitSet.fromIndices(a, &[_]usize{std.math.maxInt(usize)}));
}

// ===========================================================================
// Large-collection equivalence (08-large-collections anchor) via the pump
// ===========================================================================

test "HashMap.bulkLoadExact: large equals incremental" {
    const a = testing.allocator;
    const n = 5000;
    var keys: [n]i32 = undefined;
    var vals: [n]i64 = undefined;
    for (0..n) |i| {
        keys[i] = @intCast(i);
        vals[i] = @intCast(i * 3);
    }
    var pumped = try HashMap(i32, i64).bulkLoadExact(a, &keys, &vals, n, .err);
    defer pumped.deinit();
    var incremental = try HashMap(i32, i64).init(a);
    defer incremental.deinit();
    for (keys, vals) |k, v| _ = try incremental.put(k, v);
    try testing.expect(pumped.eql(&incremental));
}

test "TreeMap.fromSorted: large equals incremental" {
    const a = testing.allocator;
    const n = 5000;
    var keys: [n]i32 = undefined;
    var vals: [n]i64 = undefined;
    for (0..n) |i| {
        keys[i] = @intCast(i);
        vals[i] = @intCast(i);
    }
    var pumped = try TreeMap(i32, i64).fromSorted(a, &keys, &vals, .err);
    defer pumped.deinit();
    var incremental = TreeMap(i32, i64).init(a);
    defer incremental.deinit();
    for (keys, vals) |k, v| _ = try incremental.put(k, v);
    try testing.expect(pumped.eql(&incremental));
}
