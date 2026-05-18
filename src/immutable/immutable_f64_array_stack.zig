// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const F64ArrayStack = @import("../stack/f64_array_stack.zig").F64ArrayStack;

/// Immutable LIFO stack of `f64` values.
///
/// Persistent operations: `push()` and `pop()` return new immutable stacks
/// rather than modifying in place.
pub const ImmutableF64ArrayStack = struct {
    items: []const f64,
    allocator: Allocator,

    pub fn of(allocator: Allocator, values: []const f64) ImmutableF64ArrayStack {
        const owned = allocator.dupe(f64, values) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn fromMutable(allocator: Allocator, mutable: *const F64ArrayStack) ImmutableF64ArrayStack {
        return of(allocator, mutable.items.items);
    }

    pub fn deinit(self: *ImmutableF64ArrayStack) void {
        self.allocator.free(self.items);
    }

    pub fn peek(self: *const ImmutableF64ArrayStack) ?f64 {
        if (self.items.len == 0) return null;
        return self.items[self.items.len - 1];
    }

    pub fn len(self: *const ImmutableF64ArrayStack) usize {
        return self.items.len;
    }

    pub fn isEmpty(self: *const ImmutableF64ArrayStack) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableF64ArrayStack, value: f64) bool {
        for (self.items) |item| {
            if (@as(u64, @bitCast(item)) == @as(u64, @bitCast(value))) return true;
        }
        return false;
    }

    pub fn toSlice(self: *const ImmutableF64ArrayStack) []const f64 {
        return self.items;
    }

    /// Returns a new immutable stack with the value pushed on top.
    pub fn push(self: *const ImmutableF64ArrayStack, value: f64) ImmutableF64ArrayStack {
        const new_items = self.allocator.alloc(f64, self.items.len + 1) catch @panic("out of memory");
        @memcpy(new_items[0..self.items.len], self.items);
        new_items[self.items.len] = value;
        return .{ .items = new_items, .allocator = self.allocator };
    }

    /// Returns a new immutable stack without the top element, and the popped value.
    /// Returns null if empty.
    pub fn pop(self: *const ImmutableF64ArrayStack) ?struct { stack: ImmutableF64ArrayStack, value: f64 } {
        if (self.items.len == 0) return null;
        const top = self.items[self.items.len - 1];
        const new_items = self.allocator.dupe(f64, self.items[0 .. self.items.len - 1]) catch @panic("out of memory");
        return .{
            .stack = .{ .items = new_items, .allocator = self.allocator },
            .value = top,
        };
    }

    pub fn toMutable(self: *const ImmutableF64ArrayStack) F64ArrayStack {
        return F64ArrayStack.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableF64ArrayStack, other: *const ImmutableF64ArrayStack) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items, other.items) |a, b| {
            if (!(@as(u64, @bitCast(a)) == @as(u64, @bitCast(b)))) return false;
        }
        return true;
    }
};

test "ImmutableF64ArrayStack: of and peek" {
    var il = ImmutableF64ArrayStack.of(std.testing.allocator, &[_]f64{ 1.0, 2.0, 3.0 });
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 3), il.len());
    try std.testing.expectEqual(@as(?f64, 3.0), il.peek());
}

test "ImmutableF64ArrayStack: persistent push" {
    var s1 = ImmutableF64ArrayStack.of(std.testing.allocator, &[_]f64{1.0});
    defer s1.deinit();
    var s2 = s1.push(2.0);
    defer s2.deinit();
    // Original unchanged
    try std.testing.expectEqual(@as(usize, 1), s1.len());
    try std.testing.expectEqual(@as(usize, 2), s2.len());
    try std.testing.expectEqual(@as(?f64, 2.0), s2.peek());
}

test "ImmutableF64ArrayStack: persistent pop" {
    var s1 = ImmutableF64ArrayStack.of(std.testing.allocator, &[_]f64{ 1.0, 2.0 });
    defer s1.deinit();
    const result = s1.pop().?;
    var s2 = result.stack;
    defer s2.deinit();
    try std.testing.expectEqual(2.0, result.value);
    try std.testing.expectEqual(@as(usize, 2), s1.len()); // unchanged
    try std.testing.expectEqual(@as(usize, 1), s2.len());
}

test "ImmutableF64ArrayStack: toMutable independence" {
    var il = ImmutableF64ArrayStack.of(std.testing.allocator, &[_]f64{1.0});
    defer il.deinit();
    var ml = il.toMutable();
    defer ml.deinit();
    ml.push(2.0);
    try std.testing.expectEqual(@as(usize, 1), il.len());
    try std.testing.expectEqual(@as(usize, 2), ml.len());
}
