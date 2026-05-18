
const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;

/// LIFO stack of `f64` values, backed by an ArrayList.
pub const F64ArrayStack = struct {
    items: std.ArrayListUnmanaged(f64) = .empty,
    config: AllocatorConfig,

    pub fn init(allocator: Allocator) F64ArrayStack {
        return .{ .config = AllocatorConfig.init(allocator) };
    }

    pub fn initWithConfig(config: AllocatorConfig) F64ArrayStack {
        return .{ .config = config };
    }

    pub fn deinit(self: *F64ArrayStack) void {
        self.items.deinit(self.config.itemsAllocator());
    }

    pub fn of(allocator: Allocator, values: []const f64) F64ArrayStack {
        var stack = init(allocator);
        stack.items.appendSlice(stack.config.itemsAllocator(), values) catch @panic("out of memory");
        return stack;
    }

    /// Pushes a value onto the top of the stack.
    pub fn push(self: *F64ArrayStack, value: f64) void {
        self.items.append(self.config.itemsAllocator(), value) catch @panic("out of memory");
    }

    /// Removes and returns the top element, or null if empty.
    pub fn pop(self: *F64ArrayStack) ?f64 {
        if (self.items.items.len == 0) return null;
        return self.items.pop();
    }

    /// Returns the top element without removing it, or null if empty.
    pub fn peek(self: *const F64ArrayStack) ?f64 {
        if (self.items.items.len == 0) return null;
        return self.items.items[self.items.items.len - 1];
    }

    /// Returns the element at the given depth from the top (0 = top).
    pub fn peekAt(self: *const F64ArrayStack, depth: usize) ?f64 {
        if (depth >= self.items.items.len) return null;
        return self.items.items[self.items.items.len - 1 - depth];
    }

    pub fn len(self: *const F64ArrayStack) usize {
        return self.items.items.len;
    }

    /// Alias for len() — matches Go/Java naming.
    pub fn size(self: *const F64ArrayStack) usize {
        return self.len();
    }

    pub fn isEmpty(self: *const F64ArrayStack) bool {
        return self.items.items.len == 0;
    }

    pub fn clear(self: *F64ArrayStack) void {
        self.items.clearRetainingCapacity();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more items can be pushed without a
    /// reallocation.
    pub fn ensureUnusedCapacity(self: *F64ArrayStack, additional: usize) Allocator.Error!void {
        return self.items.ensureUnusedCapacity(self.config.itemsAllocator(), additional);
    }

    /// Ensures the stack's total capacity is at least `new_capacity`.
    pub fn ensureTotalCapacity(self: *F64ArrayStack, new_capacity: usize) Allocator.Error!void {
        return self.items.ensureTotalCapacity(self.config.itemsAllocator(), new_capacity);
    }

    pub fn contains(self: *const F64ArrayStack, value: f64) bool {
        for (self.items.items) |item| {
            if (@as(u64, @bitCast(item)) == @as(u64, @bitCast(value))) return true;
        }
        return false;
    }

    pub fn anySatisfy(self: *const F64ArrayStack, predicate: *const fn (f64) bool) bool {
        for (self.items.items) |item| {
            if (predicate(item)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const F64ArrayStack, predicate: *const fn (f64) bool) bool {
        for (self.items.items) |item| {
            if (!predicate(item)) return false;
        }
        return true;
    }

    // ---- Iteration ----

    /// Calls f for each element (bottom to top).
    pub fn forEach(self: *const F64ArrayStack, f: *const fn (f64) void) void {
        for (self.items.items) |item| f(item);
    }

    // ---- Functional Operations ----

    /// Returns a new stack with only elements satisfying the predicate.
    pub fn select(self: *const F64ArrayStack, predicate: *const fn (f64) bool) F64ArrayStack {
        var result = init(self.config.base);
        for (self.items.items) |item| {
            if (predicate(item)) result.push(item);
        }
        return result;
    }

    /// Returns a new stack with elements NOT satisfying the predicate.
    pub fn reject(self: *const F64ArrayStack, predicate: *const fn (f64) bool) F64ArrayStack {
        var result = init(self.config.base);
        for (self.items.items) |item| {
            if (!predicate(item)) result.push(item);
        }
        return result;
    }

    /// Returns the first element satisfying the predicate, or null.
    pub fn detect(self: *const F64ArrayStack, predicate: *const fn (f64) bool) ?f64 {
        for (self.items.items) |item| {
            if (predicate(item)) return item;
        }
        return null;
    }

    pub fn noneSatisfy(self: *const F64ArrayStack, predicate: *const fn (f64) bool) bool {
        for (self.items.items) |item| {
            if (predicate(item)) return false;
        }
        return true;
    }

    pub fn count(self: *const F64ArrayStack, predicate: *const fn (f64) bool) usize {
        var c: usize = 0;
        for (self.items.items) |item| {
            if (predicate(item)) c += 1;
        }
        return c;
    }

    pub fn injectInto(self: *const F64ArrayStack, initial: f64, f: *const fn (f64, f64) f64) f64 {
        var acc = initial;
        for (self.items.items) |item| acc = f(acc, item);
        return acc;
    }

    // ---- Conversion ----

    pub fn toSlice(self: *const F64ArrayStack) []const f64 {
        return self.items.items;
    }

    pub fn toImmutable(self: *const F64ArrayStack) @import("../immutable/immutable_f64_array_stack.zig").ImmutableF64ArrayStack {
        return @import("../immutable/immutable_f64_array_stack.zig").ImmutableF64ArrayStack.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    pub fn with(self: *F64ArrayStack, value: f64) *F64ArrayStack {
        self.push(value);
        return self;
    }

    pub fn withAll(self: *F64ArrayStack, values: []const f64) *F64ArrayStack {
        for (values) |val| self.push(val);
        return self;
    }

    // ---- Formatting ----

    /// Formats as "[top, ..., bottom]" (top-to-bottom order).
    pub fn format(self: *const F64ArrayStack, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const F64ArrayStack, other: *const F64ArrayStack) bool {
        if (self.items.items.len != other.items.items.len) return false;
        for (self.items.items, other.items.items) |a, b| {
            if (!(@as(u64, @bitCast(a)) == @as(u64, @bitCast(b)))) return false;
        }
        return true;
    }
};

test "F64ArrayStack: push peek pop" {
    var stack = F64ArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    stack.push(1.0);
    stack.push(2.0);
    stack.push(3.0);
    try std.testing.expectEqual(@as(usize, 3), stack.len());
    try std.testing.expectEqual(@as(?f64, 3.0), stack.peek());
    try std.testing.expectEqual(@as(?f64, 3.0), stack.pop());
    try std.testing.expectEqual(@as(usize, 2), stack.len());
}

test "F64ArrayStack: pop empty" {
    var stack = F64ArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    try std.testing.expectEqual(@as(?f64, null), stack.pop());
    try std.testing.expectEqual(@as(?f64, null), stack.peek());
}

test "F64ArrayStack: LIFO order" {
    var stack = F64ArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    stack.push(1.0);
    stack.push(2.0);
    stack.push(3.0);
    try std.testing.expectEqual(@as(?f64, 3.0), stack.pop());
    try std.testing.expectEqual(@as(?f64, 2.0), stack.pop());
    try std.testing.expectEqual(@as(?f64, 1.0), stack.pop());
}

test "F64ArrayStack: contains" {
    var stack = F64ArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    stack.push(1.0);
    try std.testing.expect(stack.contains(1.0));
    try std.testing.expect(!stack.contains(3.0));
}

test "F64ArrayStack: clear" {
    var stack = F64ArrayStack.of(std.testing.allocator, &[_]f64{1.0});
    defer stack.deinit();
    stack.clear();
    try std.testing.expect(stack.isEmpty());
}

test "F64ArrayStack: eql" {
    var s1 = F64ArrayStack.of(std.testing.allocator, &[_]f64{ 1.0, 2.0 });
    defer s1.deinit();
    var s2 = F64ArrayStack.of(std.testing.allocator, &[_]f64{ 1.0, 2.0 });
    defer s2.deinit();
    var s3 = F64ArrayStack.of(std.testing.allocator, &[_]f64{1.0});
    defer s3.deinit();
    try std.testing.expect(s1.eql(&s2));
    try std.testing.expect(!s1.eql(&s3));
}

test "F64ArrayStack: select and reject" {
    var stack = F64ArrayStack.of(std.testing.allocator, &[_]f64{ 1.0, 2.0, 3.0 });
    defer stack.deinit();
    var sel = stack.select(struct {
        fn f(val: f64) bool {
            return val > 1.0;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expectEqual(@as(usize, 2), sel.len());
}

test "F64ArrayStack: toImmutable" {
    var stack = F64ArrayStack.of(std.testing.allocator, &[_]f64{ 1.0, 2.0 });
    defer stack.deinit();
    var imm = stack.toImmutable();
    defer imm.deinit();
    try std.testing.expectEqual(@as(usize, 2), imm.len());
    stack.push(3.0);
    try std.testing.expectEqual(@as(usize, 2), imm.len());
}

test "F64ArrayStack: fluent with" {
    var stack = F64ArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    _ = stack.with(1.0).with(2.0);
    try std.testing.expectEqual(@as(usize, 2), stack.len());
}

test "F64ArrayStack: ensureUnusedCapacity reserves and subsequent push does not reallocate" {
    var stack = F64ArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    try stack.ensureUnusedCapacity(10);
    const reserved = stack.items.capacity;
    try std.testing.expect(reserved >= 10);
    stack.push(1.0);
    stack.push(2.0);
    stack.push(3.0);
    try std.testing.expectEqual(reserved, stack.items.capacity);
}

test "F64ArrayStack: ensureTotalCapacity sets minimum capacity" {
    var stack = F64ArrayStack.init(std.testing.allocator);
    defer stack.deinit();
    try stack.ensureTotalCapacity(64);
    try std.testing.expect(stack.items.capacity >= 64);
}

test "F64ArrayStack: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: Stack.init doesn't allocate (backed by ArrayList),
    // so the first alloc (ensureUnusedCapacity grow) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var stack = F64ArrayStack.initWithConfig(AllocatorConfig.init(failing.allocator()));
    defer stack.deinit();
    try std.testing.expectError(error.OutOfMemory, stack.ensureUnusedCapacity(1024));
}
