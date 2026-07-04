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
const multimap = @import("multimap/multimap.zig");
const hashmap = @import("hashmap/hashmap.zig");
const treemap = @import("treemap/treemap.zig");
const object = @import("object/object.zig");

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
        try testing.expectEqual(@as(usize, 3), l.len());
        try testing.expect(l.contains(s[0]));
        try testing.expect(l.contains(s[1]));
        try testing.expectEqual(@as(?usize, 0), l.indexOf(s[0]));

        var d = try l.distinct();
        defer d.deinit();
        try testing.expectEqual(@as(usize, 2), d.len());

        try testing.expect(l.remove(s[0]));
        try testing.expectEqual(@as(usize, 2), l.len());

        var l2 = try arraylist.ArrayList(T).fromSlice(testing.allocator, l.slice());
        defer l2.deinit();
        try testing.expect(l.eql(&l2));
    }
}

test "ArrayList: min/max/sort under canonical ordering" {
    inline for (type_axis) |T| {
        const s = samples(T);
        var l = try arraylist.ArrayList(T).fromSlice(testing.allocator, &[_]T{ s[1], s[0] });
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
        var l = try arraylist.ArrayList(f32).fromSlice(testing.allocator, &[_]f32{ 1.5, 2.5 });
        defer l.deinit();
        try testing.expectEqual(@as(f32, 4.0), l.sum());
    }
    {
        var l = try arraylist.ArrayList(f64).fromSlice(testing.allocator, &[_]f64{ 1.5, 2.5 });
        defer l.deinit();
        try testing.expectEqual(@as(f64, 4.0), l.sum());
    }
    // bool: i64, count of trues
    {
        var l = try arraylist.ArrayList(bool).fromSlice(testing.allocator, &[_]bool{ true, false, true });
        defer l.deinit();
        try testing.expectEqual(@as(i64, 2), l.sum());
    }
    // int widening: i64 accumulator (avoids i8 overflow)
    {
        var l = try arraylist.ArrayList(i8).fromSlice(testing.allocator, &[_]i8{ 100, 100, 100 });
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
    var big = try arraylist.ArrayList(i32).fromSlice(testing.allocator, &[_]i32{ 2_000_000_000, 2_000_000_000 });
    defer big.deinit();
    try testing.expectEqual(@as(i64, 4_000_000_000), big.sum());
}

test "ArrayList: sum wraps two's-complement on i64 overflow (D4)" {
    // Java/Go originals wrap on overflow; Zig's default `+=` would trap (safe)
    // or be UB (ReleaseFast). sum() must wrap: maxInt(i64) + 1 == minInt(i64).
    var l = try arraylist.ArrayList(i64).fromSlice(
        testing.allocator,
        &[_]i64{ std.math.maxInt(i64), 1 },
    );
    defer l.deinit();
    try testing.expectEqual(@as(i64, std.math.minInt(i64)), l.sum());

    // Symmetric underflow: minInt(i64) + (-1) == maxInt(i64).
    var u = try arraylist.ArrayList(i64).fromSlice(
        testing.allocator,
        &[_]i64{ std.math.minInt(i64), -1 },
    );
    defer u.deinit();
    try testing.expectEqual(@as(i64, std.math.maxInt(i64)), u.sum());
}

test "ArrayList: sum over wide unsigned compiles and folds low 64 bits (D4)" {
    // ArrayList(u128) is a legal generic instantiation; sum() must compile and
    // reduce wide-unsigned elements to their low 64 bits (two's-complement at
    // the i64 accumulator) rather than @intCast-trapping.
    var l = try arraylist.ArrayList(u128).fromSlice(testing.allocator, &[_]u128{ 1, 2, 3 });
    defer l.deinit();
    try testing.expectEqual(@as(i64, 6), l.sum());

    // maxInt(u128) truncates to all-ones u64 => -1 as i64.
    var w = try arraylist.ArrayList(u128).fromSlice(testing.allocator, &[_]u128{std.math.maxInt(u128)});
    defer w.deinit();
    try testing.expectEqual(@as(i64, -1), w.sum());
}

test "HashSet: parameterized add/contains/remove/set-ops" {
    inline for (type_axis) |T| {
        const s = samples(T);
        var set = hashset.HashSet(T).init(testing.allocator);
        defer set.deinit();
        try testing.expect(try set.add(s[0]));
        try testing.expect(!(try set.add(s[0])));
        try testing.expect(try set.add(s[1]));
        try testing.expectEqual(@as(usize, 2), set.len());
        try testing.expect(set.contains(s[1]));
        try testing.expect(set.remove(s[0]));
        try testing.expect(!set.contains(s[0]));

        var a = try hashset.HashSet(T).fromSlice(testing.allocator, &[_]T{s[0]});
        defer a.deinit();
        var b = try hashset.HashSet(T).fromSlice(testing.allocator, &[_]T{s[1]});
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
        var set = try treeset.TreeSet(T).fromSlice(testing.allocator, &[_]T{ s[1], s[0] });
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

test "TreeBag: iterative teardown frees a large tree without recursion (Step 10)" {
    // Like the TreeSet teardown test: the treap-backed bag's destroySubtree is
    // now an O(1)-stack rotate-to-leaf walk; a large tree torn down by clear()
    // and deinit must free every wrapping bag node exactly once (leak-checked).
    const a = testing.allocator;
    var tb = bag.TreeBag(i32).init(a);
    defer tb.deinit();
    var i: i32 = 0;
    while (i < 20_000) : (i += 1) try tb.add(@rem(i, 5_000)); // 5k distinct, counts up to 4
    try testing.expectEqual(@as(usize, 20_000), tb.len());

    tb.clear();
    try testing.expectEqual(@as(usize, 0), tb.len());
    try testing.expect(tb.isEmpty());

    i = 0;
    while (i < 8_000) : (i += 1) try tb.add(i);
    try testing.expectEqual(@as(usize, 8_000), tb.len());
    try testing.expectEqual(@as(usize, 1), tb.occurrencesOf(7_999));
}

test "HashBag/TreeBag: parameterized count semantics" {
    inline for (type_axis) |T| {
        const s = samples(T);
        var hb = bag.HashBag(T).init(testing.allocator);
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
    var q = try priority_queue.PriorityQueue(f32).fromSlice(testing.allocator, &[_]f32{ 3.0, -1.0, 2.0, -5.0 });
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

// ---------------------------------------------------------------------------
// F3/F4 regression: result-builder and slice-materializer methods must not
// leak their partial result when a mid-build allocation fails. Each sweep
// drives `std.testing.FailingAllocator` with a rising `fail_index`; on error
// we assert `error.OutOfMemory`, on success we deinit the result and stop.
// The `testing.allocator` leak check at test end is the real assertion — a
// missing `errdefer` shows up there as a leak, failing the test.
// ---------------------------------------------------------------------------

fn f34_alwaysTrue(_: void, _: i32) bool {
    return true;
}

// F3 builder using an explicit allocator param: `of` builds directly with the
// failing allocator, so it *is* the method under test.
test "F3 OOM: HashSet.of no partial-result leak" {
    var ctx: u8 = 0;
    _ = &ctx;
    var idx: usize = 0;
    while (idx < 128) : (idx += 1) {
        var fa = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = idx });
        if (hashset.HashSet(i32).fromSlice(fa.allocator(), &[_]i32{ 1, 2, 3, 4, 5, 6, 7, 8 })) |res| {
            var r = res;
            r.deinit();
            break;
        } else |err| {
            try testing.expectEqual(error.OutOfMemory, err);
        }
    }
}

test "F3 OOM: TreeSet.of no partial-result leak" {
    var idx: usize = 0;
    while (idx < 128) : (idx += 1) {
        var fa = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = idx });
        if (treeset.TreeSet(i32).fromSlice(fa.allocator(), &[_]i32{ 5, 3, 8, 1, 9, 2, 7, 4 })) |res| {
            var r = res;
            r.deinit();
            break;
        } else |err| {
            try testing.expectEqual(error.OutOfMemory, err);
        }
    }
}

// F3 predicate method using `self.allocator`: the source must share the failing
// allocator so the result allocation can fail. Low fail_index values fail while
// building the source (skipped); higher ones fail mid-`select`.
test "F3 OOM: ArrayList.select no partial-result leak" {
    var idx: usize = 0;
    while (idx < 128) : (idx += 1) {
        var fa = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = idx });
        const a = fa.allocator();
        var src = arraylist.ArrayList(i32).init(a);
        var built = true;
        for ([_]i32{ 1, 2, 3, 4, 5, 6 }) |v| {
            src.push(v) catch {
                built = false;
                break;
            };
        }
        if (!built) {
            src.deinit();
            continue;
        }
        if (src.select({}, f34_alwaysTrue)) |res| {
            var r = res;
            r.deinit();
            src.deinit();
            break;
        } else |err| {
            try testing.expectEqual(error.OutOfMemory, err);
            src.deinit();
        }
    }
}

