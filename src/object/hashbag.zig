// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn HashBag(comptime T: type) type {
    return struct {
        const Self = @This();
        const Map = std.AutoHashMapUnmanaged(T, usize);

        inner: Map,
        allocator: Allocator,
        total_size: usize,

        pub fn init(allocator: Allocator) Self {
            return .{
                .inner = .{},
                .allocator = allocator,
                .total_size = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            self.inner.deinit(self.allocator);
        }

        pub fn add(self: *Self, value: T) Allocator.Error!void {
            if (self.inner.getPtr(value)) |count_ptr| {
                count_ptr.* += 1;
            } else {
                try self.inner.put(self.allocator, value, 1);
            }
            self.total_size += 1;
        }

        pub fn occurrencesOf(self: *const Self, value: T) usize {
            return self.inner.get(value) orelse 0;
        }

        pub fn sizeDistinct(self: *const Self) usize {
            return self.inner.count();
        }

        /// Total number of items including multiplicities.
        pub fn len(self: *const Self) usize {
            return self.total_size;
        }

        pub fn contains(self: *const Self, value: T) bool {
            return self.inner.contains(value);
        }

        /// Remove one occurrence of value. Returns true if value was present.
        pub fn removeOne(self: *Self, value: T) bool {
            const ptr = self.inner.getPtr(value) orelse return false;
            if (ptr.* <= 1) {
                _ = self.inner.fetchRemove(value);
            } else {
                ptr.* -= 1;
            }
            self.total_size -= 1;
            return true;
        }

        pub fn forEachWithOccurrences(self: *const Self, ctx: *anyopaque, f: *const fn (ctx: *anyopaque, T, usize) void) void {
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                f(ctx, entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        /// Pull-based iterator yielding each element repeated by its occurrence
        /// count (the same elements as the generic `HashBag` iterator, and the
        /// expansion of `forEachWithOccurrences`), in arbitrary order.
        /// Non-allocating: wraps the backing `AutoHashMapUnmanaged` entry
        /// iterator plus an occurrence counter. The iterator borrows the bag; do
        /// not mutate while iterating. For distinct `(value, count)` traversal
        /// use `forEachWithOccurrences`.
        pub const Iterator = struct {
            inner: Map.Iterator,
            remaining: usize = 0,
            current: T = undefined,

            pub fn next(self: *Iterator) ?T {
                if (self.remaining > 0) {
                    self.remaining -= 1;
                    return self.current;
                }
                while (self.inner.next()) |entry| {
                    if (entry.value_ptr.* > 0) {
                        self.current = entry.key_ptr.*;
                        self.remaining = entry.value_ptr.* - 1;
                        return self.current;
                    }
                }
                return null;
            }
        };

        /// Returns a pull-based iterator yielding each element repeated by its
        /// occurrence count (same elements as `forEach` on the generic bag), in
        /// arbitrary order. Non-allocating.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .inner = self.inner.iterator() };
        }

        pub fn clear(self: *Self) void {
            self.inner.clearRetainingCapacity();
            self.total_size = 0;
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "HashBag basic" {
    const allocator = std.testing.allocator;
    var bag = HashBag(i32).init(allocator);
    defer bag.deinit();

    try bag.add(1);
    try bag.add(1);
    try bag.add(2);

    try std.testing.expectEqual(@as(usize, 3), bag.len());
    try std.testing.expectEqual(@as(usize, 2), bag.sizeDistinct());
    try std.testing.expectEqual(@as(usize, 2), bag.occurrencesOf(1));
    try std.testing.expectEqual(@as(usize, 1), bag.occurrencesOf(2));
    try std.testing.expectEqual(@as(usize, 0), bag.occurrencesOf(99));
}

test "HashBag removeOne" {
    const allocator = std.testing.allocator;
    var bag = HashBag(i32).init(allocator);
    defer bag.deinit();

    try bag.add(5);
    try bag.add(5);
    try bag.add(5);

    try std.testing.expect(bag.removeOne(5));
    try std.testing.expectEqual(@as(usize, 2), bag.occurrencesOf(5));
    try std.testing.expectEqual(@as(usize, 2), bag.len());

    try std.testing.expect(bag.removeOne(5));
    try std.testing.expect(bag.removeOne(5));
    try std.testing.expect(!bag.removeOne(5));
    try std.testing.expectEqual(@as(usize, 0), bag.len());
    try std.testing.expectEqual(@as(usize, 0), bag.sizeDistinct());
}

test "HashBag contains" {
    const allocator = std.testing.allocator;
    var bag = HashBag(i32).init(allocator);
    defer bag.deinit();

    try bag.add(42);
    try std.testing.expect(bag.contains(42));
    try std.testing.expect(!bag.contains(0));
}

test "HashBag clear" {
    const allocator = std.testing.allocator;
    var bag = HashBag(i32).init(allocator);
    defer bag.deinit();

    try bag.add(1);
    try bag.add(2);
    bag.clear();

    try std.testing.expectEqual(@as(usize, 0), bag.len());
    try std.testing.expectEqual(@as(usize, 0), bag.sizeDistinct());
}
