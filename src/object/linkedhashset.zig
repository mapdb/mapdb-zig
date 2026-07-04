// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Insertion-ordered hash set backed by `std.AutoArrayHashMapUnmanaged`.
/// Iteration follows insertion order.
pub fn LinkedHashSet(comptime T: type) type {
    return struct {
        const Self = @This();
        const Map = std.AutoArrayHashMapUnmanaged(T, void);

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
        pub fn add(self: *Self, value: T) Allocator.Error!bool {
            const result = try self.inner.fetchPut(self.allocator, value, {});
            return result == null;
        }

        pub fn remove(self: *Self, value: T) bool {
            return self.inner.fetchOrderedRemove(value) != null;
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

        /// Returns elements in insertion order.
        pub fn toSlice(self: *const Self, allocator: Allocator) Allocator.Error![]T {
            const keys = self.inner.keys();
            const slice = try allocator.alloc(T, keys.len);
            @memcpy(slice, keys);
            return slice;
        }

        /// Pull-based iterator yielding each element by value in insertion order.
        /// Non-allocating: indexes the backing array hash map's `keys()` slice.
        /// The iterator borrows the set; do not mutate while iterating.
        pub const Iterator = struct {
            keys: []const T,
            index: usize = 0,

            pub fn next(self: *Iterator) ?T {
                if (self.index >= self.keys.len) return null;
                const k = self.keys[self.index];
                self.index += 1;
                return k;
            }
        };

        /// Returns a pull-based iterator over the elements in insertion order.
        /// Non-allocating.
        ///
        /// No `mutIterator()` is provided for sets (deliberate exclusion): a set
        /// element IS its own identity (hash/slot derived from the element), so
        /// mutating it in place would put it in the wrong bucket and corrupt the
        /// set. Remove the old element and add the new one instead.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .keys = self.inner.keys() };
        }

        pub fn anySatisfy(self: *const Self, context: anytype, comptime predicate: fn (@TypeOf(context), T) bool) bool {
            for (self.inner.keys()) |k| {
                if (predicate(context, k)) return true;
            }
            return false;
        }

        pub fn allSatisfy(self: *const Self, context: anytype, comptime predicate: fn (@TypeOf(context), T) bool) bool {
            for (self.inner.keys()) |k| {
                if (!predicate(context, k)) return false;
            }
            return true;
        }

        pub fn noneSatisfy(self: *const Self, context: anytype, comptime predicate: fn (@TypeOf(context), T) bool) bool {
            for (self.inner.keys()) |k| {
                if (predicate(context, k)) return false;
            }
            return true;
        }

        pub fn count(self: *const Self, context: anytype, comptime predicate: fn (@TypeOf(context), T) bool) usize {
            var c: usize = 0;
            for (self.inner.keys()) |k| {
                if (predicate(context, k)) c += 1;
            }
            return c;
        }

        /// Returns a new set containing elements in either self or other.
        pub fn setUnion(self: *const Self, other: *const Self, allocator: Allocator) Allocator.Error!Self {
            var result = Self.init(allocator);
            errdefer result.deinit();
            for (self.inner.keys()) |k| {
                _ = try result.add(k);
            }
            for (other.inner.keys()) |k| {
                _ = try result.add(k);
            }
            return result;
        }

        /// Returns a new set containing elements in both self and other.
        pub fn intersect(self: *const Self, other: *const Self, allocator: Allocator) Allocator.Error!Self {
            var result = Self.init(allocator);
            errdefer result.deinit();
            for (self.inner.keys()) |k| {
                if (other.contains(k)) {
                    _ = try result.add(k);
                }
            }
            return result;
        }

        /// Returns a new set containing elements in self but not in other.
        pub fn difference(self: *const Self, other: *const Self, allocator: Allocator) Allocator.Error!Self {
            var result = Self.init(allocator);
            errdefer result.deinit();
            for (self.inner.keys()) |k| {
                if (!other.contains(k)) {
                    _ = try result.add(k);
                }
            }
            return result;
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "LinkedHashSet basic" {
    const allocator = std.testing.allocator;
    var set = LinkedHashSet(i32).init(allocator);
    defer set.deinit();

    try std.testing.expect(try set.add(1));
    try std.testing.expect(try set.add(2));
    try std.testing.expect(!try set.add(1)); // duplicate

    try std.testing.expectEqual(@as(usize, 2), set.len());
    try std.testing.expect(set.contains(1));
    try std.testing.expect(!set.contains(99));
}

test "LinkedHashSet insertion order" {
    const allocator = std.testing.allocator;
    var set = LinkedHashSet(i32).init(allocator);
    defer set.deinit();

    _ = try set.add(3);
    _ = try set.add(1);
    _ = try set.add(4);

    const slice = try set.toSlice(allocator);
    defer allocator.free(slice);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 3, 1, 4 }, slice);
}

test "LinkedHashSet remove preserves order" {
    const allocator = std.testing.allocator;
    var set = LinkedHashSet(i32).init(allocator);
    defer set.deinit();

    _ = try set.add(1);
    _ = try set.add(2);
    _ = try set.add(3);

    try std.testing.expect(set.remove(2));
    try std.testing.expect(!set.remove(2));

    const slice = try set.toSlice(allocator);
    defer allocator.free(slice);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 3 }, slice);
}

test "LinkedHashSet union intersect difference" {
    const allocator = std.testing.allocator;
    var a = LinkedHashSet(i32).init(allocator);
    defer a.deinit();
    var b = LinkedHashSet(i32).init(allocator);
    defer b.deinit();

    _ = try a.add(1);
    _ = try a.add(2);
    _ = try a.add(3);
    _ = try b.add(2);
    _ = try b.add(3);
    _ = try b.add(4);

    var u = try a.setUnion(&b, allocator);
    defer u.deinit();
    try std.testing.expectEqual(@as(usize, 4), u.len());
    const u_slice = try u.toSlice(allocator);
    defer allocator.free(u_slice);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 2, 3, 4 }, u_slice);

    var inter = try a.intersect(&b, allocator);
    defer inter.deinit();
    try std.testing.expectEqual(@as(usize, 2), inter.len());

    var diff = try a.difference(&b, allocator);
    defer diff.deinit();
    try std.testing.expectEqual(@as(usize, 1), diff.len());
    try std.testing.expect(diff.contains(1));
}

test "LinkedHashSet anySatisfy allSatisfy noneSatisfy count" {
    const allocator = std.testing.allocator;
    var set = LinkedHashSet(i32).init(allocator);
    defer set.deinit();

    _ = try set.add(2);
    _ = try set.add(4);
    _ = try set.add(6);

    const isEven = struct {
        fn f(_: void, x: i32) bool {
            return @rem(x, 2) == 0;
        }
    }.f;
    const isNeg = struct {
        fn f(_: void, x: i32) bool {
            return x < 0;
        }
    }.f;


    try std.testing.expect(set.allSatisfy({}, isEven));
    try std.testing.expect(set.anySatisfy({}, isEven));
    try std.testing.expect(set.noneSatisfy({}, isNeg));
    try std.testing.expectEqual(@as(usize, 3), set.count({}, isEven));
}

test "LinkedHashSet clear" {
    const allocator = std.testing.allocator;
    var set = LinkedHashSet(i32).init(allocator);
    defer set.deinit();

    _ = try set.add(1);
    set.clear();

    try std.testing.expect(set.isEmpty());
}