// F3 set-algebra method using `self.allocator`.
test "F3 OOM: HashSet.setUnion no partial-result leak" {
    var idx: usize = 0;
    while (idx < 256) : (idx += 1) {
        var fa = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = idx });
        const a = fa.allocator();
        var s1 = hashset.HashSet(i32).init(a);
        var s2 = hashset.HashSet(i32).init(a);
        var built = true;
        for ([_]i32{ 1, 2, 3, 4 }) |v| {
            _ = s1.add(v) catch {
                built = false;
                break;
            };
        }
        if (built) {
            for ([_]i32{ 3, 4, 5, 6 }) |v| {
                _ = s2.add(v) catch {
                    built = false;
                    break;
                };
            }
        }
        if (!built) {
            s1.deinit();
            s2.deinit();
            continue;
        }
        if (s1.setUnion(&s2)) |res| {
            var r = res;
            r.deinit();
            s1.deinit();
            s2.deinit();
            break;
        } else |err| {
            try testing.expectEqual(error.OutOfMemory, err);
            s1.deinit();
            s2.deinit();
        }
    }
}

// F4 materializer with explicit allocator param: source built on the leak-checked
// allocator, only the materialization runs on the failing allocator.
test "F4 OOM: TreeSet.rangeValues no scratch-list leak" {
    var src = treeset.TreeSet(i32).init(testing.allocator);
    defer src.deinit();
    for ([_]i32{ 1, 2, 3, 4, 5, 6, 7, 8 }) |v| _ = try src.add(v);
    var idx: usize = 0;
    while (idx < 128) : (idx += 1) {
        var fa = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = idx });
        const slice = src.rangeValues(1, 8, fa.allocator()) catch |err| {
            try testing.expectEqual(error.OutOfMemory, err);
            continue;
        };
        testing.allocator.free(slice);
        break;
    }
}

