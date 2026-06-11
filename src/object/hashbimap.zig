// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn HashBiMap(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const Forward = std.AutoHashMapUnmanaged(K, V);
        const Inverse = std.AutoHashMapUnmanaged(V, K);

        forward: Forward,
        inverse: Inverse,
        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            return .{
                .forward = .{},
                .inverse = .{},
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.forward.deinit(self.allocator);
            self.inverse.deinit(self.allocator);
        }

        /// Put a key-value pair, enforcing bijection.
        /// If the key already maps to a different value, the old value's inverse
        /// mapping is removed. If the value already maps to a different key, the
        /// old key's forward mapping is removed.
        /// Returns the previous value associated with the key, if any.
        pub fn put(self: *Self, key: K, value: V) ?V {
            // Remove any existing mapping for this value (bijection enforcement)
            if (self.inverse.get(value)) |existing_key| {
                _ = self.forward.fetchRemove(existing_key);
                _ = self.inverse.fetchRemove(value);
            }

            // Remove old inverse mapping if key already existed
            var old_value: ?V = null;
            if (self.forward.get(key)) |existing_value| {
                old_value = existing_value;
                _ = self.inverse.fetchRemove(existing_value);
            }

            self.forward.put(self.allocator, key, value) catch @panic("out of memory");
            self.inverse.put(self.allocator, value, key) catch @panic("out of memory");

            return old_value;
        }

        pub fn get(self: *const Self, key: K) ?V {
            return self.forward.get(key);
        }

        pub fn getInverse(self: *const Self, value: V) ?K {
            return self.inverse.get(value);
        }

        pub fn containsKey(self: *const Self, key: K) bool {
            return self.forward.contains(key);
        }

        pub fn containsValue(self: *const Self, value: V) bool {
            return self.inverse.contains(value);
        }

        /// Remove by key. Returns the value that was mapped.
        pub fn remove(self: *Self, key: K) ?V {
            const result = self.forward.fetchRemove(key) orelse return null;
            _ = self.inverse.fetchRemove(result.value);
            return result.value;
        }

        /// Remove by value. Returns the key that was mapped.
        pub fn removeInverse(self: *Self, value: V) ?K {
            const result = self.inverse.fetchRemove(value) orelse return null;
            _ = self.forward.fetchRemove(result.value);
            return result.value;
        }

        pub fn len(self: *const Self) usize {
            return self.forward.count();
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.forward.count() == 0;
        }

        pub fn clear(self: *Self) void {
            self.forward.clearRetainingCapacity();
            self.inverse.clearRetainingCapacity();
        }

        pub fn forEach(self: *const Self, f: *const fn (K, V) void) void {
            var it = self.forward.iterator();
            while (it.next()) |entry| {
                f(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        /// An entry yielded by `Iterator` — key and value by value.
        pub const IterEntry = struct { key: K, value: V };

        /// Pull-based iterator yielding `{ key, value }` (forward) entries in
        /// arbitrary (hash-table) order. Non-allocating: wraps the forward
        /// `AutoHashMapUnmanaged` entry iterator. The iterator borrows the bimap;
        /// do not mutate while iterating.
        pub const Iterator = struct {
            inner: Forward.Iterator,

            pub fn next(self: *Iterator) ?IterEntry {
                const entry = self.inner.next() orelse return null;
                return .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* };
            }
        };

        /// Returns a pull-based iterator over `{ key, value }` (forward) entries
        /// in arbitrary order. Non-allocating.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .inner = self.forward.iterator() };
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "HashBiMap basic" {
    const allocator = std.testing.allocator;
    var bimap = HashBiMap(i32, i32).init(allocator);
    defer bimap.deinit();

    try std.testing.expectEqual(@as(?i32, null), bimap.put(1, 10));
    try std.testing.expectEqual(@as(?i32, null), bimap.put(2, 20));

    try std.testing.expectEqual(@as(usize, 2), bimap.len());
    try std.testing.expect(bimap.containsKey(1));
    try std.testing.expect(bimap.containsValue(10));
}

test "HashBiMap get and getInverse" {
    const allocator = std.testing.allocator;
    var bimap = HashBiMap(i32, i32).init(allocator);
    defer bimap.deinit();

    _ = bimap.put(1, 100);
    _ = bimap.put(2, 200);

    try std.testing.expectEqual(@as(?i32, 100), bimap.get(1));
    try std.testing.expectEqual(@as(?i32, 1), bimap.getInverse(100));
    try std.testing.expectEqual(@as(?i32, null), bimap.get(99));
    try std.testing.expectEqual(@as(?i32, null), bimap.getInverse(999));
}

test "HashBiMap bijection enforcement" {
    const allocator = std.testing.allocator;
    var bimap = HashBiMap(i32, i32).init(allocator);
    defer bimap.deinit();

    _ = bimap.put(1, 100);
    _ = bimap.put(2, 200);

    // Reassign value 100 to key 2 — key 1 should be removed
    _ = bimap.put(2, 100);

    try std.testing.expectEqual(@as(usize, 1), bimap.len());
    try std.testing.expect(!bimap.containsKey(1));
    try std.testing.expectEqual(@as(?i32, 100), bimap.get(2));
    try std.testing.expectEqual(@as(?i32, 2), bimap.getInverse(100));
}

test "HashBiMap put replaces old value" {
    const allocator = std.testing.allocator;
    var bimap = HashBiMap(i32, i32).init(allocator);
    defer bimap.deinit();

    _ = bimap.put(1, 10);
    const old = bimap.put(1, 20);
    try std.testing.expectEqual(@as(?i32, 10), old);
    try std.testing.expectEqual(@as(?i32, 20), bimap.get(1));
    try std.testing.expect(!bimap.containsValue(10));
}

test "HashBiMap remove and removeInverse" {
    const allocator = std.testing.allocator;
    var bimap = HashBiMap(i32, i32).init(allocator);
    defer bimap.deinit();

    _ = bimap.put(1, 100);
    _ = bimap.put(2, 200);

    const removed = bimap.remove(1);
    try std.testing.expectEqual(@as(?i32, 100), removed);
    try std.testing.expect(!bimap.containsValue(100));

    const removed_inv = bimap.removeInverse(200);
    try std.testing.expectEqual(@as(?i32, 2), removed_inv);
    try std.testing.expect(bimap.isEmpty());
}

test "HashBiMap clear" {
    const allocator = std.testing.allocator;
    var bimap = HashBiMap(i32, i32).init(allocator);
    defer bimap.deinit();

    _ = bimap.put(1, 10);
    bimap.clear();
    try std.testing.expect(bimap.isEmpty());
}
