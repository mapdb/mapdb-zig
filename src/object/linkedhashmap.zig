// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Insertion-ordered hash map backed by `std.AutoArrayHashMapUnmanaged`.
/// Iteration follows insertion order.
pub fn LinkedHashMap(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const Map = std.AutoArrayHashMapUnmanaged(K, V);

        inner: Map,
        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            return .{
                .inner = .{},
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.inner.deinit(self.allocator);
        }

        /// Put a key-value pair. Returns the old value if the key was already present.
        pub fn put(self: *Self, key: K, value: V) Allocator.Error!?V {
            const result = try self.inner.fetchPut(self.allocator, key, value);
            if (result) |kv| return kv.value;
            return null;
        }

        pub fn get(self: *const Self, key: K) ?V {
            return self.inner.get(key);
        }

        /// Borrowed pointer to the value still owned by the map, or null.
        /// Aliases the stored value for in-place mutation (unlike the shallow
        /// copy from `get`). Invalidated by any structural mutation
        /// (put/remove/clear/deinit). Never free through this pointer.
        pub fn getPtr(self: *Self, key: K) ?*V {
            return self.inner.getPtr(key);
        }

        /// Const borrowed pointer to the value still owned by the map, or null.
        /// Same invalidation rules as `getPtr`; read-only.
        pub fn getConstPtr(self: *const Self, key: K) ?*const V {
            return self.inner.getPtr(key);
        }

        /// Remove a key. Returns the old value if the key was present.
        pub fn remove(self: *Self, key: K) ?V {
            const result = self.inner.fetchOrderedRemove(key);
            if (result) |kv| return kv.value;
            return null;
        }

        pub fn containsKey(self: *const Self, key: K) bool {
            return self.inner.contains(key);
        }

        pub fn len(self: *const Self) usize {
            return self.inner.count();
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.inner.count() == 0;
        }

        pub fn clear(self: *Self) void {
            self.inner.clearRetainingCapacity();
        }

        /// Returns keys in insertion order.
        pub fn keysToSlice(self: *const Self, allocator: Allocator) Allocator.Error![]K {
            const keys = self.inner.keys();
            const slice = try allocator.alloc(K, keys.len);
            @memcpy(slice, keys);
            return slice;
        }

        /// Returns values in insertion order.
        pub fn valuesToSlice(self: *const Self, allocator: Allocator) Allocator.Error![]V {
            const values = self.inner.values();
            const slice = try allocator.alloc(V, values.len);
            @memcpy(slice, values);
            return slice;
        }

        /// An entry yielded by `Iterator` — key and value by value.
        pub const IterEntry = struct { key: K, value: V };

        /// Pull-based iterator yielding `{ key, value }` entries in insertion
        /// order. Non-allocating: indexes the backing array hash map's parallel
        /// `keys()`/`values()` slices. The iterator borrows the map; do not
        /// mutate while iterating.
        pub const Iterator = struct {
            keys: []const K,
            values: []const V,
            index: usize = 0,

            pub fn next(self: *Iterator) ?IterEntry {
                if (self.index >= self.keys.len) return null;
                const e = IterEntry{ .key = self.keys[self.index], .value = self.values[self.index] };
                self.index += 1;
                return e;
            }
        };

        /// Returns a pull-based iterator over `{ key, value }` entries in
        /// insertion order. Non-allocating.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .keys = self.inner.keys(), .values = self.inner.values() };
        }

        /// An entry yielded by `MutIterator` — the key by value, the value as a
        /// `*V` pointer. The KEY is yielded by value on purpose: mutating a key
        /// in place would change its hash/slot and silently corrupt the table.
        pub const MutEntry = struct { key: K, value_ptr: *V };

        /// Pull-based MUTABLE iterator yielding `{ key, value_ptr }` in
        /// insertion order, so callers can mutate VALUES in place through
        /// `value_ptr`. Non-allocating: indexes the backing array hash map's
        /// parallel `keys()`/`values()` slices. Safe surface: the value is not
        /// part of the hash/slot computation. Same invalidation contract as
        /// `iterator()`: STRUCTURAL mutation during iteration is illegal.
        /// `iterator()` remains the canonical immutable iterator.
        pub const MutIterator = struct {
            keys: []const K,
            values: []V,
            index: usize = 0,

            pub fn next(self: *MutIterator) ?MutEntry {
                if (self.index >= self.keys.len) return null;
                const e = MutEntry{ .key = self.keys[self.index], .value_ptr = &self.values[self.index] };
                self.index += 1;
                return e;
            }
        };

        /// Returns a pull-based mutable iterator yielding `{ key, value_ptr }`
        /// entries in insertion order (additive; see `MutIterator`).
        /// Non-allocating.
        pub fn mutIterator(self: *Self) MutIterator {
            return .{ .keys = self.inner.keys(), .values = self.inner.values() };
        }

        pub fn anySatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, K, V) bool) bool {
            const keys = self.inner.keys();
            const values = self.inner.values();
            for (keys, values) |k, v| {
                if (predicate(ctx, k, v)) return true;
            }
            return false;
        }

        pub fn allSatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, K, V) bool) bool {
            const keys = self.inner.keys();
            const values = self.inner.values();
            for (keys, values) |k, v| {
                if (!predicate(ctx, k, v)) return false;
            }
            return true;
        }

        pub fn noneSatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, K, V) bool) bool {
            const keys = self.inner.keys();
            const values = self.inner.values();
            for (keys, values) |k, v| {
                if (predicate(ctx, k, v)) return false;
            }
            return true;
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "LinkedHashMap basic" {
    const allocator = std.testing.allocator;
    var map = LinkedHashMap(i32, []const u8).init(allocator);
    defer map.deinit();

    try std.testing.expectEqual(@as(?[]const u8, null), try map.put(1, "one"));
    try std.testing.expectEqual(@as(?[]const u8, null), try map.put(2, "two"));

    try std.testing.expectEqual(@as(usize, 2), map.len());
    try std.testing.expect(map.containsKey(1));
    try std.testing.expect(!map.containsKey(99));
}

test "LinkedHashMap put replaces" {
    const allocator = std.testing.allocator;
    var map = LinkedHashMap(i32, i32).init(allocator);
    defer map.deinit();

    _ = try map.put(1, 10);
    const old = try map.put(1, 20);
    try std.testing.expectEqual(@as(?i32, 10), old);
    try std.testing.expectEqual(@as(?i32, 20), map.get(1));
}

test "LinkedHashMap insertion order" {
    const allocator = std.testing.allocator;
    var map = LinkedHashMap(i32, i32).init(allocator);
    defer map.deinit();

    _ = try map.put(3, 30);
    _ = try map.put(1, 10);
    _ = try map.put(2, 20);

    const keys = try map.keysToSlice(allocator);
    defer allocator.free(keys);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 3, 1, 2 }, keys);

    const values = try map.valuesToSlice(allocator);
    defer allocator.free(values);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 30, 10, 20 }, values);
}

