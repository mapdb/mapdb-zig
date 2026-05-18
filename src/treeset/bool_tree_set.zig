// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;

/// Sorted set of unique `bool` values, backed by `std.Treap` for
/// O(log n) insert, remove, and lookup.
pub const BoolTreeSet = struct {
    fn orderFn(a: bool, b: bool) std.math.Order {
        if (a == b) return .eq;
        if (!a and b) return .lt;
        return .gt;
    }

    const TreapType = std.Treap(bool, orderFn);

    treap: TreapType = .{},
    config: AllocatorConfig,
    node_count: usize = 0,

    pub fn init(allocator: Allocator) BoolTreeSet {
        return .{ .config = AllocatorConfig.init(allocator) };
    }

    pub fn initWithConfig(config: AllocatorConfig) BoolTreeSet {
        return .{ .config = config };
    }

    pub fn deinit(self: *BoolTreeSet) void {
        destroySubtree(self.treap.root, self.config.keysAllocator());
    }

    fn destroySubtree(node_opt: ?*TreapType.Node, allocator: Allocator) void {
        const node = node_opt orelse return;
        destroySubtree(node.children[0], allocator);
        destroySubtree(node.children[1], allocator);
        allocator.destroy(node);
    }

    pub fn of(allocator: Allocator, values: []const bool) BoolTreeSet {
        var set = init(allocator);
        for (values) |val| {
            _ = set.add(val);
        }
        return set;
    }

    /// Adds a value. Returns true if it was not already present.
    pub fn add(self: *BoolTreeSet, value: bool) bool {
        var entry = self.treap.getEntryFor(value);
        if (entry.node != null) return false;
        const node = self.config.keysAllocator().create(TreapType.Node) catch @panic("out of memory");
        entry.set(node);
        self.node_count += 1;
        return true;
    }

    /// Removes a value. Returns true if it was present.
    pub fn remove(self: *BoolTreeSet, value: bool) bool {
        var entry = self.treap.getEntryFor(value);
        const node = entry.node orelse return false;
        entry.set(null);
        self.config.keysAllocator().destroy(node);
        self.node_count -= 1;
        return true;
    }

    pub fn contains(self: *const BoolTreeSet, value: bool) bool {
        var node = self.treap.root;
        while (node) |current| {
            const ord = orderFn(value, current.key);
            if (ord == .eq) return true;
            node = current.children[@intFromBool(ord == .gt)];
        }
        return false;
    }

    pub fn len(self: *const BoolTreeSet) usize {
        return self.node_count;
    }

    /// Alias for len() — matches Go/Java naming.
    pub fn size(self: *const BoolTreeSet) usize {
        return self.node_count;
    }

    pub fn isEmpty(self: *const BoolTreeSet) bool {
        return self.node_count == 0;
    }

    pub fn clear(self: *BoolTreeSet) void {
        destroySubtree(self.treap.root, self.config.keysAllocator());
        self.treap.root = null;
        self.node_count = 0;
    }

    // ---- Fallible capacity reservation ----

    /// Probes that the allocator can serve `additional` node allocations.
    /// Returns `error.OutOfMemory` if the allocator fails.
    pub fn ensureUnusedCapacity(self: *BoolTreeSet, additional: usize) Allocator.Error!void {
        const probe = try self.config.keysAllocator().alloc(TreapType.Node, additional);
        self.config.keysAllocator().free(probe);
    }

    /// Probes that the allocator can serve enough nodes for `new_capacity`
    /// total elements.
    pub fn ensureTotalCapacity(self: *BoolTreeSet, new_capacity: usize) Allocator.Error!void {
        if (new_capacity <= self.node_count) return;
        try self.ensureUnusedCapacity(new_capacity - self.node_count);
    }

    pub fn min(self: *const BoolTreeSet) ?bool {
        const node = self.treap.getMin() orelse return null;
        return node.key;
    }

    pub fn max(self: *const BoolTreeSet) ?bool {
        const node = self.treap.getMax() orelse return null;
        return node.key;
    }

    /// Returns all values in sorted order. Caller must free the returned slice.
    pub fn toSlice(self: *const BoolTreeSet, allocator: Allocator) []bool {
        var result = std.ArrayListUnmanaged(bool){};
        result.ensureTotalCapacity(allocator, self.node_count) catch @panic("out of memory");
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            result.appendAssumeCapacity(node.key);
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    // ---- Iteration ----

    pub fn forEach(self: *const BoolTreeSet, f: *const fn (bool) void) void {
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| f(node.key);
    }

    // ---- Functional Operations ----

    pub fn select(self: *const BoolTreeSet, predicate: *const fn (bool) bool) BoolTreeSet {
        var result = init(self.config.base);
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (predicate(node.key)) _ = result.add(node.key);
        }
        return result;
    }

    pub fn reject(self: *const BoolTreeSet, predicate: *const fn (bool) bool) BoolTreeSet {
        var result = init(self.config.base);
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (!predicate(node.key)) _ = result.add(node.key);
        }
        return result;
    }

    pub fn detect(self: *const BoolTreeSet, predicate: *const fn (bool) bool) ?bool {
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (predicate(node.key)) return node.key;
        }
        return null;
    }

    pub fn anySatisfy(self: *const BoolTreeSet, predicate: *const fn (bool) bool) bool {
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (predicate(node.key)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const BoolTreeSet, predicate: *const fn (bool) bool) bool {
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (!predicate(node.key)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const BoolTreeSet, predicate: *const fn (bool) bool) bool {
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (predicate(node.key)) return false;
        }
        return true;
    }

    pub fn count(self: *const BoolTreeSet, predicate: *const fn (bool) bool) usize {
        var c: usize = 0;
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (predicate(node.key)) c += 1;
        }
        return c;
    }

    // ---- Set Operations ----

    pub fn setUnion(self: *const BoolTreeSet, other: *const BoolTreeSet) BoolTreeSet {
        var result = init(self.config.base);
        var it1 = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it1.next()) |node| _ = result.add(node.key);
        var it2 = TreapType.InorderIterator{ .current = other.treap.getMin() };
        while (it2.next()) |node| _ = result.add(node.key);
        return result;
    }

    pub fn intersect(self: *const BoolTreeSet, other: *const BoolTreeSet) BoolTreeSet {
        var result = init(self.config.base);
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (other.contains(node.key)) _ = result.add(node.key);
        }
        return result;
    }

    pub fn difference(self: *const BoolTreeSet, other: *const BoolTreeSet) BoolTreeSet {
        var result = init(self.config.base);
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (!other.contains(node.key)) _ = result.add(node.key);
        }
        return result;
    }

    // ---- Range Operations ----

    /// Returns the node for the smallest element >= value, or null.
    fn ceilingNode(self: *const BoolTreeSet, value: bool) ?*TreapType.Node {
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
    pub fn ceiling(self: *const BoolTreeSet, value: bool) ?bool {
        const node = self.ceilingNode(value) orelse return null;
        return node.key;
    }

    /// Returns the largest element <= value, or null if none.
    pub fn floor(self: *const BoolTreeSet, value: bool) ?bool {
        var node = self.treap.root;
        var best: ?bool = null;
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
    pub fn rangeValues(self: *const BoolTreeSet, from: bool, to: bool, allocator: Allocator) []bool {
        var result = std.ArrayListUnmanaged(bool){};
        var it = TreapType.InorderIterator{ .current = self.ceilingNode(from) };
        while (it.next()) |node| {
            if (orderFn(node.key, to) == .gt) break;
            result.append(allocator, node.key) catch @panic("out of memory");
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    // ---- Formatting ----

    /// Formats as "{v1, v2, v3}" in sorted order.
    pub fn format(self: *const BoolTreeSet, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn with(self: *BoolTreeSet, value: bool) *BoolTreeSet {
        _ = self.add(value);
        return self;
    }

    pub fn without(self: *BoolTreeSet, value: bool) *BoolTreeSet {
        _ = self.remove(value);
        return self;
    }

    // ---- Equality ----

    pub fn eql(self: *const BoolTreeSet, other: *const BoolTreeSet) bool {
        if (self.node_count != other.node_count) return false;
        var it1 = TreapType.InorderIterator{ .current = self.treap.getMin() };
        var it2 = TreapType.InorderIterator{ .current = other.treap.getMin() };
        while (it1.next()) |n1| {
            const n2 = it2.next() orelse return false;
            if (!(n1.key == n2.key)) return false;
        }
        return true;
    }
};

test "BoolTreeSet: add and contains" {
    var set = BoolTreeSet.init(std.testing.allocator);
    defer set.deinit();
    _ = set.add(true);
    _ = set.add(false);

    try std.testing.expectEqual(@as(usize, 2), set.len());
    try std.testing.expect(set.contains(false));
}

test "BoolTreeSet: duplicate" {
    var set = BoolTreeSet.init(std.testing.allocator);
    defer set.deinit();
    try std.testing.expect(set.add(true));
    try std.testing.expect(!set.add(true));
    try std.testing.expectEqual(@as(usize, 1), set.len());
}

test "BoolTreeSet: sorted iteration" {
    var set = BoolTreeSet.of(std.testing.allocator, &[_]bool{ true, false });
    defer set.deinit();
    const items = set.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(items);
    try std.testing.expectEqual(false, items[0]);
    try std.testing.expectEqual(true, items[1]);
}

test "BoolTreeSet: min max" {
    var set = BoolTreeSet.of(std.testing.allocator, &[_]bool{ true, false });
    defer set.deinit();
    try std.testing.expectEqual(@as(?bool, false), set.min());
    try std.testing.expectEqual(@as(?bool, true), set.max());
}

test "BoolTreeSet: remove" {
    var set = BoolTreeSet.of(std.testing.allocator, &[_]bool{ true, false });
    defer set.deinit();
    try std.testing.expect(set.remove(true));
    try std.testing.expect(!set.contains(true));
}

test "BoolTreeSet: union" {
    var a = BoolTreeSet.of(std.testing.allocator, &[_]bool{true});
    defer a.deinit();
    var b = BoolTreeSet.of(std.testing.allocator, &[_]bool{false});
    defer b.deinit();
    var u = a.setUnion(&b);
    defer u.deinit();
    try std.testing.expectEqual(@as(usize, 2), u.len());
}

test "BoolTreeSet: intersect" {
    var a = BoolTreeSet.of(std.testing.allocator, &[_]bool{ true, false });
    defer a.deinit();
    var b = BoolTreeSet.of(std.testing.allocator, &[_]bool{false});
    defer b.deinit();
    var inter = a.intersect(&b);
    defer inter.deinit();
    try std.testing.expectEqual(@as(usize, 1), inter.len());
}

test "BoolTreeSet: ensureUnusedCapacity probes allocator" {
    var set = BoolTreeSet.init(std.testing.allocator);
    defer set.deinit();
    try set.ensureUnusedCapacity(100);
    _ = set.add(true);
    _ = set.add(false);
    try std.testing.expectEqual(@as(usize, 2), set.len());
}

test "BoolTreeSet: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: TreeSet.init doesn't allocate (Treap is node-based),
    // so the first alloc (ensureUnusedCapacity grow) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var set = BoolTreeSet.init(failing.allocator());
    defer set.deinit();
    try std.testing.expectError(error.OutOfMemory, set.ensureUnusedCapacity(1024));
}
