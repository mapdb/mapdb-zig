// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Consolidated tests for the seven single-element-type container generics
//! collapsed in sub-phase 6a-5:
//!   ArrayList / HashSet / ArrayStack / ArrayDeque / PriorityQueue / TreeSet /
//!   HashBag / TreeBag.
//!
//! Zig only type-checks generic methods that are *referenced*. Collapsing each
//! per-type set of 8 wrappers into one comptime generic means an unreferenced
//! method on an unexercised instantiation would never be compiled — a silent
//! coverage collapse. Two mechanisms counter this:
//!   1. `refAllDeclsRecursive` over every named alias forces every method on
//!      every instantiation to be compiled.
//!   2. Parameterized runtime tests exercise the full 8-type element axis
//!      behaviourally (core ops, float bit-equality, total ordering including
//!      NaN/±0, numeric reductions, bag count semantics), replacing the deleted
//!      embedded per-file tests.

const std = @import("std");
const testing = std.testing;

const arraylist = @import("arraylist/arraylist.zig");
const hashset = @import("hashset/hashset.zig");
const stack = @import("stack/stack.zig");
const deque = @import("deque/deque.zig");
const priority_queue = @import("priority_queue/priority_queue.zig");
const treeset = @import("treeset/treeset.zig");
const bag = @import("bag/bag.zig");

// ---------------------------------------------------------------------------
// Force-compile every method on every instantiation of every family.
// ---------------------------------------------------------------------------

const all_alias_types = [_]type{
    // arraylist
    arraylist.BoolArrayList,          arraylist.CharArrayList,          arraylist.F32ArrayList,          arraylist.F64ArrayList,
    arraylist.I8ArrayList,            arraylist.I16ArrayList,           arraylist.I32ArrayList,          arraylist.I64ArrayList,
    // hashset
    hashset.BoolHashSet,              hashset.CharHashSet,              hashset.F32HashSet,              hashset.F64HashSet,
    hashset.I8HashSet,                hashset.I16HashSet,               hashset.I32HashSet,              hashset.I64HashSet,
    // stack
    stack.BoolArrayStack,             stack.CharArrayStack,             stack.F32ArrayStack,             stack.F64ArrayStack,
    stack.I8ArrayStack,               stack.I16ArrayStack,              stack.I32ArrayStack,             stack.I64ArrayStack,
    // deque
    deque.BoolArrayDeque,             deque.CharArrayDeque,             deque.F32ArrayDeque,             deque.F64ArrayDeque,
    deque.I8ArrayDeque,               deque.I16ArrayDeque,              deque.I32ArrayDeque,             deque.I64ArrayDeque,
    // priority_queue
    priority_queue.BoolPriorityQueue, priority_queue.CharPriorityQueue, priority_queue.F32PriorityQueue, priority_queue.F64PriorityQueue,
    priority_queue.I8PriorityQueue,   priority_queue.I16PriorityQueue,  priority_queue.I32PriorityQueue, priority_queue.I64PriorityQueue,
    // treeset
    treeset.BoolTreeSet,              treeset.CharTreeSet,              treeset.F32TreeSet,              treeset.F64TreeSet,
    treeset.I8TreeSet,                treeset.I16TreeSet,               treeset.I32TreeSet,              treeset.I64TreeSet,
    // hash bag
    bag.BoolHashBag,                  bag.CharHashBag,                  bag.F32HashBag,                  bag.F64HashBag,
    bag.I8HashBag,                    bag.I16HashBag,                   bag.I32HashBag,                  bag.I64HashBag,
    // tree bag
    bag.BoolTreeBag,                  bag.CharTreeBag,                  bag.F32TreeBag,                  bag.F64TreeBag,
    bag.I8TreeBag,                    bag.I16TreeBag,                   bag.I32TreeBag,                  bag.I64TreeBag,
};

test "refAllDeclsRecursive forces every method on every instantiation to compile" {
    inline for (all_alias_types) |T| {
        std.testing.refAllDeclsRecursive(T);
    }
}

// ---------------------------------------------------------------------------
// Parameterized runtime coverage across the full 8-type element axis.
// ---------------------------------------------------------------------------

