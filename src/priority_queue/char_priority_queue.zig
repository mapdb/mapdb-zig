// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;

/// Primitive min-heap priority queue of `u21` values, backed by an
/// `ArrayListUnmanaged`. O(log n) push/pop, O(1) peek.
pub const CharPriorityQueue = struct {
    items: std.ArrayListUnmanaged(u21) = .empty,
    allocator: Allocator,

    pub fn init(allocator: Allocator) CharPriorityQueue {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *CharPriorityQueue) void {
        self.items.deinit(self.allocator);
    }

    pub fn of(allocator: Allocator, values: []const u21) CharPriorityQueue {
        var q = init(allocator);
        q.items.appendSlice(q.allocator, values) catch @panic("out of memory");
        if (q.items.items.len > 1) {
            var i: usize = q.items.items.len / 2;
            while (i > 0) {
                i -= 1;
                q.siftDown(i);
            }
        }
        return q;
    }

    /// Pushes a value onto the heap. O(log n).
    pub fn push(self: *CharPriorityQueue, value: u21) void {
        self.items.append(self.allocator, value) catch @panic("out of memory");
        self.siftUp(self.items.items.len - 1);
    }

    /// Removes and returns the smallest element, or null if empty. O(log n).
    pub fn pop(self: *CharPriorityQueue) ?u21 {
        if (self.items.items.len == 0) return null;
        const top = self.items.items[0];
        const last = self.items.pop().?;
        if (self.items.items.len > 0) {
            self.items.items[0] = last;
            self.siftDown(0);
        }
        return top;
    }

    /// Returns the smallest element without removing it, or null if empty.
    pub fn peek(self: *const CharPriorityQueue) ?u21 {
        if (self.items.items.len == 0) return null;
        return self.items.items[0];
    }

    pub fn len(self: *const CharPriorityQueue) usize {
        return self.items.items.len;
    }
    pub fn isEmpty(self: *const CharPriorityQueue) bool {
        return self.items.items.len == 0;
    }
    pub fn clear(self: *CharPriorityQueue) void {
        self.items.clearRetainingCapacity();
    }

    pub fn ensureUnusedCapacity(self: *CharPriorityQueue, additional: usize) Allocator.Error!void {
        try self.items.ensureUnusedCapacity(self.allocator, additional);
    }

    pub fn contains(self: *const CharPriorityQueue, value: u21) bool {
        for (self.items.items) |v| {
            if (v == value) return true;
        }
        return false;
    }

    /// Returns a slice view of the internal heap array (NOT sorted).
    pub fn slice(self: *const CharPriorityQueue) []const u21 {
        return self.items.items;
    }

    /// Drains the heap into a caller-owned slice in ascending order.
    pub fn drainSorted(self: *CharPriorityQueue, allocator: Allocator) []u21 {
        const out = allocator.alloc(u21, self.items.items.len) catch @panic("out of memory");
        var i: usize = 0;
        while (self.pop()) |v| : (i += 1) {
            out[i] = v;
        }
        return out;
    }

    fn siftUp(self: *CharPriorityQueue, start: usize) void {
        var i = start;
        while (i > 0) {
            const parent = (i - 1) / 2;
            if (self.items.items[i] < self.items.items[parent]) {
                const tmp = self.items.items[i];
                self.items.items[i] = self.items.items[parent];
                self.items.items[parent] = tmp;
                i = parent;
            } else break;
        }
    }

    fn siftDown(self: *CharPriorityQueue, start: usize) void {
        var i = start;
        const n = self.items.items.len;
        while (true) {
            const left = 2 * i + 1;
            if (left >= n) break;
            const right = left + 1;
            var best = left;
            if (right < n and self.items.items[right] < self.items.items[left]) {
                best = right;
            }
            if (self.items.items[best] < self.items.items[i]) {
                const tmp = self.items.items[best];
                self.items.items[best] = self.items.items[i];
                self.items.items[i] = tmp;
                i = best;
            } else break;
        }
    }
};

test "CharPriorityQueue: push peek pop min" {
    var q = CharPriorityQueue.init(std.testing.allocator);
    defer q.deinit();
    q.push('c');
    q.push('a');
    q.push('b');
    try std.testing.expectEqual(@as(usize, 3), q.len());

    try std.testing.expectEqual(@as(?u21, 'a'), q.peek());
    const a = q.pop().?;
    const b = q.pop().?;
    const c = q.pop().?;
    try std.testing.expect(!(b < a));
    try std.testing.expect(!(c < b));

    try std.testing.expectEqual(@as(?u21, null), q.pop());
}

test "CharPriorityQueue: of heapify" {
    var q = CharPriorityQueue.of(std.testing.allocator, &[_]u21{ 'c', 'a', 'b' });
    defer q.deinit();
    try std.testing.expectEqual(@as(usize, 3), q.len());
    try std.testing.expectEqual(@as(?u21, 'a'), q.peek());
}

test "CharPriorityQueue: empty" {
    var q = CharPriorityQueue.init(std.testing.allocator);
    defer q.deinit();
    try std.testing.expect(q.isEmpty());
    try std.testing.expectEqual(@as(?u21, null), q.peek());
    try std.testing.expectEqual(@as(?u21, null), q.pop());
}

test "CharPriorityQueue: contains clear" {
    var q = CharPriorityQueue.init(std.testing.allocator);
    defer q.deinit();
    q.push('a');
    try std.testing.expect(q.contains('a'));
    q.clear();
    try std.testing.expect(q.isEmpty());
}

test "CharPriorityQueue: drainSorted" {
    var q = CharPriorityQueue.of(std.testing.allocator, &[_]u21{ 'c', 'a', 'b' });
    defer q.deinit();
    const sorted = q.drainSorted(std.testing.allocator);
    defer std.testing.allocator.free(sorted);
    try std.testing.expectEqual(@as(usize, 3), sorted.len);

    var i: usize = 1;
    while (i < sorted.len) : (i += 1) {
        try std.testing.expect(!(sorted[i] < sorted[i - 1]));
    }
}
