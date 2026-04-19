// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

const std = @import("std");
const Allocator = std.mem.Allocator;

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

        pub fn push(self: *Self, item: T) void {
            self.inner.append(self.allocator, item) catch @panic("out of memory");
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

        pub fn forEach(self: *const Self, f: *const fn (*const T) void) void {
            for (self.inner.items) |*item| {
                f(item);
            }
        }

        pub fn select(self: *const Self, predicate: *const fn (T) bool) Self {
            var result = Self.init(self.allocator);
            for (self.inner.items) |item| {
                if (predicate(item)) {
                    result.push(item);
                }
            }
            return result;
        }

        pub fn reject(self: *const Self, predicate: *const fn (T) bool) Self {
            var result = Self.init(self.allocator);
            for (self.inner.items) |item| {
                if (!predicate(item)) {
                    result.push(item);
                }
            }
            return result;
        }

        pub fn toSlice(self: *const Self, allocator: Allocator) []T {
            const slice = allocator.alloc(T, self.inner.items.len) catch @panic("out of memory");
            @memcpy(slice, self.inner.items);
            return slice;
        }

        pub fn clear(self: *Self) void {
            self.inner.clearRetainingCapacity();
        }

        pub fn anySatisfy(self: *const Self, predicate: *const fn (T) bool) bool {
            for (self.inner.items) |item| {
                if (predicate(item)) return true;
            }
            return false;
        }

        pub fn allSatisfy(self: *const Self, predicate: *const fn (T) bool) bool {
            for (self.inner.items) |item| {
                if (!predicate(item)) return false;
            }
            return true;
        }

        pub fn noneSatisfy(self: *const Self, predicate: *const fn (T) bool) bool {
            for (self.inner.items) |item| {
                if (predicate(item)) return false;
            }
            return true;
        }

        pub fn count(self: *const Self, predicate: *const fn (T) bool) usize {
            var c: usize = 0;
            for (self.inner.items) |item| {
                if (predicate(item)) c += 1;
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
                .int, .float => {
                    std.mem.sort(T, self.inner.items, {}, struct {
                        fn lessThan(_: void, a: T, b: T) bool {
                            return a < b;
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

test "ArrayList basic" {
    const allocator = std.testing.allocator;
    var list = ArrayList(i32).init(allocator);
    defer list.deinit();

    list.push(10);
    list.push(20);
    list.push(30);

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

    list.push(1);
    list.push(2);

    const old = list.set(0, 99);
    try std.testing.expectEqual(@as(i32, 1), old);
    try std.testing.expectEqual(@as(?i32, 99), list.get(0));
}

test "ArrayList contains and indexOf" {
    const allocator = std.testing.allocator;
    var list = ArrayList(i32).init(allocator);
    defer list.deinit();

    list.push(5);
    list.push(10);
    list.push(15);

    try std.testing.expect(list.contains(10));
    try std.testing.expect(!list.contains(99));
    try std.testing.expectEqual(@as(?usize, 1), list.indexOf(10));
    try std.testing.expectEqual(@as(?usize, null), list.indexOf(99));
}

test "ArrayList remove" {
    const allocator = std.testing.allocator;
    var list = ArrayList(i32).init(allocator);
    defer list.deinit();

    list.push(1);
    list.push(2);
    list.push(3);

    try std.testing.expect(list.remove(2));
    try std.testing.expectEqual(@as(usize, 2), list.len());
    try std.testing.expect(!list.remove(99));
}

test "ArrayList sort" {
    const allocator = std.testing.allocator;
    var list = ArrayList(i32).init(allocator);
    defer list.deinit();

    list.push(30);
    list.push(10);
    list.push(20);

    list.sort();

    try std.testing.expectEqual(@as(?i32, 10), list.get(0));
    try std.testing.expectEqual(@as(?i32, 20), list.get(1));
    try std.testing.expectEqual(@as(?i32, 30), list.get(2));
}

test "ArrayList toSlice" {
    const allocator = std.testing.allocator;
    var list = ArrayList(i32).init(allocator);
    defer list.deinit();

    list.push(1);
    list.push(2);

    const slice = list.toSlice(allocator);
    defer allocator.free(slice);

    try std.testing.expectEqual(@as(usize, 2), slice.len);
    try std.testing.expectEqual(@as(i32, 1), slice[0]);
    try std.testing.expectEqual(@as(i32, 2), slice[1]);
}

test "ArrayList select and reject" {
    const allocator = std.testing.allocator;
    var list = ArrayList(i32).init(allocator);
    defer list.deinit();

    list.push(1);
    list.push(2);
    list.push(3);
    list.push(4);

    const isEven = struct {
        fn f(x: i32) bool {
            return @rem(x, 2) == 0;
        }
    }.f;

    var evens = list.select(&isEven);
    defer evens.deinit();
    try std.testing.expectEqual(@as(usize, 2), evens.len());

    var odds = list.reject(&isEven);
    defer odds.deinit();
    try std.testing.expectEqual(@as(usize, 2), odds.len());
}

test "ArrayList anySatisfy allSatisfy noneSatisfy count" {
    const allocator = std.testing.allocator;
    var list = ArrayList(i32).init(allocator);
    defer list.deinit();

    list.push(2);
    list.push(4);
    list.push(6);

    const isEven = struct {
        fn f(x: i32) bool {
            return @rem(x, 2) == 0;
        }
    }.f;
    const isNegative = struct {
        fn f(x: i32) bool {
            return x < 0;
        }
    }.f;

    try std.testing.expect(list.allSatisfy(&isEven));
    try std.testing.expect(list.anySatisfy(&isEven));
    try std.testing.expect(list.noneSatisfy(&isNegative));
    try std.testing.expectEqual(@as(usize, 3), list.count(&isEven));
}

test "ArrayList clear" {
    const allocator = std.testing.allocator;
    var list = ArrayList(i32).init(allocator);
    defer list.deinit();

    list.push(1);
    list.push(2);
    list.clear();

    try std.testing.expectEqual(@as(usize, 0), list.len());
    try std.testing.expect(list.isEmpty());
}
