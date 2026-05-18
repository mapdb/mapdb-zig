
const std = @import("std");
const Allocator = std.mem.Allocator;
const I64ArrayDeque = @import("../deque/i64_array_deque.zig").I64ArrayDeque;

/// Immutable deque of `i64` values, backed by an owned allocated slice.
/// All "mutating" operations return new immutable deques.
pub const ImmutableI64ArrayDeque = struct {
    items: []const i64,
    allocator: Allocator,

    pub fn of(allocator: Allocator, values: []const i64) ImmutableI64ArrayDeque {
        const owned = allocator.dupe(i64, values) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn fromMutable(allocator: Allocator, mutable: *const I64ArrayDeque) ImmutableI64ArrayDeque {
        return of(allocator, mutable.items.items);
    }

    pub fn deinit(self: *ImmutableI64ArrayDeque) void {
        self.allocator.free(self.items);
    }

    pub fn peekFirst(self: *const ImmutableI64ArrayDeque) ?i64 {
        if (self.items.len == 0) return null;
        return self.items[0];
    }

    pub fn peekLast(self: *const ImmutableI64ArrayDeque) ?i64 {
        if (self.items.len == 0) return null;
        return self.items[self.items.len - 1];
    }

    pub fn len(self: *const ImmutableI64ArrayDeque) usize {
        return self.items.len;
    }
    pub fn isEmpty(self: *const ImmutableI64ArrayDeque) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableI64ArrayDeque, value: i64) bool {
        for (self.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    pub fn toSlice(self: *const ImmutableI64ArrayDeque) []const i64 {
        return self.items;
    }

    /// Returns a new immutable deque with `value` prepended at the front.
    pub fn withFirst(self: *const ImmutableI64ArrayDeque, value: i64) ImmutableI64ArrayDeque {
        const new_items = self.allocator.alloc(i64, self.items.len + 1) catch @panic("out of memory");
        new_items[0] = value;
        @memcpy(new_items[1..], self.items);
        return .{ .items = new_items, .allocator = self.allocator };
    }

    /// Returns a new immutable deque with `value` appended at the back.
    pub fn withLast(self: *const ImmutableI64ArrayDeque, value: i64) ImmutableI64ArrayDeque {
        const new_items = self.allocator.alloc(i64, self.items.len + 1) catch @panic("out of memory");
        @memcpy(new_items[0..self.items.len], self.items);
        new_items[self.items.len] = value;
        return .{ .items = new_items, .allocator = self.allocator };
    }

    /// Returns a new deque without the front element, and the removed value.
    pub fn withoutFirst(self: *const ImmutableI64ArrayDeque) ?struct { deque: ImmutableI64ArrayDeque, value: i64 } {
        if (self.items.len == 0) return null;
        const first = self.items[0];
        const new_items = self.allocator.dupe(i64, self.items[1..]) catch @panic("out of memory");
        return .{
            .deque = .{ .items = new_items, .allocator = self.allocator },
            .value = first,
        };
    }

    /// Returns a new deque without the back element, and the removed value.
    pub fn withoutLast(self: *const ImmutableI64ArrayDeque) ?struct { deque: ImmutableI64ArrayDeque, value: i64 } {
        if (self.items.len == 0) return null;
        const last = self.items[self.items.len - 1];
        const new_items = self.allocator.dupe(i64, self.items[0 .. self.items.len - 1]) catch @panic("out of memory");
        return .{
            .deque = .{ .items = new_items, .allocator = self.allocator },
            .value = last,
        };
    }

    pub fn forEach(self: *const ImmutableI64ArrayDeque, f: *const fn (i64) void) void {
        for (self.items) |value| f(value);
    }

    pub fn toMutable(self: *const ImmutableI64ArrayDeque) I64ArrayDeque {
        return I64ArrayDeque.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableI64ArrayDeque, other: *const ImmutableI64ArrayDeque) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items, other.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }
};

test "ImmutableI64ArrayDeque: of and peek" {
    var d = ImmutableI64ArrayDeque.of(std.testing.allocator, &[_]i64{ 1, 2, 3 });
    defer d.deinit();
    try std.testing.expectEqual(@as(usize, 3), d.len());
    try std.testing.expectEqual(@as(?i64, 1), d.peekFirst());
    try std.testing.expectEqual(@as(?i64, 3), d.peekLast());
}

test "ImmutableI64ArrayDeque: persistent withFirst/withLast" {
    var d1 = ImmutableI64ArrayDeque.of(std.testing.allocator, &[_]i64{2});
    defer d1.deinit();
    var d2 = d1.withFirst(1);
    defer d2.deinit();
    var d3 = d2.withLast(3);
    defer d3.deinit();
    try std.testing.expectEqual(@as(usize, 1), d1.len());
    try std.testing.expectEqual(@as(usize, 3), d3.len());
    try std.testing.expectEqual(@as(?i64, 1), d3.peekFirst());
    try std.testing.expectEqual(@as(?i64, 3), d3.peekLast());
}

test "ImmutableI64ArrayDeque: withoutFirst/withoutLast" {
    var d = ImmutableI64ArrayDeque.of(std.testing.allocator, &[_]i64{ 1, 2, 3 });
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

test "ImmutableI64ArrayDeque: fromMutable and toMutable independence" {
    var ml = I64ArrayDeque.init(std.testing.allocator);
    defer ml.deinit();
    ml.addLast(1);
    ml.addLast(2);
    var il = ImmutableI64ArrayDeque.fromMutable(std.testing.allocator, &ml);
    defer il.deinit();
    var ml2 = il.toMutable();
    defer ml2.deinit();
    ml2.addLast(3);
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expectEqual(@as(usize, 3), ml2.len());
}

test "ImmutableI64ArrayDeque: eql and contains" {
    var a = ImmutableI64ArrayDeque.of(std.testing.allocator, &[_]i64{ 1, 2 });
    defer a.deinit();
    var b = ImmutableI64ArrayDeque.of(std.testing.allocator, &[_]i64{ 1, 2 });
    defer b.deinit();
    try std.testing.expect(a.eql(&b));
    try std.testing.expect(a.contains(1));
}
