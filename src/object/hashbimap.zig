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
        pub fn put(self: *Self, key: K, value: V) Allocator.Error!?V {
            // Reserve capacity up front so that the method is infallible past
            // this point. A mid-operation allocation failure would otherwise
            // corrupt the bijection (F1): the removals below fire first, and a
            // failing `forward.put`/`inverse.put` afterwards would leave the two
            // indexes disagreeing. `ensureUnusedCapacity` never shrinks and the
            // removals only free slots, so one reserved slot per map covers the
            // worst case (both key and value are new). If either reservation
            // fails, nothing has been mutated yet — the bimap is untouched.
            try self.forward.ensureUnusedCapacity(self.allocator, 1);
            try self.inverse.ensureUnusedCapacity(self.allocator, 1);

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

            self.forward.putAssumeCapacity(key, value);
            self.inverse.putAssumeCapacity(value, key);

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
        ///
        /// No `mutIterator()` is provided for bi-maps (deliberate exclusion):
        /// a bi-map value IS a key in the inverse index, so mutating a value in
        /// place would leave the inverse index pointing at a stale key and break
        /// the bijection. Use `put` (which maintains both directions) instead.
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

    try std.testing.expectEqual(@as(?i32, null), try bimap.put(1, 10));
    try std.testing.expectEqual(@as(?i32, null), try bimap.put(2, 20));

    try std.testing.expectEqual(@as(usize, 2), bimap.len());
    try std.testing.expect(bimap.containsKey(1));
    try std.testing.expect(bimap.containsValue(10));
}

test "HashBiMap get and getInverse" {
    const allocator = std.testing.allocator;
    var bimap = HashBiMap(i32, i32).init(allocator);
    defer bimap.deinit();

    _ = try bimap.put(1, 100);
    _ = try bimap.put(2, 200);

    try std.testing.expectEqual(@as(?i32, 100), bimap.get(1));
    try std.testing.expectEqual(@as(?i32, 1), bimap.getInverse(100));
    try std.testing.expectEqual(@as(?i32, null), bimap.get(99));
    try std.testing.expectEqual(@as(?i32, null), bimap.getInverse(999));
}

test "HashBiMap bijection enforcement" {
    const allocator = std.testing.allocator;
    var bimap = HashBiMap(i32, i32).init(allocator);
    defer bimap.deinit();

    _ = try bimap.put(1, 100);
    _ = try bimap.put(2, 200);

    // Reassign value 100 to key 2 — key 1 should be removed
    _ = try bimap.put(2, 100);

    try std.testing.expectEqual(@as(usize, 1), bimap.len());
    try std.testing.expect(!bimap.containsKey(1));
    try std.testing.expectEqual(@as(?i32, 100), bimap.get(2));
    try std.testing.expectEqual(@as(?i32, 2), bimap.getInverse(100));
}

test "HashBiMap put replaces old value" {
    const allocator = std.testing.allocator;
    var bimap = HashBiMap(i32, i32).init(allocator);
    defer bimap.deinit();

    _ = try bimap.put(1, 10);
    const old = try bimap.put(1, 20);
    try std.testing.expectEqual(@as(?i32, 10), old);
    try std.testing.expectEqual(@as(?i32, 20), bimap.get(1));
    try std.testing.expect(!bimap.containsValue(10));
}

test "HashBiMap remove and removeInverse" {
    const allocator = std.testing.allocator;
    var bimap = HashBiMap(i32, i32).init(allocator);
    defer bimap.deinit();

    _ = try bimap.put(1, 100);
    _ = try bimap.put(2, 200);

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

    _ = try bimap.put(1, 10);
    bimap.clear();
    try std.testing.expect(bimap.isEmpty());
}

/// Assert the bimap's core invariant: forward and inverse have equal size and
/// every forward `k -> v` has a matching inverse `v -> k`.
fn expectBijection(bimap: *const HashBiMap(i32, i32)) !void {
    try std.testing.expectEqual(bimap.forward.count(), bimap.inverse.count());
    var it = bimap.forward.iterator();
    while (it.next()) |e| {
        const k = e.key_ptr.*;
        const v = e.value_ptr.*;
        try std.testing.expectEqual(@as(?i32, k), bimap.inverse.get(v));
    }
}

test "HashBiMap put preserves bijection under OOM (F1)" {
    // Sweep FailingAllocator fail_index: at every allocation-failure point the
    // bimap must remain a valid bijection with no leaks (testing.allocator
    // backs the FailingAllocator, so a leak fails the test).
    var fail_index: usize = 0;
    while (fail_index < 64) : (fail_index += 1) {
        var failing = std.testing.FailingAllocator.init(
            std.testing.allocator,
            .{ .fail_index = fail_index },
        );
        var bimap = HashBiMap(i32, i32).init(failing.allocator());
        defer bimap.deinit();

        // Best-effort setup; some puts may fail at low fail indices.
        _ = bimap.put(1, 10) catch {};
        _ = bimap.put(2, 20) catch {};
        try expectBijection(&bimap);

        // The operation under test: reassign value 20 to key 1 (removes key 2
        // and key 1's old value 10). Whether it succeeds or fails with OOM, the
        // bijection invariant must hold.
        _ = bimap.put(1, 20) catch |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            try expectBijection(&bimap);
            continue;
        };
        try expectBijection(&bimap);
        // On success the reassignment is complete: key 2 and value 10 are gone.
        try std.testing.expect(!bimap.containsKey(2));
        try std.testing.expect(!bimap.containsValue(10));
        try std.testing.expectEqual(@as(?i32, 20), bimap.get(1));
    }
}
