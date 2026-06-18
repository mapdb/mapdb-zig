// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Generic sorted set. Single source for the 8 `<T>TreeSet` per-type wrappers.
//!
//! Backed by `std.Treap(T, orderFn)` for O(log n) insert/remove/lookup. The
//! key ordering is type-dependent (preserved from the per-type wrappers):
//!   * `f32`/`f64`: IEEE 754 totalOrder — see src/float_order.zig.
//!   * `bool`: explicit three-way (`false` < `true`).
//!   * everything else (int / `u21` char): `std.math.order`.
//! `eql` compares float elements by exact bits (NaN-aware, signed-zero distinct).

const std = @import("std");
const Allocator = std.mem.Allocator;
const float_order = @import("../float_order.zig");
const Range = @import("../range.zig").Range;

/// Total-ordering comparator for elements of type `T`.
fn keyOrder(comptime T: type, a: T, b: T) std.math.Order {
    return switch (@typeInfo(T)) {
        .float => switch (T) {
            f32 => float_order.totalCmpF32(a, b),
            f64 => float_order.totalCmpF64(a, b),
            else => @compileError("unsupported float key type: " ++ @typeName(T)),
        },
        .bool => if (a == b) std.math.Order.eq else if (!a and b) std.math.Order.lt else std.math.Order.gt,
        else => std.math.order(a, b),
    };
}

/// Bit-aware equality for floats; plain `==` otherwise.
fn elemEql(comptime T: type, a: T, b: T) bool {
    if (@typeInfo(T) == .float) {
        const Bits = std.meta.Int(.unsigned, @bitSizeOf(T));
        return @as(Bits, @bitCast(a)) == @as(Bits, @bitCast(b));
    }
    return a == b;
}

