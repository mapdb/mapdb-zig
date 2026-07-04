// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn HashMap(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const Map = std.AutoHashMapUnmanaged(K, V);

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
        /// Unlike `get` (a shallow copy — a *read*), this aliases the stored
        /// value so it can be mutated in place. Invalidated by any structural
        /// mutation (put/remove/clear/deinit, including rehash). Never free
        /// through this pointer — the map still owns the value.
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
            const result = self.inner.fetchRemove(key);
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

        /// An entry yielded by `Iterator` — key and value by value.
        pub const IterEntry = struct { key: K, value: V };

        /// Pull-based iterator yielding `{ key, value }` entries in arbitrary
        /// (hash-table) order. Non-allocating: wraps the backing
        /// `AutoHashMapUnmanaged` entry iterator. The iterator borrows the map;
        /// do not mutate while iterating.
        pub const Iterator = struct {
            inner: Map.Iterator,

            pub fn next(self: *Iterator) ?IterEntry {
                const entry = self.inner.next() orelse return null;
                return .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* };
            }
        };

        /// Returns a pull-based iterator over `{ key, value }` entries in
        /// arbitrary order. Non-allocating.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .inner = self.inner.iterator() };
        }

        /// An entry yielded by `MutIterator` — the key by value, the value as a
        /// `*V` pointer. The KEY is yielded by value on purpose: mutating a key
        /// in place would change its hash/slot and silently corrupt the table.
        pub const MutEntry = struct { key: K, value_ptr: *V };

        /// Pull-based MUTABLE iterator yielding `{ key, value_ptr }` in
        /// arbitrary order, so callers can mutate VALUES in place through
        /// `value_ptr`. Non-allocating: wraps the backing `AutoHashMapUnmanaged`
        /// iterator (whose entries already expose a `*V`). Safe surface: the
        /// value is not part of the hash/slot computation. Same invalidation
        /// contract as `iterator()`: STRUCTURAL mutation during iteration is
        /// illegal. `iterator()` remains the canonical immutable iterator.
        pub const MutIterator = struct {
            inner: Map.Iterator,

            pub fn next(self: *MutIterator) ?MutEntry {
                const entry = self.inner.next() orelse return null;
                return .{ .key = entry.key_ptr.*, .value_ptr = entry.value_ptr };
            }
        };

        /// Returns a pull-based mutable iterator yielding `{ key, value_ptr }`
        /// entries in arbitrary order (additive; see `MutIterator`).
        /// Non-allocating.
        pub fn mutIterator(self: *Self) MutIterator {
            return .{ .inner = self.inner.iterator() };
        }

        pub fn keysToSlice(self: *const Self, allocator: Allocator) Allocator.Error![]K {
            const slice = try allocator.alloc(K, self.inner.count());
            var it = self.inner.iterator();
            var i: usize = 0;
            while (it.next()) |entry| {
                slice[i] = entry.key_ptr.*;
                i += 1;
            }
            return slice;
        }

        pub fn valuesToSlice(self: *const Self, allocator: Allocator) Allocator.Error![]V {
            const slice = try allocator.alloc(V, self.inner.count());
            var it = self.inner.iterator();
            var i: usize = 0;
            while (it.next()) |entry| {
                slice[i] = entry.value_ptr.*;
                i += 1;
            }
            return slice;
        }

        pub fn anySatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, K, V) bool) bool {
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                if (predicate(ctx, entry.key_ptr.*, entry.value_ptr.*)) return true;
            }
            return false;
        }

        pub fn allSatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, K, V) bool) bool {
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                if (!predicate(ctx, entry.key_ptr.*, entry.value_ptr.*)) return false;
            }
            return true;
        }

        pub fn noneSatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, K, V) bool) bool {
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                if (predicate(ctx, entry.key_ptr.*, entry.value_ptr.*)) return false;
            }
            return true;
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "HashMap basic" {
    const allocator = std.testing.allocator;
    var map = HashMap(i32, []const u8).init(allocator);
    defer map.deinit();

    try std.testing.expectEqual(@as(?[]const u8, null), try map.put(1, "one"));
    try std.testing.expectEqual(@as(?[]const u8, null), try map.put(2, "two"));

    try std.testing.expectEqual(@as(usize, 2), map.len());
    try std.testing.expect(map.containsKey(1));
    try std.testing.expect(!map.containsKey(99));
}

test "HashMap put replaces" {
    const allocator = std.testing.allocator;
    var map = HashMap(i32, i32).init(allocator);
    defer map.deinit();

    _ = try map.put(1, 10);
    const old = try map.put(1, 20);
    try std.testing.expectEqual(@as(?i32, 10), old);
    try std.testing.expectEqual(@as(?i32, 20), map.get(1));
}

test "HashMap remove" {
    const allocator = std.testing.allocator;
    var map = HashMap(i32, i32).init(allocator);
    defer map.deinit();

    _ = try map.put(1, 10);
    const removed = map.remove(1);
    try std.testing.expectEqual(@as(?i32, 10), removed);
    try std.testing.expectEqual(@as(?i32, null), map.remove(1));
    try std.testing.expect(map.isEmpty());
}

test "HashMap keysToSlice valuesToSlice" {
    const allocator = std.testing.allocator;
    var map = HashMap(i32, i32).init(allocator);
    defer map.deinit();

    _ = try map.put(1, 10);
    _ = try map.put(2, 20);

    const keys = try map.keysToSlice(allocator);
    defer allocator.free(keys);
    const values = try map.valuesToSlice(allocator);
    defer allocator.free(values);

    try std.testing.expectEqual(@as(usize, 2), keys.len);
    try std.testing.expectEqual(@as(usize, 2), values.len);
}

test "HashMap anySatisfy allSatisfy noneSatisfy" {
    const allocator = std.testing.allocator;
    var map = HashMap(i32, i32).init(allocator);
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

test "HashMap clear" {
    const allocator = std.testing.allocator;
    var map = HashMap(i32, i32).init(allocator);
    defer map.deinit();

    _ = try map.put(1, 1);
    map.clear();
    try std.testing.expect(map.isEmpty());
}
