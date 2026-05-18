
const std = @import("std");
const Allocator = std.mem.Allocator;
const CharPriorityQueue = @import("../priority_queue/char_priority_queue.zig").CharPriorityQueue;

/// Immutable min-heap priority queue of `u21` values, backed by an owned
/// heap-ordered slice. All "mutating" operations return new immutable queues.
pub const ImmutableCharPriorityQueue = struct {
    items: []const u21,
    allocator: Allocator,

    /// Heapifies `values` (copy) and wraps the result. O(n).
    pub fn of(allocator: Allocator, values: []const u21) ImmutableCharPriorityQueue {
        var tmp = CharPriorityQueue.of(allocator, values);
        defer tmp.deinit();
        const owned = allocator.dupe(u21, tmp.slice()) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn fromMutable(allocator: Allocator, mutable: *const CharPriorityQueue) ImmutableCharPriorityQueue {
        const owned = allocator.dupe(u21, mutable.slice()) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableCharPriorityQueue) void {
        self.allocator.free(self.items);
    }

    /// Returns the smallest element without removing it, or null if empty.
    pub fn peek(self: *const ImmutableCharPriorityQueue) ?u21 {
        if (self.items.len == 0) return null;
        return self.items[0];
    }

    pub fn len(self: *const ImmutableCharPriorityQueue) usize {
        return self.items.len;
    }
    pub fn isEmpty(self: *const ImmutableCharPriorityQueue) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableCharPriorityQueue, value: u21) bool {
        for (self.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    /// Returns a slice view of the internal heap array (NOT sorted).
    pub fn slice(self: *const ImmutableCharPriorityQueue) []const u21 {
        return self.items;
    }

    /// Returns a new immutable queue with `value` inserted. O(n) due to copy.
    pub fn push(self: *const ImmutableCharPriorityQueue, value: u21) ImmutableCharPriorityQueue {
        var m = self.toMutable();
        defer m.deinit();
        m.push(value);
        const owned = self.allocator.dupe(u21, m.slice()) catch @panic("out of memory");
        return .{ .items = owned, .allocator = self.allocator };
    }

    /// Returns a new queue without the smallest element, and the removed value.
    pub fn pop(self: *const ImmutableCharPriorityQueue) ?struct { queue: ImmutableCharPriorityQueue, value: u21 } {
        if (self.items.len == 0) return null;
        var m = self.toMutable();
        defer m.deinit();
        const top = m.pop().?;
        const owned = self.allocator.dupe(u21, m.slice()) catch @panic("out of memory");
        return .{
            .queue = .{ .items = owned, .allocator = self.allocator },
            .value = top,
        };
    }

    pub fn toMutable(self: *const ImmutableCharPriorityQueue) CharPriorityQueue {
        return CharPriorityQueue.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableCharPriorityQueue, other: *const ImmutableCharPriorityQueue) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items, other.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }
};

test "ImmutableCharPriorityQueue: of and peek" {
    var q = ImmutableCharPriorityQueue.of(std.testing.allocator, &[_]u21{ 'c', 'a', 'b' });
    defer q.deinit();
    try std.testing.expectEqual(@as(usize, 3), q.len());
    try std.testing.expect(q.peek() != null);
}

test "ImmutableCharPriorityQueue: persistent push" {
    var q1 = ImmutableCharPriorityQueue.of(std.testing.allocator, &[_]u21{'c'});
    defer q1.deinit();
    var q2 = q1.push('a');
    defer q2.deinit();
    try std.testing.expectEqual(@as(usize, 1), q1.len());
    try std.testing.expectEqual(@as(usize, 2), q2.len());
    try std.testing.expect(q2.peek() != null);
}

test "ImmutableCharPriorityQueue: pop returns smallest and new queue" {
    var q = ImmutableCharPriorityQueue.of(std.testing.allocator, &[_]u21{ 'c', 'a', 'b' });
    defer q.deinit();
    const r = q.pop().?;
    var q2 = r.queue;
    defer q2.deinit();
    _ = r.value;
    try std.testing.expectEqual(@as(usize, 2), q2.len());
    // Original untouched
    try std.testing.expectEqual(@as(usize, 3), q.len());
}

test "ImmutableCharPriorityQueue: fromMutable independence" {
    var m = CharPriorityQueue.init(std.testing.allocator);
    defer m.deinit();
    m.push('a');
    m.push('b');
    var im = ImmutableCharPriorityQueue.fromMutable(std.testing.allocator, &m);
    defer im.deinit();
    var m2 = im.toMutable();
    defer m2.deinit();
    m2.push('c');
    try std.testing.expectEqual(@as(usize, 2), im.len());
    try std.testing.expectEqual(@as(usize, 3), m2.len());
}
