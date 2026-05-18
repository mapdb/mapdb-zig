// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const I64ArrayStack = @import("../stack/i64_array_stack.zig").I64ArrayStack;

/// Immutable LIFO stack of `i64` values.
///
/// Persistent operations: `push()` and `pop()` return new immutable stacks
/// rather than modifying in place.
pub const ImmutableI64ArrayStack = struct {
    items: []const i64,
    allocator: Allocator,

    pub fn of(allocator: Allocator, values: []const i64) ImmutableI64ArrayStack {
        const owned = allocator.dupe(i64, values) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn fromMutable(allocator: Allocator, mutable: *const I64ArrayStack) ImmutableI64ArrayStack {
        return of(allocator, mutable.items.items);
    }

    pub fn deinit(self: *ImmutableI64ArrayStack) void {
        self.allocator.free(self.items);
    }

    pub fn peek(self: *const ImmutableI64ArrayStack) ?i64 {
        if (self.items.len == 0) return null;
        return self.items[self.items.len - 1];
    }

    pub fn len(self: *const ImmutableI64ArrayStack) usize {
        return self.items.len;
    }

    pub fn isEmpty(self: *const ImmutableI64ArrayStack) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableI64ArrayStack, value: i64) bool {
        for (self.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    pub fn toSlice(self: *const ImmutableI64ArrayStack) []const i64 {
        return self.items;
    }

    /// Returns a new immutable stack with the value pushed on top.
    pub fn push(self: *const ImmutableI64ArrayStack, value: i64) ImmutableI64ArrayStack {
        const new_items = self.allocator.alloc(i64, self.items.len + 1) catch @panic("out of memory");
        @memcpy(new_items[0..self.items.len], self.items);
        new_items[self.items.len] = value;
        return .{ .items = new_items, .allocator = self.allocator };
    }

    /// Returns a new immutable stack without the top element, and the popped value.
    /// Returns null if empty.
    pub fn pop(self: *const ImmutableI64ArrayStack) ?struct { stack: ImmutableI64ArrayStack, value: i64 } {
        if (self.items.len == 0) return null;
        const top = self.items[self.items.len - 1];
        const new_items = self.allocator.dupe(i64, self.items[0 .. self.items.len - 1]) catch @panic("out of memory");
        return .{
            .stack = .{ .items = new_items, .allocator = self.allocator },
            .value = top,
        };
    }

    pub fn toMutable(self: *const ImmutableI64ArrayStack) I64ArrayStack {
        return I64ArrayStack.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableI64ArrayStack, other: *const ImmutableI64ArrayStack) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items, other.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }
};

test "ImmutableI64ArrayStack: of and peek" {
    var il = ImmutableI64ArrayStack.of(std.testing.allocator, &[_]i64{ 1, 2, 3 });
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 3), il.len());
    try std.testing.expectEqual(@as(?i64, 3), il.peek());
}

test "ImmutableI64ArrayStack: persistent push" {
    var s1 = ImmutableI64ArrayStack.of(std.testing.allocator, &[_]i64{1});
    defer s1.deinit();
    var s2 = s1.push(2);
    defer s2.deinit();
    // Original unchanged
    try std.testing.expectEqual(@as(usize, 1), s1.len());
    try std.testing.expectEqual(@as(usize, 2), s2.len());
    try std.testing.expectEqual(@as(?i64, 2), s2.peek());
}

test "ImmutableI64ArrayStack: persistent pop" {
    var s1 = ImmutableI64ArrayStack.of(std.testing.allocator, &[_]i64{ 1, 2 });
    defer s1.deinit();
    const result = s1.pop().?;
    var s2 = result.stack;
    defer s2.deinit();
    try std.testing.expectEqual(2, result.value);
    try std.testing.expectEqual(@as(usize, 2), s1.len()); // unchanged
    try std.testing.expectEqual(@as(usize, 1), s2.len());
}

test "ImmutableI64ArrayStack: toMutable independence" {
    var il = ImmutableI64ArrayStack.of(std.testing.allocator, &[_]i64{1});
    defer il.deinit();
    var ml = il.toMutable();
    defer ml.deinit();
    ml.push(2);
    try std.testing.expectEqual(@as(usize, 1), il.len());
    try std.testing.expectEqual(@as(usize, 2), ml.len());
}