test "F4 OOM: HashBag.toSlice no scratch-list leak" {
    var b = bag.HashBag(i32).init(testing.allocator);
    defer b.deinit();
    for ([_]i32{ 1, 1, 2, 3, 3, 3, 4 }) |v| try b.add(v);
    var idx: usize = 0;
    while (idx < 128) : (idx += 1) {
        var fa = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = idx });
        const slice = b.toSlice(fa.allocator()) catch |err| {
            try testing.expectEqual(error.OutOfMemory, err);
            continue;
        };
        testing.allocator.free(slice);
        break;
    }
}

test "F4 OOM: ListMultimap.valuesToSlice no scratch-list leak" {
    var mm = multimap.ListMultimap(i32, i32).init(testing.allocator);
    defer mm.deinit();
    try mm.put(1, 10);
    try mm.put(1, 11);
    try mm.put(2, 20);
    try mm.put(3, 30);
    var idx: usize = 0;
    while (idx < 128) : (idx += 1) {
        var fa = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = idx });
        const slice = mm.valuesToSlice(fa.allocator()) catch |err| {
            try testing.expectEqual(error.OutOfMemory, err);
            continue;
        };
        testing.allocator.free(slice);
        break;
    }
}

// ---------------------------------------------------------------------------
// D11: `{f}` format-string dispatch reaches the 1-arg custom `format` method.
// A regression to the legacy 4-arg signature would make `{f}` fail to compile
// or fall back to the default struct dump.
// ---------------------------------------------------------------------------

test "ArrayList: {f} dispatch renders [1, 2, 3]" {
    var l = try arraylist.ArrayList(i32).fromSlice(testing.allocator, &[_]i32{ 1, 2, 3 });
    defer l.deinit();
    const out = try std.fmt.allocPrint(testing.allocator, "{f}", .{l});
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("[1, 2, 3]", out);
}

test "HashSet: {f} dispatch renders {7}" {
    var set = try hashset.HashSet(i32).fromSlice(testing.allocator, &[_]i32{7});
    defer set.deinit();
    const out = try std.fmt.allocPrint(testing.allocator, "{f}", .{set});
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("{7}", out);
}

test "ArrayStack: {f} dispatch renders [2, 1] (top-to-bottom)" {
    var st = stack.ArrayStack(i32).init(testing.allocator);
    defer st.deinit();
    try st.push(1);
    try st.push(2);
    const out = try std.fmt.allocPrint(testing.allocator, "{f}", .{st});
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("[2, 1]", out);
}

test "ArrayDeque: {f} dispatch renders [1, 2]" {
    var d = deque.ArrayDeque(i32).init(testing.allocator);
    defer d.deinit();
    try d.addLast(1);
    try d.addLast(2);
    const out = try std.fmt.allocPrint(testing.allocator, "{f}", .{d});
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("[1, 2]", out);
}