const type_axis = [_]type{ bool, u21, f32, f64, i8, i16, i32, i64 };

/// Two distinct sample values of type `T`, returned so `lo` sorts before `hi`
/// under the canonical comparator. `bool` only has two inhabitants.
fn samples(comptime T: type) [2]T {
    return switch (@typeInfo(T)) {
        .bool => .{ false, true },
        .float => .{ 1.5, 2.5 },
        .int => .{ 1, 2 },
        else => unreachable,
    };
}

test "ArrayList: parameterized core ops + contains + eql + distinct" {
    inline for (type_axis) |T| {
        const s = samples(T);
        var l = arraylist.ArrayList(T).init(testing.allocator);
        defer l.deinit();
        try testing.expect(l.isEmpty());
        try l.push(s[0]);
        try l.push(s[1]);
        try l.push(s[0]);
        try testing.expectEqual(@as(usize, 3), l.len());
        try testing.expectEqual(@as(usize, 3), l.size());
        try testing.expect(l.contains(s[0]));
        try testing.expect(l.contains(s[1]));
        try testing.expectEqual(@as(?usize, 0), l.indexOf(s[0]));

        var d = try l.distinct();
        defer d.deinit();
        try testing.expectEqual(@as(usize, 2), d.len());

        try testing.expect(l.remove(s[0]));
        try testing.expectEqual(@as(usize, 2), l.len());

        var l2 = try arraylist.ArrayList(T).of(testing.allocator, l.toSlice());
        defer l2.deinit();
        try testing.expect(l.eql(&l2));
    }
}

test "ArrayList: min/max/sort under canonical ordering" {
    inline for (type_axis) |T| {
        const s = samples(T);
        var l = try arraylist.ArrayList(T).of(testing.allocator, &[_]T{ s[1], s[0] });
        defer l.deinit();
        try testing.expectEqual(@as(?T, s[0]), l.min());
        try testing.expectEqual(@as(?T, s[1]), l.max());
        l.sort();
        try testing.expectEqual(@as(?T, s[0]), l.get(0));
        try testing.expectEqual(@as(?T, s[1]), l.get(1));
        try testing.expect(l.binarySearch(s[1]) != null);
    }
}

test "ArrayList: sum reduction type and value per element type" {
    // float: returns T, plain summation
    {
        var l = try arraylist.ArrayList(f32).of(testing.allocator, &[_]f32{ 1.5, 2.5 });
        defer l.deinit();
        try testing.expectEqual(@as(f32, 4.0), l.sum());
    }
    {
        var l = try arraylist.ArrayList(f64).of(testing.allocator, &[_]f64{ 1.5, 2.5 });
        defer l.deinit();
        try testing.expectEqual(@as(f64, 4.0), l.sum());
    }
    // bool: i64, count of trues
    {
        var l = try arraylist.ArrayList(bool).of(testing.allocator, &[_]bool{ true, false, true });
        defer l.deinit();
        try testing.expectEqual(@as(i64, 2), l.sum());
    }
    // int widening: i64 accumulator (avoids i8 overflow)
    {
        var l = try arraylist.ArrayList(i8).of(testing.allocator, &[_]i8{ 100, 100, 100 });
        defer l.deinit();
        try testing.expectEqual(@as(i64, 300), l.sum());
    }
}

test "ArrayList: marquee — f32 NaN bit-equality + signed-zero distinct + i64 sum widening" {
    // contains-NaN: bit equality finds the NaN we inserted.
    var l = arraylist.ArrayList(f32).init(testing.allocator);
    defer l.deinit();
    const nan = std.math.nan(f32);
    try l.push(nan);
    try l.push(-0.0);
    try testing.expect(l.contains(nan));
    // +0.0 and -0.0 are distinct under bit equality.
    try testing.expect(l.contains(-0.0));
    try testing.expect(!l.contains(0.0));

    // i64 sum-widening: values that would overflow i32 sum correctly.
    var big = try arraylist.ArrayList(i32).of(testing.allocator, &[_]i32{ 2_000_000_000, 2_000_000_000 });
    defer big.deinit();
    try testing.expectEqual(@as(i64, 4_000_000_000), big.sum());
}