/// Sorted set of unique `T` values, backed by `std.Treap` for
/// O(log n) insert, remove, and lookup.
pub fn TreeSet(comptime T: type) type {
    return struct {
        fn orderFn(a: T, b: T) std.math.Order {
            return keyOrder(T, a, b);
        }

        const TreapType = std.Treap(T, orderFn);

        treap: TreapType = .{},
        allocator: Allocator,
        node_count: usize = 0,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            destroySubtree(self.treap.root, self.allocator);
        }

        fn destroySubtree(node_opt: ?*TreapType.Node, allocator: Allocator) void {
            const node = node_opt orelse return;
            destroySubtree(node.children[0], allocator);
            destroySubtree(node.children[1], allocator);
            allocator.destroy(node);
        }

        pub fn of(allocator: Allocator, values: []const T) Allocator.Error!Self {
            var set = init(allocator);
            for (values) |val| {
                _ = try set.add(val);
            }
            return set;
        }

        /// Adds a value. Returns true if it was not already present.
        pub fn add(self: *Self, value: T) Allocator.Error!bool {
            var entry = self.treap.getEntryFor(value);
            if (entry.node != null) return false;
            const node = try self.allocator.create(TreapType.Node);
            entry.set(node);
            self.node_count += 1;
            return true;
        }

        /// Removes a value. Returns true if it was present.
        pub fn remove(self: *Self, value: T) bool {
            var entry = self.treap.getEntryFor(value);
            const node = entry.node orelse return false;
            entry.set(null);
            self.allocator.destroy(node);
            self.node_count -= 1;
            return true;
        }

        pub fn contains(self: *const Self, value: T) bool {
            var node = self.treap.root;
            while (node) |current| {
                const ord = orderFn(value, current.key);
                if (ord == .eq) return true;
                node = current.children[@intFromBool(ord == .gt)];
            }
            return false;
        }

        pub fn len(self: *const Self) usize {
            return self.node_count;
        }

        /// Alias for len() — matches Go/Java naming.
        pub fn size(self: *const Self) usize {
            return self.node_count;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.node_count == 0;
        }

        pub fn clear(self: *Self) void {
            destroySubtree(self.treap.root, self.allocator);
            self.treap.root = null;
            self.node_count = 0;
        }

        // ---- Fallible capacity reservation ----

        /// Probes that the allocator can serve `additional` node allocations.
        /// Returns `error.OutOfMemory` if the allocator fails.
        pub fn ensureUnusedCapacity(self: *Self, additional: usize) Allocator.Error!void {
            const probe = try self.allocator.alloc(TreapType.Node, additional);
            self.allocator.free(probe);
        }

        /// Probes that the allocator can serve enough nodes for `new_capacity`
        /// total elements.
        pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) Allocator.Error!void {
            if (new_capacity <= self.node_count) return;
            try self.ensureUnusedCapacity(new_capacity - self.node_count);
        }

        pub fn min(self: *const Self) ?T {
            const node = self.treap.getMin() orelse return null;
            return node.key;
        }

        pub fn max(self: *const Self) ?T {
            const node = self.treap.getMax() orelse return null;
            return node.key;
        }

        /// Returns all values in sorted order. Caller must free the returned slice.
        pub fn toSlice(self: *const Self, allocator: Allocator) Allocator.Error![]T {
            var result = std.ArrayListUnmanaged(T){};
            try result.ensureTotalCapacity(allocator, self.node_count);
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                result.appendAssumeCapacity(node.key);
            }
            return result.toOwnedSlice(allocator);
        }

        // ---- Iteration ----

        /// Pull-based iterator yielding each element by value in ascending
        /// (in-order) sorted order. Non-allocating: wraps the treap's
        /// `InorderIterator`, which threads the tree via node child pointers with
        /// no heap allocation. The iterator borrows the set; do not mutate while iterating.
        pub const Iterator = struct {
            inner: TreapType.InorderIterator,

            pub fn next(self: *Iterator) ?T {
                const node = self.inner.next() orelse return null;
                return node.key;
            }
        };

        /// Returns a pull-based iterator over the elements in ascending sorted
        /// order. Non-allocating.
        ///
        /// No `mutIterator()` is provided for tree sets (deliberate exclusion):
        /// a set element IS its own ordering key, so mutating an element in
        /// place would break the sorted-order invariant and corrupt the tree.
        /// Remove the old element and add the new one instead.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .inner = TreapType.InorderIterator{ .current = self.treap.getMin() } };
        }

        // ---- Functional Operations ----

        /// Functional FILTER convenience: a new set of the elements matching
        /// `predicate`. Named `selectWhere` (not `select`) because the bare
        /// `select` name is reserved for the order-statistic select (i-th
        /// smallest by 0-based rank); see `select` below and
        /// `spec/features/rank-select.md`. The statically-typed ports cannot
        /// host both a predicate `select` and the order-statistic `select`.
        pub fn selectWhere(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) Allocator.Error!Self {
            var result = init(self.allocator);
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (predicate(ctx, node.key)) _ = try result.add(node.key);
            }
            return result;
        }

        pub fn reject(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) Allocator.Error!Self {
            var result = init(self.allocator);
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (!predicate(ctx, node.key)) _ = try result.add(node.key);
            }
            return result;
        }

        pub fn detect(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) ?T {
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (predicate(ctx, node.key)) return node.key;
            }
            return null;
        }

        pub fn anySatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) bool {
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (predicate(ctx, node.key)) return true;
            }
            return false;
        }

        pub fn allSatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) bool {
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (!predicate(ctx, node.key)) return false;
            }
            return true;
        }

        pub fn noneSatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) bool {
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (predicate(ctx, node.key)) return false;
            }
            return true;
        }

        pub fn count(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) usize {
            var c: usize = 0;
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (predicate(ctx, node.key)) c += 1;
            }
            return c;
        }

        // ---- Set Operations ----

        pub fn setUnion(self: *const Self, other: *const Self) Allocator.Error!Self {
            var result = init(self.allocator);
            var it1 = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it1.next()) |node| _ = try result.add(node.key);
            var it2 = TreapType.InorderIterator{ .current = other.treap.getMin() };
            while (it2.next()) |node| _ = try result.add(node.key);
            return result;
        }

        pub fn intersect(self: *const Self, other: *const Self) Allocator.Error!Self {
            var result = init(self.allocator);
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (other.contains(node.key)) _ = try result.add(node.key);
            }
            return result;
        }

        pub fn difference(self: *const Self, other: *const Self) Allocator.Error!Self {
            var result = init(self.allocator);
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (!other.contains(node.key)) _ = try result.add(node.key);
            }
            return result;
        }

        // ---- Range Operations ----

        /// Returns the node for the smallest element >= value, or null.
        fn ceilingNode(self: *const Self, value: T) ?*TreapType.Node {
            var node = self.treap.root;
            var best: ?*TreapType.Node = null;
            while (node) |current| {
                const ord = orderFn(value, current.key);
                if (ord == .eq) return current;
                if (ord == .lt) {
                    best = current;
                    node = current.children[0];
                } else {
                    node = current.children[1];
                }
            }
            return best;
        }

        /// Returns the smallest element >= value, or null if none.
        pub fn ceiling(self: *const Self, value: T) ?T {
            const node = self.ceilingNode(value) orelse return null;
            return node.key;
        }

        /// Returns the largest element <= value, or null if none.
        pub fn floor(self: *const Self, value: T) ?T {
            var node = self.treap.root;
            var best: ?T = null;
            while (node) |current| {
                const ord = orderFn(value, current.key);
                if (ord == .eq) return current.key;
                if (ord == .gt) {
                    best = current.key;
                    node = current.children[1];
                } else {
                    node = current.children[0];
                }
            }
            return best;
        }

        /// Returns all elements in [from, to] inclusive. Caller must free.
        pub fn rangeValues(self: *const Self, from: T, to: T, allocator: Allocator) Allocator.Error![]T {
            var result = std.ArrayListUnmanaged(T){};
            var it = TreapType.InorderIterator{ .current = self.ceilingNode(from) };
            while (it.next()) |node| {
                if (orderFn(node.key, to) == .gt) break;
                try result.append(allocator, node.key);
            }
            return result.toOwnedSlice(allocator);
        }

        // ---- NavigableSet surface ----
        //
        // Element-form navigation, poll, Range-based slice/descending iteration
        // and removeRange. Mirrors the codex-approved Rust reference
        // (mapdb-rust/src/object/treeset.rs) and the spec
        // (spec/features/navigable-map.md). Strictness: floor `<= x`,
        // ceiling `>= x`, lower `< x` (strict), higher `> x` (strict). Range
        // membership is EXACTLY `range.contains(x)` — `open(1, 2)` over i32
        // matches NOTHING yet is a valid, non-cut-empty range.
        //
        // `floor`/`ceiling` already exist above (value form, == the spec's set
        // analogue); `lower`/`higher`/`first`/`last` complete the surface.

        /// Greatest element `< x` (strict), or null.
        pub fn lower(self: *const Self, x: T) ?T {
            var node = self.treap.root;
            var best: ?T = null;
            while (node) |current| {
                // current.key < x : candidate, search right for a tighter one.
                if (orderFn(current.key, x) == .lt) {
                    best = current.key;
                    node = current.children[1];
                } else {
                    node = current.children[0];
                }
            }
            return best;
        }

        /// Least element `> x` (strict), or null.
        pub fn higher(self: *const Self, x: T) ?T {
            var node = self.treap.root;
            var best: ?T = null;
            while (node) |current| {
                // current.key > x : candidate, search left for a tighter one.
                if (orderFn(current.key, x) == .gt) {
                    best = current.key;
                    node = current.children[0];
                } else {
                    node = current.children[1];
                }
            }
            return best;
        }

        // ---- Order statistics (rank / select) ----
        //
        // This generic set is backed by `std.Treap`, whose `Node` carries no
        // subtree-size augmentation and whose rotations are internal (not
        // interceptable), so the size field cannot be threaded here. The
        // order-statistic forms are therefore computed by a BST descent (rank)
        // and an in-order index walk (select) over the treap's child links.
        // Observable results match the augmented comparator-bearing object-tree
        // variant (`object/treeset.zig`), which carries the O(log n) subtree-size
        // augmentation and the size-invariant native test; only the per-port
        // complexity guarantee differs (correctness is the cross-language
        // contract). See `spec/features/rank-select.md`.

        /// Counts every key in the subtree rooted at `node`.
        fn subtreeCount(node: ?*TreapType.Node) usize {
            const n = node orelse return 0;
            return 1 + subtreeCount(n.children[0]) + subtreeCount(n.children[1]);
        }

        /// Returns the number of elements strictly less than `value` under the
        /// set's ordering — the 0-based lower-bound index. Defined for present
        /// and absent elements alike; result in `0..=len()`. Pure query.
        pub fn rank(self: *const Self, value: T) usize {
            var r: usize = 0;
            var node = self.treap.root;
            while (node) |n| {
                switch (orderFn(value, n.key)) {
                    // value < n.key: n and its right subtree are >= value.
                    .lt => node = n.children[0],
                    // value > n.key: n and its whole left subtree are < value.
                    .gt => {
                        r += 1 + subtreeCount(n.children[0]);
                        node = n.children[1];
                    },
                    // value == n.key: exactly the left subtree is strictly less.
                    .eq => return r + subtreeCount(n.children[0]),
                }
            }
            return r;
        }

        /// Returns the `i`-th smallest element (0-based), or null if
        /// `i >= len()`. `i == len()` (and any larger index, including on an
        /// empty set) is absence, not a trap. Round-trips with `rank`. This is
        /// the ORDER-STATISTIC select — distinct from the functional
        /// `selectWhere(predicate)` filter.
        pub fn select(self: *const Self, i: usize) ?T {
            if (i >= self.node_count) return null;
            var remaining = i;
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (remaining == 0) return node.key;
                remaining -= 1;
            }
            return null;
        }

        /// Minimum element, or null. Alias for `min` completing the surface.
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
            const v = self.min() orelse return null;
            _ = self.remove(v);
            return v;
        }

        /// Removes and returns the maximum element, or null if empty. Does not
        /// trap on an empty set.
        pub fn pollLast(self: *Self) ?T {
            const v = self.max() orelse return null;
            _ = self.remove(v);
            return v;
        }

        /// Elements ∈ `range`, ascending. Caller owns the returned slice
        /// (independent snapshot; not invalidated by later mutation).
        pub fn rangeElements(self: *const Self, range: Range(T), allocator: Allocator) Allocator.Error![]T {
            var result = std.ArrayListUnmanaged(T){};
            errdefer result.deinit(allocator);
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (range.contains(node.key)) try result.append(allocator, node.key);
            }
            return result.toOwnedSlice(allocator);
        }

        /// Elements ∈ `range`, descending. Caller owns the slice.
        pub fn descendingRangeElements(self: *const Self, range: Range(T), allocator: Allocator) Allocator.Error![]T {
            const asc = try self.rangeElements(range, allocator);
            std.mem.reverse(T, asc);
            return asc;
        }

        /// All elements, descending. Caller owns the slice.
        pub fn descending(self: *const Self, allocator: Allocator) Allocator.Error![]T {
            const out = try allocator.alloc(T, self.node_count);
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            var i: usize = self.node_count;
            while (it.next()) |node| {
                i -= 1;
                out[i] = node.key;
            }
            return out;
        }

        /// A new INDEPENDENT set of the elements ∈ `range` (materialized
        /// snapshot — not a live view). Mutating the snapshot never affects the
        /// original and vice versa. The snapshot uses the same fixed ordering as
        /// the source (this generic tree is always natural / float-total order;
        /// comparator-keyed ordering is preserved by the object-tree variant).
        /// The caller owns the returned set and must `deinit` it.
        pub fn subSet(self: *const Self, range: Range(T), allocator: Allocator) Allocator.Error!Self {
            var out = init(allocator);
            errdefer out.deinit();
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (range.contains(node.key)) _ = try out.add(node.key);
            }
            return out;
        }

        /// Removes every element ∈ `range`; returns the count removed. A range
        /// that matches nothing is a no-op returning 0.
        pub fn removeRange(self: *Self, range: Range(T)) Allocator.Error!usize {
            // Collect victims first (the treap iterator must not see structural
            // mutation), then remove them.
            var victims = std.ArrayListUnmanaged(T){};
            defer victims.deinit(self.allocator);
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (range.contains(node.key)) try victims.append(self.allocator, node.key);
            }
            for (victims.items) |v| _ = self.remove(v);
            return victims.items.len;
        }

        // ---- Formatting ----

        /// Formats as "{v1, v2, v3}" in sorted order.
        pub fn format(self: *const Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.writeAll("{");
            var is_first = true;
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (!is_first) try writer.writeAll(", ");
                try writer.print("{any}", .{node.key});
                is_first = false;
            }
            try writer.writeAll("}");
        }

        // ---- Fluent API ----

        pub fn with(self: *Self, value: T) Allocator.Error!*Self {
            _ = try self.add(value);
            return self;
        }

        pub fn without(self: *Self, value: T) *Self {
            _ = self.remove(value);
            return self;
        }

        // ---- Equality ----

        pub fn eql(self: *const Self, other: *const Self) bool {
            if (self.node_count != other.node_count) return false;
            var it1 = TreapType.InorderIterator{ .current = self.treap.getMin() };
            var it2 = TreapType.InorderIterator{ .current = other.treap.getMin() };
            while (it1.next()) |n1| {
                const n2 = it2.next() orelse return false;
                if (!elemEql(T, n1.key, n2.key)) return false;
            }
            return true;
        }
    };
}

