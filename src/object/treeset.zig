// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Sorted set backed by a red-black tree with a pluggable comparator.
//!
//! Equality is defined by the comparator (`cmp(a, b) == .eq`), not by
//! built-in equality on `T`. A case-insensitive comparator produces a
//! case-insensitive sorted set. See `strategy.zig` for comparator
//! builders.

const std = @import("std");
const Allocator = std.mem.Allocator;
const strategy = @import("strategy.zig");
const treemap_mod = @import("treemap.zig");
const Range = @import("../range.zig").Range;

/// Sorted set backed by `TreeMap(T, void)`.
///
/// Elements are maintained in the order defined by the comparator. All
/// operations are O(log n). Call `deinit` to free the backing tree.
///
/// Example:
///
///     var s = TreeSet([]const u8).init(allocator, strategy.naturalComparator([]const u8));
///     defer s.deinit();
///     _ = s.add("banana");
///     _ = s.add("apple");
///     _ = s.add("cherry");
///     // Iteration order: "apple", "banana", "cherry".
/// Dynamic (fn-pointer) sorted set — the backward-compatible alias over
/// `TreeSetContext(T, FnPtrContext(T))`. `init` takes a `Comparator(T)` fn
/// pointer as before. For a zero-indirection comparator baked into the type,
/// use `TreeSetContext` with a `ComparatorContext` (see `strategy.zig`).
pub fn TreeSet(comptime T: type) type {
    return TreeSetContext(T, strategy.FnPtrContext(T));
}

