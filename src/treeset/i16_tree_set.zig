
const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;

/// Sorted set of unique `i16` values, backed by `std.Treap` for
/// O(log n) insert, remove, and lookup.
pub const I16TreeSet = struct {
    fn orderFn(a: i16, b: i16) std.math.Order {
        return std.math.order(a, b);
    }

    const TreapType = std.Treap(i16, orderFn);

    treap: TreapType = .{},
    config: AllocatorConfig,
    node_count: usize = 0,

    pub fn init(allocator: Allocator) I16TreeSet {
        return .{ .config = AllocatorConfig.init(allocator) };
    }

    pub fn initWithConfig(config: AllocatorConfig) I16TreeSet {
        return .{ .config = config };
    }

    pub fn deinit(self: *I16TreeSet) void {
        destroySubtree(self.treap.root, self.config.keysAllocator());
    }

    fn destroySubtree(node_opt: ?*TreapType.Node, allocator: Allocator) void {
        const node = node_opt orelse return;
        destroySubtree(node.children[0], allocator);
        destroySubtree(node.children[1], allocator);
        allocator.destroy(node);
    }

    pub fn of(allocator: Allocator, values: []const i16) I16TreeSet {
        var set = init(allocator);
        for (values) |val| {
            _ = set.add(val);
        }
        return set;
    }

    /// Adds a value. Returns true if it was not already present.
    pub fn add(self: *I16TreeSet, value: i16) bool {
        var entry = self.treap.getEntryFor(value);
        if (entry.node != null) return false;
        const node = self.config.keysAllocator().create(TreapType.Node) catch @panic("out of memory");
        entry.set(node);
        self.node_count += 1;
        return true;
    }

    /// Removes a value. Returns true if it was present.
    pub fn remove(self: *I16TreeSet, value: i16) bool {
        var entry = self.treap.getEntryFor(value);
        const node = entry.node orelse return false;
        entry.set(null);
        self.config.keysAllocator().destroy(node);
        self.node_count -= 1;
        return true;
    }

    pub fn contains(self: *const I16TreeSet, value: i16) bool {
        var node = self.treap.root;
        while (node) |current| {
            const ord = orderFn(value, current.key);
            if (ord == .eq) return true;
            node = current.children[@intFromBool(ord == .gt)];
        }
        return false;
    }

    pub fn len(self: *const I16TreeSet) usize {
        return self.node_count;
    }

    /// Alias for len() — matches Go/Java naming.
    pub fn size(self: *const I16TreeSet) usize {
        return self.node_count;
    }

    pub fn isEmpty(self: *const I16TreeSet) bool {
        return self.node_count == 0;
    }

    pub fn clear(self: *I16TreeSet) void {
        destroySubtree(self.treap.root, self.config.keysAllocator());
        self.treap.root = null;
        self.node_count = 0;
    }

    // ---- Fallible capacity reservation ----

    /// Probes that the allocator can serve `additional` node allocations.
    /// Returns `error.OutOfMemory` if the allocator fails.
    pub fn ensureUnusedCapacity(self: *I16TreeSet, additional: usize) Allocator.Error!void {
        const probe = try self.config.keysAllocator().alloc(TreapType.Node, additional);
        self.config.keysAllocator().free(probe);
    }

    /// Probes that the allocator can serve enough nodes for `new_capacity`
    /// total elements.
    pub fn ensureTotalCapacity(self: *I16TreeSet, new_capacity: usize) Allocator.Error!void {
        if (new_capacity <= self.node_count) return;
        try self.ensureUnusedCapacity(new_capacity - self.node_count);
    }

    pub fn min(self: *const I16TreeSet) ?i16 {
        const node = self.treap.getMin() orelse return null;
        return node.key;
    }

    pub fn max(self: *const I16TreeSet) ?i16 {
        const node = self.treap.getMax() orelse return null;
        return node.key;
    }

    /// Returns all values in sorted order. Caller must free the returned slice.
    pub fn toSlice(self: *const I16TreeSet, allocator: Allocator) []i16 {
        var result = std.ArrayListUnmanaged(i16){};
        result.ensureTotalCapacity(allocator, self.node_count) catch @panic("out of memory");
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            result.appendAssumeCapacity(node.key);
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    // ---- Iteration ----

    pub fn forEach(self: *const I16TreeSet, f: *const fn (i16) void) void {
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| f(node.key);
    }

    // ---- Functional Operations ----

    pub fn select(self: *const I16TreeSet, predicate: *const fn (i16) bool) I16TreeSet {
        var result = init(self.config.base);
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (predicate(node.key)) _ = result.add(node.key);
        }
        return result;
    }

    pub fn reject(self: *const I16TreeSet, predicate: *const fn (i16) bool) I16TreeSet {
        var result = init(self.config.base);
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (!predicate(node.key)) _ = result.add(node.key);
        }
        return result;
    }

    pub fn detect(self: *const I16TreeSet, predicate: *const fn (i16) bool) ?i16 {
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (predicate(node.key)) return node.key;
        }
        return null;
    }

    pub fn anySatisfy(self: *const I16TreeSet, predicate: *const fn (i16) bool) bool {
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (predicate(node.key)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const I16TreeSet, predicate: *const fn (i16) bool) bool {
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (!predicate(node.key)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const I16TreeSet, predicate: *const fn (i16) bool) bool {
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (predicate(node.key)) return false;
        }
        return true;
    }

    pub fn count(self: *const I16TreeSet, predicate: *const fn (i16) bool) usize {
        var c: usize = 0;
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (predicate(node.key)) c += 1;
        }
        return c;
    }

    // ---- Set Operations ----

    pub fn setUnion(self: *const I16TreeSet, other: *const I16TreeSet) I16TreeSet {
        var result = init(self.config.base);
        var it1 = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it1.next()) |node| _ = result.add(node.key);
        var it2 = TreapType.InorderIterator{ .current = other.treap.getMin() };
        while (it2.next()) |node| _ = result.add(node.key);
        return result;
    }

    pub fn intersect(self: *const I16TreeSet, other: *const I16TreeSet) I16TreeSet {
        var result = init(self.config.base);
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (other.contains(node.key)) _ = result.add(node.key);
        }
        return result;
    }

    pub fn difference(self: *const I16TreeSet, other: *const I16TreeSet) I16TreeSet {
        var result = init(self.config.base);
        var it = TreapType.InorderIterator{ .current = self.treap.getMin() };
        while (it.next()) |node| {
            if (!other.contains(node.key)) _ = result.add(node.key);
        }
        return result;
    }

    // ---- Range Operations ----

    /// Returns the node for the smallest element >= value, or null.
    fn ceilingNode(self: *const I16TreeSet, value: i16) ?*TreapType.Node {
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
    pub fn ceiling(self: *const I16TreeSet, value: i16) ?i16 {
        const node = self.ceilingNode(value) orelse return null;
        return node.key;
    }

    /// Returns the largest element <= value, or null if none.
    pub fn floor(self: *const I16TreeSet, value: i16) ?i16 {
        var node = self.treap.root;
        var best: ?i16 = null;
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
    pub fn rangeValues(self: *const I16TreeSet, from: i16, to: i16, allocator: Allocator) []i16 {
        var result = std.ArrayListUnmanaged(i16){};
        var it = TreapType.InorderIterator{ .current = self.ceilingNode(from) };
        while (it.next()) |node| {
            if (orderFn(node.key, to) == .gt) break;
            result.append(allocator, node.key) catch @panic("out of memory");
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    // ---- Formatting ----

    /// Formats as "{v1, v2, v3}" in sorted order.
    pub fn format(self: *const I16TreeSet, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn with(self: *I16TreeSet, value: i16) *I16TreeSet {
        _ = self.add(value);
        return self;
    }

    pub fn without(self: *I16TreeSet, value: i16) *I16TreeSet {
        _ = self.remove(value);
        return self;
    }

    // ---- Equality ----

    pub fn eql(self: *const I16TreeSet, other: *const I16TreeSet) bool {
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

test "I16TreeSet: add and contains" {
    var set = I16TreeSet.init(std.testing.allocator);
    defer set.deinit();
    _ = set.add(1);
    _ = set.add(2);
    _ = set.add(3);
    try std.testing.expectEqual(@as(usize, 3), set.len());
    try std.testing.expect(set.contains(2));
    try std.testing.expect(!set.contains(99));
}

test "I16TreeSet: duplicate" {
    var set = I16TreeSet.init(std.testing.allocator);
    defer set.deinit();
    try std.testing.expect(set.add(1));
    try std.testing.expect(!set.add(1));
    try std.testing.expectEqual(@as(usize, 1), set.len());
}

test "I16TreeSet: sorted iteration" {
    var set = I16TreeSet.of(std.testing.allocator, &[_]i16{ 3, 1, 2 });
    defer set.deinit();
    const items = set.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(items);
    try std.testing.expectEqual(1, items[0]);
    try std.testing.expectEqual(2, items[1]);
    try std.testing.expectEqual(3, items[2]);
}

test "I16TreeSet: min max" {
    var set = I16TreeSet.of(std.testing.allocator, &[_]i16{ 3, 1, 2 });
    defer set.deinit();
    try std.testing.expectEqual(@as(?i16, 1), set.min());
    try std.testing.expectEqual(@as(?i16, 3), set.max());
}

test "I16TreeSet: remove" {
    var set = I16TreeSet.of(std.testing.allocator, &[_]i16{ 1, 2 });
    defer set.deinit();
    try std.testing.expect(set.remove(1));
    try std.testing.expect(!set.contains(1));
}

test "I16TreeSet: union" {
    var a = I16TreeSet.of(std.testing.allocator, &[_]i16{ 1, 2 });
    defer a.deinit();
    var b = I16TreeSet.of(std.testing.allocator, &[_]i16{ 2, 3 });
    defer b.deinit();
    var u = a.setUnion(&b);
    defer u.deinit();
    try std.testing.expectEqual(@as(usize, 3), u.len());
}

test "I16TreeSet: intersect" {
    var a = I16TreeSet.of(std.testing.allocator, &[_]i16{ 1, 2 });
    defer a.deinit();
    var b = I16TreeSet.of(std.testing.allocator, &[_]i16{ 2, 3 });
    defer b.deinit();
    var inter = a.intersect(&b);
    defer inter.deinit();
    try std.testing.expectEqual(@as(usize, 1), inter.len());
}

test "I16TreeSet: ensureUnusedCapacity probes allocator" {
    var set = I16TreeSet.init(std.testing.allocator);
    defer set.deinit();
    try set.ensureUnusedCapacity(100);
    _ = set.add(1);
    _ = set.add(2);
    try std.testing.expectEqual(@as(usize, 2), set.len());
}

test "I16TreeSet: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: TreeSet.init doesn't allocate (Treap is node-based),
    // so the first alloc (ensureUnusedCapacity grow) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var set = I16TreeSet.init(failing.allocator());
    defer set.deinit();
    try std.testing.expectError(error.OutOfMemory, set.ensureUnusedCapacity(1024));
}