// ---------------------------------------------------------------------------
// NavigableSet surface tests (mirror mapdb-rust/src/object/treeset.rs).
// ---------------------------------------------------------------------------

const Range_i32 = Range(i32);

fn setOf(allocator: Allocator, elems: []const i32) !TreeSet(i32) {
    var s = TreeSet(i32).init(allocator);
    for (elems) |e| _ = try s.add(e);
    return s;
}

test "TreeSet nav: floor/ceiling/lower/higher strictness + first/last" {
    var s = try setOf(std.testing.allocator, &.{ 10, 20, 30 });
    defer s.deinit();
    try std.testing.expectEqual(@as(?i32, 20), s.floor(25));
    try std.testing.expectEqual(@as(?i32, 30), s.ceiling(25));
    try std.testing.expectEqual(@as(?i32, 10), s.floor(10)); // inclusive
    try std.testing.expectEqual(@as(?i32, null), s.lower(10)); // strict
    try std.testing.expectEqual(@as(?i32, null), s.higher(30)); // strict
    try std.testing.expectEqual(@as(?i32, 10), s.ceiling(5));
    try std.testing.expectEqual(@as(?i32, 20), s.lower(25));
    try std.testing.expectEqual(@as(?i32, 30), s.higher(25));
    try std.testing.expectEqual(@as(?i32, 10), s.first());
    try std.testing.expectEqual(@as(?i32, 30), s.last());
}