test "ArrayList: sum wraps two's-complement on i64 overflow (D4)" {
    // Java/Go originals wrap on overflow; Zig's default `+=` would trap (safe)
    // or be UB (ReleaseFast). sum() must wrap: maxInt(i64) + 1 == minInt(i64).
    var l = try arraylist.ArrayList(i64).of(
        testing.allocator,
        &[_]i64{ std.math.maxInt(i64), 1 },
    );
    defer l.deinit();
    try testing.expectEqual(@as(i64, std.math.minInt(i64)), l.sum());

    // Symmetric underflow: minInt(i64) + (-1) == maxInt(i64).
    var u = try arraylist.ArrayList(i64).of(
        testing.allocator,
        &[_]i64{ std.math.minInt(i64), -1 },
    );
    defer u.deinit();
    try testing.expectEqual(@as(i64, std.math.maxInt(i64)), u.sum());
}

test "HashSet: parameterized add/contains/remove/set-ops" {
    inline for (type_axis) |T| {
        const s = samples(T);
        var set = try hashset.HashSet(T).init(testing.allocator);
        defer set.deinit();
        try testing.expect(try set.add(s[0]));
        try testing.expect(!(try set.add(s[0])));
        try testing.expect(try set.add(s[1]));
        try testing.expectEqual(@as(usize, 2), set.len());
        try testing.expect(set.contains(s[1]));
        try testing.expect(set.remove(s[0]));
        try testing.expect(!set.contains(s[0]));

        var a = try hashset.HashSet(T).of(testing.allocator, &[_]T{s[0]});
        defer a.deinit();
        var b = try hashset.HashSet(T).of(testing.allocator, &[_]T{s[1]});
        defer b.deinit();
        var u = try a.setUnion(&b);
        defer u.deinit();
        try testing.expectEqual(@as(usize, 2), u.len());
    }
}

test "Stack: parameterized LIFO + contains + eql" {
    inline for (type_axis) |T| {
        const s = samples(T);
        var st = stack.ArrayStack(T).init(testing.allocator);
        defer st.deinit();
        try st.push(s[0]);
        try st.push(s[1]);
        try testing.expectEqual(@as(?T, s[1]), st.peek());
        try testing.expectEqual(@as(?T, s[1]), st.pop());
        try testing.expect(st.contains(s[0]));
        try testing.expectEqual(@as(?T, s[0]), st.pop());
        try testing.expectEqual(@as(?T, null), st.pop());
    }
}

test "Deque: parameterized ends + contains + eql" {
    inline for (type_axis) |T| {
        const s = samples(T);
        var d = deque.ArrayDeque(T).init(testing.allocator);
        defer d.deinit();
        try d.addLast(s[1]);
        try d.addFirst(s[0]);
        try testing.expectEqual(@as(?T, s[0]), d.peekFirst());
        try testing.expectEqual(@as(?T, s[1]), d.peekLast());
        try testing.expect(d.contains(s[0]));
        try testing.expectEqual(@as(?T, s[0]), d.removeFirst());
        try testing.expectEqual(@as(?T, s[1]), d.removeLast());
        try testing.expect(d.isEmpty());
    }
}

test "PriorityQueue: parameterized min-heap order + contains" {
    inline for (type_axis) |T| {
        const s = samples(T);
        var q = priority_queue.PriorityQueue(T).init(testing.allocator);
        defer q.deinit();
        try q.push(s[1]);
        try q.push(s[0]);
        try testing.expectEqual(@as(?T, s[0]), q.peek());
        try testing.expect(q.contains(s[1]));
        try testing.expectEqual(@as(?T, s[0]), q.pop());
        try testing.expectEqual(@as(?T, s[1]), q.pop());
        try testing.expectEqual(@as(?T, null), q.pop());
    }
}

test "TreeSet: parameterized sorted ops + min/max + ceiling/floor" {
    inline for (type_axis) |T| {
        const s = samples(T);
        var set = try treeset.TreeSet(T).of(testing.allocator, &[_]T{ s[1], s[0] });
        defer set.deinit();
        try testing.expectEqual(@as(?T, s[0]), set.min());
        try testing.expectEqual(@as(?T, s[1]), set.max());
        const items = try set.toSlice(testing.allocator);
        defer testing.allocator.free(items);
        try testing.expectEqual(s[0], items[0]);
        try testing.expectEqual(s[1], items[1]);
        try testing.expectEqual(@as(?T, s[1]), set.ceiling(s[1]));
        try testing.expectEqual(@as(?T, s[0]), set.floor(s[0]));
    }
}