test "HashBag: {f} dispatch renders {5x2}" {
    var hb = bag.HashBag(i32).init(testing.allocator);
    defer hb.deinit();
    try hb.add(5);
    try hb.add(5);
    const out = try std.fmt.allocPrint(testing.allocator, "{f}", .{hb});
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("{5x2}", out);
}

test "TreeBag: {f} dispatch renders {1x2, 2x1} in sorted order" {
    var tb = bag.TreeBag(i32).init(testing.allocator);
    defer tb.deinit();
    try tb.add(2);
    try tb.add(1);
    try tb.add(1);
    const out = try std.fmt.allocPrint(testing.allocator, "{f}", .{tb});
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("{1x2, 2x1}", out);
}

fn f_isEven(_: void, v: i32) bool {
    return @rem(v, 2) == 0;
}

// Regression: select/reject are generic methods that only compile when
// instantiated. A stale `try init(...)` (from the lazy-infallible-init wave)
// slipped past `zig build test` because nothing exercised them. These tests
// force instantiation so that class of break is caught at build time.
test "HashSet.select/reject compile and filter (infallible-init regression)" {
    var s = try hashset.HashSet(i32).fromSlice(testing.allocator, &[_]i32{ 1, 2, 3, 4, 5, 6 });
    defer s.deinit();

    var evens = try s.select({}, f_isEven);
    defer evens.deinit();
    try testing.expectEqual(@as(usize, 3), evens.len());
    try testing.expect(evens.contains(2) and evens.contains(4) and evens.contains(6));
    try testing.expect(!evens.contains(1));

    var odds = try s.reject({}, f_isEven);
    defer odds.deinit();
    try testing.expectEqual(@as(usize, 3), odds.len());
    try testing.expect(odds.contains(1) and odds.contains(3) and odds.contains(5));
    try testing.expect(!odds.contains(2));
}

test "HashBag.select/reject compile and filter, preserving counts (infallible-init regression)" {
    var b = bag.HashBag(i32).init(testing.allocator);
    defer b.deinit();
    try b.addOccurrences(2, 3);
    try b.addOccurrences(3, 2);
    try b.addOccurrences(4, 1);

    var evens = try b.select({}, f_isEven);
    defer evens.deinit();
    try testing.expectEqual(@as(usize, 3), evens.occurrencesOf(2));
    try testing.expectEqual(@as(usize, 1), evens.occurrencesOf(4));
    try testing.expectEqual(@as(usize, 0), evens.occurrencesOf(3));

    var odds = try b.reject({}, f_isEven);
    defer odds.deinit();
    try testing.expectEqual(@as(usize, 2), odds.occurrencesOf(3));
    try testing.expectEqual(@as(usize, 0), odds.occurrencesOf(2));
}

// ---------------------------------------------------------------------------
// Functional-op instantiation coverage.
//
// Predicate/callback methods (`context: anytype, comptime f`) are generic:
// their bodies are only semantically analyzed when instantiated. A body error
// (e.g. the Step-5 stale `try init` in select/reject, or a Step-1 anytype-
// callback slip) stays invisible to `zig build test` unless *something* calls
// the method at a concrete type. Several of these had zero call-sites in the
// whole suite. This harness force-instantiates the predicate family across
// every primitive AND object collection so that class of break fails the build.
//
// Invoked by pointer (not by comptime type) so collections with differing
// constructors — e.g. object TreeSet/TreeMap need a comparator — can be built
// by the caller and still share one method-invoker.
// ---------------------------------------------------------------------------

fn fop_elemPred(_: void, _: i32) bool {
    return true;
}
fn fop_elemConsume(_: void, _: i32) void {}
fn fop_elemFold(_: void, a: i32, b: i32) i32 {
    return a +% b;
}
fn fop_kvPred(_: void, _: i32, _: i32) bool {
    return true;
}
fn fop_kvConsume(_: void, _: i32, _: i32) void {}
fn fop_kvFold(_: void, acc: i32, _: i32, v: i32) i32 {
    return acc +% v;
}

fn fopElem(c: anytype) void {
    const T = @TypeOf(c.*);
    if (@hasDecl(T, "detect")) _ = c.detect({}, fop_elemPred);
    if (@hasDecl(T, "anySatisfy")) _ = c.anySatisfy({}, fop_elemPred);
    if (@hasDecl(T, "allSatisfy")) _ = c.allSatisfy({}, fop_elemPred);
    if (@hasDecl(T, "noneSatisfy")) _ = c.noneSatisfy({}, fop_elemPred);
    if (@hasDecl(T, "forEach")) c.forEach({}, fop_elemConsume);
    if (@hasDecl(T, "injectInto")) _ = c.injectInto({}, 0, fop_elemFold);
}