test "TreeSet nav: empty set returns absence" {
    var s = try setOf(std.testing.allocator, &.{});
    defer s.deinit();
    try std.testing.expectEqual(@as(?i32, null), s.floor(5));
    try std.testing.expectEqual(@as(?i32, null), s.ceiling(5));
    try std.testing.expectEqual(@as(?i32, null), s.lower(5));
    try std.testing.expectEqual(@as(?i32, null), s.higher(5));
    try std.testing.expectEqual(@as(?i32, null), s.first());
    try std.testing.expectEqual(@as(?i32, null), s.last());
}

test "TreeSet nav: signed i32 MIN/MAX + descending" {
    var s = try setOf(std.testing.allocator, &.{ std.math.minInt(i32), -1, 0, 1, std.math.maxInt(i32) });
    defer s.deinit();
    try std.testing.expectEqual(@as(?i32, std.math.minInt(i32)), s.floor(std.math.minInt(i32)));
    try std.testing.expectEqual(@as(?i32, null), s.lower(std.math.minInt(i32)));
    try std.testing.expectEqual(@as(?i32, 0), s.higher(-1));
    try std.testing.expectEqual(@as(?i32, std.math.maxInt(i32)), s.ceiling(std.math.maxInt(i32)));
    try std.testing.expectEqual(@as(?i32, null), s.higher(std.math.maxInt(i32)));
    const desc = try s.descending(std.testing.allocator);
    defer std.testing.allocator.free(desc);
    try std.testing.expectEqualSlices(i32, &.{ std.math.maxInt(i32), 1, 0, -1, std.math.minInt(i32) }, desc);
}

