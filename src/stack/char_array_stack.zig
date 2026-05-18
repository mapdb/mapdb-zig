
const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;

/// LIFO stack of `u21` values, backed by an ArrayList.
pub const CharArrayStack = struct {
    items: std.ArrayListUnmanaged(u21) = .empty,
    config: AllocatorConfig,

    pub fn init(allocator: Allocator) CharArrayStack {
        return .{ .config = AllocatorConfig.init(allocator) };
    }

    pub fn initWithConfig(config: AllocatorConfig) CharArrayStack {
        return .{ .config = config };
    }

    pub fn deinit(self: *CharArrayStack) void {
        self.items.deinit(self.config.itemsAllocator());
    }

    pub fn of(allocator: Allocator, values: []const u21) CharArrayStack {
        var stack = init(allocator);
        stack.items.appendSlice(stack.config.itemsAllocator(), values) catch @panic("out of memory");
        return stack;
    }

    /// Pushes a value onto the top of the stack.
    pub fn push(self: *CharArrayStack, value: u21) void {
        self.items.append(self.config.itemsAllocator(), value) catch @panic("out of memory");
    }

    /// Removes and returns the top element, or null if empty.
    pub fn pop(self: *CharArrayStack) ?u21 {
        if (self.items.items.len == 0) return null;
        return self.items.pop();
    }

    /// Returns the top element without removing it, or null if empty.
    pub fn peek(self: *const CharArrayStack) ?u21 {
        if (self.items.items.len == 0) return null;
        return self.items.items[self.items.items.len - 1];
    }

    /// Returns the element at the given depth from the top (0 = top).
    pub fn peekAt(self: *const CharArrayStack, depth: usize) ?u21 {
        if (depth >= self.items.items.len) return null;
        return self.items.items[self.items.items.len - 1 - depth];
    }

    pub fn len(self: *const CharArrayStack) usize {
        return self.items.items.len;
    }

    /// Alias for len() — matches Go/Java naming.
    pub fn size(self: *const CharArrayStack) usize {
        return self.len();
    }

    pub fn isEmpty(self: *const CharArrayStack) bool {
        return self.items.items.len == 0;
    }

    pub fn clear(self: *CharArrayStack) void {
        self.items.clearRetainingCapacity();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more items can be pushed without a
    /// reallocation.
    pub fn ensureUnusedCapacity(self: *CharArrayStack, additional: usize) Allocator.Error!void {
        return self.items.ensureUnusedCapacity(self.config.itemsAllocator(), additional);
    }

    /// Ensures the stack's total capacity is at least `new_capacity`.
    pub fn ensureTotalCapacity(self: *CharArrayStack, new_capacity: usize) Allocator.Error!void {
        return self.items.ensureTotalCapacity(self.config.itemsAllocator(), new_capacity);
    }

    pub fn contains(self: *const CharArrayStack, value: u21) bool {
        for (self.items.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    pub fn anySatisfy(self: *const CharArrayStack, predicate: *const fn (u21) bool) bool {
        for (self.items.items) |item| {
            if (predicate(item)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const CharArrayStack, predicate: *const fn (u21) bool) bool {
        for (self.items.items) |item| {
            if (!predicate(item)) return false;
        }
        return true;
    }

    // ---- Iteration ----

    /// Calls f for each element (bottom to top).
    pub fn forEach(self: *const CharArrayStack, f: *const fn (u21) void) void {
        for (self.items.items) |item| f(item);
    }

    // ---- Functional Operations ----

    /// Returns a new stack with only elements satisfying the predicate.
    pub fn select(self: *const CharArrayStack, predicate: *const fn (u21) bool) CharArrayStack {
        var result = init(self.config.base);
        for (self.items.items) |item| {
            if (predicate(item)) result.push(item);
        }
        return result;
    }

    /// Returns a new stack with elements NOT satisfying the predicate.
    pub fn reject(self: *const CharArrayStack, predicate: *const fn (u21) bool) CharArrayStack {
        var result = init(self.config.base);
        for (self.items.items) |item| {
            if (!predicate(item)) result.push(item);
        }
        return result;
    }

    /// Returns the first element satisfying the predicate, or null.
    pub fn detect(self: *const CharArrayStack, predicate: *const fn (u21) bool) ?u21 {
        for (self.items.items) |item| {
            if (predicate(item)) return item;
        }
        return null;
    }

    pub fn noneSatisfy(self: *const CharArrayStack, predicate: *const fn (u21) bool) bool {
        for (self.items.items) |item| {
            if (predicate(item)) return false;
        }
        return true;
    }

    pub fn count(self: *const CharArrayStack, predicate: *const fn (u21) bool) usize {
        var c: usize = 0;
        for (self.items.items) |item| {
            if (predicate(item)) c += 1;
        }
        return c;
    }

    pub fn injectInto(self: *const CharArrayStack, initial: u21, f: *const fn (u21, u21) u21) u21 {
        var acc = initial;
        for (self.items.items) |item| acc = f(acc, item);
        return acc;
    }

    // ---- Conversion ----

    pub fn toSlice(self: *const CharArrayStack) []const u21 {
        return self.items.items;
    }

    pub fn toImmutable(self: *const CharArrayStack) @import("../immutable/immutable_char_array_stack.zig").ImmutableCharArrayStack {
        return @import("../immutable/immutable_char_array_stack.zig").ImmutableCharArrayStack.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    pub fn with(self: *CharArrayStack, value: u21) *CharArrayStack {
        self.push(value);
        return self;
    }

    pub fn withAll(self: *CharArrayStack, values: []const u21) *CharArrayStack {
        for (values) |val| self.push(val);
        return self;
    }

    // ---- Formatting ----

    /// Formats as "[top, ..., bottom]" (top-to-bottom order).
    pub fn format(self: *const CharArrayStack, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const CharArrayStack, other: *const CharArrayStack) bool {
        if (self.items.items.len != other.items.items.len) return false;
        for (self.items.items, other.items.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }
};

test "CharArrayStack: push peek pop" {
    var stack = CharArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    stack.push('a');
    stack.push('b');
    stack.push('c');
    try std.testing.expectEqual(@as(usize, 3), stack.len());
    try std.testing.expectEqual(@as(?u21, 'c'), stack.peek());
    try std.testing.expectEqual(@as(?u21, 'c'), stack.pop());
    try std.testing.expectEqual(@as(usize, 2), stack.len());
}

test "CharArrayStack: pop empty" {
    var stack = CharArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    try std.testing.expectEqual(@as(?u21, null), stack.pop());
    try std.testing.expectEqual(@as(?u21, null), stack.peek());
}

test "CharArrayStack: LIFO order" {
    var stack = CharArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    stack.push('a');
    stack.push('b');
    stack.push('c');
    try std.testing.expectEqual(@as(?u21, 'c'), stack.pop());
    try std.testing.expectEqual(@as(?u21, 'b'), stack.pop());
    try std.testing.expectEqual(@as(?u21, 'a'), stack.pop());
}

test "CharArrayStack: contains" {
    var stack = CharArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    stack.push('a');
    try std.testing.expect(stack.contains('a'));
    try std.testing.expect(!stack.contains('c'));
}

test "CharArrayStack: clear" {
    var stack = CharArrayStack.of(std.testing.allocator, &[_]u21{'a'});
    defer stack.deinit();
    stack.clear();
    try std.testing.expect(stack.isEmpty());
}

test "CharArrayStack: eql" {
    var s1 = CharArrayStack.of(std.testing.allocator, &[_]u21{ 'a', 'b' });
    defer s1.deinit();
    var s2 = CharArrayStack.of(std.testing.allocator, &[_]u21{ 'a', 'b' });
    defer s2.deinit();
    var s3 = CharArrayStack.of(std.testing.allocator, &[_]u21{'a'});
    defer s3.deinit();
    try std.testing.expect(s1.eql(&s2));
    try std.testing.expect(!s1.eql(&s3));
}

test "CharArrayStack: select and reject" {
    var stack = CharArrayStack.of(std.testing.allocator, &[_]u21{ 'a', 'b', 'c' });
    defer stack.deinit();
    var sel = stack.select(struct {
        fn f(val: u21) bool {
            return val > 'a';
        }
    }.f);
    defer sel.deinit();
    try std.testing.expectEqual(@as(usize, 2), sel.len());
}

test "CharArrayStack: toImmutable" {
    var stack = CharArrayStack.of(std.testing.allocator, &[_]u21{ 'a', 'b' });
    defer stack.deinit();
    var imm = stack.toImmutable();
    defer imm.deinit();
    try std.testing.expectEqual(@as(usize, 2), imm.len());
    stack.push('c');
    try std.testing.expectEqual(@as(usize, 2), imm.len());
}

test "CharArrayStack: fluent with" {
    var stack = CharArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    _ = stack.with('a').with('b');
    try std.testing.expectEqual(@as(usize, 2), stack.len());
}

test "CharArrayStack: ensureUnusedCapacity reserves and subsequent push does not reallocate" {
    var stack = CharArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    try stack.ensureUnusedCapacity(10);
    const reserved = stack.items.capacity;
    try std.testing.expect(reserved >= 10);
    stack.push('a');
    stack.push('b');
    stack.push('c');
    try std.testing.expectEqual(reserved, stack.items.capacity);
}

test "CharArrayStack: ensureTotalCapacity sets minimum capacity" {
    var stack = CharArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    try stack.ensureTotalCapacity(64);
    try std.testing.expect(stack.items.capacity >= 64);
}

test "CharArrayStack: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: Stack.init doesn't allocate (backed by ArrayList),
    // so the first alloc (ensureUnusedCapacity grow) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var stack = CharArrayStack.initWithConfig(AllocatorConfig.init(failing.allocator()));
    defer stack.deinit();
    try std.testing.expectError(error.OutOfMemory, stack.ensureUnusedCapacity(1024));
}
