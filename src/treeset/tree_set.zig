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

/// Sorted set of unique `T` values, backed by `std.Treap` for
/// O(log n) insert, remove, and lookup.
pub fn TreeSet(comptime T: type) type {
    return struct {
        fn orderFn(a: T, b: T) std.math.Order {
            return keyOrder(T, a, b);
        }

        const TreapType = std.Treap(T, orderFn);

        treap: TreapType = .{},
        config: AllocatorConfig,
        node_count: usize = 0,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{ .config = AllocatorConfig.init(allocator) };
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
            allocator.destroy(node);
        }

        pub fn of(allocator: Allocator, values: []const T) Self {
            var set = init(allocator);
            for (values) |val| {
                _ = set.add(val);
            }
            return set;
        }

        /// Adds a value. Returns true if it was not already present.
        pub fn add(self: *Self, value: T) bool {
            var entry = self.treap.getEntryFor(value);
            if (entry.node != null) return false;
            const node = self.config.keysAllocator().create(TreapType.Node) catch @panic("out of memory");
            entry.set(node);
            self.node_count += 1;
            return true;
        }

        /// Removes a value. Returns true if it was present.
        pub fn remove(self: *Self, value: T) bool {
            var entry = self.treap.getEntryFor(value);
            const node = entry.node orelse return false;
            entry.set(null);
            self.config.keysAllocator().destroy(node);
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
            destroySubtree(self.treap.root, self.config.keysAllocator());
            self.treap.root = null;
            self.node_count = 0;
        }

        // ---- Fallible capacity reservation ----

        /// Probes that the allocator can serve `additional` node allocations.
        /// Returns `error.OutOfMemory` if the allocator fails.
        pub fn ensureUnusedCapacity(self: *Self, additional: usize) Allocator.Error!void {
            const probe = try self.config.keysAllocator().alloc(TreapType.Node, additional);
            self.config.keysAllocator().free(probe);
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
        pub fn toSlice(self: *const Self, allocator: Allocator) []T {
            var result = std.ArrayListUnmanaged(T){};
            result.ensureTotalCapacity(allocator, self.node_count) catch @panic("out of memory");
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                result.appendAssumeCapacity(node.key);
            }
            return result.toOwnedSlice(allocator) catch @panic("out of memory");
        }

        // ---- Iteration ----

        pub fn forEach(self: *const Self, f: *const fn (T) void) void {
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| f(node.key);
        }

        // ---- Functional Operations ----

        pub fn select(self: *const Self, predicate: *const fn (T) bool) Self {
            var result = init(self.config.base);
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (predicate(node.key)) _ = result.add(node.key);
            }
            return result;
        }

        pub fn reject(self: *const Self, predicate: *const fn (T) bool) Self {
            var result = init(self.config.base);
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (!predicate(node.key)) _ = result.add(node.key);
            }
            return result;
        }

        pub fn detect(self: *const Self, predicate: *const fn (T) bool) ?T {
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (predicate(node.key)) return node.key;
            }
            return null;
        }

        pub fn anySatisfy(self: *const Self, predicate: *const fn (T) bool) bool {
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (predicate(node.key)) return true;
            }
            return false;
        }

        pub fn allSatisfy(self: *const Self, predicate: *const fn (T) bool) bool {
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (!predicate(node.key)) return false;
            }
            return true;
        }

        pub fn noneSatisfy(self: *const Self, predicate: *const fn (T) bool) bool {
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (predicate(node.key)) return false;
            }
            return true;
        }

        pub fn count(self: *const Self, predicate: *const fn (T) bool) usize {
            var c: usize = 0;
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (predicate(node.key)) c += 1;
            }
            return c;
        }

        // ---- Set Operations ----

        pub fn setUnion(self: *const Self, other: *const Self) Self {
            var result = init(self.config.base);
            var it1 = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it1.next()) |node| _ = result.add(node.key);
            var it2 = TreapType.InorderIterator{ .current = other.treap.getMin() };
            while (it2.next()) |node| _ = result.add(node.key);
            return result;
        }

        pub fn intersect(self: *const Self, other: *const Self) Self {
            var result = init(self.config.base);
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (other.contains(node.key)) _ = result.add(node.key);
            }
            return result;
        }

        pub fn difference(self: *const Self, other: *const Self) Self {
            var result = init(self.config.base);
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (!other.contains(node.key)) _ = result.add(node.key);
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
        pub fn rangeValues(self: *const Self, from: T, to: T, allocator: Allocator) []T {
            var result = std.ArrayListUnmanaged(T){};
            var it = TreapType.InorderIterator{ .current = self.ceilingNode(from) };
            while (it.next()) |node| {
                if (orderFn(node.key, to) == .gt) break;
                result.append(allocator, node.key) catch @panic("out of memory");
            }
            return result.toOwnedSlice(allocator) catch @panic("out of memory");
        }

        // ---- Formatting ----

        /// Formats as "{v1, v2, v3}" in sorted order.
        pub fn format(self: *const Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.writeAll("{");
            var first = true;
            var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
            while (it.next()) |node| {
                if (!first) try writer.writeAll(", ");
                try writer.print("{any}", .{node.key});
                first = false;
            }
            try writer.writeAll("}");
        }

        // ---- Fluent API ----

        pub fn with(self: *Self, value: T) *Self {
            _ = self.add(value);
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
