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
const Range = @import("../range.zig").Range;

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
            /// Number of nodes in the subtree rooted here (this node plus both
            /// children's subtrees). Maintained in O(1) on every structural
            /// change — insert, remove, and all rotations — so the
            /// order-statistic `rank`/`select` run in O(log n). Invariant after
            /// any operation: `size == 1 + size(left) + size(right)`.
            size: usize = 1,
        };

        /// Subtree size of a node link (0 if null).
        fn nodeSize(n: ?*Node) usize {
            const node = n orelse return 0;
            return node.size;
        }

        /// Recompute a node's cached subtree size from its children. Called after
        /// any rotation or child relinking so the augmentation stays consistent.
        fn fixSize(n: *Node) void {
            n.size = 1 + nodeSize(n.left) + nodeSize(n.right);
        }

        root: ?*Node,
        size: usize,
        cmp: Cmp,
        allocator: Allocator,

        pub fn init(allocator: Allocator, cmp: Cmp) Self {
            return .{
                .root = null,
                .size = 0,
                .cmp = cmp,
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
        pub fn put(self: *Self, key: K, value: V) Allocator.Error!?V {
            if (self.root == null) {
                const n = try self.allocator.create(Node);
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
                            const n = try self.allocator.create(Node);
                            n.* = .{ .key = key, .value = value, .parent = current };
                            current.left = n;
                            incSizeToRoot(current);
                            self.fixAfterInsert(n);
                            self.size += 1;
                            return null;
                        }
                    },
                    .gt => {
                        if (current.right) |right| {
                            current = right;
                        } else {
                            const n = try self.allocator.create(Node);
                            n.* = .{ .key = key, .value = value, .parent = current };
                            current.right = n;
                            incSizeToRoot(current);
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

        /// Borrowed pointer to the value still owned by the map, or null.
        /// Aliases the stored value for in-place mutation (unlike the shallow
        /// copy from `get`). Invalidated by any structural mutation
        /// (put/remove/clear/deinit). Never free through this pointer.
        /// (Node storage keeps the pointee address stable across unrelated
        /// inserts/rotations, but do not rely on that — the documented contract
        /// is "invalidated by any structural mutation", uniform with the hash
        /// maps, so the implementation stays free to change.)
        pub fn getPtr(self: *Self, key: K) ?*V {
            const n = self.findNode(key) orelse return null;
            return &n.value;
        }

        /// Const borrowed pointer to the value still owned by the map, or null.
        /// Same invalidation rules as `getPtr`; read-only.
        pub fn getConstPtr(self: *const Self, key: K) ?*const V {
            const n = self.findNode(key) orelse return null;
            return &n.value;
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

        /// Returns a copy of this map's comparator. Used to preserve ordering
        /// semantics when building a materialized snapshot (`subMap`).
        pub fn comparator(self: *const Self) Cmp {
            return self.cmp;
        }

        // ---- NavigableMap surface ----
        //
        // Point navigation, poll, Range-based slice/descending iteration and
        // removeRange on the comparator-bearing red-black tree. Mirrors the
        // codex-approved Rust reference (mapdb-rust/src/object/treemap.rs) and
        // the spec (spec/features/navigable-map.md). All comparisons go through
        // the map's comparator, so reverse/custom/float-total ordering carries
        // through exactly as in-order iteration does. Strictness: floor `<= k`,
        // ceiling `>= k`, lower `< k` (strict), higher `> k` (strict). Range
        // membership is EXACTLY `range.contains(key)`.

        /// Which side of `k` a point-navigation query selects.
        const Bound = enum { floor, ceiling, lower, higher };

        /// An entry: the same `{ key, value }` shape `min`/`max` return.
        pub const Entry = struct { key: K, value: V };

        /// Shared walk for the four point-navigation queries: descend the tree
        /// tracking the best candidate seen on the relevant side.
        fn boundNode(self: *const Self, k: K, bound: Bound) ?*Node {
            var current = self.root;
            var best: ?*Node = null;
            while (current) |n| {
                const ord = self.cmp(k, n.key);
                const take = switch (bound) {
                    .floor => ord != .lt, // n.key <= k
                    .lower => ord == .gt, // n.key <  k
                    .ceiling => ord != .gt, // n.key >= k
                    .higher => ord == .lt, // n.key >  k
                };
                if (take) {
                    best = n;
                    current = switch (bound) {
                        .floor, .lower => n.right,
                        .ceiling, .higher => n.left,
                    };
                } else {
                    current = switch (bound) {
                        .floor, .lower => n.left,
                        .ceiling, .higher => n.right,
                    };
                }
            }
            return best;
        }

        fn boundEntry(self: *const Self, k: K, bound: Bound) ?Entry {
            const n = self.boundNode(k, bound) orelse return null;
            return .{ .key = n.key, .value = n.value };
        }

        /// Greatest key `<= k` and its value, or null.
        pub fn floorEntry(self: *const Self, k: K) ?Entry {
            return self.boundEntry(k, .floor);
        }

        /// Greatest key `<= k`, or null.
        pub fn floorKey(self: *const Self, k: K) ?K {
            const e = self.floorEntry(k) orelse return null;
            return e.key;
        }

        /// Least key `>= k` and its value, or null.
        pub fn ceilingEntry(self: *const Self, k: K) ?Entry {
            return self.boundEntry(k, .ceiling);
        }

        /// Least key `>= k`, or null.
        pub fn ceilingKey(self: *const Self, k: K) ?K {
            const e = self.ceilingEntry(k) orelse return null;
            return e.key;
        }

        /// Greatest key `< k` (strict) and its value, or null.
        pub fn lowerEntry(self: *const Self, k: K) ?Entry {
            return self.boundEntry(k, .lower);
        }

        /// Greatest key `< k` (strict), or null.
        pub fn lowerKey(self: *const Self, k: K) ?K {
            const e = self.lowerEntry(k) orelse return null;
            return e.key;
        }

        /// Least key `> k` (strict) and its value, or null.
        pub fn higherEntry(self: *const Self, k: K) ?Entry {
            return self.boundEntry(k, .higher);
        }

        /// Least key `> k` (strict), or null.
        pub fn higherKey(self: *const Self, k: K) ?K {
            const e = self.higherEntry(k) orelse return null;
            return e.key;
        }

        // ── Order statistics (rank / select) ────────────────────────────
        //
        // Backed by the per-node subtree-size augmentation; both run in
        // O(log n) on the balanced tree. Comparisons go through the map's
        // comparator, so the order is exactly the in-order traversal order
        // (reverse/custom/float-total ordering carries through).

        /// Returns the number of keys strictly less than `key` under the map's
        /// comparator — the 0-based lower-bound index the key occupies (if
        /// present) or would occupy (if absent). Defined for present and absent
        /// keys alike; the result is in `0..=len()` (`len()` for any key greater
        /// than the maximum). Pure query; never mutates.
        pub fn rank(self: *const Self, key: K) usize {
            var r: usize = 0;
            var current = self.root;
            while (current) |n| {
                switch (self.cmp(key, n.key)) {
                    // key < n.key: n and its right subtree are >= key; descend
                    // left without counting.
                    .lt => current = n.left,
                    // key > n.key: n and its whole left subtree are strictly
                    // less than key; count them, then descend right.
                    .gt => {
                        r += 1 + nodeSize(n.left);
                        current = n.right;
                    },
                    // key == n.key: exactly the left subtree is strictly less.
                    .eq => return r + nodeSize(n.left),
                }
            }
            return r;
        }

        /// Walks to the node at 0-based sorted index `i`, or null if out of
        /// range. The subtree-size augmentation makes this O(log n).
        fn selectNode(self: *const Self, i: usize) ?*Node {
            var idx = i;
            var current = self.root;
            while (current) |n| {
                const left = nodeSize(n.left);
                if (idx < left) {
                    current = n.left;
                } else if (idx == left) {
                    return n;
                } else {
                    // Skip the left subtree and this node.
                    idx -= left + 1;
                    current = n.right;
                }
            }
            return null;
        }

        /// Returns the `i`-th smallest key (0-based), or null if `i >= len()`.
        /// `i == len()` (and any larger index, including on an empty map) is
        /// absence, not a trap. Round-trips with `rank`:
        /// `selectKey(rank(k)) == k` for any present `k`, and
        /// `rank(selectKey(i)) == i` for every `0 <= i < len()`.
        pub fn selectKey(self: *const Self, i: usize) ?K {
            const n = self.selectNode(i) orelse return null;
            return n.key;
        }

        /// Returns the `i`-th smallest `{ key, value }` entry (0-based), or null
        /// if `i >= len()`. Same index domain as `selectKey`.
        pub fn selectEntry(self: *const Self, i: usize) ?Entry {
            const n = self.selectNode(i) orelse return null;
            return .{ .key = n.key, .value = n.value };
        }

        /// Test-only: verifies the subtree-size invariant at every node and that
        /// the root total equals `len()`. Returns the recomputed total.
        fn checkSizeInvariant(node: ?*Node) usize {
            const n = node orelse return 0;
            const l = checkSizeInvariant(n.left);
            const r = checkSizeInvariant(n.right);
            std.debug.assert(n.size == 1 + l + r);
            return n.size;
        }

        /// Test-only helper asserting the whole-tree size invariant.
        pub fn assertSizeInvariant(self: *const Self) void {
            std.debug.assert(checkSizeInvariant(self.root) == self.size);
        }

        /// Minimum entry, or null. Alias for `min`.
        pub fn firstEntry(self: *const Self) ?Entry {
            const m = self.min() orelse return null;
            return .{ .key = m.key, .value = m.value };
        }

        /// Minimum key, or null.
        pub fn firstKey(self: *const Self) ?K {
            const m = self.min() orelse return null;
            return m.key;
        }

        /// Maximum entry, or null. Alias for `max`.
        pub fn lastEntry(self: *const Self) ?Entry {
            const m = self.max() orelse return null;
            return .{ .key = m.key, .value = m.value };
        }

        /// Maximum key, or null.
        pub fn lastKey(self: *const Self) ?K {
            const m = self.max() orelse return null;
            return m.key;
        }

        /// Removes and returns the minimum entry, or null if empty. Does not
        /// trap on an empty map.
        pub fn pollFirstEntry(self: *Self) ?Entry {
            const r = self.root orelse return null;
            const n = minNode(r);
            const e = Entry{ .key = n.key, .value = n.value };
            self.deleteNode(n);
            self.size -= 1;
            return e;
        }

        /// Removes and returns the maximum entry, or null if empty. Does not
        /// trap on an empty map.
        pub fn pollLastEntry(self: *Self) ?Entry {
            const r = self.root orelse return null;
            const n = maxNode(r);
            const e = Entry{ .key = n.key, .value = n.value };
            self.deleteNode(n);
            self.size -= 1;
            return e;
        }

        /// Keys whose key ∈ `range`, ascending. Caller owns the slice.
        pub fn rangeKeysIn(self: *const Self, range: Range(K), allocator: Allocator) Allocator.Error![]K {
            var out = std.ArrayListUnmanaged(K){};
            errdefer out.deinit(allocator);
            var it = self.iterator();
            while (it.next()) |e| {
                if (range.contains(e.key)) try out.append(allocator, e.key);
            }
            return out.toOwnedSlice(allocator);
        }

        /// `{ key, value }` entries whose key ∈ `range`, ascending. Caller owns.
        pub fn rangeEntriesIn(self: *const Self, range: Range(K), allocator: Allocator) Allocator.Error![]Entry {
            var out = std.ArrayListUnmanaged(Entry){};
            errdefer out.deinit(allocator);
            var it = self.iterator();
            while (it.next()) |e| {
                if (range.contains(e.key)) try out.append(allocator, .{ .key = e.key, .value = e.value });
            }
            return out.toOwnedSlice(allocator);
        }

        /// Keys whose key ∈ `range`, descending. Caller owns the slice.
        pub fn descendingRangeKeys(self: *const Self, range: Range(K), allocator: Allocator) Allocator.Error![]K {
            const asc = try self.rangeKeysIn(range, allocator);
            std.mem.reverse(K, asc);
            return asc;
        }

        /// `{ key, value }` entries whose key ∈ `range`, descending. Caller owns.
        pub fn descendingRangeEntries(self: *const Self, range: Range(K), allocator: Allocator) Allocator.Error![]Entry {
            const asc = try self.rangeEntriesIn(range, allocator);
            std.mem.reverse(Entry, asc);
            return asc;
        }

        /// All keys, descending. Caller owns the slice.
        pub fn descendingKeys(self: *const Self, allocator: Allocator) Allocator.Error![]K {
            const out = try allocator.alloc(K, self.size);
            var it = self.iterator();
            var i: usize = self.size;
            while (it.next()) |e| {
                i -= 1;
                out[i] = e.key;
            }
            return out;
        }

        /// All `{ key, value }` entries, descending. Caller owns the slice.
        pub fn descendingEntries(self: *const Self, allocator: Allocator) Allocator.Error![]Entry {
            const out = try allocator.alloc(Entry, self.size);
            var it = self.iterator();
            var i: usize = self.size;
            while (it.next()) |e| {
                i -= 1;
                out[i] = .{ .key = e.key, .value = e.value };
            }
            return out;
        }

        /// A new INDEPENDENT map of the entries whose key ∈ `range`
        /// (materialized snapshot — not a live view). Mutating the snapshot
        /// never affects the original and vice versa. The snapshot PRESERVES the
        /// source map's comparator, so reverse/custom/float-total-order keyed
        /// maps keep their ordering semantics in the slice. Caller owns the
        /// returned map and must `deinit` it.
        pub fn subMap(self: *const Self, range: Range(K), allocator: Allocator) Allocator.Error!Self {
            var out = init(allocator, self.cmp);
            errdefer out.deinit();
            var it = self.iterator();
            while (it.next()) |e| {
                if (range.contains(e.key)) _ = try out.put(e.key, e.value);
            }
            return out;
        }

        /// Removes every entry whose key ∈ `range`; returns the count removed.
        /// A range that matches nothing is a no-op returning 0.
        pub fn removeRange(self: *Self, range: Range(K), allocator: Allocator) Allocator.Error!usize {
            var victims = std.ArrayListUnmanaged(K){};
            defer victims.deinit(allocator);
            var it = self.iterator();
            while (it.next()) |e| {
                if (range.contains(e.key)) try victims.append(allocator, e.key);
            }
            for (victims.items) |k| _ = self.remove(k);
            return victims.items.len;
        }

        pub fn forEach(self: *const Self, context: anytype, comptime f: fn (@TypeOf(context), K, V) void) void {
            self.inOrder(self.root, context, f);
        }

        fn inOrder(self: *const Self, node: ?*Node, context: anytype, comptime f: fn (@TypeOf(context), K, V) void) void {
            const n = node orelse return;
            self.inOrder(n.left, context, f);
            f(context, n.key, n.value);
            self.inOrder(n.right, context, f);
        }

        /// An entry yielded by `Iterator` — key and value by value.
        pub const IterEntry = struct { key: K, value: V };

        /// Pull-based iterator yielding `{ key, value }` entries in ascending
        /// (in-order) sorted key order. Non-allocating: performs a classic
        /// parent-pointer in-order traversal (leftmost node, then repeatedly the
        /// in-order successor) over the red-black tree's `left`/`right`/`parent`
        /// links — no recursion stack, no heap. The iterator borrows the map; do
        /// not mutate while iterating.
        pub const Iterator = struct {
            current: ?*Node,

            fn leftmost(node: *Node) *Node {
                var n = node;
                while (n.left) |l| n = l;
                return n;
            }

            pub fn next(self: *Iterator) ?IterEntry {
                const node = self.current orelse return null;
                const entry = IterEntry{ .key = node.key, .value = node.value };
                // Advance to the in-order successor.
                if (node.right) |r| {
                    self.current = leftmost(r);
                } else {
                    var n = node;
                    var p = n.parent;
                    while (p != null and n == p.?.right) {
                        n = p.?;
                        p = n.parent;
                    }
                    self.current = p;
                }
                return entry;
            }
        };

        /// Returns a pull-based iterator over `{ key, value }` entries in
        /// ascending sorted key order. Non-allocating.
        pub fn iterator(self: *const Self) Iterator {
            const start = if (self.root) |r| minNode(r) else null;
            return .{ .current = start };
        }

        /// An entry yielded by `MutIterator` — the key by value, the value as a
        /// `*V` pointer. The KEY is yielded by value on purpose: mutating a key
        /// in place would break the sorted-key ordering invariant.
        pub const MutEntry = struct { key: K, value_ptr: *V };

        /// Pull-based MUTABLE iterator yielding `{ key, value_ptr }` in
        /// ascending sorted key order, so callers can mutate VALUES in place
        /// through `value_ptr`. Non-allocating: the same parent-pointer
        /// in-order traversal as `Iterator`, returning `&node.value`. Safe
        /// surface: the value is not part of the ordering key. Same
        /// invalidation contract as `iterator()`: STRUCTURAL mutation during
        /// iteration is illegal. `iterator()` remains the canonical immutable
        /// iterator.
        pub const MutIterator = struct {
            current: ?*Node,

            fn leftmost(node: *Node) *Node {
                var n = node;
                while (n.left) |l| n = l;
                return n;
            }

            pub fn next(self: *MutIterator) ?MutEntry {
                const node = self.current orelse return null;
                const entry = MutEntry{ .key = node.key, .value_ptr = &node.value };
                // Advance to the in-order successor.
                if (node.right) |r| {
                    self.current = leftmost(r);
                } else {
                    var n = node;
                    var p = n.parent;
                    while (p != null and n == p.?.right) {
                        n = p.?;
                        p = n.parent;
                    }
                    self.current = p;
                }
                return entry;
            }
        };

        /// Returns a pull-based mutable iterator yielding `{ key, value_ptr }`
        /// entries in ascending sorted key order (additive; see `MutIterator`).
        /// Non-allocating.
        pub fn mutIterator(self: *Self) MutIterator {
            const start = if (self.root) |r| minNode(r) else null;
            return .{ .current = start };
        }

        pub fn keysToSlice(self: *const Self, allocator: Allocator) Allocator.Error![]K {
            const slice = try allocator.alloc(K, self.size);
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

        pub fn valuesToSlice(self: *const Self, allocator: Allocator) Allocator.Error![]V {
            const slice = try allocator.alloc(V, self.size);
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
            // `r` took `n`'s former position, so it inherits `n`'s old subtree
            // size; recompute bottom-up — the demoted `n` first (now `r`'s left
            // child), then the promoted `r`.
            fixSize(n);
            fixSize(r);
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
            // Symmetric to rotateLeft: recompute the demoted `n`, then the
            // promoted `l`.
            fixSize(n);
            fixSize(l);
        }

        /// Walks from `n` up to the root, bumping each ancestor's cached subtree
        /// size by one after a new leaf was linked below `n`.
        fn incSizeToRoot(start: ?*Node) void {
            var n = start;
            while (n) |node| : (n = node.parent) node.size += 1;
        }

        /// Walks from `n` up to the root recomputing each node's cached subtree
        /// size from its children. Used after a delete splice — the rotations
        /// inside `fixAfterDelete` already maintain their own sizes.
        fn fixSizeToRoot(start: ?*Node) void {
            var n = start;
            while (n) |node| : (n = node.parent) fixSize(node);
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
            // `n` is the node physically spliced out. `fix_size_from` is the
            // lowest surviving node whose cached subtree size must be refreshed;
            // recomputing that path to the root once the structure is final
            // restores the invariant. Rotations inside `fixAfterDelete` maintain
            // their own sizes and everything below `fix_size_from` stays consistent.
            var fix_size_from: ?*Node = null;
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
                fix_size_from = c;
                if (n.color == .black) {
                    self.fixAfterDelete(c);
                }
            } else if (n.parent == null) {
                self.root = null;
            } else {
                if (n.color == .black) {
                    self.fixAfterDelete(n);
                }
                // fixAfterDelete may have rotated `n` to a new parent; read it now.
                fix_size_from = n.parent;
                if (n.parent) |p| {
                    if (n == p.left) {
                        p.left = null;
                    } else {
                        p.right = null;
                    }
                }
            }
            fixSizeToRoot(fix_size_from);
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

    _ = try map.put(1, 10);
    const old = map.put(1, 20);
    try std.testing.expectEqual(@as(?i32, 10), old);
    try std.testing.expectEqual(@as(?i32, 20), map.get(1));
    try std.testing.expectEqual(@as(usize, 1), map.len());
}

test "TreeMap remove" {
    const allocator = std.testing.allocator;
    var map = TreeMap(i32, i32).init(allocator, strat.naturalComparator(i32));
    defer map.deinit();

    _ = try map.put(1, 10);
    _ = try map.put(2, 20);
    _ = try map.put(3, 30);

    const removed = map.remove(2);
    try std.testing.expectEqual(@as(?i32, 20), removed);
    try std.testing.expectEqual(@as(usize, 2), map.len());
    try std.testing.expectEqual(@as(?i32, null), map.remove(99));
}

test "TreeMap containsKey" {
    const allocator = std.testing.allocator;
    var map = TreeMap(i32, i32).init(allocator, strat.naturalComparator(i32));
    defer map.deinit();

    _ = try map.put(5, 50);
    try std.testing.expect(map.containsKey(5));
    try std.testing.expect(!map.containsKey(6));
}

test "TreeMap min/max" {
    const allocator = std.testing.allocator;
    var map = TreeMap(i32, i32).init(allocator, strat.naturalComparator(i32));
    defer map.deinit();

    _ = try map.put(5, 50);
    _ = try map.put(1, 10);
    _ = try map.put(9, 90);

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

    _ = try map.put(3, 30);
    _ = try map.put(1, 10);
    _ = try map.put(2, 20);

    const keys = try map.keysToSlice(allocator);
    defer allocator.free(keys);

    try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 2, 3 }, keys);
}

test "TreeMap reverse comparator" {
    const allocator = std.testing.allocator;
    var map = TreeMap(i32, i32).init(allocator, strat.reverseComparator(i32));
    defer map.deinit();

    _ = try map.put(1, 10);
    _ = try map.put(3, 30);
    _ = try map.put(2, 20);

    const keys = try map.keysToSlice(allocator);
    defer allocator.free(keys);

    try std.testing.expectEqualSlices(i32, &[_]i32{ 3, 2, 1 }, keys);
}

test "TreeMap clear and isEmpty" {
    const allocator = std.testing.allocator;
    var map = TreeMap(i32, i32).init(allocator, strat.naturalComparator(i32));
    defer map.deinit();

    _ = try map.put(1, 10);
    _ = try map.put(2, 20);
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
        _ = try map.put(i, i * 10);
    }
    try std.testing.expectEqual(@as(usize, 1000), map.len());

    // Remove even keys
    i = 0;
    while (i < 1000) : (i += 2) {
        _ = map.remove(i);
    }
    try std.testing.expectEqual(@as(usize, 500), map.len());

    // Verify remaining are odd and sorted
    const keys = try map.keysToSlice(allocator);
    defer allocator.free(keys);

    try std.testing.expectEqual(@as(usize, 500), keys.len);
    for (keys, 0..) |k, idx| {
        const expected: i32 = @intCast(idx * 2 + 1);
        try std.testing.expectEqual(expected, k);
    }
}

// ---------------------------------------------------------------------------
// NavigableMap surface (comparator-bearing tree).
// ---------------------------------------------------------------------------

const ObjRange = Range(i32);

fn objMapOf(allocator: Allocator, keys: []const i32) !TreeMap(i32, i32) {
    var m = TreeMap(i32, i32).init(allocator, strat.naturalComparator(i32));
    for (keys) |k| _ = try m.put(k, k *% 10);
    return m;
}

test "object.TreeMap nav: floor/ceiling/lower/higher + entry + first/last" {
    const allocator = std.testing.allocator;
    var m = try objMapOf(allocator, &.{ 10, 20, 30 });
    defer m.deinit();
    try std.testing.expectEqual(@as(?i32, 20), m.floorKey(25));
    try std.testing.expectEqual(@as(?i32, 30), m.ceilingKey(25));
    try std.testing.expectEqual(@as(?i32, 10), m.floorKey(10));
    try std.testing.expectEqual(@as(?i32, null), m.lowerKey(10));
    try std.testing.expectEqual(@as(?i32, null), m.higherKey(30));
    try std.testing.expectEqual(@as(?i32, 10), m.ceilingKey(5));
    try std.testing.expectEqual(@as(?i32, 20), m.lowerKey(25));
    try std.testing.expectEqual(@as(?i32, 30), m.higherKey(25));
    try std.testing.expectEqual(@as(i32, 200), m.floorEntry(25).?.value);
    try std.testing.expectEqual(@as(?i32, 10), m.firstKey());
    try std.testing.expectEqual(@as(?i32, 30), m.lastKey());
}

test "object.TreeMap nav: empty returns absence" {
    const allocator = std.testing.allocator;
    var m = try objMapOf(allocator, &.{});
    defer m.deinit();
    try std.testing.expectEqual(@as(?i32, null), m.floorKey(5));
    try std.testing.expectEqual(@as(?i32, null), m.higherKey(5));
    try std.testing.expectEqual(@as(?i32, null), m.firstKey());
    try std.testing.expect(m.pollFirstEntry() == null);
    try std.testing.expect(m.pollLastEntry() == null);
}

test "object.TreeMap nav: signed extremes + descending" {
    const allocator = std.testing.allocator;
    var m = try objMapOf(allocator, &.{ std.math.minInt(i32), -1, 0, 1, std.math.maxInt(i32) });
    defer m.deinit();
    try std.testing.expectEqual(@as(?i32, std.math.minInt(i32)), m.floorKey(std.math.minInt(i32)));
    try std.testing.expectEqual(@as(?i32, null), m.lowerKey(std.math.minInt(i32)));
    try std.testing.expectEqual(@as(?i32, 0), m.higherKey(-1));
    try std.testing.expectEqual(@as(?i32, null), m.higherKey(std.math.maxInt(i32)));
    const desc = try m.descendingKeys(allocator);
    defer allocator.free(desc);
    try std.testing.expectEqualSlices(i32, &.{ std.math.maxInt(i32), 1, 0, -1, std.math.minInt(i32) }, desc);
}

test "object.TreeMap poll: first/last then empty" {
    const allocator = std.testing.allocator;
    var m = try objMapOf(allocator, &.{ 10, 20, 30 });
    defer m.deinit();
    try std.testing.expectEqual(@as(i32, 10), m.pollFirstEntry().?.key);
    try std.testing.expectEqual(@as(i32, 30), m.pollLastEntry().?.key);
    try std.testing.expectEqual(@as(i32, 20), m.pollFirstEntry().?.key);
    try std.testing.expect(m.pollFirstEntry() == null);
}

test "object.TreeMap range/removeRange + open(1,2) empty" {
    const allocator = std.testing.allocator;
    var m = try objMapOf(allocator, &.{ 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 });
    defer m.deinit();
    const rk = try m.rangeKeysIn(ObjRange.closedOpen(30, 70), allocator);
    defer allocator.free(rk);
    try std.testing.expectEqualSlices(i32, &.{ 30, 40, 50, 60 }, rk);
    var m2 = try objMapOf(allocator, &.{ 1, 2 });
    defer m2.deinit();
    const empty = try m2.rangeKeysIn(ObjRange.open(1, 2), allocator);
    defer allocator.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
    try std.testing.expectEqual(@as(usize, 4), try m.removeRange(ObjRange.closedOpen(30, 70), allocator));
    try std.testing.expectEqual(@as(usize, 0), try m.removeRange(ObjRange.closedOpen(30, 70), allocator));
}

test "object.TreeMap subMap: preserves reverse comparator + snapshot independence" {
    const allocator = std.testing.allocator;
    // Reverse comparator: source iterates descending.
    var m = TreeMap(i32, i32).init(allocator, strat.reverseComparator(i32));
    defer m.deinit();
    for ([_]i32{ 10, 20, 30, 40, 50 }) |k| _ = try m.put(k, k * 10);
    const src_keys = try m.keysToSlice(allocator);
    defer allocator.free(src_keys);
    try std.testing.expectEqualSlices(i32, &.{ 50, 40, 30, 20, 10 }, src_keys);
    // subMap of {20,30,40} must ALSO be reverse-ordered, proving the comparator
    // carried into the snapshot (not reset to natural order).
    var sub = try m.subMap(ObjRange.closedOpen(20, 50), allocator);
    defer sub.deinit();
    const sub_keys = try sub.keysToSlice(allocator);
    defer allocator.free(sub_keys);
    try std.testing.expectEqualSlices(i32, &.{ 40, 30, 20 }, sub_keys);
    // Independence: mutate snapshot, original unchanged; and vice versa.
    _ = try sub.put(99, 990);
    _ = sub.remove(20);
    try std.testing.expect(m.containsKey(20));
    try std.testing.expect(!m.containsKey(99));
    _ = m.remove(30);
    try std.testing.expect(sub.containsKey(30));
}

// ---------------------------------------------------------------------------
// Order statistics (rank / select).
// ---------------------------------------------------------------------------

test "object.TreeMap rank: present and absent keys" {
    const allocator = std.testing.allocator;
    var m = try objMapOf(allocator, &.{ 10, 20, 30, 40, 50 });
    defer m.deinit();
    // present keys → their 0-based index
    try std.testing.expectEqual(@as(usize, 0), m.rank(10));
    try std.testing.expectEqual(@as(usize, 2), m.rank(30));
    try std.testing.expectEqual(@as(usize, 4), m.rank(50));
    // absent keys → lower-bound index
    try std.testing.expectEqual(@as(usize, 0), m.rank(5)); // before min
    try std.testing.expectEqual(@as(usize, 2), m.rank(25)); // between 20 and 30
    try std.testing.expectEqual(@as(usize, 5), m.rank(55)); // past max → size
    m.assertSizeInvariant();
}

test "object.TreeMap selectKey/selectEntry" {
    const allocator = std.testing.allocator;
    var m = try objMapOf(allocator, &.{ 10, 20, 30, 40, 50 });
    defer m.deinit();
    try std.testing.expectEqual(@as(?i32, 10), m.selectKey(0));
    try std.testing.expectEqual(@as(?i32, 30), m.selectKey(2));
    try std.testing.expectEqual(@as(?i32, 50), m.selectKey(4));
    try std.testing.expectEqual(@as(?i32, null), m.selectKey(5)); // == size
    try std.testing.expectEqual(@as(?i32, null), m.selectKey(999));
    // entry form carries value = key*10
    try std.testing.expectEqual(@as(i32, 10), m.selectEntry(0).?.key);
    try std.testing.expectEqual(@as(i32, 100), m.selectEntry(0).?.value);
    try std.testing.expectEqual(@as(i32, 300), m.selectEntry(2).?.value);
    try std.testing.expect(m.selectEntry(5) == null);
}

test "object.TreeMap rank/select: empty and single" {
    const allocator = std.testing.allocator;
    var empty = try objMapOf(allocator, &.{});
    defer empty.deinit();
    try std.testing.expectEqual(@as(usize, 0), empty.rank(5));
    try std.testing.expectEqual(@as(?i32, null), empty.selectKey(0));

    var single = try objMapOf(allocator, &.{});
    defer single.deinit();
    _ = try single.put(7, 70);
    try std.testing.expectEqual(@as(usize, 0), single.rank(6));
    try std.testing.expectEqual(@as(usize, 0), single.rank(7));
    try std.testing.expectEqual(@as(usize, 1), single.rank(8));
    try std.testing.expectEqual(@as(?i32, 7), single.selectKey(0));
    try std.testing.expectEqual(@as(i32, 70), single.selectEntry(0).?.value);
    try std.testing.expectEqual(@as(?i32, null), single.selectKey(1));
}

test "object.TreeMap rank/select: signed extremes" {
    const allocator = std.testing.allocator;
    var m = try objMapOf(allocator, &.{ std.math.minInt(i32), -1, 0, 1, std.math.maxInt(i32) });
    defer m.deinit();
    try std.testing.expectEqual(@as(usize, 0), m.rank(std.math.minInt(i32)));
    try std.testing.expectEqual(@as(usize, 2), m.rank(0));
    try std.testing.expectEqual(@as(usize, 4), m.rank(std.math.maxInt(i32)));
    try std.testing.expectEqual(@as(?i32, std.math.minInt(i32)), m.selectKey(0));
    try std.testing.expectEqual(@as(?i32, std.math.maxInt(i32)), m.selectKey(4));
    try std.testing.expectEqual(@as(?i32, null), m.selectKey(5));
}

test "object.TreeMap rank/select: stable after remove" {
    const allocator = std.testing.allocator;
    var m = try objMapOf(allocator, &.{ 10, 20, 30, 40, 50 });
    defer m.deinit();
    try std.testing.expectEqual(@as(?i32, 300), m.remove(30));
    // stale subtree sizes after a remove/transplant would corrupt these
    try std.testing.expectEqual(@as(usize, 2), m.rank(40));
    try std.testing.expectEqual(@as(usize, 2), m.rank(35));
    try std.testing.expectEqual(@as(?i32, 40), m.selectKey(2));
    try std.testing.expectEqual(@as(?i32, null), m.selectKey(4));
    m.assertSizeInvariant();
}

test "object.TreeMap round-trip select(rank(k))==k and rank(select(i))==i" {
    const allocator = std.testing.allocator;
    var m = try objMapOf(allocator, &.{ 10, 20, 30, 40, 50, -7, 0, 99 });
    defer m.deinit();
    const keys = try m.keysToSlice(allocator);
    defer allocator.free(keys);
    for (keys) |k| {
        try std.testing.expectEqual(@as(?i32, k), m.selectKey(m.rank(k)));
    }
    var i: usize = 0;
    while (i < m.len()) : (i += 1) {
        const k = m.selectKey(i).?;
        try std.testing.expectEqual(i, m.rank(k));
    }
    try std.testing.expectEqual(@as(?i32, null), m.selectKey(m.len()));
}

test "object.TreeMap rank/select: follows reverse comparator" {
    const allocator = std.testing.allocator;
    var m = TreeMap(i32, i32).init(allocator, strat.reverseComparator(i32));
    defer m.deinit();
    for ([_]i32{ 10, 20, 30, 40, 50 }) |k| _ = try m.put(k, k * 10);
    // Under reverse order the 0-th element is the largest natural key.
    try std.testing.expectEqual(@as(?i32, 50), m.selectKey(0));
    try std.testing.expectEqual(@as(?i32, 10), m.selectKey(4));
    try std.testing.expectEqual(@as(usize, 0), m.rank(50));
    try std.testing.expectEqual(@as(usize, 4), m.rank(10));
    m.assertSizeInvariant();
}

/// Deterministic xorshift mirroring the Rust reference's randomized invariant
/// test, so the seeded churn is reproducible across ports.
fn nextRand(state: *u64) u64 {
    var x = state.*;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    state.* = x;
    return x;
}

test "object.TreeMap subtree-size invariant over randomized insert/remove" {
    const allocator = std.testing.allocator;
    var m = TreeMap(i32, i32).init(allocator, strat.naturalComparator(i32));
    defer m.deinit();
    // Oracle: a sorted set of the present keys, kept via a generic TreeSet.
    var present = std.AutoHashMap(i32, void).init(allocator);
    defer present.deinit();
    var state: u64 = 0x9E37_79B9_7F4A_7C15;
    var iter: usize = 0;
    while (iter < 4000) : (iter += 1) {
        const key: i32 = @intCast(nextRand(&state) % 200);
        if (nextRand(&state) & 1 == 0) {
            _ = try m.put(key, key *% 10);
            try present.put(key, {});
        } else {
            _ = m.remove(key);
            _ = present.remove(key);
        }
        m.assertSizeInvariant();
        try std.testing.expectEqual(present.count(), m.len());
    }
    // After the churn, rank/select must agree with the sorted oracle ordering.
    var sorted = std.ArrayListUnmanaged(i32){};
    defer sorted.deinit(allocator);
    var kit = present.keyIterator();
    while (kit.next()) |k| try sorted.append(allocator, k.*);
    std.mem.sort(i32, sorted.items, {}, std.sort.asc(i32));
    for (sorted.items, 0..) |k, i| {
        try std.testing.expectEqual(i, m.rank(k));
        try std.testing.expectEqual(@as(?i32, k), m.selectKey(i));
    }
    try std.testing.expectEqual(@as(?i32, null), m.selectKey(sorted.items.len));
}
