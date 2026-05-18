
const std = @import("std");
const Allocator = std.mem.Allocator;
const BoolArrayStack = @import("../stack/bool_array_stack.zig").BoolArrayStack;

/// Immutable LIFO stack of `bool` values.
///
/// Persistent operations: `push()` and `pop()` return new immutable stacks
/// rather than modifying in place.
pub const ImmutableBoolArrayStack = struct {
    items: []const bool,
    allocator: Allocator,

    pub fn of(allocator: Allocator, values: []const bool) ImmutableBoolArrayStack {
        const owned = allocator.dupe(bool, values) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn fromMutable(allocator: Allocator, mutable: *const BoolArrayStack) ImmutableBoolArrayStack {
        return of(allocator, mutable.items.items);
    }

    pub fn deinit(self: *ImmutableBoolArrayStack) void {
        self.allocator.free(self.items);
    }

    pub fn peek(self: *const ImmutableBoolArrayStack) ?bool {
        if (self.items.len == 0) return null;
        return self.items[self.items.len - 1];
    }

    pub fn len(self: *const ImmutableBoolArrayStack) usize {
        return self.items.len;
    }

    pub fn isEmpty(self: *const ImmutableBoolArrayStack) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableBoolArrayStack, value: bool) bool {
        for (self.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    pub fn toSlice(self: *const ImmutableBoolArrayStack) []const bool {
        return self.items;
    }

    /// Returns a new immutable stack with the value pushed on top.
    pub fn push(self: *const ImmutableBoolArrayStack, value: bool) ImmutableBoolArrayStack {
        const new_items = self.allocator.alloc(bool, self.items.len + 1) catch @panic("out of memory");
        @memcpy(new_items[0..self.items.len], self.items);
        new_items[self.items.len] = value;
        return .{ .items = new_items, .allocator = self.allocator };
    }

    /// Returns a new immutable stack without the top element, and the popped value.
    /// Returns null if empty.
    pub fn pop(self: *const ImmutableBoolArrayStack) ?struct { stack: ImmutableBoolArrayStack, value: bool } {
        if (self.items.len == 0) return null;
        const top = self.items[self.items.len - 1];
        const new_items = self.allocator.dupe(bool, self.items[0 .. self.items.len - 1]) catch @panic("out of memory");
        return .{
            .stack = .{ .items = new_items, .allocator = self.allocator },
            .value = top,
        };
    }

    pub fn toMutable(self: *const ImmutableBoolArrayStack) BoolArrayStack {
        return BoolArrayStack.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableBoolArrayStack, other: *const ImmutableBoolArrayStack) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items, other.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }
};

test "ImmutableBoolArrayStack: of and peek" {
    var il = ImmutableBoolArrayStack.of(std.testing.allocator, &[_]bool{ true, false, true });
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 3), il.len());
    try std.testing.expectEqual(@as(?bool, true), il.peek());
}

test "ImmutableBoolArrayStack: persistent push" {
    var s1 = ImmutableBoolArrayStack.of(std.testing.allocator, &[_]bool{true});
    defer s1.deinit();
    var s2 = s1.push(false);
    defer s2.deinit();
    // Original unchanged
    try std.testing.expectEqual(@as(usize, 1), s1.len());
    try std.testing.expectEqual(@as(usize, 2), s2.len());
    try std.testing.expectEqual(@as(?bool, false), s2.peek());
}

test "ImmutableBoolArrayStack: persistent pop" {
    var s1 = ImmutableBoolArrayStack.of(std.testing.allocator, &[_]bool{ true, false });
    defer s1.deinit();
    const result = s1.pop().?;
    var s2 = result.stack;
    defer s2.deinit();
    try std.testing.expectEqual(false, result.value);
    try std.testing.expectEqual(@as(usize, 2), s1.len()); // unchanged
    try std.testing.expectEqual(@as(usize, 1), s2.len());
}

test "ImmutableBoolArrayStack: toMutable independence" {
    var il = ImmutableBoolArrayStack.of(std.testing.allocator, &[_]bool{true});
    defer il.deinit();
    var ml = il.toMutable();
    defer ml.deinit();
    ml.push(false);
    try std.testing.expectEqual(@as(usize, 1), il.len());
    try std.testing.expectEqual(@as(usize, 2), ml.len());
}
