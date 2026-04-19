// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Sorted map backed by a red-black tree with a pluggable comparator.
//!
//! Equality is defined by the comparator: two keys are considered the
//! same iff `cmp(a, b) == .eq`, regardless of any built-in equality on
//! the key type. This matches Java's `TreeMap` contract and lets you
//! customise identity — e.g. a case-insensitive comparator produces a
//! case-insensitive sorted map.

const std = @import("std");
const Allocator = std.mem.Allocator;
const strategy = @import("strategy.zig");

/// Sorted map backed by a red-black tree.
///
/// Keys are maintained in the order defined by the comparator. All
/// operations are O(log n).
///
/// Heap-allocates nodes via the allocator passed to `init`. Call
/// `deinit` to free all nodes.
///
/// Example:
///
///     var m = TreeMap(i32, []const u8).init(allocator, strategy.naturalComparator(i32));
///     defer m.deinit();
///     _ = m.put(3, "three");
///     _ = m.put(1, "one");
///     _ = m.put(2, "two");
///     // Iteration order: 1→"one", 2→"two", 3→"three".
pub fn TreeMap(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const Cmp = strategy.Comparator(K);

        const Color = enum { red, black };

        const Node = struct {
            key: K,
            value: V,
            left: ?*Node = null,
            right: ?*Node = null,
            parent: ?*Node = null,
            color: Color = .red,
        };

        root: ?*Node,
        size: usize,
        cmp: Cmp,
        allocator: Allocator,

        pub fn init(allocator: Allocator, comparator: Cmp) Self {
            return .{
                .root = null,
                .size = 0,
                .cmp = comparator,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.freeSubtree(self.root);
            self.root = null;
            self.size = 0;
        }

        fn freeSubtree(self: *Self, node: ?*Node) void {
            const n = node orelse return;
            self.freeSubtree(n.left);
            self.freeSubtree(n.right);
            self.allocator.destroy(n);
        }

        /// Put a key-value pair. Returns the old value if the key was already present.
        pub fn put(self: *Self, key: K, value: V) ?V {
            if (self.root == null) {
                const n = self.allocator.create(Node) catch @panic("out of memory");
                n.* = .{ .key = key, .value = value, .color = .black };
                self.root = n;
                self.size += 1;
                return null;
            }
            var current = self.root.?;
            while (true) {
                const ord = self.cmp(key, current.key);
                switch (ord) {
                    .lt => {
                        if (current.left) |left| {
                            current = left;
                        } else {
                            const n = self.allocator.create(Node) catch @panic("out of memory");
                            n.* = .{ .key = key, .value = value, .parent = current };
                            current.left = n;
                            self.fixAfterInsert(n);
                            self.size += 1;
                            return null;
                        }
                    },
                    .gt => {
                        if (current.right) |right| {
                            current = right;
                        } else {
                            const n = self.allocator.create(Node) catch @panic("out of memory");
                            n.* = .{ .key = key, .value = value, .parent = current };
                            current.right = n;
                            self.fixAfterInsert(n);
                            self.size += 1;
                            return null;
                        }
                    },
                    .eq => {
                        const old = current.value;
                        current.value = value;
                        return old;
                    },
                }
            }
        }

        pub fn get(self: *const Self, key: K) ?V {
            const n = self.findNode(key) orelse return null;
            return n.value;
        }

        pub fn containsKey(self: *const Self, key: K) bool {
            return self.findNode(key) != null;
        }

        /// Remove a key. Returns the old value if the key was present.
        pub fn remove(self: *Self, key: K) ?V {
            const n = self.findNode(key) orelse return null;
            const old = n.value;
            self.deleteNode(n);
            self.size -= 1;
            return old;
        }

        pub fn len(self: *const Self) usize {
            return self.size;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.size == 0;
        }

        pub fn clear(self: *Self) void {
            self.freeSubtree(self.root);
            self.root = null;
            self.size = 0;
        }

        /// Returns the smallest key and its value.
        pub fn min(self: *const Self) ?struct { key: K, value: V } {
            const r = self.root orelse return null;
            const n = minNode(r);
            return .{ .key = n.key, .value = n.value };
        }

        /// Returns the largest key and its value.
        pub fn max(self: *const Self) ?struct { key: K, value: V } {
            const r = self.root orelse return null;
            const n = maxNode(r);
            return .{ .key = n.key, .value = n.value };
        }

        pub fn forEach(self: *const Self, f: *const fn (K, V) void) void {
            self.inOrder(self.root, f);
        }

        fn inOrder(self: *const Self, node: ?*Node, f: *const fn (K, V) void) void {
            const n = node orelse return;
            self.inOrder(n.left, f);
            f(n.key, n.value);
            self.inOrder(n.right, f);
        }

        pub fn keysToSlice(self: *const Self, allocator: Allocator) []K {
            const slice = allocator.alloc(K, self.size) catch @panic("out of memory");
            var i: usize = 0;
            self.inOrderCollectKeys(self.root, slice, &i);
            return slice;
        }

        fn inOrderCollectKeys(self: *const Self, node: ?*Node, slice: []K, i: *usize) void {
            const n = node orelse return;
            self.inOrderCollectKeys(n.left, slice, i);
            slice[i.*] = n.key;
            i.* += 1;
            self.inOrderCollectKeys(n.right, slice, i);
        }

        pub fn valuesToSlice(self: *const Self, allocator: Allocator) []V {
            const slice = allocator.alloc(V, self.size) catch @panic("out of memory");
            var i: usize = 0;
            self.inOrderCollectValues(self.root, slice, &i);
            return slice;
        }

        fn inOrderCollectValues(self: *const Self, node: ?*Node, slice: []V, i: *usize) void {
            const n = node orelse return;
            self.inOrderCollectValues(n.left, slice, i);
            slice[i.*] = n.value;
            i.* += 1;
            self.inOrderCollectValues(n.right, slice, i);
        }

        // ── internal: lookup ────────────────────────────────────────────

        fn findNode(self: *const Self, key: K) ?*Node {
            var current = self.root;
            while (current) |n| {
                switch (self.cmp(key, n.key)) {
                    .lt => current = n.left,
                    .gt => current = n.right,
                    .eq => return n,
                }
            }
            return null;
        }

        fn minNode(n: *Node) *Node {
            var current = n;
            while (current.left) |left| {
                current = left;
            }
            return current;
        }

        fn maxNode(n: *Node) *Node {
            var current = n;
            while (current.right) |right| {
                current = right;
            }
            return current;
        }

        // ── internal: red-black tree operations ─────────────────────────

        fn isRed(n: ?*Node) bool {
            const node = n orelse return false;
            return node.color == .red;
        }

        fn rotateLeft(self: *Self, n: *Node) void {
            const r = n.right.?;
            n.right = r.left;
            if (r.left) |rl| {
                rl.parent = n;
            }
            r.parent = n.parent;
            if (n.parent) |p| {
                if (n == p.left) {
                    p.left = r;
                } else {
                    p.right = r;
                }
            } else {
                self.root = r;
            }
            r.left = n;
            n.parent = r;
        }

        fn rotateRight(self: *Self, n: *Node) void {
            const l = n.left.?;
            n.left = l.right;
            if (l.right) |lr| {
                lr.parent = n;
            }
            l.parent = n.parent;
            if (n.parent) |p| {
                if (n == p.right) {
                    p.right = l;
                } else {
                    p.left = l;
                }
            } else {
                self.root = l;
            }
            l.right = n;
            n.parent = l;
        }

        fn fixAfterInsert(self: *Self, node: *Node) void {
            var n = node;
            n.color = .red;
            while (n != self.root.? and n.parent != null and n.parent.?.color == .red) {
                const parent = n.parent.?;
                const grandparent = parent.parent.?;
                if (parent == grandparent.left) {
                    const uncle = grandparent.right;
                    if (isRed(uncle)) {
                        parent.color = .black;
                        uncle.?.color = .black;
                        grandparent.color = .red;
                        n = grandparent;
                    } else {
                        if (n == parent.right) {
                            n = parent;
                            self.rotateLeft(n);
                        }
                        n.parent.?.color = .black;
                        n.parent.?.parent.?.color = .red;
                        self.rotateRight(n.parent.?.parent.?);
                    }
                } else {
                    const uncle = grandparent.left;
                    if (isRed(uncle)) {
                        parent.color = .black;
                        uncle.?.color = .black;
                        grandparent.color = .red;
                        n = grandparent;
                    } else {
                        if (n == parent.left) {
                            n = parent;
                            self.rotateRight(n);
                        }
                        n.parent.?.color = .black;
                        n.parent.?.parent.?.color = .red;
                        self.rotateLeft(n.parent.?.parent.?);
                    }
                }
            }
            self.root.?.color = .black;
        }

        fn deleteNode(self: *Self, node: *Node) void {
            var n = node;
            // If two children, replace with in-order successor
            if (n.left != null and n.right != null) {
                const succ = minNode(n.right.?);
                n.key = succ.key;
                n.value = succ.value;
                n = succ;
            }
            const child: ?*Node = n.left orelse n.right;
            if (child) |c| {
                c.parent = n.parent;
                if (n.parent) |p| {
                    if (n == p.left) {
                        p.left = c;
                    } else {
                        p.right = c;
                    }
                } else {
                    self.root = c;
                }
                if (n.color == .black) {
                    self.fixAfterDelete(c);
                }
            } else if (n.parent == null) {
                self.root = null;
            } else {
                if (n.color == .black) {
                    self.fixAfterDelete(n);
                }
                if (n.parent) |p| {
                    if (n == p.left) {
                        p.left = null;
                    } else {
                        p.right = null;
                    }
                }
            }
            self.allocator.destroy(n);
        }

        fn fixAfterDelete(self: *Self, node: *Node) void {
            var n = node;
            while (n != self.root.? and !isRed(n)) {
                const parent = n.parent orelse break;
                if (n == parent.left) {
                    var sib = parent.right orelse {
                        n = parent;
                        continue;
                    };
                    if (isRed(sib)) {
                        sib.color = .black;
                        parent.color = .red;
                        self.rotateLeft(parent);
                        sib = parent.right orelse {
                            n = parent;
                            continue;
                        };
                    }
                    if (!isRed(sib.left) and !isRed(sib.right)) {
                        sib.color = .red;
                        n = parent;
                    } else {
                        if (!isRed(sib.right)) {
                            if (sib.left) |sl| {
                                sl.color = .black;
                            }
                            sib.color = .red;
                            self.rotateRight(sib);
                            sib = parent.right.?;
                        }
                        sib.color = parent.color;
                        parent.color = .black;
                        if (sib.right) |sr| {
                            sr.color = .black;
                        }
                        self.rotateLeft(parent);
                        n = self.root.?;
                    }
                } else {
                    var sib = parent.left orelse {
                        n = parent;
                        continue;
                    };
                    if (isRed(sib)) {
                        sib.color = .black;
                        parent.color = .red;
                        self.rotateRight(parent);
                        sib = parent.left orelse {
                            n = parent;
                            continue;
                        };
                    }
                    if (!isRed(sib.right) and !isRed(sib.left)) {
                        sib.color = .red;
                        n = parent;
                    } else {
                        if (!isRed(sib.left)) {
                            if (sib.right) |sr| {
                                sr.color = .black;
                            }
                            sib.color = .red;
                            self.rotateLeft(sib);
                            sib = parent.left.?;
                        }
                        sib.color = parent.color;
                        parent.color = .black;
                        if (sib.left) |sl| {
                            sl.color = .black;
                        }
                        self.rotateRight(parent);
                        n = self.root.?;
                    }
                }
            }
            n.color = .black;
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const strat = @import("strategy.zig");

test "TreeMap basic put/get" {
    const allocator = std.testing.allocator;
    var map = TreeMap(i32, []const u8).init(allocator, strat.naturalComparator(i32));
    defer map.deinit();

    try std.testing.expectEqual(@as(?[]const u8, null), map.put(2, "two"));
    try std.testing.expectEqual(@as(?[]const u8, null), map.put(1, "one"));
    try std.testing.expectEqual(@as(?[]const u8, null), map.put(3, "three"));

    try std.testing.expectEqual(@as(usize, 3), map.len());
    try std.testing.expectEqualStrings("one", map.get(1).?);
    try std.testing.expectEqualStrings("two", map.get(2).?);
    try std.testing.expectEqualStrings("three", map.get(3).?);
    try std.testing.expectEqual(@as(?[]const u8, null), map.get(99));
}

test "TreeMap put overwrites" {
    const allocator = std.testing.allocator;
    var map = TreeMap(i32, i32).init(allocator, strat.naturalComparator(i32));
    defer map.deinit();

    _ = map.put(1, 10);
    const old = map.put(1, 20);
    try std.testing.expectEqual(@as(?i32, 10), old);
    try std.testing.expectEqual(@as(?i32, 20), map.get(1));
    try std.testing.expectEqual(@as(usize, 1), map.len());
}

test "TreeMap remove" {
    const allocator = std.testing.allocator;
    var map = TreeMap(i32, i32).init(allocator, strat.naturalComparator(i32));
    defer map.deinit();

    _ = map.put(1, 10);
    _ = map.put(2, 20);
    _ = map.put(3, 30);

    const removed = map.remove(2);
    try std.testing.expectEqual(@as(?i32, 20), removed);
    try std.testing.expectEqual(@as(usize, 2), map.len());
    try std.testing.expectEqual(@as(?i32, null), map.remove(99));
}

test "TreeMap containsKey" {
    const allocator = std.testing.allocator;
    var map = TreeMap(i32, i32).init(allocator, strat.naturalComparator(i32));
    defer map.deinit();

    _ = map.put(5, 50);
    try std.testing.expect(map.containsKey(5));
    try std.testing.expect(!map.containsKey(6));
}

test "TreeMap min/max" {
    const allocator = std.testing.allocator;
    var map = TreeMap(i32, i32).init(allocator, strat.naturalComparator(i32));
    defer map.deinit();

    _ = map.put(5, 50);
    _ = map.put(1, 10);
    _ = map.put(9, 90);

    const m = map.min().?;
    try std.testing.expectEqual(@as(i32, 1), m.key);
    try std.testing.expectEqual(@as(i32, 10), m.value);

    const mx = map.max().?;
    try std.testing.expectEqual(@as(i32, 9), mx.key);
    try std.testing.expectEqual(@as(i32, 90), mx.value);
}

test "TreeMap sorted order via keysToSlice" {
    const allocator = std.testing.allocator;
    var map = TreeMap(i32, i32).init(allocator, strat.naturalComparator(i32));
    defer map.deinit();

    _ = map.put(3, 30);
    _ = map.put(1, 10);
    _ = map.put(2, 20);

    const keys = map.keysToSlice(allocator);
    defer allocator.free(keys);

    try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 2, 3 }, keys);
}

test "TreeMap reverse comparator" {
    const allocator = std.testing.allocator;
    var map = TreeMap(i32, i32).init(allocator, strat.reverseComparator(i32));
    defer map.deinit();

    _ = map.put(1, 10);
    _ = map.put(3, 30);
    _ = map.put(2, 20);

    const keys = map.keysToSlice(allocator);
    defer allocator.free(keys);

    try std.testing.expectEqualSlices(i32, &[_]i32{ 3, 2, 1 }, keys);
}

test "TreeMap clear and isEmpty" {
    const allocator = std.testing.allocator;
    var map = TreeMap(i32, i32).init(allocator, strat.naturalComparator(i32));
    defer map.deinit();

    _ = map.put(1, 10);
    _ = map.put(2, 20);
    try std.testing.expect(!map.isEmpty());

    map.clear();
    try std.testing.expect(map.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), map.len());
}

test "TreeMap stress insert 1000 remove half" {
    const allocator = std.testing.allocator;
    var map = TreeMap(i32, i32).init(allocator, strat.naturalComparator(i32));
    defer map.deinit();

    var i: i32 = 0;
    while (i < 1000) : (i += 1) {
        _ = map.put(i, i * 10);
    }
    try std.testing.expectEqual(@as(usize, 1000), map.len());

    // Remove even keys
    i = 0;
    while (i < 1000) : (i += 2) {
        _ = map.remove(i);
    }
    try std.testing.expectEqual(@as(usize, 500), map.len());

    // Verify remaining are odd and sorted
    const keys = map.keysToSlice(allocator);
    defer allocator.free(keys);

    try std.testing.expectEqual(@as(usize, 500), keys.len);
    for (keys, 0..) |k, idx| {
        const expected: i32 = @intCast(idx * 2 + 1);
        try std.testing.expectEqual(expected, k);
    }
}
