// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const float_order = @import("../float_order.zig");

/// Sorted bag (multiset) of `f32` values with occurrence counting.
///
/// Backed by `std.Treap` for O(log n) insert, remove, and lookup.
/// Each tree node carries an occurrence count via the intrusive
/// `BagNode` wrapper around `TreapType.Node`.
pub const F32TreeBag = struct {
    fn orderFn(a: f32, b: f32) std.math.Order {
        // IEEE 754 totalOrder — see src/float_order.zig. A raw bit
        // compare is not a total order when NaN coexists with negatives.
        return float_order.totalCmpF32(a, b);
    }

    const TreapType = std.Treap(f32, orderFn);

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

    pub fn init(allocator: Allocator) F32TreeBag {
        return initWithConfig(AllocatorConfig.init(allocator));
    }

    pub fn initWithConfig(config: AllocatorConfig) F32TreeBag {
        return .{ .config = config };
    }

    pub fn deinit(self: *F32TreeBag) void {
        destroySubtree(self.treap.root, self.config.keysAllocator());
    }

    fn destroySubtree(node_opt: ?*TreapType.Node, allocator: Allocator) void {
        const node = node_opt orelse return;
        destroySubtree(node.children[0], allocator);
        destroySubtree(node.children[1], allocator);
        allocator.destroy(bagNodeFromTreapNode(node));
    }

    fn addOccurrences(self: *F32TreeBag, value: f32, occ: usize) void {
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
    pub fn add(self: *F32TreeBag, value: f32) void {
        self.addOccurrences(value, 1);
    }

    /// Remove one occurrence. Returns true if the value was present.
    pub fn remove(self: *F32TreeBag, value: f32) bool {
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
    pub fn removeAll(self: *F32TreeBag, value: f32) bool {
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
    pub fn occurrencesOf(self: *const F32TreeBag, value: f32) usize {
        var node = self.treap.root;
        while (node) |current| {
            const ord = orderFn(value, current.key);
            if (ord == .eq) return bagNodeFromTreapNode(current).occ;
            node = current.children[@intFromBool(ord == .gt)];
        }
        return 0;
    }

    pub fn contains(self: *const F32TreeBag, value: f32) bool {
        var node = self.treap.root;
        while (node) |current| {
            const ord = orderFn(value, current.key);
            if (ord == .eq) return true;
            node = current.children[@intFromBool(ord == .gt)];
        }
        return false;
    }

    /// Total number of elements (counting duplicates).
    pub fn totalSize(self: *const F32TreeBag) usize {
        return self.total_size;
    }

    /// Number of distinct values.
    pub fn sizeDistinct(self: *const F32TreeBag) usize {
        return self.distinct_count;
    }

    /// Alias for totalSize().
    pub fn len(self: *const F32TreeBag) usize {
        return self.total_size;
    }

    pub fn isEmpty(self: *const F32TreeBag) bool {
        return self.total_size == 0;
    }

    pub fn clear(self: *F32TreeBag) void {
        destroySubtree(self.treap.root, self.config.keysAllocator());
        self.treap.root = null;
        self.total_size = 0;
        self.distinct_count = 0;
    }

    // ---- Fallible capacity reservation ----

    /// Probes that the allocator can serve `additional` node allocations.
    /// Returns `error.OutOfMemory` if the allocator fails.
    pub fn ensureUnusedCapacity(self: *F32TreeBag, additional: usize) Allocator.Error!void {
        const probe = try self.config.keysAllocator().alloc(BagNode, additional);
        self.config.keysAllocator().free(probe);
    }

    /// Probes that the allocator can serve enough nodes for `new_capacity`
    /// total distinct values.
    pub fn ensureTotalCapacity(self: *F32TreeBag, new_capacity: usize) Allocator.Error!void {
        if (new_capacity <= self.distinct_count) return;
        try self.ensureUnusedCapacity(new_capacity - self.distinct_count);
    }

    pub fn min(self: *const F32TreeBag) ?f32 {
        const node = self.treap.getMin() orelse return null;
        return node.key;
    }

    pub fn max(self: *const F32TreeBag) ?f32 {
        const node = self.treap.getMax() orelse return null;
        return node.key;
    }

    // ---- Iteration ----

    /// Calls f(value) for each element (including duplicates).
    pub fn forEach(self: *const F32TreeBag, f: *const fn (f32) void) void {
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |treap_node| {
            const occ = bagNodeFromTreapNode(treap_node).occ;
            var j: usize = 0;
            while (j < occ) : (j += 1) f(treap_node.key);
        }
    }

    /// Calls f(value, count) for each distinct value.
    pub fn forEachWithOccurrences(self: *const F32TreeBag, f: *const fn (f32, usize) void) void {
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |treap_node| {
            f(treap_node.key, bagNodeFromTreapNode(treap_node).occ);
        }
    }

    // ---- Functional Operations ----

    /// Returns a new bag with only elements satisfying the predicate (preserving counts).
    pub fn select(self: *const F32TreeBag, predicate: *const fn (f32) bool) F32TreeBag {
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
    pub fn reject(self: *const F32TreeBag, predicate: *const fn (f32) bool) F32TreeBag {
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
    pub fn detect(self: *const F32TreeBag, predicate: *const fn (f32) bool) ?f32 {
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |treap_node| {
            if (predicate(treap_node.key)) return treap_node.key;
        }
        return null;
    }

    pub fn anySatisfy(self: *const F32TreeBag, predicate: *const fn (f32) bool) bool {
        return self.detect(predicate) != null;
    }

    pub fn allSatisfy(self: *const F32TreeBag, predicate: *const fn (f32) bool) bool {
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |treap_node| {
            if (!predicate(treap_node.key)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const F32TreeBag, predicate: *const fn (f32) bool) bool {
        return self.detect(predicate) == null;
    }

    // ---- Conversion ----

    /// Returns all elements (with duplicates) as an allocated slice, in sorted order.
    pub fn toSlice(self: *const F32TreeBag, allocator: Allocator) []f32 {
        var buf = std.ArrayListUnmanaged(f32){};
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

    pub fn with(self: *F32TreeBag, value: f32) *F32TreeBag {
        self.add(value);
        return self;
    }

    pub fn without(self: *F32TreeBag, value: f32) *F32TreeBag {
        _ = self.remove(value);
        return self;
    }

    // ---- Formatting ----

    /// Formats as "{v1x2, v2x1}" in sorted order.
    pub fn format(self: *const F32TreeBag, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const F32TreeBag, other: *const F32TreeBag) bool {
        if (self.total_size != other.total_size) return false;
        if (self.distinct_count != other.distinct_count) return false;
        var it1 = TreapType.InorderIterator{ .current = self.treap.getMin() };
        var it2 = TreapType.InorderIterator{ .current = other.treap.getMin() };
        while (it1.next()) |n1| {
            const n2 = it2.next() orelse return false;
            if (!(@as(u32, @bitCast(n1.key)) == @as(u32, @bitCast(n2.key)))) return false;
            if (bagNodeFromTreapNode(n1).occ != bagNodeFromTreapNode(n2).occ) return false;
        }
        return true;
    }
};

test "F32TreeBag: add and occurrences" {
    var b = F32TreeBag.init(std.testing.allocator);
    defer b.deinit();
    b.add(1.0);
    b.add(1.0);
    b.add(2.0);
    try std.testing.expectEqual(@as(usize, 2), b.occurrencesOf(1.0));
    try std.testing.expectEqual(@as(usize, 1), b.occurrencesOf(2.0));
    try std.testing.expectEqual(@as(usize, 3), b.totalSize());
    try std.testing.expectEqual(@as(usize, 2), b.sizeDistinct());
}

test "F32TreeBag: remove" {
    var b = F32TreeBag.init(std.testing.allocator);
    defer b.deinit();
    b.add(1.0);
    b.add(1.0);
    b.add(1.0);
    try std.testing.expect(b.remove(1.0));
    try std.testing.expectEqual(@as(usize, 2), b.occurrencesOf(1.0));
}

test "F32TreeBag: removeAll" {
    var b = F32TreeBag.init(std.testing.allocator);
    defer b.deinit();
    b.add(1.0);
    b.add(1.0);
    b.add(2.0);
    try std.testing.expect(b.removeAll(1.0));
    try std.testing.expect(!b.contains(1.0));
    try std.testing.expectEqual(@as(usize, 1), b.totalSize());
}

test "F32TreeBag: clear" {
    var b = F32TreeBag.init(std.testing.allocator);
    defer b.deinit();
    b.add(1.0);
    b.clear();
    try std.testing.expect(b.isEmpty());
}

test "F32TreeBag: sorted order and min/max" {
    var b = F32TreeBag.init(std.testing.allocator);
    defer b.deinit();
    b.add(3.0);
    b.add(1.0);
    b.add(2.0);
    try std.testing.expectEqual(@as(?f32, 1.0), b.min());
    try std.testing.expectEqual(@as(?f32, 3.0), b.max());
}

test "F32TreeBag: select and reject" {
    var b = F32TreeBag.init(std.testing.allocator);
    defer b.deinit();
    b.add(1.0);
    b.add(2.0);
    b.add(3.0);
    var sel = b.select(struct {
        fn f(val: f32) bool {
            return val > 1.0;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expectEqual(@as(usize, 2), sel.totalSize());
}

test "F32TreeBag: toSlice" {
    var b = F32TreeBag.init(std.testing.allocator);
    defer b.deinit();
    b.add(1.0);
    b.add(1.0);
    b.add(2.0);
    const slice = b.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqual(@as(usize, 3), slice.len);
}

test "F32TreeBag: fluent with/without" {
    var b = F32TreeBag.init(std.testing.allocator);
    defer b.deinit();
    _ = b.with(1.0).with(1.0).with(2.0);
    try std.testing.expectEqual(@as(usize, 3), b.totalSize());
    _ = b.without(1.0);
    try std.testing.expectEqual(@as(usize, 2), b.totalSize());
}

test "F32TreeBag: eql" {
    var b1 = F32TreeBag.init(std.testing.allocator);
    defer b1.deinit();
    b1.add(1.0);
    b1.add(1.0);
    b1.add(2.0);
    var b2 = F32TreeBag.init(std.testing.allocator);
    defer b2.deinit();
    b2.add(2.0);
    b2.add(1.0);
    b2.add(1.0);
    try std.testing.expect(b1.eql(&b2));
}

test "F32TreeBag: forEachWithOccurrences" {
    var b = F32TreeBag.init(std.testing.allocator);
    defer b.deinit();
    b.add(1.0);
    b.add(1.0);
    b.add(2.0);
    b.forEachWithOccurrences(struct {
        fn f(_: f32, _: usize) void {}
    }.f);
    try std.testing.expectEqual(@as(usize, 2), b.sizeDistinct());
}

test "F32TreeBag: ensureUnusedCapacity probes allocator" {
    var b = F32TreeBag.init(std.testing.allocator);
    defer b.deinit();
    try b.ensureUnusedCapacity(100);
    b.add(1.0);
    b.add(2.0);
    try std.testing.expectEqual(@as(usize, 2), b.sizeDistinct());
}

test "F32TreeBag: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: TreeBag.init doesn't allocate (Treap is node-based),
    // so the first alloc (ensureUnusedCapacity grow) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var b = F32TreeBag.init(failing.allocator());
    defer b.deinit();
    try std.testing.expectError(error.OutOfMemory, b.ensureUnusedCapacity(1024));
}
