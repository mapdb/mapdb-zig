
const std = @import("std");
const Allocator = std.mem.Allocator;
const I64PriorityQueue = @import("../priority_queue/i64_priority_queue.zig").I64PriorityQueue;

/// Immutable min-heap priority queue of `i64` values, backed by an owned
/// heap-ordered slice. All "mutating" operations return new immutable queues.
pub const ImmutableI64PriorityQueue = struct {
    items: []const i64,
    allocator: Allocator,

    /// Heapifies `values` (copy) and wraps the result. O(n).
    pub fn of(allocator: Allocator, values: []const i64) ImmutableI64PriorityQueue {
        var tmp = I64PriorityQueue.of(allocator, values);
        defer tmp.deinit();
        const owned = allocator.dupe(i64, tmp.slice()) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn fromMutable(allocator: Allocator, mutable: *const I64PriorityQueue) ImmutableI64PriorityQueue {
        const owned = allocator.dupe(i64, mutable.slice()) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableI64PriorityQueue) void {
        self.allocator.free(self.items);
    }

    /// Returns the smallest element without removing it, or null if empty.
    pub fn peek(self: *const ImmutableI64PriorityQueue) ?i64 {
        if (self.items.len == 0) return null;
        return self.items[0];
    }

    pub fn len(self: *const ImmutableI64PriorityQueue) usize {
        return self.items.len;
    }
    pub fn isEmpty(self: *const ImmutableI64PriorityQueue) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableI64PriorityQueue, value: i64) bool {
        for (self.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    /// Returns a slice view of the internal heap array (NOT sorted).
    pub fn slice(self: *const ImmutableI64PriorityQueue) []const i64 {
        return self.items;
    }

    /// Returns a new immutable queue with `value` inserted. O(n) due to copy.
    pub fn push(self: *const ImmutableI64PriorityQueue, value: i64) ImmutableI64PriorityQueue {
        var m = self.toMutable();
        defer m.deinit();
        m.push(value);
        const owned = self.allocator.dupe(i64, m.slice()) catch @panic("out of memory");
        return .{ .items = owned, .allocator = self.allocator };
    }

    /// Returns a new queue without the smallest element, and the removed value.
    pub fn pop(self: *const ImmutableI64PriorityQueue) ?struct { queue: ImmutableI64PriorityQueue, value: i64 } {
        if (self.items.len == 0) return null;
        var m = self.toMutable();
        defer m.deinit();
        const top = m.pop().?;
        const owned = self.allocator.dupe(i64, m.slice()) catch @panic("out of memory");
        return .{
            .queue = .{ .items = owned, .allocator = self.allocator },
            .value = top,
        };
    }

    pub fn toMutable(self: *const ImmutableI64PriorityQueue) I64PriorityQueue {
        return I64PriorityQueue.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableI64PriorityQueue, other: *const ImmutableI64PriorityQueue) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items, other.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }
};

test "ImmutableI64PriorityQueue: of and peek" {
    var q = ImmutableI64PriorityQueue.of(std.testing.allocator, &[_]i64{ 3, 1, 2 });
    defer q.deinit();
    try std.testing.expectEqual(@as(usize, 3), q.len());
    try std.testing.expect(q.peek() != null);
}

test "ImmutableI64PriorityQueue: persistent push" {
    var q1 = ImmutableI64PriorityQueue.of(std.testing.allocator, &[_]i64{3});
    defer q1.deinit();
    var q2 = q1.push(1);
    defer q2.deinit();
    try std.testing.expectEqual(@as(usize, 1), q1.len());
    try std.testing.expectEqual(@as(usize, 2), q2.len());
    try std.testing.expect(q2.peek() != null);
}

test "ImmutableI64PriorityQueue: pop returns smallest and new queue" {
    var q = ImmutableI64PriorityQueue.of(std.testing.allocator, &[_]i64{ 3, 1, 2 });
    defer q.deinit();
    const r = q.pop().?;
    var q2 = r.queue;
    defer q2.deinit();
    _ = r.value;
    try std.testing.expectEqual(@as(usize, 2), q2.len());
    // Original untouched
    try std.testing.expectEqual(@as(usize, 3), q.len());
}

test "ImmutableI64PriorityQueue: fromMutable independence" {
    var m = I64PriorityQueue.init(std.testing.allocator);
    defer m.deinit();
    m.push(1);
    m.push(2);
    var im = ImmutableI64PriorityQueue.fromMutable(std.testing.allocator, &m);
    defer im.deinit();
    var m2 = im.toMutable();
    defer m2.deinit();
    m2.push(3);
    try std.testing.expectEqual(@as(usize, 2), im.len());
    try std.testing.expectEqual(@as(usize, 3), m2.len());
}
