// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const F64PriorityQueue = @import("../priority_queue/f64_priority_queue.zig").F64PriorityQueue;

/// Immutable min-heap priority queue of `f64` values, backed by an owned
/// heap-ordered slice. All "mutating" operations return new immutable queues.
pub const ImmutableF64PriorityQueue = struct {
    items: []const f64,
    allocator: Allocator,

    /// Heapifies `values` (copy) and wraps the result. O(n).
    pub fn of(allocator: Allocator, values: []const f64) ImmutableF64PriorityQueue {
        var tmp = F64PriorityQueue.of(allocator, values);
        defer tmp.deinit();
        const owned = allocator.dupe(f64, tmp.slice()) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn fromMutable(allocator: Allocator, mutable: *const F64PriorityQueue) ImmutableF64PriorityQueue {
        const owned = allocator.dupe(f64, mutable.slice()) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableF64PriorityQueue) void {
        self.allocator.free(self.items);
    }

    /// Returns the smallest element without removing it, or null if empty.
    pub fn peek(self: *const ImmutableF64PriorityQueue) ?f64 {
        if (self.items.len == 0) return null;
        return self.items[0];
    }

    pub fn len(self: *const ImmutableF64PriorityQueue) usize {
        return self.items.len;
    }
    pub fn isEmpty(self: *const ImmutableF64PriorityQueue) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableF64PriorityQueue, value: f64) bool {
        for (self.items) |item| {
            if (@as(u64, @bitCast(item)) == @as(u64, @bitCast(value))) return true;
        }
        return false;
    }

    /// Returns a slice view of the internal heap array (NOT sorted).
    pub fn slice(self: *const ImmutableF64PriorityQueue) []const f64 {
        return self.items;
    }

    /// Returns a new immutable queue with `value` inserted. O(n) due to copy.
    pub fn push(self: *const ImmutableF64PriorityQueue, value: f64) ImmutableF64PriorityQueue {
        var m = self.toMutable();
        defer m.deinit();
        m.push(value);
        const owned = self.allocator.dupe(f64, m.slice()) catch @panic("out of memory");
        return .{ .items = owned, .allocator = self.allocator };
    }

    /// Returns a new queue without the smallest element, and the removed value.
    pub fn pop(self: *const ImmutableF64PriorityQueue) ?struct { queue: ImmutableF64PriorityQueue, value: f64 } {
        if (self.items.len == 0) return null;
        var m = self.toMutable();
        defer m.deinit();
        const top = m.pop().?;
        const owned = self.allocator.dupe(f64, m.slice()) catch @panic("out of memory");
        return .{
            .queue = .{ .items = owned, .allocator = self.allocator },
            .value = top,
        };
    }

    pub fn toMutable(self: *const ImmutableF64PriorityQueue) F64PriorityQueue {
        return F64PriorityQueue.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableF64PriorityQueue, other: *const ImmutableF64PriorityQueue) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items, other.items) |a, b| {
            if (!(@as(u64, @bitCast(a)) == @as(u64, @bitCast(b)))) return false;
        }
        return true;
    }
};

test "ImmutableF64PriorityQueue: of and peek" {
    var q = ImmutableF64PriorityQueue.of(std.testing.allocator, &[_]f64{ 3.0, 1.0, 2.0 });
    defer q.deinit();
    try std.testing.expectEqual(@as(usize, 3), q.len());
    try std.testing.expect(q.peek() != null);
}

test "ImmutableF64PriorityQueue: persistent push" {
    var q1 = ImmutableF64PriorityQueue.of(std.testing.allocator, &[_]f64{3.0});
    defer q1.deinit();
    var q2 = q1.push(1.0);
    defer q2.deinit();
    try std.testing.expectEqual(@as(usize, 1), q1.len());
    try std.testing.expectEqual(@as(usize, 2), q2.len());
    try std.testing.expect(q2.peek() != null);
}

test "ImmutableF64PriorityQueue: pop returns smallest and new queue" {
    var q = ImmutableF64PriorityQueue.of(std.testing.allocator, &[_]f64{ 3.0, 1.0, 2.0 });
    defer q.deinit();
    const r = q.pop().?;
    var q2 = r.queue;
    defer q2.deinit();
    _ = r.value;
    try std.testing.expectEqual(@as(usize, 2), q2.len());
    // Original untouched
    try std.testing.expectEqual(@as(usize, 3), q.len());
}

test "ImmutableF64PriorityQueue: fromMutable independence" {
    var m = F64PriorityQueue.init(std.testing.allocator);
    defer m.deinit();
    m.push(1.0);
    m.push(2.0);
    var im = ImmutableF64PriorityQueue.fromMutable(std.testing.allocator, &m);
    defer im.deinit();
    var m2 = im.toMutable();
    defer m2.deinit();
    m2.push(3.0);
    try std.testing.expectEqual(@as(usize, 2), im.len());
    try std.testing.expectEqual(@as(usize, 3), m2.len());
}