/// Sorted set over a comptime comparator `Context`, backed by
/// `TreeMapContext(T, void, Context)`. A stateless context inlines its `cmp`;
/// `TreeSet(T)` is the dynamic fn-pointer specialisation.
pub fn TreeSetContext(comptime T: type, comptime Context: type) type {
    return struct {
        const Self = @This();
        const Map = treemap_mod.TreeMapContext(T, void, Context);

        inner: Map,

        /// Construct over a comparator context value, or — for the `TreeSet`
        /// alias — a bare `Comparator(T)` fn pointer (wrapped automatically).
        /// A stateless context is passed as a typed `Ctx{}` value. Delegates normalisation to
        /// the backing map's `init`.
        pub fn init(allocator: Allocator, ctx_or_cmp: anytype) Self {
            return .{ .inner = Map.init(allocator, ctx_or_cmp) };
        }

        pub fn deinit(self: *Self) void {
            self.inner.deinit();
        }

        /// Add an element. Returns true if it was newly inserted, false if already present.
        pub fn add(self: *Self, value: T) Allocator.Error!bool {
            const old = try self.inner.put(value, {});
            return old == null;
        }

        /// Remove an element. Returns true if it was present.
        pub fn remove(self: *Self, value: T) bool {
            const old = self.inner.remove(value);
            // old is ?void — if non-null, the key was present
            return old != null;
        }

        pub fn contains(self: *const Self, value: T) bool {
            return self.inner.containsKey(value);
        }

        pub fn len(self: *const Self) usize {
            return self.inner.len();
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.inner.isEmpty();
        }

        pub fn clear(self: *Self) void {
            self.inner.clear();
        }

        /// Returns the smallest element.
        pub fn min(self: *const Self) ?T {
            const m = self.inner.min() orelse return null;
            return m.key;
        }

        /// Returns the largest element.
        pub fn max(self: *const Self) ?T {
            const m = self.inner.max() orelse return null;
            return m.key;
        }

        // ---- NavigableSet surface ----
        //
        // Element-form navigation, poll, Range-based slice/descending iteration
        // and removeRange, delegating to the backing `TreeMap`. Mirrors the
        // codex-approved Rust reference (mapdb-rust/src/object/treeset.rs) and
        // the spec (spec/features/navigable-map.md). All comparisons use the
        // set's comparator. Strictness: floor `<= x`, ceiling `>= x`,
        // lower `< x`, higher `> x`. Range membership is `range.contains(x)`.

        /// Greatest element `<= x`, or null.
        pub fn floor(self: *const Self, x: T) ?T {
            return self.inner.floorKey(x);
        }

        /// Least element `>= x`, or null.
        pub fn ceiling(self: *const Self, x: T) ?T {
            return self.inner.ceilingKey(x);
        }

        /// Greatest element `< x` (strict), or null.
        pub fn lower(self: *const Self, x: T) ?T {
            return self.inner.lowerKey(x);
        }

        /// Least element `> x` (strict), or null.
        pub fn higher(self: *const Self, x: T) ?T {
            return self.inner.higherKey(x);
        }

        // ---- Order statistics (rank / select) ----
        //
        // Backed by the subtree-size augmentation on the backing `TreeMap`;
        // both run in O(log n). See `treemap.zig` for the exact semantics.

        /// Returns the number of elements strictly less than `value` under the
        /// set's comparator — the 0-based lower-bound index. Defined for present
        /// and absent elements alike; result in `0..=len()`. Pure query.
        pub fn rank(self: *const Self, value: T) usize {
            return self.inner.rank(value);
        }

        /// Returns the `i`-th smallest element (0-based), or null if
        /// `i >= len()`. `i == len()` (and any larger index, including on an
        /// empty set) is absence, not a trap. Round-trips with `rank`. This is
        /// the ORDER-STATISTIC select — distinct from the functional
        /// `selectWhere(predicate)` filter.
        pub fn select(self: *const Self, i: usize) ?T {
            const e = self.inner.selectEntry(i) orelse return null;
            return e.key;
        }

        /// Minimum element, or null. Alias for `min`.
        pub fn first(self: *const Self) ?T {
            return self.min();
        }

        /// Maximum element, or null. Alias for `max`.
        pub fn last(self: *const Self) ?T {
            return self.max();
        }

        /// Removes and returns the minimum element, or null if empty. Does not
        /// trap on an empty set.
        pub fn pollFirst(self: *Self) ?T {
            const e = self.inner.pollFirstEntry() orelse return null;
            return e.key;
        }

        /// Removes and returns the maximum element, or null if empty. Does not
        /// trap on an empty set.
        pub fn pollLast(self: *Self) ?T {
            const e = self.inner.pollLastEntry() orelse return null;
            return e.key;
        }

        /// Elements ∈ `range`, ascending. Caller owns the slice.
        pub fn rangeElements(self: *const Self, range: Range(T), allocator: Allocator) Allocator.Error![]T {
            return self.inner.rangeKeysIn(range, allocator);
        }

        /// Elements ∈ `range`, descending. Caller owns the slice.
        pub fn descendingRangeElements(self: *const Self, range: Range(T), allocator: Allocator) Allocator.Error![]T {
            return self.inner.descendingRangeKeys(range, allocator);
        }

        /// All elements, descending. Caller owns the slice.
        pub fn descending(self: *const Self, allocator: Allocator) Allocator.Error![]T {
            return self.inner.descendingKeys(allocator);
        }

        /// A new INDEPENDENT set of the elements ∈ `range` (materialized
        /// snapshot — not a live view). PRESERVES the source set's comparator so
        /// reverse/custom/float-total-order ordering is retained. Caller owns
        /// the returned set and must `deinit` it.
        pub fn subSet(self: *const Self, range: Range(T), allocator: Allocator) Allocator.Error!Self {
            // Reconstruct with the same comparator *context* (works for both the
            // dynamic alias and comptime-context sets, unlike `comparator()`).
            var out = Self.init(allocator, self.inner.comparatorContext());
            errdefer out.deinit();
            var it = self.iterator();
            while (it.next()) |x| {
                if (range.contains(x)) _ = try out.add(x);
            }
            return out;
        }

        /// Removes every element ∈ `range`; returns the count removed. A range
        /// that matches nothing is a no-op returning 0.
        pub fn removeRange(self: *Self, range: Range(T), allocator: Allocator) Allocator.Error!usize {
            return self.inner.removeRange(range, allocator);
        }

        pub fn forEach(self: *const Self, context: anytype, comptime f: fn (@TypeOf(context), T) void) void {
            var it = self.iterator();
            while (it.next()) |value| f(context, value);
        }

        /// Pull-based iterator yielding each element by value in ascending
        /// (in-order) sorted order. Non-allocating: delegates to the backing
        /// `TreeMap`'s parent-pointer in-order iterator (no recursion, no heap).
        /// The iterator borrows the set; do not mutate while iterating.
        pub const Iterator = struct {
            inner: Map.Iterator,

            pub fn next(self: *Iterator) ?T {
                const entry = self.inner.next() orelse return null;
                return entry.key;
            }
        };

        /// Returns a pull-based iterator over the elements in ascending sorted
        /// order. Non-allocating.
        ///
        /// No `mutIterator()` is provided for tree sets (deliberate exclusion):
        /// a set element IS its own ordering key, so mutating it in place would
        /// break the sorted-order invariant and corrupt the tree. Remove the old
        /// element and add the new one instead.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .inner = self.inner.iterator() };
        }

        pub fn toSlice(self: *const Self, allocator: Allocator) Allocator.Error![]T {
            return try self.inner.keysToSlice(allocator);
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const strat = @import("strategy.zig");

test "TreeSet basic add/contains" {
    const allocator = std.testing.allocator;
    var set = TreeSet(i32).init(allocator, strat.naturalComparator(i32));
    defer set.deinit();

    try std.testing.expect(try set.add(3));
    try std.testing.expect(try set.add(1));
    try std.testing.expect(try set.add(2));
    try std.testing.expect(!(try set.add(1))); // duplicate

    try std.testing.expectEqual(@as(usize, 3), set.len());
    try std.testing.expect(set.contains(1));
    try std.testing.expect(set.contains(2));
    try std.testing.expect(set.contains(3));
    try std.testing.expect(!set.contains(99));
}

test "TreeSet sorted order via toSlice" {
    const allocator = std.testing.allocator;
    var set = TreeSet(i32).init(allocator, strat.naturalComparator(i32));
    defer set.deinit();

    _ = try set.add(3);
    _ = try set.add(1);
    _ = try set.add(2);

    const slice = try set.toSlice(allocator);
    defer allocator.free(slice);

    try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 2, 3 }, slice);
}

