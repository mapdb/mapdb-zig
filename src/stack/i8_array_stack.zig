// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;

/// LIFO stack of `i8` values, backed by an ArrayList.
pub const I8ArrayStack = struct {
    items: std.ArrayListUnmanaged(i8) = .empty,
    config: AllocatorConfig,

    pub fn init(allocator: Allocator) I8ArrayStack {
        return .{ .config = AllocatorConfig.init(allocator) };
    }

    pub fn initWithConfig(config: AllocatorConfig) I8ArrayStack {
        return .{ .config = config };
    }

    pub fn deinit(self: *I8ArrayStack) void {
        self.items.deinit(self.config.itemsAllocator());
    }

    pub fn of(allocator: Allocator, values: []const i8) I8ArrayStack {
        var stack = init(allocator);
        stack.items.appendSlice(stack.config.itemsAllocator(), values) catch @panic("out of memory");
        return stack;
    }

    /// Pushes a value onto the top of the stack.
    pub fn push(self: *I8ArrayStack, value: i8) void {
        self.items.append(self.config.itemsAllocator(), value) catch @panic("out of memory");
    }

    /// Removes and returns the top element, or null if empty.
    pub fn pop(self: *I8ArrayStack) ?i8 {
        if (self.items.items.len == 0) return null;
        return self.items.pop();
    }

    /// Returns the top element without removing it, or null if empty.
    pub fn peek(self: *const I8ArrayStack) ?i8 {
        if (self.items.items.len == 0) return null;
        return self.items.items[self.items.items.len - 1];
    }

    /// Returns the element at the given depth from the top (0 = top).
    pub fn peekAt(self: *const I8ArrayStack, depth: usize) ?i8 {
        if (depth >= self.items.items.len) return null;
        return self.items.items[self.items.items.len - 1 - depth];
    }

    pub fn len(self: *const I8ArrayStack) usize {
        return self.items.items.len;
    }

    /// Alias for len() — matches Go/Java naming.
    pub fn size(self: *const I8ArrayStack) usize {
        return self.len();
    }

    pub fn isEmpty(self: *const I8ArrayStack) bool {
        return self.items.items.len == 0;
    }

    pub fn clear(self: *I8ArrayStack) void {
        self.items.clearRetainingCapacity();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more items can be pushed without a
    /// reallocation.
    pub fn ensureUnusedCapacity(self: *I8ArrayStack, additional: usize) Allocator.Error!void {
        return self.items.ensureUnusedCapacity(self.config.itemsAllocator(), additional);
    }

    /// Ensures the stack's total capacity is at least `new_capacity`.
    pub fn ensureTotalCapacity(self: *I8ArrayStack, new_capacity: usize) Allocator.Error!void {
        return self.items.ensureTotalCapacity(self.config.itemsAllocator(), new_capacity);
    }

    pub fn contains(self: *const I8ArrayStack, value: i8) bool {
        for (self.items.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    pub fn anySatisfy(self: *const I8ArrayStack, predicate: *const fn (i8) bool) bool {
        for (self.items.items) |item| {
            if (predicate(item)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const I8ArrayStack, predicate: *const fn (i8) bool) bool {
        for (self.items.items) |item| {
            if (!predicate(item)) return false;
        }
        return true;
    }

    // ---- Iteration ----

    /// Calls f for each element (bottom to top).
    pub fn forEach(self: *const I8ArrayStack, f: *const fn (i8) void) void {
        for (self.items.items) |item| f(item);
    }

    // ---- Functional Operations ----

    /// Returns a new stack with only elements satisfying the predicate.
    pub fn select(self: *const I8ArrayStack, predicate: *const fn (i8) bool) I8ArrayStack {
        var result = init(self.config.base);
        for (self.items.items) |item| {
            if (predicate(item)) result.push(item);
        }
        return result;
    }

    /// Returns a new stack with elements NOT satisfying the predicate.
    pub fn reject(self: *const I8ArrayStack, predicate: *const fn (i8) bool) I8ArrayStack {
        var result = init(self.config.base);
        for (self.items.items) |item| {
            if (!predicate(item)) result.push(item);
        }
        return result;
    }

    /// Returns the first element satisfying the predicate, or null.
    pub fn detect(self: *const I8ArrayStack, predicate: *const fn (i8) bool) ?i8 {
        for (self.items.items) |item| {
            if (predicate(item)) return item;
        }
        return null;
    }

    pub fn noneSatisfy(self: *const I8ArrayStack, predicate: *const fn (i8) bool) bool {
        for (self.items.items) |item| {
            if (predicate(item)) return false;
        }
        return true;
    }

    pub fn count(self: *const I8ArrayStack, predicate: *const fn (i8) bool) usize {
        var c: usize = 0;
        for (self.items.items) |item| {
            if (predicate(item)) c += 1;
        }
        return c;
    }

    pub fn injectInto(self: *const I8ArrayStack, initial: i8, f: *const fn (i8, i8) i8) i8 {
        var acc = initial;
        for (self.items.items) |item| acc = f(acc, item);
        return acc;
    }

    // ---- Conversion ----

    pub fn toSlice(self: *const I8ArrayStack) []const i8 {
        return self.items.items;
    }

    pub fn toImmutable(self: *const I8ArrayStack) @import("../immutable/immutable_i8_array_stack.zig").ImmutableI8ArrayStack {
        return @import("../immutable/immutable_i8_array_stack.zig").ImmutableI8ArrayStack.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    pub fn with(self: *I8ArrayStack, value: i8) *I8ArrayStack {
        self.push(value);
        return self;
    }

    pub fn withAll(self: *I8ArrayStack, values: []const i8) *I8ArrayStack {
        for (values) |val| self.push(val);
        return self;
    }

    // ---- Formatting ----

    /// Formats as "[top, ..., bottom]" (top-to-bottom order).
    pub fn format(self: *const I8ArrayStack, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll("[");
        var i = self.items.items.len;
        var first = true;
        while (i > 0) {
            i -= 1;
            if (!first) try writer.writeAll(", ");
            try writer.print("{any}", .{self.items.items[i]});
            first = false;
        }
        try writer.writeAll("]");
    }

    // ---- Equality ----

    pub fn eql(self: *const I8ArrayStack, other: *const I8ArrayStack) bool {
        if (self.items.items.len != other.items.items.len) return false;
        for (self.items.items, other.items.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }
};

test "I8ArrayStack: push peek pop" {
    var stack = I8ArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    stack.push(1);
    stack.push(2);
    stack.push(3);
    try std.testing.expectEqual(@as(usize, 3), stack.len());
    try std.testing.expectEqual(@as(?i8, 3), stack.peek());
    try std.testing.expectEqual(@as(?i8, 3), stack.pop());
    try std.testing.expectEqual(@as(usize, 2), stack.len());
}

test "I8ArrayStack: pop empty" {
    var stack = I8ArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    try std.testing.expectEqual(@as(?i8, null), stack.pop());
    try std.testing.expectEqual(@as(?i8, null), stack.peek());
}

test "I8ArrayStack: LIFO order" {
    var stack = I8ArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    stack.push(1);
    stack.push(2);
    stack.push(3);
    try std.testing.expectEqual(@as(?i8, 3), stack.pop());
    try std.testing.expectEqual(@as(?i8, 2), stack.pop());
    try std.testing.expectEqual(@as(?i8, 1), stack.pop());
}

test "I8ArrayStack: contains" {
    var stack = I8ArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    stack.push(1);
    try std.testing.expect(stack.contains(1));
    try std.testing.expect(!stack.contains(3));
}

test "I8ArrayStack: clear" {
    var stack = I8ArrayStack.of(std.testing.allocator, &[_]i8{1});
    defer stack.deinit();
    stack.clear();
    try std.testing.expect(stack.isEmpty());
}

test "I8ArrayStack: eql" {
    var s1 = I8ArrayStack.of(std.testing.allocator, &[_]i8{ 1, 2 });
    defer s1.deinit();
    var s2 = I8ArrayStack.of(std.testing.allocator, &[_]i8{ 1, 2 });
    defer s2.deinit();
    var s3 = I8ArrayStack.of(std.testing.allocator, &[_]i8{1});
    defer s3.deinit();
    try std.testing.expect(s1.eql(&s2));
    try std.testing.expect(!s1.eql(&s3));
}

test "I8ArrayStack: select and reject" {
    var stack = I8ArrayStack.of(std.testing.allocator, &[_]i8{ 1, 2, 3 });
    defer stack.deinit();
    var sel = stack.select(struct {
        fn f(val: i8) bool {
            return val > 1;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expectEqual(@as(usize, 2), sel.len());
}

test "I8ArrayStack: toImmutable" {
    var stack = I8ArrayStack.of(std.testing.allocator, &[_]i8{ 1, 2 });
    defer stack.deinit();
    var imm = stack.toImmutable();
    defer imm.deinit();
    try std.testing.expectEqual(@as(usize, 2), imm.len());
    stack.push(3);
    try std.testing.expectEqual(@as(usize, 2), imm.len());
}

test "I8ArrayStack: fluent with" {
    var stack = I8ArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    _ = stack.with(1).with(2);
    try std.testing.expectEqual(@as(usize, 2), stack.len());
}

test "I8ArrayStack: ensureUnusedCapacity reserves and subsequent push does not reallocate" {
    var stack = I8ArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    try stack.ensureUnusedCapacity(10);
    const reserved = stack.items.capacity;
    try std.testing.expect(reserved >= 10);
    stack.push(1);
    stack.push(2);
    stack.push(3);
    try std.testing.expectEqual(reserved, stack.items.capacity);
}

test "I8ArrayStack: ensureTotalCapacity sets minimum capacity" {
    var stack = I8ArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    try stack.ensureTotalCapacity(64);
    try std.testing.expect(stack.items.capacity >= 64);
}

test "I8ArrayStack: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: Stack.init doesn't allocate (backed by ArrayList),
    // so the first alloc (ensureUnusedCapacity grow) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var stack = I8ArrayStack.initWithConfig(AllocatorConfig.init(failing.allocator()));
    defer stack.deinit();
    try std.testing.expectError(error.OutOfMemory, stack.ensureUnusedCapacity(1024));
}
