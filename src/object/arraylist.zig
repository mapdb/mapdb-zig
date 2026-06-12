// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

const std = @import("std");
const Allocator = std.mem.Allocator;
const float_order = @import("../float_order.zig");

/// Return an equality function appropriate for type T.
fn eqlFn(comptime T: type) fn (T, T) bool {
    return struct {
        fn eql(a: T, b: T) bool {
            const info = @typeInfo(T);
            switch (info) {
                .int, .comptime_int, .float, .comptime_float, .bool => return a == b,
                .pointer => return a == b,
                .@"enum" => return a == b,
                else => return std.meta.eql(a, b),
            }
        }
    }.eql;
}

pub fn ArrayList(comptime T: type) type {
    return struct {
        const Self = @This();

        inner: std.ArrayListUnmanaged(T),
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

        pub fn push(self: *Self, item: T) Allocator.Error!void {
            try self.inner.append(self.allocator, item);
        }

        pub fn get(self: *const Self, index: usize) ?T {
            if (index >= self.inner.items.len) return null;
            return self.inner.items[index];
        }

        pub fn set(self: *Self, index: usize, value: T) T {
            const old = self.inner.items[index];
            self.inner.items[index] = value;
            return old;
        }

        pub fn len(self: *const Self) usize {
            return self.inner.items.len;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.inner.items.len == 0;
        }

        pub fn contains(self: *const Self, value: T) bool {
            const eq = comptime eqlFn(T);
            for (self.inner.items) |item| {
                if (eq(item, value)) return true;
            }
            return false;
        }

        pub fn indexOf(self: *const Self, value: T) ?usize {
            const eq = comptime eqlFn(T);
            for (self.inner.items, 0..) |item, i| {
                if (eq(item, value)) return i;
            }
            return null;
        }

        /// Pull-based iterator yielding each element by value in insertion order.
        /// Non-allocating: indexes directly into the backing slice. The iterator
        /// borrows the list; do not mutate while iterating.
        pub const Iterator = struct {
            items: []const T,
            index: usize = 0,

            pub fn next(self: *Iterator) ?T {
                if (self.index >= self.items.len) return null;
                const item = self.items[self.index];
                self.index += 1;
                return item;
            }
        };

        /// Returns a pull-based iterator over the elements in insertion order.
        /// Non-allocating.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .items = self.inner.items };
        }

        pub fn select(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) Allocator.Error!Self {
            var result = Self.init(self.allocator);
            for (self.inner.items) |item| {
                if (predicate(ctx, item)) {
                    try result.push(item);
                }
            }
            return result;
        }

        pub fn reject(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) Allocator.Error!Self {
            var result = Self.init(self.allocator);
            for (self.inner.items) |item| {
                if (!predicate(ctx, item)) {
                    try result.push(item);
                }
            }
            return result;
        }

        pub fn toSlice(self: *const Self, allocator: Allocator) Allocator.Error![]T {
            const slice = try allocator.alloc(T, self.inner.items.len);
            @memcpy(slice, self.inner.items);
            return slice;
        }

        pub fn clear(self: *Self) void {
            self.inner.clearRetainingCapacity();
        }

        pub fn anySatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) bool {
            for (self.inner.items) |item| {
                if (predicate(ctx, item)) return true;
            }
            return false;
        }

        pub fn allSatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) bool {
            for (self.inner.items) |item| {
                if (!predicate(ctx, item)) return false;
            }
            return true;
        }

        pub fn noneSatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) bool {
            for (self.inner.items) |item| {
                if (predicate(ctx, item)) return false;
            }
            return true;
        }

        pub fn count(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) usize {
            var c: usize = 0;
            for (self.inner.items) |item| {
                if (predicate(ctx, item)) c += 1;
            }
            return c;
        }

        pub fn remove(self: *Self, value: T) bool {
            const eq = comptime eqlFn(T);
            for (self.inner.items, 0..) |item, i| {
                if (eq(item, value)) {
                    _ = self.inner.orderedRemove(i);
                    return true;
                }
            }
            return false;
        }

        pub fn sort(self: *Self) void {
            const info = @typeInfo(T);
            switch (info) {
                .int => {
                    std.mem.sort(T, self.inner.items, {}, struct {
                        fn lessThan(_: void, a: T, b: T) bool {
                            return a < b;
                        }
                    }.lessThan);
                },
                .float => {
                    // Raw `<` is not a strict weak ordering when NaN is present
                    // (NaN compares "equal" to everything, non-transitively),
                    // so std.mem.sort would yield unspecified order and ±0 would
                    // collapse. Use the IEEE totalOrder comparator instead.
                    std.mem.sort(T, self.inner.items, {}, struct {
                        fn lessThan(_: void, a: T, b: T) bool {
                            return float_order.totalCmp(T)(a, b) == .lt;
                        }
                    }.lessThan);
                },
                else => {
                    // Check if T has an `order` method
                    if (@hasDecl(T, "order")) {
                        std.mem.sort(T, self.inner.items, {}, struct {
                            fn lessThan(_: void, a: T, b: T) bool {
                                return T.order(a, b) == .lt;
                            }
                        }.lessThan);
                    }
                },
            }
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "ArrayList(f32).sort uses IEEE total order (NaN + ±0 + negatives)" {
    const allocator = std.testing.allocator;
    var list = ArrayList(f32).init(allocator);
    defer list.deinit();
    const nan = std.math.nan(f32);
    try list.push(nan);
    try list.push(1.0);
    try list.push(-1.0);
    try list.push(-0.0);
    try list.push(0.0);
    try list.push(-std.math.inf(f32));
    list.sort();
    const items = list.inner.items;
    // -Inf < -1 < -0.0 < +0.0 < +1 < +NaN ; total order is transitive.
    try std.testing.expect(items[0] == -std.math.inf(f32));
    try std.testing.expectEqual(@as(f32, -1.0), items[1]);
    // -0.0 must sort strictly before +0.0 (distinct bit patterns).
    try std.testing.expect(@as(u32, @bitCast(items[2])) == @as(u32, @bitCast(@as(f32, -0.0))));
    try std.testing.expect(@as(u32, @bitCast(items[3])) == @as(u32, @bitCast(@as(f32, 0.0))));
    try std.testing.expectEqual(@as(f32, 1.0), items[4]);
    try std.testing.expect(std.math.isNan(items[5])); // +NaN sorts last
}

test "ArrayList basic" {
    const allocator = std.testing.allocator;
    var list = ArrayList(i32).init(allocator);
    defer list.deinit();

    try list.push(10);
    try list.push(20);
    try list.push(30);

    try std.testing.expectEqual(@as(usize, 3), list.len());
    try std.testing.expect(!list.isEmpty());
    try std.testing.expectEqual(@as(?i32, 10), list.get(0));
    try std.testing.expectEqual(@as(?i32, 20), list.get(1));
    try std.testing.expectEqual(@as(?i32, null), list.get(100));
}

test "ArrayList set" {
    const allocator = std.testing.allocator;
    var list = ArrayList(i32).init(allocator);
    defer list.deinit();

    try list.push(1);
    try list.push(2);

    const old = list.set(0, 99);
    try std.testing.expectEqual(@as(i32, 1), old);
    try std.testing.expectEqual(@as(?i32, 99), list.get(0));
}

test "ArrayList contains and indexOf" {
    const allocator = std.testing.allocator;
    var list = ArrayList(i32).init(allocator);
    defer list.deinit();

    try list.push(5);
    try list.push(10);
    try list.push(15);

    try std.testing.expect(list.contains(10));
    try std.testing.expect(!list.contains(99));
    try std.testing.expectEqual(@as(?usize, 1), list.indexOf(10));
    try std.testing.expectEqual(@as(?usize, null), list.indexOf(99));
}

test "ArrayList remove" {
    const allocator = std.testing.allocator;
    var list = ArrayList(i32).init(allocator);
    defer list.deinit();

    try list.push(1);
    try list.push(2);
    try list.push(3);

    try std.testing.expect(list.remove(2));
    try std.testing.expectEqual(@as(usize, 2), list.len());
    try std.testing.expect(!list.remove(99));
}

test "ArrayList sort" {
    const allocator = std.testing.allocator;
    var list = ArrayList(i32).init(allocator);
    defer list.deinit();

    try list.push(30);
    try list.push(10);
    try list.push(20);

    list.sort();

    try std.testing.expectEqual(@as(?i32, 10), list.get(0));
    try std.testing.expectEqual(@as(?i32, 20), list.get(1));
    try std.testing.expectEqual(@as(?i32, 30), list.get(2));
}

test "ArrayList toSlice" {
    const allocator = std.testing.allocator;
    var list = ArrayList(i32).init(allocator);
    defer list.deinit();

    try list.push(1);
    try list.push(2);

    const slice = try list.toSlice(allocator);
    defer allocator.free(slice);

    try std.testing.expectEqual(@as(usize, 2), slice.len);
    try std.testing.expectEqual(@as(i32, 1), slice[0]);
    try std.testing.expectEqual(@as(i32, 2), slice[1]);
}

test "ArrayList select and reject" {
    const allocator = std.testing.allocator;
    var list = ArrayList(i32).init(allocator);
    defer list.deinit();

    try list.push(1);
    try list.push(2);
    try list.push(3);
    try list.push(4);

    const isEven = struct {
        fn f(_: *anyopaque, x: i32) bool {
            return @rem(x, 2) == 0;
        }
    }.f;

    var dummy: u8 = 0;
    const ctx: *anyopaque = &dummy;

    var evens = try list.select(ctx, &isEven);
    defer evens.deinit();
    try std.testing.expectEqual(@as(usize, 2), evens.len());

    var odds = try list.reject(ctx, &isEven);
    defer odds.deinit();
    try std.testing.expectEqual(@as(usize, 2), odds.len());
}

test "ArrayList anySatisfy allSatisfy noneSatisfy count" {
    const allocator = std.testing.allocator;
    var list = ArrayList(i32).init(allocator);
    defer list.deinit();

    try list.push(2);
    try list.push(4);
    try list.push(6);

    const isEven = struct {
        fn f(_: *anyopaque, x: i32) bool {
            return @rem(x, 2) == 0;
        }
    }.f;
    const isNegative = struct {
        fn f(_: *anyopaque, x: i32) bool {
            return x < 0;
        }
    }.f;

    var dummy: u8 = 0;
    const ctx: *anyopaque = &dummy;

    try std.testing.expect(list.allSatisfy(ctx, &isEven));
    try std.testing.expect(list.anySatisfy(ctx, &isEven));
    try std.testing.expect(list.noneSatisfy(ctx, &isNegative));
    try std.testing.expectEqual(@as(usize, 3), list.count(ctx, &isEven));
}

test "ArrayList clear" {
    const allocator = std.testing.allocator;
    var list = ArrayList(i32).init(allocator);
    defer list.deinit();

    try list.push(1);
    try list.push(2);
    list.clear();

    try std.testing.expectEqual(@as(usize, 0), list.len());
    try std.testing.expect(list.isEmpty());
}
