
const std = @import("std");
const Allocator = std.mem.Allocator;
const CharArrayDeque = @import("../deque/char_array_deque.zig").CharArrayDeque;

/// Immutable deque of `u21` values, backed by an owned allocated slice.
/// All "mutating" operations return new immutable deques.
pub const ImmutableCharArrayDeque = struct {
    items: []const u21,
    allocator: Allocator,

    pub fn of(allocator: Allocator, values: []const u21) ImmutableCharArrayDeque {
        const owned = allocator.dupe(u21, values) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn fromMutable(allocator: Allocator, mutable: *const CharArrayDeque) ImmutableCharArrayDeque {
        return of(allocator, mutable.items.items);
    }

    pub fn deinit(self: *ImmutableCharArrayDeque) void {
        self.allocator.free(self.items);
    }

    pub fn peekFirst(self: *const ImmutableCharArrayDeque) ?u21 {
        if (self.items.len == 0) return null;
        return self.items[0];
    }

    pub fn peekLast(self: *const ImmutableCharArrayDeque) ?u21 {
        if (self.items.len == 0) return null;
        return self.items[self.items.len - 1];
    }

    pub fn len(self: *const ImmutableCharArrayDeque) usize {
        return self.items.len;
    }
    pub fn isEmpty(self: *const ImmutableCharArrayDeque) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableCharArrayDeque, value: u21) bool {
        for (self.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    pub fn toSlice(self: *const ImmutableCharArrayDeque) []const u21 {
        return self.items;
    }

    /// Returns a new immutable deque with `value` prepended at the front.
    pub fn withFirst(self: *const ImmutableCharArrayDeque, value: u21) ImmutableCharArrayDeque {
        const new_items = self.allocator.alloc(u21, self.items.len + 1) catch @panic("out of memory");
        new_items[0] = value;
        @memcpy(new_items[1..], self.items);
        return .{ .items = new_items, .allocator = self.allocator };
    }

    /// Returns a new immutable deque with `value` appended at the back.
    pub fn withLast(self: *const ImmutableCharArrayDeque, value: u21) ImmutableCharArrayDeque {
        const new_items = self.allocator.alloc(u21, self.items.len + 1) catch @panic("out of memory");
        @memcpy(new_items[0..self.items.len], self.items);
        new_items[self.items.len] = value;
        return .{ .items = new_items, .allocator = self.allocator };
    }

    /// Returns a new deque without the front element, and the removed value.
    pub fn withoutFirst(self: *const ImmutableCharArrayDeque) ?struct { deque: ImmutableCharArrayDeque, value: u21 } {
        if (self.items.len == 0) return null;
        const first = self.items[0];
        const new_items = self.allocator.dupe(u21, self.items[1..]) catch @panic("out of memory");
        return .{
            .deque = .{ .items = new_items, .allocator = self.allocator },
            .value = first,
        };
    }

    /// Returns a new deque without the back element, and the removed value.
    pub fn withoutLast(self: *const ImmutableCharArrayDeque) ?struct { deque: ImmutableCharArrayDeque, value: u21 } {
        if (self.items.len == 0) return null;
        const last = self.items[self.items.len - 1];
        const new_items = self.allocator.dupe(u21, self.items[0 .. self.items.len - 1]) catch @panic("out of memory");
        return .{
            .deque = .{ .items = new_items, .allocator = self.allocator },
            .value = last,
        };
    }

    pub fn forEach(self: *const ImmutableCharArrayDeque, f: *const fn (u21) void) void {
        for (self.items) |value| f(value);
    }

    pub fn toMutable(self: *const ImmutableCharArrayDeque) CharArrayDeque {
        return CharArrayDeque.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableCharArrayDeque, other: *const ImmutableCharArrayDeque) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items, other.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }
};

test "ImmutableCharArrayDeque: of and peek" {
    var d = ImmutableCharArrayDeque.of(std.testing.allocator, &[_]u21{ 'a', 'b', 'c' });
    defer d.deinit();
    try std.testing.expectEqual(@as(usize, 3), d.len());
    try std.testing.expectEqual(@as(?u21, 'a'), d.peekFirst());
    try std.testing.expectEqual(@as(?u21, 'c'), d.peekLast());
}

test "ImmutableCharArrayDeque: persistent withFirst/withLast" {
    var d1 = ImmutableCharArrayDeque.of(std.testing.allocator, &[_]u21{'b'});
    defer d1.deinit();
    var d2 = d1.withFirst('a');
    defer d2.deinit();
    var d3 = d2.withLast('c');
    defer d3.deinit();
    try std.testing.expectEqual(@as(usize, 1), d1.len());
    try std.testing.expectEqual(@as(usize, 3), d3.len());
    try std.testing.expectEqual(@as(?u21, 'a'), d3.peekFirst());
    try std.testing.expectEqual(@as(?u21, 'c'), d3.peekLast());
}

test "ImmutableCharArrayDeque: withoutFirst/withoutLast" {
    var d = ImmutableCharArrayDeque.of(std.testing.allocator, &[_]u21{ 'a', 'b', 'c' });
    defer d.deinit();
    const r1 = d.withoutFirst().?;
    var d2 = r1.deque;
    defer d2.deinit();
    try std.testing.expectEqual('a', r1.value);
    try std.testing.expectEqual(@as(usize, 2), d2.len());

    const r2 = d.withoutLast().?;
    var d3 = r2.deque;
    defer d3.deinit();
    try std.testing.expectEqual('c', r2.value);
    try std.testing.expectEqual(@as(usize, 2), d3.len());

    // Original untouched
    try std.testing.expectEqual(@as(usize, 3), d.len());
}

test "ImmutableCharArrayDeque: fromMutable and toMutable independence" {
    var ml = CharArrayDeque.init(std.testing.allocator);
    defer ml.deinit();
    ml.addLast('a');
    ml.addLast('b');
    var il = ImmutableCharArrayDeque.fromMutable(std.testing.allocator, &ml);
    defer il.deinit();
    var ml2 = il.toMutable();
    defer ml2.deinit();
    ml2.addLast('c');
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expectEqual(@as(usize, 3), ml2.len());
}

test "ImmutableCharArrayDeque: eql and contains" {
    var a = ImmutableCharArrayDeque.of(std.testing.allocator, &[_]u21{ 'a', 'b' });
    defer a.deinit();
    var b = ImmutableCharArrayDeque.of(std.testing.allocator, &[_]u21{ 'a', 'b' });
    defer b.deinit();
    try std.testing.expect(a.eql(&b));
    try std.testing.expect(a.contains('a'));
}
