// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn HashSet(comptime T: type) type {
    return struct {
        const Self = @This();
        const Map = std.AutoHashMapUnmanaged(T, void);

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

        /// Add an element. Returns true if it was newly inserted, false if already present.
        pub fn add(self: *Self, value: T) bool {
            const result = self.inner.fetchPut(self.allocator, value, {}) catch @panic("out of memory");
            return result == null;
        }

        pub fn remove(self: *Self, value: T) bool {
            return self.inner.fetchRemove(value) != null;
        }

        pub fn contains(self: *const Self, value: T) bool {
            return self.inner.contains(value);
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

        pub fn forEach(self: *const Self, f: *const fn (T) void) void {
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                f(entry.key_ptr.*);
            }
        }

        /// Pull-based iterator yielding each element by value in arbitrary
        /// (hash-table) order. Non-allocating: wraps the backing
        /// `AutoHashMapUnmanaged` key iterator. The iterator borrows the set;
        /// do not mutate while iterating.
        pub const Iterator = struct {
            inner: Map.Iterator,

            pub fn next(self: *Iterator) ?T {
                const entry = self.inner.next() orelse return null;
                return entry.key_ptr.*;
            }
        };

        /// Returns a pull-based iterator over the elements in arbitrary order.
        /// Non-allocating.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .inner = self.inner.iterator() };
        }

        pub fn anySatisfy(self: *const Self, predicate: *const fn (T) bool) bool {
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                if (predicate(entry.key_ptr.*)) return true;
            }
            return false;
        }

        pub fn allSatisfy(self: *const Self, predicate: *const fn (T) bool) bool {
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                if (!predicate(entry.key_ptr.*)) return false;
            }
            return true;
        }

        pub fn noneSatisfy(self: *const Self, predicate: *const fn (T) bool) bool {
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                if (predicate(entry.key_ptr.*)) return false;
            }
            return true;
        }

        pub fn count(self: *const Self, predicate: *const fn (T) bool) usize {
            var c: usize = 0;
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                if (predicate(entry.key_ptr.*)) c += 1;
            }
            return c;
        }

        pub fn toSlice(self: *const Self, allocator: Allocator) []T {
            const slice = allocator.alloc(T, self.inner.count()) catch @panic("out of memory");
            var it = self.inner.iterator();
            var i: usize = 0;
            while (it.next()) |entry| {
                slice[i] = entry.key_ptr.*;
                i += 1;
            }
            return slice;
        }

        /// Returns a new set containing elements in either self or other.
        pub fn setUnion(self: *const Self, other: *const Self, allocator: Allocator) Self {
            var result = Self.init(allocator);
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                _ = result.add(entry.key_ptr.*);
            }
            var it2 = other.inner.iterator();
            while (it2.next()) |entry| {
                _ = result.add(entry.key_ptr.*);
            }
            return result;
        }

        /// Returns a new set containing elements in both self and other.
        pub fn intersect(self: *const Self, other: *const Self, allocator: Allocator) Self {
            var result = Self.init(allocator);
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                if (other.contains(entry.key_ptr.*)) {
                    _ = result.add(entry.key_ptr.*);
                }
            }
            return result;
        }

        /// Returns a new set containing elements in self but not in other.
        pub fn difference(self: *const Self, other: *const Self, allocator: Allocator) Self {
            var result = Self.init(allocator);
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                if (!other.contains(entry.key_ptr.*)) {
                    _ = result.add(entry.key_ptr.*);
                }
            }
            return result;
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "HashSet basic" {
    const allocator = std.testing.allocator;
    var set = HashSet(i32).init(allocator);
    defer set.deinit();

    try std.testing.expect(set.add(1));
    try std.testing.expect(set.add(2));
    try std.testing.expect(!set.add(1)); // duplicate

    try std.testing.expectEqual(@as(usize, 2), set.len());
    try std.testing.expect(set.contains(1));
    try std.testing.expect(!set.contains(99));
}

test "HashSet remove" {
    const allocator = std.testing.allocator;
    var set = HashSet(i32).init(allocator);
    defer set.deinit();

    _ = set.add(10);
    _ = set.add(20);

    try std.testing.expect(set.remove(10));
    try std.testing.expect(!set.remove(10));
    try std.testing.expectEqual(@as(usize, 1), set.len());
}

test "HashSet toSlice" {
    const allocator = std.testing.allocator;
    var set = HashSet(i32).init(allocator);
    defer set.deinit();

    _ = set.add(5);
    _ = set.add(10);

    const slice = set.toSlice(allocator);
    defer allocator.free(slice);

    try std.testing.expectEqual(@as(usize, 2), slice.len);
}

test "HashSet union intersect difference" {
    const allocator = std.testing.allocator;
    var a = HashSet(i32).init(allocator);
    defer a.deinit();
    var b = HashSet(i32).init(allocator);
    defer b.deinit();

    _ = a.add(1);
    _ = a.add(2);
    _ = a.add(3);
    _ = b.add(2);
    _ = b.add(3);
    _ = b.add(4);

    var u = a.setUnion(&b, allocator);
    defer u.deinit();
    try std.testing.expectEqual(@as(usize, 4), u.len());

    var inter = a.intersect(&b, allocator);
    defer inter.deinit();
    try std.testing.expectEqual(@as(usize, 2), inter.len());

    var diff = a.difference(&b, allocator);
    defer diff.deinit();
    try std.testing.expectEqual(@as(usize, 1), diff.len());
    try std.testing.expect(diff.contains(1));
}

test "HashSet anySatisfy allSatisfy noneSatisfy count" {
    const allocator = std.testing.allocator;
    var set = HashSet(i32).init(allocator);
    defer set.deinit();

    _ = set.add(2);
    _ = set.add(4);
    _ = set.add(6);

    const isEven = struct {
        fn f(x: i32) bool {
            return @rem(x, 2) == 0;
        }
    }.f;
    const isNeg = struct {
        fn f(x: i32) bool {
            return x < 0;
        }
    }.f;

    try std.testing.expect(set.allSatisfy(&isEven));
    try std.testing.expect(set.anySatisfy(&isEven));
    try std.testing.expect(set.noneSatisfy(&isNeg));
    try std.testing.expectEqual(@as(usize, 3), set.count(&isEven));
}

test "HashSet clear" {
    const allocator = std.testing.allocator;
    var set = HashSet(i32).init(allocator);
    defer set.deinit();

    _ = set.add(1);
    set.clear();

    try std.testing.expect(set.isEmpty());
}
