
const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;

/// LIFO stack of `i64` values, backed by an ArrayList.
pub const I64ArrayStack = struct {
    items: std.ArrayListUnmanaged(i64) = .empty,
    config: AllocatorConfig,

    pub fn init(allocator: Allocator) I64ArrayStack {
        return .{ .config = AllocatorConfig.init(allocator) };
    }

    pub fn initWithConfig(config: AllocatorConfig) I64ArrayStack {
        return .{ .config = config };
    }

    pub fn deinit(self: *I64ArrayStack) void {
        self.items.deinit(self.config.itemsAllocator());
    }

    pub fn of(allocator: Allocator, values: []const i64) I64ArrayStack {
        var stack = init(allocator);
        stack.items.appendSlice(stack.config.itemsAllocator(), values) catch @panic("out of memory");
        return stack;
    }

    /// Pushes a value onto the top of the stack.
    pub fn push(self: *I64ArrayStack, value: i64) void {
        self.items.append(self.config.itemsAllocator(), value) catch @panic("out of memory");
    }

    /// Removes and returns the top element, or null if empty.
    pub fn pop(self: *I64ArrayStack) ?i64 {
        if (self.items.items.len == 0) return null;
        return self.items.pop();
    }

    /// Returns the top element without removing it, or null if empty.
    pub fn peek(self: *const I64ArrayStack) ?i64 {
        if (self.items.items.len == 0) return null;
        return self.items.items[self.items.items.len - 1];
    }

    /// Returns the element at the given depth from the top (0 = top).
    pub fn peekAt(self: *const I64ArrayStack, depth: usize) ?i64 {
        if (depth >= self.items.items.len) return null;
        return self.items.items[self.items.items.len - 1 - depth];
    }

    pub fn len(self: *const I64ArrayStack) usize {
        return self.items.items.len;
    }

    /// Alias for len() — matches Go/Java naming.
    pub fn size(self: *const I64ArrayStack) usize {
        return self.len();
    }

    pub fn isEmpty(self: *const I64ArrayStack) bool {
        return self.items.items.len == 0;
    }

    pub fn clear(self: *I64ArrayStack) void {
        self.items.clearRetainingCapacity();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more items can be pushed without a
    /// reallocation. See `docs/zig/error-handling.md`.
    pub fn ensureUnusedCapacity(self: *I64ArrayStack, additional: usize) Allocator.Error!void {
        return self.items.ensureUnusedCapacity(self.config.itemsAllocator(), additional);
    }

    /// Ensures the stack's total capacity is at least `new_capacity`.
    pub fn ensureTotalCapacity(self: *I64ArrayStack, new_capacity: usize) Allocator.Error!void {
        return self.items.ensureTotalCapacity(self.config.itemsAllocator(), new_capacity);
    }

    pub fn contains(self: *const I64ArrayStack, value: i64) bool {
        for (self.items.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    pub fn anySatisfy(self: *const I64ArrayStack, predicate: *const fn (i64) bool) bool {
        for (self.items.items) |item| {
            if (predicate(item)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const I64ArrayStack, predicate: *const fn (i64) bool) bool {
        for (self.items.items) |item| {
            if (!predicate(item)) return false;
        }
        return true;
    }

    // ---- Iteration ----

    /// Calls f for each element (bottom to top).
    pub fn forEach(self: *const I64ArrayStack, f: *const fn (i64) void) void {
        for (self.items.items) |item| f(item);
    }

    // ---- Functional Operations ----

    /// Returns a new stack with only elements satisfying the predicate.
    pub fn select(self: *const I64ArrayStack, predicate: *const fn (i64) bool) I64ArrayStack {
        var result = init(self.config.base);
        for (self.items.items) |item| {
            if (predicate(item)) result.push(item);
        }
        return result;
    }

    /// Returns a new stack with elements NOT satisfying the predicate.
    pub fn reject(self: *const I64ArrayStack, predicate: *const fn (i64) bool) I64ArrayStack {
        var result = init(self.config.base);
        for (self.items.items) |item| {
            if (!predicate(item)) result.push(item);
        }
        return result;
    }

    /// Returns the first element satisfying the predicate, or null.
    pub fn detect(self: *const I64ArrayStack, predicate: *const fn (i64) bool) ?i64 {
        for (self.items.items) |item| {
            if (predicate(item)) return item;
        }
        return null;
    }

    pub fn noneSatisfy(self: *const I64ArrayStack, predicate: *const fn (i64) bool) bool {
        for (self.items.items) |item| {
            if (predicate(item)) return false;
        }
        return true;
    }

    pub fn count(self: *const I64ArrayStack, predicate: *const fn (i64) bool) usize {
        var c: usize = 0;
        for (self.items.items) |item| {
            if (predicate(item)) c += 1;
        }
        return c;
    }

    pub fn injectInto(self: *const I64ArrayStack, initial: i64, f: *const fn (i64, i64) i64) i64 {
        var acc = initial;
        for (self.items.items) |item| acc = f(acc, item);
        return acc;
    }

    // ---- Conversion ----

    pub fn toSlice(self: *const I64ArrayStack) []const i64 {
        return self.items.items;
    }

    pub fn toImmutable(self: *const I64ArrayStack) @import("../immutable/immutable_i64_array_stack.zig").ImmutableI64ArrayStack {
        return @import("../immutable/immutable_i64_array_stack.zig").ImmutableI64ArrayStack.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    pub fn with(self: *I64ArrayStack, value: i64) *I64ArrayStack {
        self.push(value);
        return self;
    }

    pub fn withAll(self: *I64ArrayStack, values: []const i64) *I64ArrayStack {
        for (values) |val| self.push(val);
        return self;
    }

    // ---- Formatting ----

    /// Formats as "[top, ..., bottom]" (top-to-bottom order).
    pub fn format(self: *const I64ArrayStack, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const I64ArrayStack, other: *const I64ArrayStack) bool {
        if (self.items.items.len != other.items.items.len) return false;
        for (self.items.items, other.items.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }
};

test "I64ArrayStack: push peek pop" {
    var stack = I64ArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    stack.push(1);
    stack.push(2);
    stack.push(3);
    try std.testing.expectEqual(@as(usize, 3), stack.len());
    try std.testing.expectEqual(@as(?i64, 3), stack.peek());
    try std.testing.expectEqual(@as(?i64, 3), stack.pop());
    try std.testing.expectEqual(@as(usize, 2), stack.len());
}

test "I64ArrayStack: pop empty" {
    var stack = I64ArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    try std.testing.expectEqual(@as(?i64, null), stack.pop());
    try std.testing.expectEqual(@as(?i64, null), stack.peek());
}

test "I64ArrayStack: LIFO order" {
    var stack = I64ArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    stack.push(1);
    stack.push(2);
    stack.push(3);
    try std.testing.expectEqual(@as(?i64, 3), stack.pop());
    try std.testing.expectEqual(@as(?i64, 2), stack.pop());
    try std.testing.expectEqual(@as(?i64, 1), stack.pop());
}

test "I64ArrayStack: contains" {
    var stack = I64ArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    stack.push(1);
    try std.testing.expect(stack.contains(1));
    try std.testing.expect(!stack.contains(3));
}

test "I64ArrayStack: clear" {
    var stack = I64ArrayStack.of(std.testing.allocator, &[_]i64{1});
    defer stack.deinit();
    stack.clear();
    try std.testing.expect(stack.isEmpty());
}

test "I64ArrayStack: eql" {
    var s1 = I64ArrayStack.of(std.testing.allocator, &[_]i64{ 1, 2 });
    defer s1.deinit();
    var s2 = I64ArrayStack.of(std.testing.allocator, &[_]i64{ 1, 2 });
    defer s2.deinit();
    var s3 = I64ArrayStack.of(std.testing.allocator, &[_]i64{1});
    defer s3.deinit();
    try std.testing.expect(s1.eql(&s2));
    try std.testing.expect(!s1.eql(&s3));
}

test "I64ArrayStack: select and reject" {
    var stack = I64ArrayStack.of(std.testing.allocator, &[_]i64{ 1, 2, 3 });
    defer stack.deinit();
    var sel = stack.select(struct {
        fn f(val: i64) bool {
            return val > 1;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expectEqual(@as(usize, 2), sel.len());
}

test "I64ArrayStack: toImmutable" {
    var stack = I64ArrayStack.of(std.testing.allocator, &[_]i64{ 1, 2 });
    defer stack.deinit();
    var imm = stack.toImmutable();
    defer imm.deinit();
    try std.testing.expectEqual(@as(usize, 2), imm.len());
    stack.push(3);
    try std.testing.expectEqual(@as(usize, 2), imm.len());
}

test "I64ArrayStack: fluent with" {
    var stack = I64ArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    _ = stack.with(1).with(2);
    try std.testing.expectEqual(@as(usize, 2), stack.len());
}

test "I64ArrayStack: ensureUnusedCapacity reserves and subsequent push does not reallocate" {
    var stack = I64ArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    try stack.ensureUnusedCapacity(10);
    const reserved = stack.items.capacity;
    try std.testing.expect(reserved >= 10);
    stack.push(1);
    stack.push(2);
    stack.push(3);
    try std.testing.expectEqual(reserved, stack.items.capacity);
}

test "I64ArrayStack: ensureTotalCapacity sets minimum capacity" {
    var stack = I64ArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    try stack.ensureTotalCapacity(64);
    try std.testing.expect(stack.items.capacity >= 64);
}

test "I64ArrayStack: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: Stack.init doesn't allocate (backed by ArrayList),
    // so the first alloc (ensureUnusedCapacity grow) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var stack = I64ArrayStack.initWithConfig(AllocatorConfig.init(failing.allocator()));
    defer stack.deinit();
    try std.testing.expectError(error.OutOfMemory, stack.ensureUnusedCapacity(1024));
}