test "TreeSet remove" {
    const allocator = std.testing.allocator;
    var set = TreeSet(i32).init(allocator, strat.naturalComparator(i32));
    defer set.deinit();

    _ = try set.add(1);
    _ = try set.add(2);
    _ = try set.add(3);

    try std.testing.expect(set.remove(2));
    try std.testing.expect(!set.remove(99));
    try std.testing.expectEqual(@as(usize, 2), set.len());
    try std.testing.expect(!set.contains(2));
}

test "TreeSet min/max" {
    const allocator = std.testing.allocator;
    var set = TreeSet(i32).init(allocator, strat.naturalComparator(i32));
    defer set.deinit();

    _ = try set.add(5);
    _ = try set.add(1);
    _ = try set.add(9);

    try std.testing.expectEqual(@as(?i32, 1), set.min());
    try std.testing.expectEqual(@as(?i32, 9), set.max());
}

test "TreeSet clear and isEmpty" {
    const allocator = std.testing.allocator;
    var set = TreeSet(i32).init(allocator, strat.naturalComparator(i32));
    defer set.deinit();

    _ = try set.add(1);
    try std.testing.expect(!set.isEmpty());
    set.clear();
    try std.testing.expect(set.isEmpty());
}

test "TreeSet stress insert 1000 remove half" {
    const allocator = std.testing.allocator;
    var set = TreeSet(i32).init(allocator, strat.naturalComparator(i32));
    defer set.deinit();

    var i: i32 = 0;
    while (i < 1000) : (i += 1) {
        _ = try set.add(i);
    }
    try std.testing.expectEqual(@as(usize, 1000), set.len());

    // Remove even values
    i = 0;
    while (i < 1000) : (i += 2) {
        _ = set.remove(i);
    }
    try std.testing.expectEqual(@as(usize, 500), set.len());

    // Verify remaining are odd and sorted
    const slice = try set.toSlice(allocator);
    defer allocator.free(slice);

    try std.testing.expectEqual(@as(usize, 500), slice.len);
    for (slice, 0..) |v, idx| {
        const expected: i32 = @intCast(idx * 2 + 1);
        try std.testing.expectEqual(expected, v);
    }
}

