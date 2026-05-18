// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;

/// Sorted set of unique `u21` values, backed by `std.Treap` for
/// O(log n) insert, remove, and lookup.
pub const CharTreeSet = struct {
    fn orderFn(a: u21, b: u21) std.math.Order {
        return std.math.order(a, b);
    }

    const TreapType = std.Treap(u21, orderFn);

    treap: TreapType = .{},
    config: AllocatorConfig,
    node_count: usize = 0,

    pub fn init(allocator: Allocator) CharTreeSet {
        return .{ .config = AllocatorConfig.init(allocator) };
    }

    pub fn initWithConfig(config: AllocatorConfig) CharTreeSet {
        return .{ .config = config };
    }

    pub fn deinit(self: *CharTreeSet) void {
        destroySubtree(self.treap.root, self.config.keysAllocator());
    }

    fn destroySubtree(node_opt: ?*TreapType.Node, allocator: Allocator) void {
        const node = node_opt orelse return;
        destroySubtree(node.children[0], allocator);
        destroySubtree(node.children[1], allocator);
        allocator.destroy(node);
    }

    pub fn of(allocator: Allocator, values: []const u21) CharTreeSet {
        var set = init(allocator);
        for (values) |val| {
            _ = set.add(val);
        }
        return set;
    }

    /// Adds a value. Returns true if it was not already present.
    pub fn add(self: *CharTreeSet, value: u21) bool {
        var entry = self.treap.getEntryFor(value);
        if (entry.node != null) return false;
        const node = self.config.keysAllocator().create(TreapType.Node) catch @panic("out of memory");
        entry.set(node);
        self.node_count += 1;
        return true;
    }

    /// Removes a value. Returns true if it was present.
    pub fn remove(self: *CharTreeSet, value: u21) bool {
        var entry = self.treap.getEntryFor(value);
        const node = entry.node orelse return false;
        entry.set(null);
        self.config.keysAllocator().destroy(node);
        self.node_count -= 1;
        return true;
    }

    pub fn contains(self: *const CharTreeSet, value: u21) bool {
        var node = self.treap.root;
        while (node) |current| {
            const ord = orderFn(value, current.key);
            if (ord == .eq) return true;
            node = current.children[@intFromBool(ord == .gt)];
        }
        return false;
    }

    pub fn len(self: *const CharTreeSet) usize {
        return self.node_count;
    }

    /// Alias for len() — matches Go/Java naming.
    pub fn size(self: *const CharTreeSet) usize {
        return self.node_count;
    }

    pub fn isEmpty(self: *const CharTreeSet) bool {
        return self.node_count == 0;
    }

    pub fn clear(self: *CharTreeSet) void {
        destroySubtree(self.treap.root, self.config.keysAllocator());
        self.treap.root = null;
        self.node_count = 0;
    }

    // ---- Fallible capacity reservation ----

    /// Probes that the allocator can serve `additional` node allocations.
    /// Returns `error.OutOfMemory` if the allocator fails.
    pub fn ensureUnusedCapacity(self: *CharTreeSet, additional: usize) Allocator.Error!void {
        const probe = try self.config.keysAllocator().alloc(TreapType.Node, additional);
        self.config.keysAllocator().free(probe);
    }

    /// Probes that the allocator can serve enough nodes for `new_capacity`
    /// total elements.
    pub fn ensureTotalCapacity(self: *CharTreeSet, new_capacity: usize) Allocator.Error!void {
        if (new_capacity <= self.node_count) return;
        try self.ensureUnusedCapacity(new_capacity - self.node_count);
    }

    pub fn min(self: *const CharTreeSet) ?u21 {
        const node = self.treap.getMin() orelse return null;
        return node.key;
    }

    pub fn max(self: *const CharTreeSet) ?u21 {
        const node = self.treap.getMax() orelse return null;
        return node.key;
    }

    /// Returns all values in sorted order. Caller must free the returned slice.
    pub fn toSlice(self: *const CharTreeSet, allocator: Allocator) []u21 {
        var result = std.ArrayListUnmanaged(u21){};
        result.ensureTotalCapacity(allocator, self.node_count) catch @panic("out of memory");
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            result.appendAssumeCapacity(node.key);
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    // ---- Iteration ----

    pub fn forEach(self: *const CharTreeSet, f: *const fn (u21) void) void {
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| f(node.key);
    }

    // ---- Functional Operations ----

    pub fn select(self: *const CharTreeSet, predicate: *const fn (u21) bool) CharTreeSet {
        var result = init(self.config.base);
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (predicate(node.key)) _ = result.add(node.key);
        }
        return result;
    }

    pub fn reject(self: *const CharTreeSet, predicate: *const fn (u21) bool) CharTreeSet {
        var result = init(self.config.base);
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (!predicate(node.key)) _ = result.add(node.key);
        }
        return result;
    }

    pub fn detect(self: *const CharTreeSet, predicate: *const fn (u21) bool) ?u21 {
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (predicate(node.key)) return node.key;
        }
        return null;
    }

    pub fn anySatisfy(self: *const CharTreeSet, predicate: *const fn (u21) bool) bool {
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (predicate(node.key)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const CharTreeSet, predicate: *const fn (u21) bool) bool {
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (!predicate(node.key)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const CharTreeSet, predicate: *const fn (u21) bool) bool {
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (predicate(node.key)) return false;
        }
        return true;
    }

    pub fn count(self: *const CharTreeSet, predicate: *const fn (u21) bool) usize {
        var c: usize = 0;
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (predicate(node.key)) c += 1;
        }
        return c;
    }

    // ---- Set Operations ----

    pub fn setUnion(self: *const CharTreeSet, other: *const CharTreeSet) CharTreeSet {
        var result = init(self.config.base);
        var it1 = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it1.next()) |node| _ = result.add(node.key);
        var it2 = TreapType.InorderIterator{ .current = other.treap.getMin() };
        while (it2.next()) |node| _ = result.add(node.key);
        return result;
    }

    pub fn intersect(self: *const CharTreeSet, other: *const CharTreeSet) CharTreeSet {
        var result = init(self.config.base);
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (other.contains(node.key)) _ = result.add(node.key);
        }
        return result;
    }

    pub fn difference(self: *const CharTreeSet, other: *const CharTreeSet) CharTreeSet {
        var result = init(self.config.base);
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (!other.contains(node.key)) _ = result.add(node.key);
        }
        return result;
    }

    // ---- Range Operations ----

    /// Returns the node for the smallest element >= value, or null.
    fn ceilingNode(self: *const CharTreeSet, value: u21) ?*TreapType.Node {
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
    pub fn ceiling(self: *const CharTreeSet, value: u21) ?u21 {
        const node = self.ceilingNode(value) orelse return null;
        return node.key;
    }

    /// Returns the largest element <= value, or null if none.
    pub fn floor(self: *const CharTreeSet, value: u21) ?u21 {
        var node = self.treap.root;
        var best: ?u21 = null;
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
    pub fn rangeValues(self: *const CharTreeSet, from: u21, to: u21, allocator: Allocator) []u21 {
        var result = std.ArrayListUnmanaged(u21){};
        var it = TreapType.InorderIterator{ .current = self.ceilingNode(from) };
        while (it.next()) |node| {
            if (orderFn(node.key, to) == .gt) break;
            result.append(allocator, node.key) catch @panic("out of memory");
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    // ---- Formatting ----

    /// Formats as "{v1, v2, v3}" in sorted order.
    pub fn format(self: *const CharTreeSet, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn with(self: *CharTreeSet, value: u21) *CharTreeSet {
        _ = self.add(value);
        return self;
    }

    pub fn without(self: *CharTreeSet, value: u21) *CharTreeSet {
        _ = self.remove(value);
        return self;
    }

    // ---- Equality ----

    pub fn eql(self: *const CharTreeSet, other: *const CharTreeSet) bool {
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

test "CharTreeSet: add and contains" {
    var set = CharTreeSet.init(std.testing.allocator);
    defer set.deinit();
    _ = set.add('a');
    _ = set.add('b');
    _ = set.add('c');
    try std.testing.expectEqual(@as(usize, 3), set.len());
    try std.testing.expect(set.contains('b'));
    try std.testing.expect(!set.contains('z'));
}

test "CharTreeSet: duplicate" {
    var set = CharTreeSet.init(std.testing.allocator);
    defer set.deinit();
    try std.testing.expect(set.add('a'));
    try std.testing.expect(!set.add('a'));
    try std.testing.expectEqual(@as(usize, 1), set.len());
}

test "CharTreeSet: sorted iteration" {
    var set = CharTreeSet.of(std.testing.allocator, &[_]u21{ 'c', 'a', 'b' });
    defer set.deinit();
    const items = set.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(items);
    try std.testing.expectEqual('a', items[0]);
    try std.testing.expectEqual('b', items[1]);
    try std.testing.expectEqual('c', items[2]);
}

test "CharTreeSet: min max" {
    var set = CharTreeSet.of(std.testing.allocator, &[_]u21{ 'c', 'a', 'b' });
    defer set.deinit();
    try std.testing.expectEqual(@as(?u21, 'a'), set.min());
    try std.testing.expectEqual(@as(?u21, 'c'), set.max());
}

test "CharTreeSet: remove" {
    var set = CharTreeSet.of(std.testing.allocator, &[_]u21{ 'a', 'b' });
    defer set.deinit();
    try std.testing.expect(set.remove('a'));
    try std.testing.expect(!set.contains('a'));
}

test "CharTreeSet: union" {
    var a = CharTreeSet.of(std.testing.allocator, &[_]u21{ 'a', 'b' });
    defer a.deinit();
    var b = CharTreeSet.of(std.testing.allocator, &[_]u21{ 'b', 'c' });
    defer b.deinit();
    var u = a.setUnion(&b);
    defer u.deinit();
    try std.testing.expectEqual(@as(usize, 3), u.len());
}

test "CharTreeSet: intersect" {
    var a = CharTreeSet.of(std.testing.allocator, &[_]u21{ 'a', 'b' });
    defer a.deinit();
    var b = CharTreeSet.of(std.testing.allocator, &[_]u21{ 'b', 'c' });
    defer b.deinit();
    var inter = a.intersect(&b);
    defer inter.deinit();
    try std.testing.expectEqual(@as(usize, 1), inter.len());
}

test "CharTreeSet: ensureUnusedCapacity probes allocator" {
    var set = CharTreeSet.init(std.testing.allocator);
    defer set.deinit();
    try set.ensureUnusedCapacity(100);
    _ = set.add('a');
    _ = set.add('b');
    try std.testing.expectEqual(@as(usize, 2), set.len());
}

test "CharTreeSet: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: TreeSet.init doesn't allocate (Treap is node-based),
    // so the first alloc (ensureUnusedCapacity grow) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var set = CharTreeSet.init(failing.allocator());
    defer set.deinit();
    try std.testing.expectError(error.OutOfMemory, set.ensureUnusedCapacity(1024));
}