test "TreeSet poll: first/last then empty (does not trap)" {
    var s = try setOf(std.testing.allocator, &.{ 10, 20, 30 });
    defer s.deinit();
    try std.testing.expectEqual(@as(?i32, 10), s.pollFirst());
    try std.testing.expectEqual(@as(?i32, 30), s.pollLast());
    try std.testing.expectEqual(@as(?i32, 20), s.pollFirst());
    try std.testing.expectEqual(@as(?i32, null), s.pollFirst());
    try std.testing.expectEqual(@as(?i32, null), s.pollLast());
}

test "TreeSet poll: single element then empty" {
    var s = try setOf(std.testing.allocator, &.{});
    defer s.deinit();
    _ = try s.add(7);
    try std.testing.expectEqual(@as(?i32, 7), s.pollFirst());
    try std.testing.expectEqual(@as(?i32, null), s.pollFirst());
    try std.testing.expect(s.isEmpty());
}

test "TreeSet range + descending + open(1,2) empty" {
    var s = try setOf(std.testing.allocator, &.{ 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 });
    defer s.deinit();
    const re = try s.rangeElements(Range_i32.closedOpen(30, 70), std.testing.allocator);
    defer std.testing.allocator.free(re);
    try std.testing.expectEqualSlices(i32, &.{ 30, 40, 50, 60 }, re);
    const red = try s.descendingRangeElements(Range_i32.closedOpen(30, 70), std.testing.allocator);
    defer std.testing.allocator.free(red);
    try std.testing.expectEqualSlices(i32, &.{ 60, 50, 40, 30 }, red);
    const oc = try s.rangeElements(Range_i32.openClosed(30, 70), std.testing.allocator);
    defer std.testing.allocator.free(oc);
    try std.testing.expectEqualSlices(i32, &.{ 40, 50, 60, 70 }, oc);

    var s2 = try setOf(std.testing.allocator, &.{ 1, 2 });
    defer s2.deinit();
    const empty = try s2.rangeElements(Range_i32.open(1, 2), std.testing.allocator);
    defer std.testing.allocator.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
}