// ---------------------------------------------------------------------------
// NavigableSet surface (comparator-bearing tree).
// ---------------------------------------------------------------------------

const ObjSetRange = Range(i32);

fn objSetOf(allocator: Allocator, elems: []const i32) !TreeSet(i32) {
    var s = TreeSet(i32).init(allocator, strat.naturalComparator(i32));
    for (elems) |e| _ = try s.add(e);
    return s;
}

test "object.TreeSet nav: floor/ceiling/lower/higher + first/last" {
    const allocator = std.testing.allocator;
    var s = try objSetOf(allocator, &.{ 10, 20, 30 });
    defer s.deinit();
    try std.testing.expectEqual(@as(?i32, 20), s.floor(25));
    try std.testing.expectEqual(@as(?i32, 30), s.ceiling(25));
    try std.testing.expectEqual(@as(?i32, 10), s.floor(10));
    try std.testing.expectEqual(@as(?i32, null), s.lower(10));
    try std.testing.expectEqual(@as(?i32, null), s.higher(30));
    try std.testing.expectEqual(@as(?i32, 10), s.ceiling(5));
    try std.testing.expectEqual(@as(?i32, 10), s.first());
    try std.testing.expectEqual(@as(?i32, 30), s.last());
}

test "object.TreeSet poll: first/last then empty" {
    const allocator = std.testing.allocator;
    var s = try objSetOf(allocator, &.{ 10, 20, 30 });
    defer s.deinit();
    try std.testing.expectEqual(@as(?i32, 10), s.pollFirst());
    try std.testing.expectEqual(@as(?i32, 30), s.pollLast());
    try std.testing.expectEqual(@as(?i32, 20), s.pollFirst());
    try std.testing.expectEqual(@as(?i32, null), s.pollFirst());
    try std.testing.expectEqual(@as(?i32, null), s.pollLast());
}

test "object.TreeSet range/removeRange + descending" {
    const allocator = std.testing.allocator;
    var s = try objSetOf(allocator, &.{ 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 });
    defer s.deinit();
    const re = try s.rangeElements(ObjSetRange.closedOpen(30, 70), allocator);
    defer allocator.free(re);
    try std.testing.expectEqualSlices(i32, &.{ 30, 40, 50, 60 }, re);
    const desc = try s.descending(allocator);
    defer allocator.free(desc);
    try std.testing.expectEqualSlices(i32, &.{ 100, 90, 80, 70, 60, 50, 40, 30, 20, 10 }, desc);
    try std.testing.expectEqual(@as(usize, 4), try s.removeRange(ObjSetRange.closedOpen(30, 70), allocator));
    try std.testing.expectEqual(@as(usize, 0), try s.removeRange(ObjSetRange.closedOpen(30, 70), allocator));
}

test "object.TreeSet subSet: preserves reverse comparator + snapshot independence" {
    const allocator = std.testing.allocator;
    var s = TreeSet(i32).init(allocator, strat.reverseComparator(i32));
    defer s.deinit();
    for ([_]i32{ 10, 20, 30, 40, 50 }) |k| _ = try s.add(k);
    const src = try s.toSlice(allocator);
    defer allocator.free(src);
    try std.testing.expectEqualSlices(i32, &.{ 50, 40, 30, 20, 10 }, src);
    // The snapshot must also be reverse-ordered, proving comparator carried.
    var sub = try s.subSet(ObjSetRange.closedOpen(20, 50), allocator);
    defer sub.deinit();
    const sub_v = try sub.toSlice(allocator);
    defer allocator.free(sub_v);
    try std.testing.expectEqualSlices(i32, &.{ 40, 30, 20 }, sub_v);
    // Independence both directions.
    _ = try sub.add(99);
    _ = sub.remove(20);
    try std.testing.expect(s.contains(20));
    try std.testing.expect(!s.contains(99));
    _ = s.remove(30);
    try std.testing.expect(sub.contains(30));
}