test "LinkedHashMap remove preserves order" {
    const allocator = std.testing.allocator;
    var map = LinkedHashMap(i32, i32).init(allocator);
    defer map.deinit();

    _ = try map.put(1, 10);
    _ = try map.put(2, 20);
    _ = try map.put(3, 30);

    const removed = map.remove(2);
    try std.testing.expectEqual(@as(?i32, 20), removed);

    const keys = try map.keysToSlice(allocator);
    defer allocator.free(keys);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 3 }, keys);
}

test "LinkedHashMap clear" {
    const allocator = std.testing.allocator;
    var map = LinkedHashMap(i32, i32).init(allocator);
    defer map.deinit();

    _ = try map.put(1, 1);
    map.clear();
    try std.testing.expect(map.isEmpty());
}

test "LinkedHashMap anySatisfy allSatisfy noneSatisfy" {
    const allocator = std.testing.allocator;
    var map = LinkedHashMap(i32, i32).init(allocator);
    defer map.deinit();

    _ = try map.put(1, 2);
    _ = try map.put(2, 4);

    const valEven = struct {
        fn f(_: *anyopaque, _: i32, v: i32) bool {
            return @rem(v, 2) == 0;
        }
    }.f;
    const valNeg = struct {
        fn f(_: *anyopaque, _: i32, v: i32) bool {
            return v < 0;
        }
    }.f;

    var dummy: u8 = 0;
    const ctx: *anyopaque = &dummy;

    try std.testing.expect(map.allSatisfy(ctx, &valEven));
    try std.testing.expect(map.anySatisfy(ctx, &valEven));
    try std.testing.expect(map.noneSatisfy(ctx, &valNeg));
}
