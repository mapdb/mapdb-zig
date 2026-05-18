// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;

/// Double-ended queue of `bool` values, backed by an `ArrayListUnmanaged`.
/// Back operations (addLast, removeLast) are O(1) amortized.
/// Front operations (addFirst, removeFirst) are O(n) due to shifting.
pub const BoolArrayDeque = struct {
    items: std.ArrayListUnmanaged(bool) = .empty,
    allocator: Allocator,

    pub fn init(allocator: Allocator) BoolArrayDeque {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *BoolArrayDeque) void {
        self.items.deinit(self.allocator);
    }

    pub fn of(allocator: Allocator, values: []const bool) BoolArrayDeque {
        var d = init(allocator);
        d.items.appendSlice(d.allocator, values) catch @panic("out of memory");
        return d;
    }

    /// Adds a value to the front of the deque. O(n) due to shift.
    pub fn addFirst(self: *BoolArrayDeque, value: bool) void {
        self.items.insert(self.allocator, 0, value) catch @panic("out of memory");
    }

    /// Adds a value to the back of the deque. O(1) amortized.
    pub fn addLast(self: *BoolArrayDeque, value: bool) void {
        self.items.append(self.allocator, value) catch @panic("out of memory");
    }

    /// Removes and returns the front element, or null if empty. O(n).
    pub fn removeFirst(self: *BoolArrayDeque) ?bool {
        if (self.items.items.len == 0) return null;
        return self.items.orderedRemove(0);
    }

    /// Removes and returns the back element, or null if empty. O(1).
    pub fn removeLast(self: *BoolArrayDeque) ?bool {
        return self.items.pop();
    }

    /// Returns the front element without removing it, or null if empty.
    pub fn peekFirst(self: *const BoolArrayDeque) ?bool {
        if (self.items.items.len == 0) return null;
        return self.items.items[0];
    }

    /// Returns the back element without removing it, or null if empty.
    pub fn peekLast(self: *const BoolArrayDeque) ?bool {
        if (self.items.items.len == 0) return null;
        return self.items.items[self.items.items.len - 1];
    }

    pub fn len(self: *const BoolArrayDeque) usize {
        return self.items.items.len;
    }
    pub fn isEmpty(self: *const BoolArrayDeque) bool {
        return self.items.items.len == 0;
    }
    pub fn clear(self: *BoolArrayDeque) void {
        self.items.clearRetainingCapacity();
    }

    /// Ensures capacity for `additional` more items.
    pub fn ensureUnusedCapacity(self: *BoolArrayDeque, additional: usize) Allocator.Error!void {
        try self.items.ensureUnusedCapacity(self.allocator, additional);
    }

    pub fn contains(self: *const BoolArrayDeque, value: bool) bool {
        for (self.items.items) |v| {
            if (v == value) return true;
        }
        return false;
    }

    /// Returns a slice view of the items in front-to-back order. Valid until
    /// the next mutation.
    pub fn slice(self: *const BoolArrayDeque) []const bool {
        return self.items.items;
    }

    /// Returns an owned copy of the items in front-to-back order. Caller frees.
    pub fn toOwnedSlice(self: *const BoolArrayDeque, allocator: Allocator) []bool {
        const out = allocator.alloc(bool, self.items.items.len) catch @panic("out of memory");
        @memcpy(out, self.items.items);
        return out;
    }

    pub fn forEach(self: *const BoolArrayDeque, f: *const fn (bool) void) void {
        for (self.items.items) |value| f(value);
    }

    pub fn anySatisfy(self: *const BoolArrayDeque, predicate: *const fn (bool) bool) bool {
        for (self.items.items) |value| {
            if (predicate(value)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const BoolArrayDeque, predicate: *const fn (bool) bool) bool {
        for (self.items.items) |value| {
            if (!predicate(value)) return false;
        }
        return true;
    }

    pub fn eql(self: *const BoolArrayDeque, other: *const BoolArrayDeque) bool {
        if (self.items.items.len != other.items.items.len) return false;
        for (self.items.items, other.items.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }

    pub fn format(self: *const BoolArrayDeque, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll("[");
        for (self.items.items, 0..) |value, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{any}", .{value});
        }
        try writer.writeAll("]");
    }
};

test "BoolArrayDeque: addLast removeFirst FIFO" {
    var d = BoolArrayDeque.init(std.testing.allocator);
    defer d.deinit();
    d.addLast(true);
    d.addLast(false);
    d.addLast(true);
    try std.testing.expectEqual(@as(usize, 3), d.len());
    try std.testing.expectEqual(@as(?bool, true), d.removeFirst());
    try std.testing.expectEqual(@as(?bool, false), d.removeFirst());
    try std.testing.expectEqual(@as(?bool, true), d.removeFirst());
    try std.testing.expect(d.isEmpty());
}

test "BoolArrayDeque: addFirst removeLast" {
    var d = BoolArrayDeque.init(std.testing.allocator);
    defer d.deinit();
    d.addFirst(true);
    d.addFirst(false);
    d.addFirst(true);
    try std.testing.expectEqual(@as(?bool, true), d.peekFirst());
    try std.testing.expectEqual(@as(?bool, true), d.peekLast());
    try std.testing.expectEqual(@as(?bool, true), d.removeLast());
    try std.testing.expectEqual(@as(?bool, false), d.removeLast());
    try std.testing.expectEqual(@as(?bool, true), d.removeLast());
}

test "BoolArrayDeque: remove empty" {
    var d = BoolArrayDeque.init(std.testing.allocator);
    defer d.deinit();
    try std.testing.expectEqual(@as(?bool, null), d.removeFirst());
    try std.testing.expectEqual(@as(?bool, null), d.removeLast());
    try std.testing.expectEqual(@as(?bool, null), d.peekFirst());
    try std.testing.expectEqual(@as(?bool, null), d.peekLast());
}

test "BoolArrayDeque: mixed ops" {
    var d = BoolArrayDeque.init(std.testing.allocator);
    defer d.deinit();
    d.addLast(false);
    d.addFirst(true);
    d.addLast(true);
    try std.testing.expectEqual(@as(?bool, true), d.removeFirst());
    try std.testing.expectEqual(@as(?bool, true), d.removeLast());
    try std.testing.expectEqual(@as(?bool, false), d.removeFirst());
}

test "BoolArrayDeque: contains and clear" {
    var d = BoolArrayDeque.init(std.testing.allocator);
    defer d.deinit();
    d.addLast(true);
    d.addLast(false);
    try std.testing.expect(d.contains(true));
    try std.testing.expect(d.contains(false));
    d.clear();
    try std.testing.expect(d.isEmpty());
}

test "BoolArrayDeque: toOwnedSlice" {
    var d = BoolArrayDeque.init(std.testing.allocator);
    defer d.deinit();
    d.addLast(true);
    d.addLast(false);
    d.addLast(true);
    const out = d.toOwnedSlice(std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqual(@as(usize, 3), out.len);
}

test "BoolArrayDeque: eql" {
    var d1 = BoolArrayDeque.init(std.testing.allocator);
    defer d1.deinit();
    var d2 = BoolArrayDeque.init(std.testing.allocator);
    defer d2.deinit();
    d1.addLast(true);
    d1.addLast(false);
    d2.addLast(true);
    d2.addLast(false);
    try std.testing.expect(d1.eql(&d2));
}
