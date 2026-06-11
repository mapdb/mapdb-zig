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
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const float_order = @import("../float_order.zig");

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
        config: AllocatorConfig,
        total_size: usize = 0,
        distinct_count: usize = 0,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return initWithConfig(AllocatorConfig.init(allocator));
        }

        pub fn initWithConfig(config: AllocatorConfig) Self {
            return .{ .config = config };
        }

        pub fn deinit(self: *Self) void {
            destroySubtree(self.treap.root, self.config.keysAllocator());
        }

        fn destroySubtree(node_opt: ?*TreapType.Node, allocator: Allocator) void {
            const node = node_opt orelse return;
            destroySubtree(node.children[0], allocator);
            destroySubtree(node.children[1], allocator);
            allocator.destroy(bagNodeFromTreapNode(node));
        }

        fn addOccurrences(self: *Self, value: T, occ: usize) void {
            var entry = self.treap.getEntryFor(value);
            if (entry.node) |treap_node| {
                bagNodeFromTreapNode(treap_node).occ += occ;
            } else {
                const bag_node = self.config.keysAllocator().create(BagNode) catch @panic("out of memory");
                bag_node.occ = occ;
                entry.set(&bag_node.treap_node);
                self.distinct_count += 1;
            }
            self.total_size += occ;
        }

        /// Add one occurrence of the value.
        pub fn add(self: *Self, value: T) void {
            self.addOccurrences(value, 1);
        }

        /// Remove one occurrence. Returns true if the value was present.
        pub fn remove(self: *Self, value: T) bool {
            var entry = self.treap.getEntryFor(value);
            const treap_node = entry.node orelse return false;
            const bag_node = bagNodeFromTreapNode(treap_node);
            bag_node.occ -= 1;
            if (bag_node.occ == 0) {
                entry.set(null);
                self.config.keysAllocator().destroy(bag_node);
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
            self.config.keysAllocator().destroy(bag_node);
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
            destroySubtree(self.treap.root, self.config.keysAllocator());
            self.treap.root = null;
            self.total_size = 0;
            self.distinct_count = 0;
        }

        // ---- Fallible capacity reservation ----

        /// Probes that the allocator can serve `additional` node allocations.
        /// Returns `error.OutOfMemory` if the allocator fails.
        pub fn ensureUnusedCapacity(self: *Self, additional: usize) Allocator.Error!void {
            const probe = try self.config.keysAllocator().alloc(BagNode, additional);
            self.config.keysAllocator().free(probe);
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
        pub fn iterator(self: *const Self) Iterator {
            return .{ .inner = TreapType.InorderIterator{ .current = self.treap.getMin() } };
        }

        /// Calls f(value) for each element (including duplicates).
        pub fn forEach(self: *const Self, f: *const fn (T) void) void {
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |treap_node| {
                const occ = bagNodeFromTreapNode(treap_node).occ;
                var j: usize = 0;
                while (j < occ) : (j += 1) f(treap_node.key);
            }
        }

        /// Calls f(value, count) for each distinct value.
        pub fn forEachWithOccurrences(self: *const Self, f: *const fn (T, usize) void) void {
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |treap_node| {
                f(treap_node.key, bagNodeFromTreapNode(treap_node).occ);
            }
        }

        // ---- Functional Operations ----

        /// Returns a new bag with only elements satisfying the predicate (preserving counts).
        pub fn select(self: *const Self, predicate: *const fn (T) bool) Self {
            var result = init(self.config.base);
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |treap_node| {
                if (predicate(treap_node.key)) {
                    result.addOccurrences(treap_node.key, bagNodeFromTreapNode(treap_node).occ);
                }
            }
            return result;
        }

        /// Returns a new bag with elements NOT satisfying the predicate.
        pub fn reject(self: *const Self, predicate: *const fn (T) bool) Self {
            var result = init(self.config.base);
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |treap_node| {
                if (!predicate(treap_node.key)) {
                    result.addOccurrences(treap_node.key, bagNodeFromTreapNode(treap_node).occ);
                }
            }
            return result;
        }

        /// Returns the first distinct value satisfying the predicate, or null.
        pub fn detect(self: *const Self, predicate: *const fn (T) bool) ?T {
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |treap_node| {
                if (predicate(treap_node.key)) return treap_node.key;
            }
            return null;
        }

        pub fn anySatisfy(self: *const Self, predicate: *const fn (T) bool) bool {
            return self.detect(predicate) != null;
        }

        pub fn allSatisfy(self: *const Self, predicate: *const fn (T) bool) bool {
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |treap_node| {
                if (!predicate(treap_node.key)) return false;
            }
            return true;
        }

        pub fn noneSatisfy(self: *const Self, predicate: *const fn (T) bool) bool {
            return self.detect(predicate) == null;
        }

        // ---- Conversion ----

        /// Returns all elements (with duplicates) as an allocated slice, in sorted order.
        pub fn toSlice(self: *const Self, allocator: Allocator) []T {
            var buf = std.ArrayListUnmanaged(T){};
            buf.ensureTotalCapacity(allocator, self.total_size) catch @panic("out of memory");
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |treap_node| {
                const occ = bagNodeFromTreapNode(treap_node).occ;
                var j: usize = 0;
                while (j < occ) : (j += 1) buf.appendAssumeCapacity(treap_node.key);
            }
            return buf.toOwnedSlice(allocator) catch @panic("out of memory");
        }

        // ---- Fluent API ----

        pub fn with(self: *Self, value: T) *Self {
            self.add(value);
            return self;
        }

        pub fn without(self: *Self, value: T) *Self {
            _ = self.remove(value);
            return self;
        }

        // ---- Formatting ----

        /// Formats as "{v1x2, v2x1}" in sorted order.
        pub fn format(self: *const Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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
