
const std = @import("std");
const Allocator = std.mem.Allocator;
const I32PriorityQueue = @import("../priority_queue/i32_priority_queue.zig").I32PriorityQueue;

/// Immutable min-heap priority queue of `i32` values, backed by an owned
/// heap-ordered slice. All "mutating" operations return new immutable queues.
pub const ImmutableI32PriorityQueue = struct {
    items: []const i32,
    allocator: Allocator,

    /// Heapifies `values` (copy) and wraps the result. O(n).
    pub fn of(allocator: Allocator, values: []const i32) ImmutableI32PriorityQueue {
        var tmp = I32PriorityQueue.of(allocator, values);
        defer tmp.deinit();
        const owned = allocator.dupe(i32, tmp.slice()) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn fromMutable(allocator: Allocator, mutable: *const I32PriorityQueue) ImmutableI32PriorityQueue {
        const owned = allocator.dupe(i32, mutable.slice()) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableI32PriorityQueue) void {
        self.allocator.free(self.items);
    }

    /// Returns the smallest element without removing it, or null if empty.
    pub fn peek(self: *const ImmutableI32PriorityQueue) ?i32 {
        if (self.items.len == 0) return null;
        return self.items[0];
    }

    pub fn len(self: *const ImmutableI32PriorityQueue) usize {
        return self.items.len;
    }
    pub fn isEmpty(self: *const ImmutableI32PriorityQueue) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableI32PriorityQueue, value: i32) bool {
        for (self.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    /// Returns a slice view of the internal heap array (NOT sorted).
    pub fn slice(self: *const ImmutableI32PriorityQueue) []const i32 {
        return self.items;
    }

    /// Returns a new immutable queue with `value` inserted. O(n) due to copy.
    pub fn push(self: *const ImmutableI32PriorityQueue, value: i32) ImmutableI32PriorityQueue {
        var m = self.toMutable();
        defer m.deinit();
        m.push(value);
        const owned = self.allocator.dupe(i32, m.slice()) catch @panic("out of memory");
        return .{ .items = owned, .allocator = self.allocator };
    }

    /// Returns a new queue without the smallest element, and the removed value.
    pub fn pop(self: *const ImmutableI32PriorityQueue) ?struct { queue: ImmutableI32PriorityQueue, value: i32 } {
        if (self.items.len == 0) return null;
        var m = self.toMutable();
        defer m.deinit();
        const top = m.pop().?;
        const owned = self.allocator.dupe(i32, m.slice()) catch @panic("out of memory");
        return .{
            .queue = .{ .items = owned, .allocator = self.allocator },
            .value = top,
        };
    }

    pub fn toMutable(self: *const ImmutableI32PriorityQueue) I32PriorityQueue {
        return I32PriorityQueue.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableI32PriorityQueue, other: *const ImmutableI32PriorityQueue) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items, other.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }
};

test "ImmutableI32PriorityQueue: of and peek" {
    var q = ImmutableI32PriorityQueue.of(std.testing.allocator, &[_]i32{ 3, 1, 2 });
    defer q.deinit();
    try std.testing.expectEqual(@as(usize, 3), q.len());
    try std.testing.expect(q.peek() != null);
}

test "ImmutableI32PriorityQueue: persistent push" {
    var q1 = ImmutableI32PriorityQueue.of(std.testing.allocator, &[_]i32{3});
    defer q1.deinit();
    var q2 = q1.push(1);
    defer q2.deinit();
    try std.testing.expectEqual(@as(usize, 1), q1.len());
    try std.testing.expectEqual(@as(usize, 2), q2.len());
    try std.testing.expect(q2.peek() != null);
}

test "ImmutableI32PriorityQueue: pop returns smallest and new queue" {
    var q = ImmutableI32PriorityQueue.of(std.testing.allocator, &[_]i32{ 3, 1, 2 });
    defer q.deinit();
    const r = q.pop().?;
    var q2 = r.queue;
    defer q2.deinit();
    _ = r.value;
    try std.testing.expectEqual(@as(usize, 2), q2.len());
    // Original untouched
    try std.testing.expectEqual(@as(usize, 3), q.len());
}

test "ImmutableI32PriorityQueue: fromMutable independence" {
    var m = I32PriorityQueue.init(std.testing.allocator);
    defer m.deinit();
    m.push(1);
    m.push(2);
    var im = ImmutableI32PriorityQueue.fromMutable(std.testing.allocator, &m);
    defer im.deinit();
    var m2 = im.toMutable();
    defer m2.deinit();
    m2.push(3);
    try std.testing.expectEqual(@as(usize, 2), im.len());
    try std.testing.expectEqual(@as(usize, 3), m2.len());
}