fn fopKV(c: anytype) void {
    const T = @TypeOf(c.*);
    if (@hasDecl(T, "detect")) _ = c.detect({}, fop_kvPred);
    if (@hasDecl(T, "anySatisfy")) _ = c.anySatisfy({}, fop_kvPred);
    if (@hasDecl(T, "allSatisfy")) _ = c.allSatisfy({}, fop_kvPred);
    if (@hasDecl(T, "noneSatisfy")) _ = c.noneSatisfy({}, fop_kvPred);
    if (@hasDecl(T, "forEach")) c.forEach({}, fop_kvConsume);
    if (@hasDecl(T, "injectInto")) _ = c.injectInto({}, 0, fop_kvFold);
}

test "functional-op predicate family instantiates on every primitive collection" {
    const a = testing.allocator;
    inline for (.{
        arraylist.ArrayList(i32),
        hashset.HashSet(i32),
        stack.ArrayStack(i32),
        deque.ArrayDeque(i32),
        treeset.TreeSet(i32),
        bag.TreeBag(i32),
        bag.HashBag(i32),
    }) |T| {
        var c = T.init(a);
        defer c.deinit();
        fopElem(&c);
    }

    inline for (.{
        hashmap.HashMap(i32, i32),
        treemap.TreeMap(i32, i32),
        multimap.ListMultimap(i32, i32),
        multimap.SetMultimap(i32, i32),
    }) |T| {
        var c = T.init(a);
        defer c.deinit();
        fopKV(&c);
    }
}

test "functional-op predicate family instantiates on every object collection" {
    const a = testing.allocator;

    // Element object variants taking init(allocator).
    inline for (.{
        object.ArrayList(i32),
        object.HashSet(i32),
        object.LinkedHashSet(i32),
    }) |T| {
        var c = T.init(a);
        defer c.deinit();
        fopElem(&c);
    }
    // Object TreeSet needs a comparator.
    var ots = object.TreeSet(i32).init(a, object.naturalComparator(i32));
    defer ots.deinit();
    fopElem(&ots);

    // KV object variants taking init(allocator).
    inline for (.{
        object.HashMap(i32, i32),
        object.LinkedHashMap(i32, i32),
    }) |T| {
        var c = T.init(a);
        defer c.deinit();
        fopKV(&c);
    }
    // Object TreeMap needs a comparator.
    var otm = object.TreeMap(i32, i32).init(a, object.naturalComparator(i32));
    defer otm.deinit();
    fopKV(&otm);
}

// Object shapes not reachable through fopElem/fopKV: the filter-form
// select/reject (object.ArrayList only — object.TreeSet.select is index access),
// HashBag's forEachWithOccurrences, and the strategy-backed map/set forEach.
// These are the object analogues of the original select/reject compile break, so
// they are worth instantiating explicitly.
fn fop_occ(_: void, _: i32, _: usize) void {}
fn fop_hash(x: i32) u64 {
    return @intCast(@as(u32, @bitCast(x)));
}
fn fop_eql(x: i32, y: i32) bool {
    return x == y;
}

test "functional-op residual object shapes instantiate (select/reject, occurrences, strategy forEach)" {
    const a = testing.allocator;

    // object.ArrayList filter-form select/reject (allocating — the direct
    // analogue of the HashSet/HashBag break this whole pass chased).
    var oal = object.ArrayList(i32).init(a);
    defer oal.deinit();
    {
        var r = try oal.select({}, fop_elemPred);
        r.deinit();
    }
    {
        var r = try oal.reject({}, fop_elemPred);
        r.deinit();
    }

    // object.HashBag distinct occurrences callback shape.
    var ohb = object.HashBag(i32).init(a);
    defer ohb.deinit();
    ohb.forEachWithOccurrences({}, fop_occ);

    // Strategy-backed set/map forEach callback bodies.
    const strat = object.HashingStrategy(i32){ .hashFn = &fop_hash, .eqlFn = &fop_eql };
    var shs = object.HashSetWithStrategy(i32).init(a, strat);
    defer shs.deinit();
    shs.forEach({}, fop_elemConsume);
    var shm = object.HashMapWithStrategy(i32, i32).init(a, strat);
    defer shm.deinit();
    shm.forEach({}, fop_kvConsume);
}
