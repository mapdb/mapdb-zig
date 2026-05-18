
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Double-ended queue of `u21` values, backed by an `ArrayListUnmanaged`.
/// Back operations (addLast, removeLast) are O(1) amortized.
/// Front operations (addFirst, removeFirst) are O(n) due to shifting.
pub const CharArrayDeque = struct {
    items: std.ArrayListUnmanaged(u21) = .empty,
    allocator: Allocator,

    pub fn init(allocator: Allocator) CharArrayDeque {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *CharArrayDeque) void {
        self.items.deinit(self.allocator);
    }

    pub fn of(allocator: Allocator, values: []const u21) CharArrayDeque {
        var d = init(allocator);
        d.items.appendSlice(d.allocator, values) catch @panic("out of memory");
        return d;
    }

    /// Adds a value to the front of the deque. O(n) due to shift.
    pub fn addFirst(self: *CharArrayDeque, value: u21) void {
        self.items.insert(self.allocator, 0, value) catch @panic("out of memory");
    }

    /// Adds a value to the back of the deque. O(1) amortized.
    pub fn addLast(self: *CharArrayDeque, value: u21) void {
        self.items.append(self.allocator, value) catch @panic("out of memory");
    }

    /// Removes and returns the front element, or null if empty. O(n).
    pub fn removeFirst(self: *CharArrayDeque) ?u21 {
        if (self.items.items.len == 0) return null;
        return self.items.orderedRemove(0);
    }

    /// Removes and returns the back element, or null if empty. O(1).
    pub fn removeLast(self: *CharArrayDeque) ?u21 {
        return self.items.pop();
    }

    /// Returns the front element without removing it, or null if empty.
    pub fn peekFirst(self: *const CharArrayDeque) ?u21 {
        if (self.items.items.len == 0) return null;
        return self.items.items[0];
    }

    /// Returns the back element without removing it, or null if empty.
    pub fn peekLast(self: *const CharArrayDeque) ?u21 {
        if (self.items.items.len == 0) return null;
        return self.items.items[self.items.items.len - 1];
    }

    pub fn len(self: *const CharArrayDeque) usize {
        return self.items.items.len;
    }
    pub fn isEmpty(self: *const CharArrayDeque) bool {
        return self.items.items.len == 0;
    }
    pub fn clear(self: *CharArrayDeque) void {
        self.items.clearRetainingCapacity();
    }

    /// Ensures capacity for `additional` more items.
    pub fn ensureUnusedCapacity(self: *CharArrayDeque, additional: usize) Allocator.Error!void {
        try self.items.ensureUnusedCapacity(self.allocator, additional);
    }

    pub fn contains(self: *const CharArrayDeque, value: u21) bool {
        for (self.items.items) |v| {
            if (v == value) return true;
        }
        return false;
    }

    /// Returns a slice view of the items in front-to-back order. Valid until
    /// the next mutation.
    pub fn slice(self: *const CharArrayDeque) []const u21 {
        return self.items.items;
    }

    /// Returns an owned copy of the items in front-to-back order. Caller frees.
    pub fn toOwnedSlice(self: *const CharArrayDeque, allocator: Allocator) []u21 {
        const out = allocator.alloc(u21, self.items.items.len) catch @panic("out of memory");
        @memcpy(out, self.items.items);
        return out;
    }

    pub fn forEach(self: *const CharArrayDeque, f: *const fn (u21) void) void {
        for (self.items.items) |value| f(value);
    }

    pub fn anySatisfy(self: *const CharArrayDeque, predicate: *const fn (u21) bool) bool {
        for (self.items.items) |value| {
            if (predicate(value)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const CharArrayDeque, predicate: *const fn (u21) bool) bool {
        for (self.items.items) |value| {
            if (!predicate(value)) return false;
        }
        return true;
    }

    pub fn eql(self: *const CharArrayDeque, other: *const CharArrayDeque) bool {
        if (self.items.items.len != other.items.items.len) return false;
        for (self.items.items, other.items.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }

    pub fn format(self: *const CharArrayDeque, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll("[");
        for (self.items.items, 0..) |value, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{any}", .{value});
        }
        try writer.writeAll("]");
    }
};

test "CharArrayDeque: addLast removeFirst FIFO" {
    var d = CharArrayDeque.init(std.testing.allocator);
    defer d.deinit();
    d.addLast('a');
    d.addLast('b');
    d.addLast('c');
    try std.testing.expectEqual(@as(usize, 3), d.len());
    try std.testing.expectEqual(@as(?u21, 'a'), d.removeFirst());
    try std.testing.expectEqual(@as(?u21, 'b'), d.removeFirst());
    try std.testing.expectEqual(@as(?u21, 'c'), d.removeFirst());
    try std.testing.expect(d.isEmpty());
}

test "CharArrayDeque: addFirst removeLast" {
    var d = CharArrayDeque.init(std.testing.allocator);
    defer d.deinit();
    d.addFirst('a');
    d.addFirst('b');
    d.addFirst('c');
    try std.testing.expectEqual(@as(?u21, 'c'), d.peekFirst());
    try std.testing.expectEqual(@as(?u21, 'a'), d.peekLast());
    try std.testing.expectEqual(@as(?u21, 'a'), d.removeLast());
    try std.testing.expectEqual(@as(?u21, 'b'), d.removeLast());
    try std.testing.expectEqual(@as(?u21, 'c'), d.removeLast());
}

test "CharArrayDeque: remove empty" {
    var d = CharArrayDeque.init(std.testing.allocator);
    defer d.deinit();
    try std.testing.expectEqual(@as(?u21, null), d.removeFirst());
    try std.testing.expectEqual(@as(?u21, null), d.removeLast());
    try std.testing.expectEqual(@as(?u21, null), d.peekFirst());
    try std.testing.expectEqual(@as(?u21, null), d.peekLast());
}

test "CharArrayDeque: mixed ops" {
    var d = CharArrayDeque.init(std.testing.allocator);
    defer d.deinit();
    d.addLast('b');
    d.addFirst('a');
    d.addLast('c');
    try std.testing.expectEqual(@as(?u21, 'a'), d.removeFirst());
    try std.testing.expectEqual(@as(?u21, 'c'), d.removeLast());
    try std.testing.expectEqual(@as(?u21, 'b'), d.removeFirst());
}

test "CharArrayDeque: contains and clear" {
    var d = CharArrayDeque.init(std.testing.allocator);
    defer d.deinit();
    d.addLast('a');
    d.addLast('b');
    try std.testing.expect(d.contains('a'));
    try std.testing.expect(d.contains('b'));
    d.clear();
    try std.testing.expect(d.isEmpty());
}

test "CharArrayDeque: toOwnedSlice" {
    var d = CharArrayDeque.init(std.testing.allocator);
    defer d.deinit();
    d.addLast('a');
    d.addLast('b');
    d.addLast('c');
    const out = d.toOwnedSlice(std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqual(@as(usize, 3), out.len);
}

test "CharArrayDeque: eql" {
    var d1 = CharArrayDeque.init(std.testing.allocator);
    defer d1.deinit();
    var d2 = CharArrayDeque.init(std.testing.allocator);
    defer d2.deinit();
    d1.addLast('a');
    d1.addLast('b');
    d2.addLast('a');
    d2.addLast('b');
    try std.testing.expect(d1.eql(&d2));
}