// ---------------------------------------------------------------------------
// Order statistics (rank / select).
// ---------------------------------------------------------------------------

test "object.TreeSet rank/select: present, absent, signed, round-trip" {
    const allocator = std.testing.allocator;
    var s = try objSetOf(allocator, &.{ 10, 20, 30, 40, 50 });
    defer s.deinit();
    try std.testing.expectEqual(@as(usize, 0), s.rank(10));
    try std.testing.expectEqual(@as(usize, 2), s.rank(30));
    try std.testing.expectEqual(@as(usize, 4), s.rank(50));
    try std.testing.expectEqual(@as(usize, 0), s.rank(5));
    try std.testing.expectEqual(@as(usize, 2), s.rank(25));
    try std.testing.expectEqual(@as(usize, 5), s.rank(55));
    try std.testing.expectEqual(@as(?i32, 10), s.select(0));
    try std.testing.expectEqual(@as(?i32, 30), s.select(2));
    try std.testing.expectEqual(@as(?i32, 50), s.select(4));
    try std.testing.expectEqual(@as(?i32, null), s.select(5));
    // round-trip
    var i: usize = 0;
    while (i < s.len()) : (i += 1) {
        const v = s.select(i).?;
        try std.testing.expectEqual(i, s.rank(v));
    }
}

test "object.TreeSet rank/select: empty and single" {
    const allocator = std.testing.allocator;
    var empty = try objSetOf(allocator, &.{});
    defer empty.deinit();
    try std.testing.expectEqual(@as(usize, 0), empty.rank(5));
    try std.testing.expectEqual(@as(?i32, null), empty.select(0));

    var single = try objSetOf(allocator, &.{});
    defer single.deinit();
    _ = try single.add(7);
    try std.testing.expectEqual(@as(usize, 0), single.rank(6));
    try std.testing.expectEqual(@as(usize, 0), single.rank(7));
    try std.testing.expectEqual(@as(usize, 1), single.rank(8));
    try std.testing.expectEqual(@as(?i32, 7), single.select(0));
    try std.testing.expectEqual(@as(?i32, null), single.select(1));
}

// ── Step 2: comptime comparator context tests ───────────────────────────────

test "TreeSetContext: stateless context matches dynamic alias; zero-sized" {
    const a = std.testing.allocator;
    const Ctx = strat.ComparatorContext(i32, strat.naturalComparator(i32));
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(Ctx));
    var s = TreeSetContext(i32, Ctx).init(a, Ctx{});
    defer s.deinit();
    for ([_]i32{ 5, 1, 4, 2, 3 }) |v| _ = try s.add(v);
    try std.testing.expectEqual(@as(usize, 5), s.len());
    try std.testing.expect(s.contains(3) and !s.contains(9));
    try std.testing.expectEqual(@as(?i32, 1), s.first());
    try std.testing.expectEqual(@as(?i32, 5), s.last());
    // The comptime-context set is smaller than the fn-pointer alias.
    try std.testing.expect(@sizeOf(TreeSetContext(i32, Ctx)) < @sizeOf(TreeSet(i32)));
}

test "TreeSet dynamic alias still takes a bare fn pointer (reverse order)" {
    const a = std.testing.allocator;
    var s = TreeSet(i32).init(a, strat.reverseComparator(i32));
    defer s.deinit();
    for ([_]i32{ 1, 2, 3 }) |v| _ = try s.add(v);
    try std.testing.expectEqual(@as(?i32, 3), s.first()); // reverse: largest first
    try std.testing.expectEqual(@as(?i32, 1), s.last());
}
