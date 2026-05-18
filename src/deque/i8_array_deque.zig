
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Double-ended queue of `i8` values, backed by an `ArrayListUnmanaged`.
/// Back operations (addLast, removeLast) are O(1) amortized.
/// Front operations (addFirst, removeFirst) are O(n) due to shifting.
pub const I8ArrayDeque = struct {
    items: std.ArrayListUnmanaged(i8) = .empty,
    allocator: Allocator,

    pub fn init(allocator: Allocator) I8ArrayDeque {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *I8ArrayDeque) void {
        self.items.deinit(self.allocator);
    }

    pub fn of(allocator: Allocator, values: []const i8) I8ArrayDeque {
        var d = init(allocator);
        d.items.appendSlice(d.allocator, values) catch @panic("out of memory");
        return d;
    }

    /// Adds a value to the front of the deque. O(n) due to shift.
    pub fn addFirst(self: *I8ArrayDeque, value: i8) void {
        self.items.insert(self.allocator, 0, value) catch @panic("out of memory");
    }

    /// Adds a value to the back of the deque. O(1) amortized.
    pub fn addLast(self: *I8ArrayDeque, value: i8) void {
        self.items.append(self.allocator, value) catch @panic("out of memory");
    }

    /// Removes and returns the front element, or null if empty. O(n).
    pub fn removeFirst(self: *I8ArrayDeque) ?i8 {
        if (self.items.items.len == 0) return null;
        return self.items.orderedRemove(0);
    }

    /// Removes and returns the back element, or null if empty. O(1).
    pub fn removeLast(self: *I8ArrayDeque) ?i8 {
        return self.items.pop();
    }

    /// Returns the front element without removing it, or null if empty.
    pub fn peekFirst(self: *const I8ArrayDeque) ?i8 {
        if (self.items.items.len == 0) return null;
        return self.items.items[0];
    }

    /// Returns the back element without removing it, or null if empty.
    pub fn peekLast(self: *const I8ArrayDeque) ?i8 {
        if (self.items.items.len == 0) return null;
        return self.items.items[self.items.items.len - 1];
    }

    pub fn len(self: *const I8ArrayDeque) usize {
        return self.items.items.len;
    }
    pub fn isEmpty(self: *const I8ArrayDeque) bool {
        return self.items.items.len == 0;
    }
    pub fn clear(self: *I8ArrayDeque) void {
        self.items.clearRetainingCapacity();
    }

    /// Ensures capacity for `additional` more items.
    pub fn ensureUnusedCapacity(self: *I8ArrayDeque, additional: usize) Allocator.Error!void {
        try self.items.ensureUnusedCapacity(self.allocator, additional);
    }

    pub fn contains(self: *const I8ArrayDeque, value: i8) bool {
        for (self.items.items) |v| {
            if (v == value) return true;
        }
        return false;
    }

    /// Returns a slice view of the items in front-to-back order. Valid until
    /// the next mutation.
    pub fn slice(self: *const I8ArrayDeque) []const i8 {
        return self.items.items;
    }

    /// Returns an owned copy of the items in front-to-back order. Caller frees.
    pub fn toOwnedSlice(self: *const I8ArrayDeque, allocator: Allocator) []i8 {
        const out = allocator.alloc(i8, self.items.items.len) catch @panic("out of memory");
        @memcpy(out, self.items.items);
        return out;
    }

    pub fn forEach(self: *const I8ArrayDeque, f: *const fn (i8) void) void {
        for (self.items.items) |value| f(value);
    }

    pub fn anySatisfy(self: *const I8ArrayDeque, predicate: *const fn (i8) bool) bool {
        for (self.items.items) |value| {
            if (predicate(value)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const I8ArrayDeque, predicate: *const fn (i8) bool) bool {
        for (self.items.items) |value| {
            if (!predicate(value)) return false;
        }
        return true;
    }

    pub fn eql(self: *const I8ArrayDeque, other: *const I8ArrayDeque) bool {
        if (self.items.items.len != other.items.items.len) return false;
        for (self.items.items, other.items.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }

    pub fn format(self: *const I8ArrayDeque, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll("[");
        for (self.items.items, 0..) |value, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{any}", .{value});
        }
        try writer.writeAll("]");
    }
};

test "I8ArrayDeque: addLast removeFirst FIFO" {
    var d = I8ArrayDeque.init(std.testing.allocator);
    defer d.deinit();
    d.addLast(1);
    d.addLast(2);
    d.addLast(3);
    try std.testing.expectEqual(@as(usize, 3), d.len());
    try std.testing.expectEqual(@as(?i8, 1), d.removeFirst());
    try std.testing.expectEqual(@as(?i8, 2), d.removeFirst());
    try std.testing.expectEqual(@as(?i8, 3), d.removeFirst());
    try std.testing.expect(d.isEmpty());
}

test "I8ArrayDeque: addFirst removeLast" {
    var d = I8ArrayDeque.init(std.testing.allocator);
    defer d.deinit();
    d.addFirst(1);
    d.addFirst(2);
    d.addFirst(3);
    try std.testing.expectEqual(@as(?i8, 3), d.peekFirst());
    try std.testing.expectEqual(@as(?i8, 1), d.peekLast());
    try std.testing.expectEqual(@as(?i8, 1), d.removeLast());
    try std.testing.expectEqual(@as(?i8, 2), d.removeLast());
    try std.testing.expectEqual(@as(?i8, 3), d.removeLast());
}

test "I8ArrayDeque: remove empty" {
    var d = I8ArrayDeque.init(std.testing.allocator);
    defer d.deinit();
    try std.testing.expectEqual(@as(?i8, null), d.removeFirst());
    try std.testing.expectEqual(@as(?i8, null), d.removeLast());
    try std.testing.expectEqual(@as(?i8, null), d.peekFirst());
    try std.testing.expectEqual(@as(?i8, null), d.peekLast());
}

test "I8ArrayDeque: mixed ops" {
    var d = I8ArrayDeque.init(std.testing.allocator);
    defer d.deinit();
    d.addLast(2);
    d.addFirst(1);
    d.addLast(3);
    try std.testing.expectEqual(@as(?i8, 1), d.removeFirst());
    try std.testing.expectEqual(@as(?i8, 3), d.removeLast());
    try std.testing.expectEqual(@as(?i8, 2), d.removeFirst());
}

test "I8ArrayDeque: contains and clear" {
    var d = I8ArrayDeque.init(std.testing.allocator);
    defer d.deinit();
    d.addLast(1);
    d.addLast(2);
    try std.testing.expect(d.contains(1));
    try std.testing.expect(d.contains(2));
    d.clear();
    try std.testing.expect(d.isEmpty());
}

test "I8ArrayDeque: toOwnedSlice" {
    var d = I8ArrayDeque.init(std.testing.allocator);
    defer d.deinit();
    d.addLast(1);
    d.addLast(2);
    d.addLast(3);
    const out = d.toOwnedSlice(std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqual(@as(usize, 3), out.len);
}

test "I8ArrayDeque: eql" {
    var d1 = I8ArrayDeque.init(std.testing.allocator);
    defer d1.deinit();
    var d2 = I8ArrayDeque.init(std.testing.allocator);
    defer d2.deinit();
    d1.addLast(1);
    d1.addLast(2);
    d2.addLast(1);
    d2.addLast(2);
    try std.testing.expect(d1.eql(&d2));
}
