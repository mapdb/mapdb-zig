// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Sorted set backed by a red-black tree with a pluggable comparator.
//!
//! Equality is defined by the comparator (`cmp(a, b) == .eq`), not by
//! built-in equality on `T`. A case-insensitive comparator produces a
//! case-insensitive sorted set. See `strategy.zig` for comparator
//! builders.

const std = @import("std");
const Allocator = std.mem.Allocator;
const strategy = @import("strategy.zig");
const treemap_mod = @import("treemap.zig");

/// Sorted set backed by `TreeMap(T, void)`.
///
/// Elements are maintained in the order defined by the comparator. All
/// operations are O(log n). Call `deinit` to free the backing tree.
///
/// Example:
///
///     var s = TreeSet([]const u8).init(allocator, strategy.naturalComparator([]const u8));
///     defer s.deinit();
///     _ = s.add("banana");
///     _ = s.add("apple");
///     _ = s.add("cherry");
///     // Iteration order: "apple", "banana", "cherry".
pub fn TreeSet(comptime T: type) type {
    return struct {
        const Self = @This();
        const Map = treemap_mod.TreeMap(T, void);

        inner: Map,

        pub fn init(allocator: Allocator, comparator: strategy.Comparator(T)) Self {
            return .{ .inner = Map.init(allocator, comparator) };
        }

        pub fn deinit(self: *Self) void {
            self.inner.deinit();
        }

        /// Add an element. Returns true if it was newly inserted, false if already present.
        pub fn add(self: *Self, value: T) bool {
            const old = self.inner.put(value, {});
            return old == null;
        }

        /// Remove an element. Returns true if it was present.
        pub fn remove(self: *Self, value: T) bool {
            const old = self.inner.remove(value);
            // old is ?void — if non-null, the key was present
            return old != null;
        }

        pub fn contains(self: *const Self, value: T) bool {
            return self.inner.containsKey(value);
        }

        pub fn len(self: *const Self) usize {
            return self.inner.len();
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.inner.isEmpty();
        }

        pub fn clear(self: *Self) void {
            self.inner.clear();
        }

        /// Returns the smallest element.
        pub fn min(self: *const Self) ?T {
            const m = self.inner.min() orelse return null;
            return m.key;
        }

        /// Returns the largest element.
        pub fn max(self: *const Self) ?T {
            const m = self.inner.max() orelse return null;
            return m.key;
        }

        pub fn forEach(self: *const Self, f: *const fn (T) void) void {
            const wrapper = struct {
                var func: *const fn (T) void = undefined;
                fn call(k: T, _: void) void {
                    func(k);
                }
            };
            wrapper.func = f;
            self.inner.forEach(&wrapper.call);
        }

        /// Pull-based iterator yielding each element by value in ascending
        /// (in-order) sorted order. Non-allocating: delegates to the backing
        /// `TreeMap`'s parent-pointer in-order iterator (no recursion, no heap).
        /// The iterator borrows the set; do not mutate while iterating.
        pub const Iterator = struct {
            inner: Map.Iterator,

            pub fn next(self: *Iterator) ?T {
                const entry = self.inner.next() orelse return null;
                return entry.key;
            }
        };

        /// Returns a pull-based iterator over the elements in ascending sorted
        /// order. Non-allocating.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .inner = self.inner.iterator() };
        }

        pub fn toSlice(self: *const Self, allocator: Allocator) []T {
            return self.inner.keysToSlice(allocator);
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const strat = @import("strategy.zig");

test "TreeSet basic add/contains" {
    const allocator = std.testing.allocator;
    var set = TreeSet(i32).init(allocator, strat.naturalComparator(i32));
    defer set.deinit();

    try std.testing.expect(set.add(3));
    try std.testing.expect(set.add(1));
    try std.testing.expect(set.add(2));
    try std.testing.expect(!set.add(1)); // duplicate

    try std.testing.expectEqual(@as(usize, 3), set.len());
    try std.testing.expect(set.contains(1));
    try std.testing.expect(set.contains(2));
    try std.testing.expect(set.contains(3));
    try std.testing.expect(!set.contains(99));
}

test "TreeSet sorted order via toSlice" {
    const allocator = std.testing.allocator;
    var set = TreeSet(i32).init(allocator, strat.naturalComparator(i32));
    defer set.deinit();

    _ = set.add(3);
    _ = set.add(1);
    _ = set.add(2);

    const slice = set.toSlice(allocator);
    defer allocator.free(slice);

    try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 2, 3 }, slice);
}

test "TreeSet remove" {
    const allocator = std.testing.allocator;
    var set = TreeSet(i32).init(allocator, strat.naturalComparator(i32));
    defer set.deinit();

    _ = set.add(1);
    _ = set.add(2);
    _ = set.add(3);

    try std.testing.expect(set.remove(2));
    try std.testing.expect(!set.remove(99));
    try std.testing.expectEqual(@as(usize, 2), set.len());
    try std.testing.expect(!set.contains(2));
}

test "TreeSet min/max" {
    const allocator = std.testing.allocator;
    var set = TreeSet(i32).init(allocator, strat.naturalComparator(i32));
    defer set.deinit();

    _ = set.add(5);
    _ = set.add(1);
    _ = set.add(9);

    try std.testing.expectEqual(@as(?i32, 1), set.min());
    try std.testing.expectEqual(@as(?i32, 9), set.max());
}

test "TreeSet clear and isEmpty" {
    const allocator = std.testing.allocator;
    var set = TreeSet(i32).init(allocator, strat.naturalComparator(i32));
    defer set.deinit();

    _ = set.add(1);
    try std.testing.expect(!set.isEmpty());
    set.clear();
    try std.testing.expect(set.isEmpty());
}

test "TreeSet stress insert 1000 remove half" {
    const allocator = std.testing.allocator;
    var set = TreeSet(i32).init(allocator, strat.naturalComparator(i32));
    defer set.deinit();

    var i: i32 = 0;
    while (i < 1000) : (i += 1) {
        _ = set.add(i);
    }
    try std.testing.expectEqual(@as(usize, 1000), set.len());

    // Remove even values
    i = 0;
    while (i < 1000) : (i += 2) {
        _ = set.remove(i);
    }
    try std.testing.expectEqual(@as(usize, 500), set.len());

    // Verify remaining are odd and sorted
    const slice = set.toSlice(allocator);
    defer allocator.free(slice);

    try std.testing.expectEqual(@as(usize, 500), slice.len);
    for (slice, 0..) |v, idx| {
        const expected: i32 = @intCast(idx * 2 + 1);
        try std.testing.expectEqual(expected, v);
    }
}
