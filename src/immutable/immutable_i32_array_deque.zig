// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const I32ArrayDeque = @import("../deque/i32_array_deque.zig").I32ArrayDeque;

/// Immutable deque of `i32` values, backed by an owned allocated slice.
/// All "mutating" operations return new immutable deques.
pub const ImmutableI32ArrayDeque = struct {
    items: []const i32,
    allocator: Allocator,

    pub fn of(allocator: Allocator, values: []const i32) ImmutableI32ArrayDeque {
        const owned = allocator.dupe(i32, values) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn fromMutable(allocator: Allocator, mutable: *const I32ArrayDeque) ImmutableI32ArrayDeque {
        return of(allocator, mutable.items.items);
    }

    pub fn deinit(self: *ImmutableI32ArrayDeque) void {
        self.allocator.free(self.items);
    }

    pub fn peekFirst(self: *const ImmutableI32ArrayDeque) ?i32 {
        if (self.items.len == 0) return null;
        return self.items[0];
    }

    pub fn peekLast(self: *const ImmutableI32ArrayDeque) ?i32 {
        if (self.items.len == 0) return null;
        return self.items[self.items.len - 1];
    }

    pub fn len(self: *const ImmutableI32ArrayDeque) usize {
        return self.items.len;
    }
    pub fn isEmpty(self: *const ImmutableI32ArrayDeque) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableI32ArrayDeque, value: i32) bool {
        for (self.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    pub fn toSlice(self: *const ImmutableI32ArrayDeque) []const i32 {
        return self.items;
    }

    /// Returns a new immutable deque with `value` prepended at the front.
    pub fn withFirst(self: *const ImmutableI32ArrayDeque, value: i32) ImmutableI32ArrayDeque {
        const new_items = self.allocator.alloc(i32, self.items.len + 1) catch @panic("out of memory");
        new_items[0] = value;
        @memcpy(new_items[1..], self.items);
        return .{ .items = new_items, .allocator = self.allocator };
    }

    /// Returns a new immutable deque with `value` appended at the back.
    pub fn withLast(self: *const ImmutableI32ArrayDeque, value: i32) ImmutableI32ArrayDeque {
        const new_items = self.allocator.alloc(i32, self.items.len + 1) catch @panic("out of memory");
        @memcpy(new_items[0..self.items.len], self.items);
        new_items[self.items.len] = value;
        return .{ .items = new_items, .allocator = self.allocator };
    }

    /// Returns a new deque without the front element, and the removed value.
    pub fn withoutFirst(self: *const ImmutableI32ArrayDeque) ?struct { deque: ImmutableI32ArrayDeque, value: i32 } {
        if (self.items.len == 0) return null;
        const first = self.items[0];
        const new_items = self.allocator.dupe(i32, self.items[1..]) catch @panic("out of memory");
        return .{
            .deque = .{ .items = new_items, .allocator = self.allocator },
            .value = first,
        };
    }

    /// Returns a new deque without the back element, and the removed value.
    pub fn withoutLast(self: *const ImmutableI32ArrayDeque) ?struct { deque: ImmutableI32ArrayDeque, value: i32 } {
        if (self.items.len == 0) return null;
        const last = self.items[self.items.len - 1];
        const new_items = self.allocator.dupe(i32, self.items[0 .. self.items.len - 1]) catch @panic("out of memory");
        return .{
            .deque = .{ .items = new_items, .allocator = self.allocator },
            .value = last,
        };
    }

    pub fn forEach(self: *const ImmutableI32ArrayDeque, f: *const fn (i32) void) void {
        for (self.items) |value| f(value);
    }

    pub fn toMutable(self: *const ImmutableI32ArrayDeque) I32ArrayDeque {
        return I32ArrayDeque.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableI32ArrayDeque, other: *const ImmutableI32ArrayDeque) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items, other.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }
};

test "ImmutableI32ArrayDeque: of and peek" {
    var d = ImmutableI32ArrayDeque.of(std.testing.allocator, &[_]i32{ 1, 2, 3 });
    defer d.deinit();
    try std.testing.expectEqual(@as(usize, 3), d.len());
    try std.testing.expectEqual(@as(?i32, 1), d.peekFirst());
    try std.testing.expectEqual(@as(?i32, 3), d.peekLast());
}

test "ImmutableI32ArrayDeque: persistent withFirst/withLast" {
    var d1 = ImmutableI32ArrayDeque.of(std.testing.allocator, &[_]i32{2});
    defer d1.deinit();
    var d2 = d1.withFirst(1);
    defer d2.deinit();
    var d3 = d2.withLast(3);
    defer d3.deinit();
    try std.testing.expectEqual(@as(usize, 1), d1.len());
    try std.testing.expectEqual(@as(usize, 3), d3.len());
    try std.testing.expectEqual(@as(?i32, 1), d3.peekFirst());
    try std.testing.expectEqual(@as(?i32, 3), d3.peekLast());
}

test "ImmutableI32ArrayDeque: withoutFirst/withoutLast" {
    var d = ImmutableI32ArrayDeque.of(std.testing.allocator, &[_]i32{ 1, 2, 3 });
    defer d.deinit();
    const r1 = d.withoutFirst().?;
    var d2 = r1.deque;
    defer d2.deinit();
    try std.testing.expectEqual(1, r1.value);
    try std.testing.expectEqual(@as(usize, 2), d2.len());

    const r2 = d.withoutLast().?;
    var d3 = r2.deque;
    defer d3.deinit();
    try std.testing.expectEqual(3, r2.value);
    try std.testing.expectEqual(@as(usize, 2), d3.len());

    // Original untouched
    try std.testing.expectEqual(@as(usize, 3), d.len());
}

test "ImmutableI32ArrayDeque: fromMutable and toMutable independence" {
    var ml = I32ArrayDeque.init(std.testing.allocator);
    defer ml.deinit();
    ml.addLast(1);
    ml.addLast(2);
    var il = ImmutableI32ArrayDeque.fromMutable(std.testing.allocator, &ml);
    defer il.deinit();
    var ml2 = il.toMutable();
    defer ml2.deinit();
    ml2.addLast(3);
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expectEqual(@as(usize, 3), ml2.len());
}

test "ImmutableI32ArrayDeque: eql and contains" {
    var a = ImmutableI32ArrayDeque.of(std.testing.allocator, &[_]i32{ 1, 2 });
    defer a.deinit();
    var b = ImmutableI32ArrayDeque.of(std.testing.allocator, &[_]i32{ 1, 2 });
    defer b.deinit();
    try std.testing.expect(a.eql(&b));
    try std.testing.expect(a.contains(1));
}
