
const std = @import("std");
const Allocator = std.mem.Allocator;
const BoolArrayDeque = @import("../deque/bool_array_deque.zig").BoolArrayDeque;

/// Immutable deque of `bool` values, backed by an owned allocated slice.
/// All "mutating" operations return new immutable deques.
pub const ImmutableBoolArrayDeque = struct {
    items: []const bool,
    allocator: Allocator,

    pub fn of(allocator: Allocator, values: []const bool) ImmutableBoolArrayDeque {
        const owned = allocator.dupe(bool, values) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn fromMutable(allocator: Allocator, mutable: *const BoolArrayDeque) ImmutableBoolArrayDeque {
        return of(allocator, mutable.items.items);
    }

    pub fn deinit(self: *ImmutableBoolArrayDeque) void {
        self.allocator.free(self.items);
    }

    pub fn peekFirst(self: *const ImmutableBoolArrayDeque) ?bool {
        if (self.items.len == 0) return null;
        return self.items[0];
    }

    pub fn peekLast(self: *const ImmutableBoolArrayDeque) ?bool {
        if (self.items.len == 0) return null;
        return self.items[self.items.len - 1];
    }

    pub fn len(self: *const ImmutableBoolArrayDeque) usize {
        return self.items.len;
    }
    pub fn isEmpty(self: *const ImmutableBoolArrayDeque) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableBoolArrayDeque, value: bool) bool {
        for (self.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    pub fn toSlice(self: *const ImmutableBoolArrayDeque) []const bool {
        return self.items;
    }

    /// Returns a new immutable deque with `value` prepended at the front.
    pub fn withFirst(self: *const ImmutableBoolArrayDeque, value: bool) ImmutableBoolArrayDeque {
        const new_items = self.allocator.alloc(bool, self.items.len + 1) catch @panic("out of memory");
        new_items[0] = value;
        @memcpy(new_items[1..], self.items);
        return .{ .items = new_items, .allocator = self.allocator };
    }

    /// Returns a new immutable deque with `value` appended at the back.
    pub fn withLast(self: *const ImmutableBoolArrayDeque, value: bool) ImmutableBoolArrayDeque {
        const new_items = self.allocator.alloc(bool, self.items.len + 1) catch @panic("out of memory");
        @memcpy(new_items[0..self.items.len], self.items);
        new_items[self.items.len] = value;
        return .{ .items = new_items, .allocator = self.allocator };
    }

    /// Returns a new deque without the front element, and the removed value.
    pub fn withoutFirst(self: *const ImmutableBoolArrayDeque) ?struct { deque: ImmutableBoolArrayDeque, value: bool } {
        if (self.items.len == 0) return null;
        const first = self.items[0];
        const new_items = self.allocator.dupe(bool, self.items[1..]) catch @panic("out of memory");
        return .{
            .deque = .{ .items = new_items, .allocator = self.allocator },
            .value = first,
        };
    }

    /// Returns a new deque without the back element, and the removed value.
    pub fn withoutLast(self: *const ImmutableBoolArrayDeque) ?struct { deque: ImmutableBoolArrayDeque, value: bool } {
        if (self.items.len == 0) return null;
        const last = self.items[self.items.len - 1];
        const new_items = self.allocator.dupe(bool, self.items[0 .. self.items.len - 1]) catch @panic("out of memory");
        return .{
            .deque = .{ .items = new_items, .allocator = self.allocator },
            .value = last,
        };
    }

    pub fn forEach(self: *const ImmutableBoolArrayDeque, f: *const fn (bool) void) void {
        for (self.items) |value| f(value);
    }

    pub fn toMutable(self: *const ImmutableBoolArrayDeque) BoolArrayDeque {
        return BoolArrayDeque.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableBoolArrayDeque, other: *const ImmutableBoolArrayDeque) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items, other.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }
};

test "ImmutableBoolArrayDeque: of and peek" {
    var d = ImmutableBoolArrayDeque.of(std.testing.allocator, &[_]bool{ true, false, true });
    defer d.deinit();
    try std.testing.expectEqual(@as(usize, 3), d.len());
    try std.testing.expectEqual(@as(?bool, true), d.peekFirst());
    try std.testing.expectEqual(@as(?bool, true), d.peekLast());
}

test "ImmutableBoolArrayDeque: persistent withFirst/withLast" {
    var d1 = ImmutableBoolArrayDeque.of(std.testing.allocator, &[_]bool{false});
    defer d1.deinit();
    var d2 = d1.withFirst(true);
    defer d2.deinit();
    var d3 = d2.withLast(true);
    defer d3.deinit();
    try std.testing.expectEqual(@as(usize, 1), d1.len());
    try std.testing.expectEqual(@as(usize, 3), d3.len());
    try std.testing.expectEqual(@as(?bool, true), d3.peekFirst());
    try std.testing.expectEqual(@as(?bool, true), d3.peekLast());
}

test "ImmutableBoolArrayDeque: withoutFirst/withoutLast" {
    var d = ImmutableBoolArrayDeque.of(std.testing.allocator, &[_]bool{ true, false, true });
    defer d.deinit();
    const r1 = d.withoutFirst().?;
    var d2 = r1.deque;
    defer d2.deinit();
    try std.testing.expectEqual(true, r1.value);
    try std.testing.expectEqual(@as(usize, 2), d2.len());

    const r2 = d.withoutLast().?;
    var d3 = r2.deque;
    defer d3.deinit();
    try std.testing.expectEqual(true, r2.value);
    try std.testing.expectEqual(@as(usize, 2), d3.len());

    // Original untouched
    try std.testing.expectEqual(@as(usize, 3), d.len());
}

test "ImmutableBoolArrayDeque: fromMutable and toMutable independence" {
    var ml = BoolArrayDeque.init(std.testing.allocator);
    defer ml.deinit();
    ml.addLast(true);
    ml.addLast(false);
    var il = ImmutableBoolArrayDeque.fromMutable(std.testing.allocator, &ml);
    defer il.deinit();
    var ml2 = il.toMutable();
    defer ml2.deinit();
    ml2.addLast(true);
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expectEqual(@as(usize, 3), ml2.len());
}

test "ImmutableBoolArrayDeque: eql and contains" {
    var a = ImmutableBoolArrayDeque.of(std.testing.allocator, &[_]bool{ true, false });
    defer a.deinit();
    var b = ImmutableBoolArrayDeque.of(std.testing.allocator, &[_]bool{ true, false });
    defer b.deinit();
    try std.testing.expect(a.eql(&b));
    try std.testing.expect(a.contains(true));
}
