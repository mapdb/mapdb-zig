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
        pub fn put(self: *Self, key: K, value: V) ?V {
            const result = self.inner.fetchPut(self.allocator, key, value) catch @panic("out of memory");
            if (result) |kv| return kv.value;
            return null;
        }

        pub fn get(self: *const Self, key: K) ?V {
            return self.inner.get(key);
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
        pub fn keysToSlice(self: *const Self, allocator: Allocator) []K {
            const keys = self.inner.keys();
            const slice = allocator.alloc(K, keys.len) catch @panic("out of memory");
            @memcpy(slice, keys);
            return slice;
        }

        /// Returns values in insertion order.
        pub fn valuesToSlice(self: *const Self, allocator: Allocator) []V {
            const values = self.inner.values();
            const slice = allocator.alloc(V, values.len) catch @panic("out of memory");
            @memcpy(slice, values);
            return slice;
        }

        pub fn forEach(self: *const Self, f: *const fn (K, V) void) void {
            const keys = self.inner.keys();
            const values = self.inner.values();
            for (keys, values) |k, v| {
                f(k, v);
            }
        }

        pub fn anySatisfy(self: *const Self, predicate: *const fn (K, V) bool) bool {
            const keys = self.inner.keys();
            const values = self.inner.values();
            for (keys, values) |k, v| {
                if (predicate(k, v)) return true;
            }
            return false;
        }

        pub fn allSatisfy(self: *const Self, predicate: *const fn (K, V) bool) bool {
            const keys = self.inner.keys();
            const values = self.inner.values();
            for (keys, values) |k, v| {
                if (!predicate(k, v)) return false;
            }
            return true;
        }

        pub fn noneSatisfy(self: *const Self, predicate: *const fn (K, V) bool) bool {
            const keys = self.inner.keys();
            const values = self.inner.values();
            for (keys, values) |k, v| {
                if (predicate(k, v)) return false;
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

    try std.testing.expectEqual(@as(?[]const u8, null), map.put(1, "one"));
    try std.testing.expectEqual(@as(?[]const u8, null), map.put(2, "two"));

    try std.testing.expectEqual(@as(usize, 2), map.len());
    try std.testing.expect(map.containsKey(1));
    try std.testing.expect(!map.containsKey(99));
}

test "LinkedHashMap put replaces" {
    const allocator = std.testing.allocator;
    var map = LinkedHashMap(i32, i32).init(allocator);
    defer map.deinit();

    _ = map.put(1, 10);
    const old = map.put(1, 20);
    try std.testing.expectEqual(@as(?i32, 10), old);
    try std.testing.expectEqual(@as(?i32, 20), map.get(1));
}

test "LinkedHashMap insertion order" {
    const allocator = std.testing.allocator;
    var map = LinkedHashMap(i32, i32).init(allocator);
    defer map.deinit();

    _ = map.put(3, 30);
    _ = map.put(1, 10);
    _ = map.put(2, 20);

    const keys = map.keysToSlice(allocator);
    defer allocator.free(keys);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 3, 1, 2 }, keys);

    const values = map.valuesToSlice(allocator);
    defer allocator.free(values);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 30, 10, 20 }, values);
}

test "LinkedHashMap remove preserves order" {
    const allocator = std.testing.allocator;
    var map = LinkedHashMap(i32, i32).init(allocator);
    defer map.deinit();

    _ = map.put(1, 10);
    _ = map.put(2, 20);
    _ = map.put(3, 30);

    const removed = map.remove(2);
    try std.testing.expectEqual(@as(?i32, 20), removed);

    const keys = map.keysToSlice(allocator);
    defer allocator.free(keys);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 3 }, keys);
}

test "LinkedHashMap clear" {
    const allocator = std.testing.allocator;
    var map = LinkedHashMap(i32, i32).init(allocator);
    defer map.deinit();

    _ = map.put(1, 1);
    map.clear();
    try std.testing.expect(map.isEmpty());
}

test "LinkedHashMap anySatisfy allSatisfy noneSatisfy" {
    const allocator = std.testing.allocator;
    var map = LinkedHashMap(i32, i32).init(allocator);
    defer map.deinit();

    _ = map.put(1, 2);
    _ = map.put(2, 4);

    const valEven = struct {
        fn f(_: i32, v: i32) bool {
            return @rem(v, 2) == 0;
        }
    }.f;
    const valNeg = struct {
        fn f(_: i32, v: i32) bool {
            return v < 0;
        }
    }.f;

    try std.testing.expect(map.allSatisfy(&valEven));
    try std.testing.expect(map.anySatisfy(&valEven));
    try std.testing.expect(map.noneSatisfy(&valNeg));
}
