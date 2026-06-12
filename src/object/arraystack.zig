// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

const std = @import("std");
const Allocator = std.mem.Allocator;

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

pub fn ArrayStack(comptime T: type) type {
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

        /// Pop the top element. Returns null if the stack is empty.
        pub fn pop(self: *Self) ?T {
            return self.inner.pop();
        }

        /// Peek at the top element without removing it.
        pub fn peek(self: *const Self) ?T {
            if (self.inner.items.len == 0) return null;
            return self.inner.items[self.inner.items.len - 1];
        }

        /// Peek at a specific depth from the top (0 = top).
        pub fn peekAt(self: *const Self, depth: usize) ?T {
            if (depth >= self.inner.items.len) return null;
            return self.inner.items[self.inner.items.len - 1 - depth];
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

        pub fn clear(self: *Self) void {
            self.inner.clearRetainingCapacity();
        }

        /// Pull-based iterator yielding each element by value in bottom-to-top
        /// (push) order. Non-allocating: indexes directly into the backing slice.
        /// The iterator borrows the stack; do not mutate while iterating.
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

        /// Returns a pull-based iterator over the elements in bottom-to-top order.
        /// Non-allocating.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .items = self.inner.items };
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "ArrayStack basic" {
    const allocator = std.testing.allocator;
    var stack = ArrayStack(i32).init(allocator);
    defer stack.deinit();

    try stack.push(1);
    try stack.push(2);
    try stack.push(3);

    try std.testing.expectEqual(@as(usize, 3), stack.len());
    try std.testing.expect(!stack.isEmpty());

    try std.testing.expectEqual(@as(?i32, 3), stack.peek());
    try std.testing.expectEqual(@as(?i32, 3), stack.pop());
    try std.testing.expectEqual(@as(?i32, 2), stack.pop());
    try std.testing.expectEqual(@as(?i32, 1), stack.pop());
    try std.testing.expectEqual(@as(?i32, null), stack.pop());
    try std.testing.expect(stack.isEmpty());
}

test "ArrayStack peekAt" {
    const allocator = std.testing.allocator;
    var stack = ArrayStack(i32).init(allocator);
    defer stack.deinit();

    try stack.push(10);
    try stack.push(20);
    try stack.push(30);

    try std.testing.expectEqual(@as(?i32, 30), stack.peekAt(0));
    try std.testing.expectEqual(@as(?i32, 20), stack.peekAt(1));
    try std.testing.expectEqual(@as(?i32, 10), stack.peekAt(2));
    try std.testing.expectEqual(@as(?i32, null), stack.peekAt(3));
}

test "ArrayStack contains" {
    const allocator = std.testing.allocator;
    var stack = ArrayStack(i32).init(allocator);
    defer stack.deinit();

    try stack.push(5);
    try stack.push(10);

    try std.testing.expect(stack.contains(5));
    try std.testing.expect(stack.contains(10));
    try std.testing.expect(!stack.contains(99));
}

test "ArrayStack clear" {
    const allocator = std.testing.allocator;
    var stack = ArrayStack(i32).init(allocator);
    defer stack.deinit();

    try stack.push(1);
    try stack.push(2);
    stack.clear();

    try std.testing.expect(stack.isEmpty());
    try std.testing.expectEqual(@as(?i32, null), stack.peek());
}