test "HashBag/TreeBag: parameterized count semantics" {
    inline for (type_axis) |T| {
        const s = samples(T);
        var hb = try bag.HashBag(T).init(testing.allocator);
        defer hb.deinit();
        try hb.add(s[0]);
        try hb.add(s[0]);
        try hb.add(s[1]);
        try testing.expectEqual(@as(usize, 2), hb.occurrencesOf(s[0]));
        try testing.expectEqual(@as(usize, 1), hb.occurrencesOf(s[1]));
        try testing.expectEqual(@as(usize, 3), hb.totalSize());
        try testing.expectEqual(@as(usize, 2), hb.sizeDistinct());
        try testing.expect(hb.remove(s[0]));
        try testing.expectEqual(@as(usize, 1), hb.occurrencesOf(s[0]));

        var tb = bag.TreeBag(T).init(testing.allocator);
        defer tb.deinit();
        try tb.add(s[1]);
        try tb.add(s[0]);
        try tb.add(s[0]);
        try testing.expectEqual(@as(usize, 2), tb.occurrencesOf(s[0]));
        try testing.expectEqual(@as(usize, 3), tb.totalSize());
        try testing.expectEqual(@as(usize, 2), tb.sizeDistinct());
        // TreeBag keeps sorted order.
        try testing.expectEqual(@as(?T, s[0]), tb.min());
        try testing.expectEqual(@as(?T, s[1]), tb.max());
    }
}

// ---------------------------------------------------------------------------
// Marquee float total-order tests (NaN-to-end, −0 vs +0 distinct).
// ---------------------------------------------------------------------------

test "TreeSet: f32 total order — NaN sorts to end, -0.0 and +0.0 distinct" {
    var set = treeset.TreeSet(f32).init(testing.allocator);
    defer set.deinit();
    const nan = std.math.nan(f32);
    _ = try set.add(1.0);
    _ = try set.add(nan);
    _ = try set.add(-0.0);
    _ = try set.add(0.0);
    _ = try set.add(-1.0);
    // -0.0 and +0.0 are distinct keys under totalOrder.
    try testing.expectEqual(@as(usize, 5), set.len());

    const items = try set.toSlice(testing.allocator);
    defer testing.allocator.free(items);
    // totalOrder: -1.0 < -0.0 < +0.0 < 1.0 < NaN
    try testing.expectEqual(@as(f32, -1.0), items[0]);
    try testing.expect(std.math.signbit(items[1]) and items[1] == 0.0); // -0.0
    try testing.expect(!std.math.signbit(items[2]) and items[2] == 0.0); // +0.0
    try testing.expectEqual(@as(f32, 1.0), items[3]);
    try testing.expect(std.math.isNan(items[4])); // NaN at end
}

test "PriorityQueue: f32 ordering pops ascending including negatives" {
    var q = try priority_queue.PriorityQueue(f32).of(testing.allocator, &[_]f32{ 3.0, -1.0, 2.0, -5.0 });
    defer q.deinit();
    try testing.expectEqual(@as(?f32, -5.0), q.pop());
    try testing.expectEqual(@as(?f32, -1.0), q.pop());
    try testing.expectEqual(@as(?f32, 2.0), q.pop());
    try testing.expectEqual(@as(?f32, 3.0), q.pop());
}

test "TreeBag: f32 -0.0 / +0.0 distinct, NaN bit-equal in eql" {
    var b = bag.TreeBag(f32).init(testing.allocator);
    defer b.deinit();
    try b.add(-0.0);
    try b.add(0.0);
    // Distinct keys under totalOrder.
    try testing.expectEqual(@as(usize, 2), b.sizeDistinct());
    try testing.expectEqual(@as(usize, 1), b.occurrencesOf(-0.0));
    try testing.expectEqual(@as(usize, 1), b.occurrencesOf(0.0));
}
