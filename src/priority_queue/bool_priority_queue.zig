// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;

/// Primitive min-heap priority queue of `bool` values, backed by an
/// `ArrayListUnmanaged`. O(log n) push/pop, O(1) peek.
pub const BoolPriorityQueue = struct {
    items: std.ArrayListUnmanaged(bool) = .empty,
    allocator: Allocator,

    pub fn init(allocator: Allocator) BoolPriorityQueue {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *BoolPriorityQueue) void {
        self.items.deinit(self.allocator);
    }

    pub fn of(allocator: Allocator, values: []const bool) BoolPriorityQueue {
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
    pub fn push(self: *BoolPriorityQueue, value: bool) void {
        self.items.append(self.allocator, value) catch @panic("out of memory");
        self.siftUp(self.items.items.len - 1);
    }

    /// Removes and returns the smallest element, or null if empty. O(log n).
    pub fn pop(self: *BoolPriorityQueue) ?bool {
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
    pub fn peek(self: *const BoolPriorityQueue) ?bool {
        if (self.items.items.len == 0) return null;
        return self.items.items[0];
    }

    pub fn len(self: *const BoolPriorityQueue) usize {
        return self.items.items.len;
    }
    pub fn isEmpty(self: *const BoolPriorityQueue) bool {
        return self.items.items.len == 0;
    }
    pub fn clear(self: *BoolPriorityQueue) void {
        self.items.clearRetainingCapacity();
    }

    pub fn ensureUnusedCapacity(self: *BoolPriorityQueue, additional: usize) Allocator.Error!void {
        try self.items.ensureUnusedCapacity(self.allocator, additional);
    }

    pub fn contains(self: *const BoolPriorityQueue, value: bool) bool {
        for (self.items.items) |v| {
            if (v == value) return true;
        }
        return false;
    }

    /// Returns a slice view of the internal heap array (NOT sorted).
    pub fn slice(self: *const BoolPriorityQueue) []const bool {
        return self.items.items;
    }

    /// Drains the heap into a caller-owned slice in ascending order.
    pub fn drainSorted(self: *BoolPriorityQueue, allocator: Allocator) []bool {
        const out = allocator.alloc(bool, self.items.items.len) catch @panic("out of memory");
        var i: usize = 0;
        while (self.pop()) |v| : (i += 1) {
            out[i] = v;
        }
        return out;
    }

    fn siftUp(self: *BoolPriorityQueue, start: usize) void {
        var i = start;
        while (i > 0) {
            const parent = (i - 1) / 2;
            if ((!self.items.items[i] and self.items.items[parent])) {
                const tmp = self.items.items[i];
                self.items.items[i] = self.items.items[parent];
                self.items.items[parent] = tmp;
                i = parent;
            } else break;
        }
    }

    fn siftDown(self: *BoolPriorityQueue, start: usize) void {
        var i = start;
        const n = self.items.items.len;
        while (true) {
            const left = 2 * i + 1;
            if (left >= n) break;
            const right = left + 1;
            var best = left;
            if (right < n and (!self.items.items[right] and self.items.items[left])) {
                best = right;
            }
            if ((!self.items.items[best] and self.items.items[i])) {
                const tmp = self.items.items[best];
                self.items.items[best] = self.items.items[i];
                self.items.items[i] = tmp;
                i = best;
            } else break;
        }
    }
};

test "BoolPriorityQueue: push peek pop min" {
    var q = BoolPriorityQueue.init(std.testing.allocator);
    defer q.deinit();
    q.push(true);
    q.push(true);
    q.push(false);
    try std.testing.expectEqual(@as(usize, 3), q.len());
    _ = q.pop();
    _ = q.pop();
    _ = q.pop();
    try std.testing.expectEqual(@as(?bool, null), q.pop());
}

test "BoolPriorityQueue: of heapify" {
    var q = BoolPriorityQueue.of(std.testing.allocator, &[_]bool{ true, true, false });
    defer q.deinit();
    try std.testing.expectEqual(@as(usize, 3), q.len());
}

test "BoolPriorityQueue: empty" {
    var q = BoolPriorityQueue.init(std.testing.allocator);
    defer q.deinit();
    try std.testing.expect(q.isEmpty());
    try std.testing.expectEqual(@as(?bool, null), q.peek());
    try std.testing.expectEqual(@as(?bool, null), q.pop());
}

test "BoolPriorityQueue: contains clear" {
    var q = BoolPriorityQueue.init(std.testing.allocator);
    defer q.deinit();
    q.push(true);
    try std.testing.expect(q.contains(true));
    q.clear();
    try std.testing.expect(q.isEmpty());
}

test "BoolPriorityQueue: drainSorted" {
    var q = BoolPriorityQueue.of(std.testing.allocator, &[_]bool{ true, true, false });
    defer q.deinit();
    const sorted = q.drainSorted(std.testing.allocator);
    defer std.testing.allocator.free(sorted);
    try std.testing.expectEqual(@as(usize, 3), sorted.len);
}
