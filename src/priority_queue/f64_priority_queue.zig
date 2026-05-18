
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Primitive min-heap priority queue of `f64` values, backed by an
/// `ArrayListUnmanaged`. O(log n) push/pop, O(1) peek.
pub const F64PriorityQueue = struct {
    items: std.ArrayListUnmanaged(f64) = .empty,
    allocator: Allocator,

    pub fn init(allocator: Allocator) F64PriorityQueue {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *F64PriorityQueue) void {
        self.items.deinit(self.allocator);
    }

    pub fn of(allocator: Allocator, values: []const f64) F64PriorityQueue {
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
    pub fn push(self: *F64PriorityQueue, value: f64) void {
        self.items.append(self.allocator, value) catch @panic("out of memory");
        self.siftUp(self.items.items.len - 1);
    }

    /// Removes and returns the smallest element, or null if empty. O(log n).
    pub fn pop(self: *F64PriorityQueue) ?f64 {
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
    pub fn peek(self: *const F64PriorityQueue) ?f64 {
        if (self.items.items.len == 0) return null;
        return self.items.items[0];
    }

    pub fn len(self: *const F64PriorityQueue) usize {
        return self.items.items.len;
    }
    pub fn isEmpty(self: *const F64PriorityQueue) bool {
        return self.items.items.len == 0;
    }
    pub fn clear(self: *F64PriorityQueue) void {
        self.items.clearRetainingCapacity();
    }

    pub fn ensureUnusedCapacity(self: *F64PriorityQueue, additional: usize) Allocator.Error!void {
        try self.items.ensureUnusedCapacity(self.allocator, additional);
    }

    pub fn contains(self: *const F64PriorityQueue, value: f64) bool {
        for (self.items.items) |v| {
            if (@as(u64, @bitCast(v)) == @as(u64, @bitCast(value))) return true;
        }
        return false;
    }

    /// Returns a slice view of the internal heap array (NOT sorted).
    pub fn slice(self: *const F64PriorityQueue) []const f64 {
        return self.items.items;
    }

    /// Drains the heap into a caller-owned slice in ascending order.
    pub fn drainSorted(self: *F64PriorityQueue, allocator: Allocator) []f64 {
        const out = allocator.alloc(f64, self.items.items.len) catch @panic("out of memory");
        var i: usize = 0;
        while (self.pop()) |v| : (i += 1) {
            out[i] = v;
        }
        return out;
    }

    fn siftUp(self: *F64PriorityQueue, start: usize) void {
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

    fn siftDown(self: *F64PriorityQueue, start: usize) void {
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

test "F64PriorityQueue: push peek pop min" {
    var q = F64PriorityQueue.init(std.testing.allocator);
    defer q.deinit();
    q.push(3.0);
    q.push(1.0);
    q.push(2.0);
    try std.testing.expectEqual(@as(usize, 3), q.len());

    try std.testing.expectEqual(@as(?f64, 1.0), q.peek());
    const a = q.pop().?;
    const b = q.pop().?;
    const c = q.pop().?;
    try std.testing.expect(!(b < a));
    try std.testing.expect(!(c < b));

    try std.testing.expectEqual(@as(?f64, null), q.pop());
}

test "F64PriorityQueue: of heapify" {
    var q = F64PriorityQueue.of(std.testing.allocator, &[_]f64{ 3.0, 1.0, 2.0 });
    defer q.deinit();
    try std.testing.expectEqual(@as(usize, 3), q.len());
    try std.testing.expectEqual(@as(?f64, 1.0), q.peek());
}

test "F64PriorityQueue: empty" {
    var q = F64PriorityQueue.init(std.testing.allocator);
    defer q.deinit();
    try std.testing.expect(q.isEmpty());
    try std.testing.expectEqual(@as(?f64, null), q.peek());
    try std.testing.expectEqual(@as(?f64, null), q.pop());
}

test "F64PriorityQueue: contains clear" {
    var q = F64PriorityQueue.init(std.testing.allocator);
    defer q.deinit();
    q.push(1.0);
    try std.testing.expect(q.contains(1.0));
    q.clear();
    try std.testing.expect(q.isEmpty());
}

test "F64PriorityQueue: drainSorted" {
    var q = F64PriorityQueue.of(std.testing.allocator, &[_]f64{ 3.0, 1.0, 2.0 });
    defer q.deinit();
    const sorted = q.drainSorted(std.testing.allocator);
    defer std.testing.allocator.free(sorted);
    try std.testing.expectEqual(@as(usize, 3), sorted.len);

    var i: usize = 1;
    while (i < sorted.len) : (i += 1) {
        try std.testing.expect(!(sorted[i] < sorted[i - 1]));
    }
}