test "TreeSet removeRange: count + no-op repeat" {
    var s = try setOf(std.testing.allocator, &.{ 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 });
    defer s.deinit();
    try std.testing.expectEqual(@as(usize, 4), try s.removeRange(Range_i32.closedOpen(30, 70)));
    try std.testing.expectEqual(@as(usize, 0), try s.removeRange(Range_i32.closedOpen(30, 70)));
    const v = try s.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(v);
    try std.testing.expectEqualSlices(i32, &.{ 10, 20, 70, 80, 90, 100 }, v);
}

test "TreeSet subSet: independent materialized snapshot" {
    var s = try setOf(std.testing.allocator, &.{ 10, 20, 30, 40, 50 });
    defer s.deinit();
    var snap = try s.subSet(Range_i32.closed(20, 40), std.testing.allocator);
    defer snap.deinit();
    const sv = try snap.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(sv);
    try std.testing.expectEqualSlices(i32, &.{ 20, 30, 40 }, sv);
    // Mutate snapshot — original unchanged.
    _ = try snap.add(99);
    _ = snap.remove(20);
    try std.testing.expect(s.contains(20));
    try std.testing.expect(!s.contains(99));
    // Mutate original — snapshot unchanged.
    _ = s.remove(30);
    try std.testing.expect(snap.contains(30));
}

test "TreeSet rank/select: present, absent, signed, round-trip" {
    var s = try setOf(std.testing.allocator, &.{ 10, 20, 30, 40, 50 });
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
    var i: usize = 0;
    while (i < s.len()) : (i += 1) {
        const v = s.select(i).?;
        try std.testing.expectEqual(i, s.rank(v));
    }
}

test "TreeSet rank/select: empty, single, signed extremes" {
    var empty = try setOf(std.testing.allocator, &.{});
    defer empty.deinit();
    try std.testing.expectEqual(@as(usize, 0), empty.rank(5));
    try std.testing.expectEqual(@as(?i32, null), empty.select(0));

    var single = try setOf(std.testing.allocator, &.{});
    defer single.deinit();
    _ = try single.add(7);
    try std.testing.expectEqual(@as(usize, 0), single.rank(6));
    try std.testing.expectEqual(@as(usize, 0), single.rank(7));
    try std.testing.expectEqual(@as(usize, 1), single.rank(8));
    try std.testing.expectEqual(@as(?i32, 7), single.select(0));
    try std.testing.expectEqual(@as(?i32, null), single.select(1));

    var ext = try setOf(std.testing.allocator, &.{ std.math.minInt(i32), -1, 0, 1, std.math.maxInt(i32) });
    defer ext.deinit();
    try std.testing.expectEqual(@as(usize, 0), ext.rank(std.math.minInt(i32)));
    try std.testing.expectEqual(@as(usize, 2), ext.rank(0));
    try std.testing.expectEqual(@as(usize, 4), ext.rank(std.math.maxInt(i32)));
    try std.testing.expectEqual(@as(?i32, std.math.minInt(i32)), ext.select(0));
    try std.testing.expectEqual(@as(?i32, std.math.maxInt(i32)), ext.select(4));
    try std.testing.expectEqual(@as(?i32, null), ext.select(5));
}
