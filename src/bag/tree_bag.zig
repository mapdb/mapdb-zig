// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Generic sorted bag (multiset) with occurrence counting. Single source for
//! the 8 `<T>TreeBag` per-type wrappers.
//!
//! Backed by `std.Treap(T, orderFn)` with an intrusive occurrence count per
//! node. The key ordering is type-dependent (preserved from the per-type
//! wrappers):
//!   * `f32`/`f64`: IEEE 754 totalOrder — see src/float_order.zig.
//!   * `bool`: explicit three-way (`false` < `true`).
//!   * everything else (int / `u21` char): `std.math.order`.
//! `eql` compares float elements by exact bits (NaN-aware, signed-zero distinct).

const std = @import("std");
const Allocator = std.mem.Allocator;
const float_order = @import("../float_order.zig");
const pump = @import("../pump.zig");

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

/// Sorted bag (multiset) of `T` values with occurrence counting.
///
/// Backed by `std.Treap` for O(log n) insert, remove, and lookup.
/// Each tree node carries an occurrence count via the intrusive
/// `BagNode` wrapper around `TreapType.Node`.
pub fn TreeBag(comptime T: type) type {
    return struct {
        fn orderFn(a: T, b: T) std.math.Order {
            return keyOrder(T, a, b);
        }

        const TreapType = std.Treap(T, orderFn);

        /// Intrusive node: embeds the Treap node and adds an occurrence count.
        const BagNode = struct {
            treap_node: TreapType.Node,
            occ: usize,
        };

        fn bagNodeFromTreapNode(treap_node: *TreapType.Node) *BagNode {
            return @fieldParentPtr("treap_node", treap_node);
        }

        treap: TreapType = .{},
        allocator: Allocator,
        total_size: usize = 0,
        distinct_count: usize = 0,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            destroySubtree(self.treap.root, self.allocator);
        }

        fn destroySubtree(root_node: ?*TreapType.Node, allocator: Allocator) void {
            // Iterative teardown (no recursion): treap depth is only *expected*
            // O(log n), so recursion risks a stack overflow on a large set.
            // Right-rotate the left child to the root until the root has no left
            // child, peel it, descend right. O(n) time, O(1) stack (each edge
            // rotated at most once). Traversal uses the intrusive treap links;
            // the freed allocation is the wrapping bag node.
            var root = root_node;
            while (root) |node| {
                if (node.children[0]) |left| {
                    node.children[0] = left.children[1];
                    left.children[1] = node;
                    root = left;
                } else {
                    root = node.children[1];
                    allocator.destroy(bagNodeFromTreapNode(node));
                }
            }
        }

        // ---- Data pump (bulk import) ----

        /// Effective error set of every pump entry point on this bag. Bags count
        /// duplicates rather than rejecting them, so there is no `DuplicateKey`;
        /// `CountOverflow` guards count accumulation, `NotSorted` guards the
        /// ascending-input contract.
        pub const BulkError = (error{ NotSorted, CountOverflow } || Allocator.Error);

        /// Bulk-loads a fresh `TreeBag` from a presorted (ascending, with equal
        /// runs allowed) flat value slice. A run of equal consecutive values
        /// becomes one entry with `count = run length`; a strictly-decreasing
        /// step is `error.NotSorted`. Count accumulation is overflow-checked.
        ///
        /// **Complexity carve-out (per the spec):** treap-backed, so each
        /// distinct value still pays an O(log d) treap insertion → O(n + d log d)
        /// where d is the distinct count, NOT O(n). Behaviourally identical to
        /// the same values added one-by-one. On any error nothing leaks.
        pub fn fromSorted(allocator: Allocator, values: []const T) BulkError!Self {
            var self = init(allocator);
            errdefer self.deinit();
            // One allocator warm-up sized for the worst case (all distinct).
            try self.ensureUnusedCapacity(values.len);
            var i: usize = 0;
            while (i < values.len) {
                const v = values[i];
                var run: usize = 1;
                var j = i + 1;
                while (j < values.len and orderFn(values[j], v) == .eq) : (j += 1) {
                    if (run == std.math.maxInt(usize)) return error.CountOverflow;
                    run += 1;
                }
                // Boundary between runs must be strictly ascending.
                if (j < values.len and orderFn(v, values[j]) != .lt) return error.NotSorted;
                if (self.total_size > std.math.maxInt(usize) - run) return error.CountOverflow;
                try self.addOccurrences(v, run);
                i = j;
            }
            return self;
        }

        /// Bulk-loads a fresh `TreeBag` from presorted parallel (value, count)
        /// slices (values strictly ascending). A descending/equal value step is
        /// `error.NotSorted`; count accumulation is overflow-checked. Same
        /// O(n + d log d) carve-out as `fromSorted`. On any error nothing leaks.
        pub fn fromSortedCounts(allocator: Allocator, values: []const T, counts: []const usize) BulkError!Self {
            std.debug.assert(values.len == counts.len);
            var self = init(allocator);
            errdefer self.deinit();
            try self.ensureUnusedCapacity(values.len);
            for (values, counts, 0..) |v, c, idx| {
                if (idx > 0 and orderFn(values[idx - 1], v) != .lt) return error.NotSorted;
                if (c == 0) continue;
                if (self.total_size > std.math.maxInt(usize) - c) return error.CountOverflow;
                try self.addOccurrences(v, c);
            }
            return self;
        }

        fn addOccurrences(self: *Self, value: T, occ: usize) Allocator.Error!void {
            var entry = self.treap.getEntryFor(value);
            if (entry.node) |treap_node| {
                bagNodeFromTreapNode(treap_node).occ += occ;
            } else {
                const bag_node = try self.allocator.create(BagNode);
                bag_node.occ = occ;
                entry.set(&bag_node.treap_node);
                self.distinct_count += 1;
            }
            self.total_size += occ;
        }

        /// Add one occurrence of the value.
        pub fn add(self: *Self, value: T) Allocator.Error!void {
            try self.addOccurrences(value, 1);
        }

        /// Remove one occurrence. Returns true if the value was present.
        pub fn remove(self: *Self, value: T) bool {
            var entry = self.treap.getEntryFor(value);
            const treap_node = entry.node orelse return false;
            const bag_node = bagNodeFromTreapNode(treap_node);
            bag_node.occ -= 1;
            if (bag_node.occ == 0) {
                entry.set(null);
                self.allocator.destroy(bag_node);
                self.distinct_count -= 1;
            }
            self.total_size -= 1;
            return true;
        }

        /// Remove all occurrences of the value. Returns true if present.
        pub fn removeAll(self: *Self, value: T) bool {
            var entry = self.treap.getEntryFor(value);
            const treap_node = entry.node orelse return false;
            const bag_node = bagNodeFromTreapNode(treap_node);
            self.total_size -= bag_node.occ;
            entry.set(null);
            self.allocator.destroy(bag_node);
            self.distinct_count -= 1;
            return true;
        }

        /// Returns the number of occurrences of the value.
        pub fn occurrencesOf(self: *const Self, value: T) usize {
            var node = self.treap.root;
            while (node) |current| {
                const ord = orderFn(value, current.key);
                if (ord == .eq) return bagNodeFromTreapNode(current).occ;
                node = current.children[@intFromBool(ord == .gt)];
            }
            return 0;
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

        /// Total number of elements (counting duplicates).
        pub fn totalSize(self: *const Self) usize {
            return self.total_size;
        }

        /// Number of distinct values.
        pub fn sizeDistinct(self: *const Self) usize {
            return self.distinct_count;
        }

        /// Alias for totalSize().
        pub fn len(self: *const Self) usize {
            return self.total_size;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.total_size == 0;
        }

        pub fn clear(self: *Self) void {
            destroySubtree(self.treap.root, self.allocator);
            self.treap.root = null;
            self.total_size = 0;
            self.distinct_count = 0;
        }

        // ---- Fallible capacity reservation ----

        /// Probes that the allocator can serve `additional` node allocations.
        /// Returns `error.OutOfMemory` if the allocator fails.
        pub fn ensureUnusedCapacity(self: *Self, additional: usize) Allocator.Error!void {
            const probe = try self.allocator.alloc(BagNode, additional);
            self.allocator.free(probe);
        }

        /// Probes that the allocator can serve enough nodes for `new_capacity`
        /// total distinct values.
        pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) Allocator.Error!void {
            if (new_capacity <= self.distinct_count) return;
            try self.ensureUnusedCapacity(new_capacity - self.distinct_count);
        }

        pub fn min(self: *const Self) ?T {
            const node = self.treap.getMin() orelse return null;
            return node.key;
        }

        pub fn max(self: *const Self) ?T {
            const node = self.treap.getMax() orelse return null;
            return node.key;
        }

        // ---- Iteration ----

        /// Pull-based iterator yielding each element by value, repeated once per
        /// occurrence (matching `forEach`), in ascending sorted order.
        /// Non-allocating: wraps the treap's `InorderIterator` (which threads the
        /// tree via node child pointers with no heap allocation) and tracks how
        /// many occurrences of the current value remain. The iterator borrows the
        /// bag; do not mutate while iterating.
        pub const Iterator = struct {
            inner: TreapType.InorderIterator,
            remaining: usize = 0,
            current: T = undefined,

            pub fn next(self: *Iterator) ?T {
                if (self.remaining > 0) {
                    self.remaining -= 1;
                    return self.current;
                }
                const node = self.inner.next() orelse return null;
                self.current = node.key;
                self.remaining = bagNodeFromTreapNode(node).occ - 1;
                return node.key;
            }
        };

        /// Returns a pull-based iterator yielding each element repeated by its
        /// occurrence count (same elements as `forEach`), in ascending sorted
        /// order. Non-allocating.
        ///
        /// No `mutIterator()` is provided for bags (deliberate exclusion): a bag
        /// element IS its own identity and ordering key — the key whose
        /// occurrence count is tracked — so mutating an element in place would
        /// break the sorted order and corrupt the count map. Remove occurrences
        /// of the old element and add the new one instead.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .inner = TreapType.InorderIterator{ .current = self.treap.getMin() } };
        }

        /// Calls f(context, value, count) for each distinct value.
        pub fn forEachWithOccurrences(self: *const Self, context: anytype, comptime f: fn (@TypeOf(context), T, usize) void) void {
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |treap_node| {
                f(context, treap_node.key, bagNodeFromTreapNode(treap_node).occ);
            }
        }

        // ---- Functional Operations ----

        /// Returns a new bag with only elements satisfying the predicate (preserving counts).
        pub fn select(self: *const Self, context: anytype, comptime predicate: fn (@TypeOf(context), T) bool) Allocator.Error!Self {
            var result = init(self.allocator);
            errdefer result.deinit();
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |treap_node| {
                if (predicate(context, treap_node.key)) {
                    try result.addOccurrences(treap_node.key, bagNodeFromTreapNode(treap_node).occ);
                }
            }
            return result;
        }

        /// Returns a new bag with elements NOT satisfying the predicate.
        pub fn reject(self: *const Self, context: anytype, comptime predicate: fn (@TypeOf(context), T) bool) Allocator.Error!Self {
            var result = init(self.allocator);
            errdefer result.deinit();
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |treap_node| {
                if (!predicate(context, treap_node.key)) {
                    try result.addOccurrences(treap_node.key, bagNodeFromTreapNode(treap_node).occ);
                }
            }
            return result;
        }

        /// Returns the first distinct value satisfying the predicate, or null.
        pub fn detect(self: *const Self, context: anytype, comptime predicate: fn (@TypeOf(context), T) bool) ?T {
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |treap_node| {
                if (predicate(context, treap_node.key)) return treap_node.key;
            }
            return null;
        }

        pub fn anySatisfy(self: *const Self, context: anytype, comptime predicate: fn (@TypeOf(context), T) bool) bool {
            return self.detect(context, predicate) != null;
        }

        pub fn allSatisfy(self: *const Self, context: anytype, comptime predicate: fn (@TypeOf(context), T) bool) bool {
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |treap_node| {
                if (!predicate(context, treap_node.key)) return false;
            }
            return true;
        }

        pub fn noneSatisfy(self: *const Self, context: anytype, comptime predicate: fn (@TypeOf(context), T) bool) bool {
            return self.detect(context, predicate) == null;
        }

        // ---- Conversion ----

        /// Returns all elements (with duplicates) as an allocated slice, in sorted order.
        pub fn toSlice(self: *const Self, allocator: Allocator) Allocator.Error![]T {
            var buf = std.ArrayListUnmanaged(T){};
            errdefer buf.deinit(allocator);
            try buf.ensureTotalCapacity(allocator, self.total_size);
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |treap_node| {
                const occ = bagNodeFromTreapNode(treap_node).occ;
                var j: usize = 0;
                while (j < occ) : (j += 1) buf.appendAssumeCapacity(treap_node.key);
            }
            return buf.toOwnedSlice(allocator);
        }

        // ---- Fluent API ----

        pub fn with(self: *Self, value: T) Allocator.Error!*Self {
            try self.add(value);
            return self;
        }

        pub fn without(self: *Self, value: T) *Self {
            _ = self.remove(value);
            return self;
        }

        // ---- Formatting ----

        /// Formats as "{v1x2, v2x1}" in sorted order.
        pub fn format(self: *const Self, writer: anytype) !void {
            try writer.writeAll("{");
            var first = true;
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |treap_node| {
                if (!first) try writer.writeAll(", ");
                try writer.print("{any}", .{treap_node.key});
                try writer.writeAll("x");
                try writer.print("{any}", .{bagNodeFromTreapNode(treap_node).occ});
                first = false;
            }
            try writer.writeAll("}");
        }

        // ---- Equality ----

        pub fn eql(self: *const Self, other: *const Self) bool {
            if (self.total_size != other.total_size) return false;
            if (self.distinct_count != other.distinct_count) return false;
            var it1 = TreapType.InorderIterator{ .current = self.treap.getMin() };
            var it2 = TreapType.InorderIterator{ .current = other.treap.getMin() };
            while (it1.next()) |n1| {
                const n2 = it2.next() orelse return false;
                if (!elemEql(T, n1.key, n2.key)) return false;
                if (bagNodeFromTreapNode(n1).occ != bagNodeFromTreapNode(n2).occ) return false;
            }
            return true;
        }
    };
}
