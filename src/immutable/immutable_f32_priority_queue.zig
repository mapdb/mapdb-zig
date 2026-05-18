
const std = @import("std");
const Allocator = std.mem.Allocator;
const F32PriorityQueue = @import("../priority_queue/f32_priority_queue.zig").F32PriorityQueue;

/// Immutable min-heap priority queue of `f32` values, backed by an owned
/// heap-ordered slice. All "mutating" operations return new immutable queues.
pub const ImmutableF32PriorityQueue = struct {
    items: []const f32,
    allocator: Allocator,

    /// Heapifies `values` (copy) and wraps the result. O(n).
    pub fn of(allocator: Allocator, values: []const f32) ImmutableF32PriorityQueue {
        var tmp = F32PriorityQueue.of(allocator, values);
        defer tmp.deinit();
        const owned = allocator.dupe(f32, tmp.slice()) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn fromMutable(allocator: Allocator, mutable: *const F32PriorityQueue) ImmutableF32PriorityQueue {
        const owned = allocator.dupe(f32, mutable.slice()) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableF32PriorityQueue) void {
        self.allocator.free(self.items);
    }

    /// Returns the smallest element without removing it, or null if empty.
    pub fn peek(self: *const ImmutableF32PriorityQueue) ?f32 {
        if (self.items.len == 0) return null;
        return self.items[0];
    }

    pub fn len(self: *const ImmutableF32PriorityQueue) usize {
        return self.items.len;
    }
    pub fn isEmpty(self: *const ImmutableF32PriorityQueue) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableF32PriorityQueue, value: f32) bool {
        for (self.items) |item| {
            if (@as(u32, @bitCast(item)) == @as(u32, @bitCast(value))) return true;
        }
        return false;
    }

    /// Returns a slice view of the internal heap array (NOT sorted).
    pub fn slice(self: *const ImmutableF32PriorityQueue) []const f32 {
        return self.items;
    }

    /// Returns a new immutable queue with `value` inserted. O(n) due to copy.
    pub fn push(self: *const ImmutableF32PriorityQueue, value: f32) ImmutableF32PriorityQueue {
        var m = self.toMutable();
        defer m.deinit();
        m.push(value);
        const owned = self.allocator.dupe(f32, m.slice()) catch @panic("out of memory");
        return .{ .items = owned, .allocator = self.allocator };
    }

    /// Returns a new queue without the smallest element, and the removed value.
    pub fn pop(self: *const ImmutableF32PriorityQueue) ?struct { queue: ImmutableF32PriorityQueue, value: f32 } {
        if (self.items.len == 0) return null;
        var m = self.toMutable();
        defer m.deinit();
        const top = m.pop().?;
        const owned = self.allocator.dupe(f32, m.slice()) catch @panic("out of memory");
        return .{
            .queue = .{ .items = owned, .allocator = self.allocator },
            .value = top,
        };
    }

    pub fn toMutable(self: *const ImmutableF32PriorityQueue) F32PriorityQueue {
        return F32PriorityQueue.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableF32PriorityQueue, other: *const ImmutableF32PriorityQueue) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items, other.items) |a, b| {
            if (!(@as(u32, @bitCast(a)) == @as(u32, @bitCast(b)))) return false;
        }
        return true;
    }
};

test "ImmutableF32PriorityQueue: of and peek" {
    var q = ImmutableF32PriorityQueue.of(std.testing.allocator, &[_]f32{ 3.0, 1.0, 2.0 });
    defer q.deinit();
    try std.testing.expectEqual(@as(usize, 3), q.len());
    try std.testing.expect(q.peek() != null);
}

test "ImmutableF32PriorityQueue: persistent push" {
    var q1 = ImmutableF32PriorityQueue.of(std.testing.allocator, &[_]f32{3.0});
    defer q1.deinit();
    var q2 = q1.push(1.0);
    defer q2.deinit();
    try std.testing.expectEqual(@as(usize, 1), q1.len());
    try std.testing.expectEqual(@as(usize, 2), q2.len());
    try std.testing.expect(q2.peek() != null);
}

test "ImmutableF32PriorityQueue: pop returns smallest and new queue" {
    var q = ImmutableF32PriorityQueue.of(std.testing.allocator, &[_]f32{ 3.0, 1.0, 2.0 });
    defer q.deinit();
    const r = q.pop().?;
    var q2 = r.queue;
    defer q2.deinit();
    _ = r.value;
    try std.testing.expectEqual(@as(usize, 2), q2.len());
    // Original untouched
    try std.testing.expectEqual(@as(usize, 3), q.len());
}

test "ImmutableF32PriorityQueue: fromMutable independence" {
    var m = F32PriorityQueue.init(std.testing.allocator);
    defer m.deinit();
    m.push(1.0);
    m.push(2.0);
    var im = ImmutableF32PriorityQueue.fromMutable(std.testing.allocator, &m);
    defer im.deinit();
    var m2 = im.toMutable();
    defer m2.deinit();
    m2.push(3.0);
    try std.testing.expectEqual(@as(usize, 2), im.len());
    try std.testing.expectEqual(@as(usize, 3), m2.len());
}
