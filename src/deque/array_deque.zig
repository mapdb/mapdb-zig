// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Generic double-ended queue. Single source for the 8 `<T>ArrayDeque` per-type
//! wrappers.
//!
//! Backed by a **power-of-two ring buffer** (`buf` + `head` index + `count`), so
//! BOTH ends are O(1) amortized — `addFirst`/`removeFirst` and
//! `addLast`/`removeLast` alike. This matches Java's `ArrayDeque` (the API being
//! ported) and makes the type's primary use — a FIFO queue (`addLast` +
//! `removeFirst`) — O(n) to drain instead of the O(n²) a flat-array
//! `insert(0,…)`/`orderedRemove(0)` deque would cost.
//!
//! Logical element `i` (0 = front) lives at physical slot `(head + i) & mask`,
//! where `mask = buf.len - 1`. The store is non-contiguous when the live range
//! wraps past the end; `slice()` compacts it back to a single run on demand (see
//! there). The only element-type-dependent logic is `contains` / `eql`, which
//! compare float elements by bit pattern (NaN-aware, +0.0 / -0.0 distinct) and
//! other types with `==`.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Bit-aware equality. Float members compare by reinterpreting to the same-width
/// unsigned integer; non-float members use plain `==`.
fn elemEql(comptime T: type, a: T, b: T) bool {
    if (@typeInfo(T) == .float) {
        const Bits = std.meta.Int(.unsigned, @bitSizeOf(T));
        return @as(Bits, @bitCast(a)) == @as(Bits, @bitCast(b));
    }
    return a == b;
}

/// Double-ended queue of `T` values, backed by a power-of-two ring buffer.
/// All four end operations (addFirst/addLast/removeFirst/removeLast) are O(1)
/// amortized.
pub fn ArrayDeque(comptime T: type) type {
    return struct {
        /// Backing store: `buf.len` is 0 (never allocated) or a power of two.
        buf: []T = &.{},
        /// Physical index of the front element (logical index 0).
        head: usize = 0,
        /// Number of live elements (`0 ..= buf.len`).
        count: usize = 0,
        allocator: Allocator,

        const Self = @This();

        /// Smallest allocation, a power of two, made on the first push.
        const MIN_CAPACITY: usize = 8;

        pub fn init(allocator: Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            if (self.buf.len != 0) self.allocator.free(self.buf);
            // Reset to the empty state so a redundant deinit / post-deinit read
            // is a safe no-op rather than touching freed memory.
            self.buf = &.{};
            self.head = 0;
            self.count = 0;
        }

        pub fn fromSlice(allocator: Allocator, values: []const T) Allocator.Error!Self {
            var d = init(allocator);
            errdefer d.deinit();
            try d.ensureUnusedCapacity(values.len);
            for (values) |v| d.addLastAssumeCapacity(v);
            return d;
        }

        // ---- capacity ------------------------------------------------------

        /// Grow (never shrink) so at least `needed` elements fit. Reallocating
        /// re-lays the live range contiguously at index 0.
        fn ensureCapacity(self: *Self, needed: usize) Allocator.Error!void {
            if (needed <= self.buf.len) return;
            var new_cap: usize = if (self.buf.len == 0) MIN_CAPACITY else self.buf.len;
            while (new_cap < needed) new_cap *|= 2;
            const new_buf = try self.allocator.alloc(T, new_cap);
            // Copy in logical (front-to-back) order into the fresh, unwrapped buf.
            const mask = self.buf.len -% 1;
            for (0..self.count) |i| new_buf[i] = self.buf[(self.head + i) & mask];
            if (self.buf.len != 0) self.allocator.free(self.buf);
            self.buf = new_buf;
            self.head = 0;
        }

        /// Ensures capacity for `additional` more items.
        pub fn ensureUnusedCapacity(self: *Self, additional: usize) Allocator.Error!void {
            try self.ensureCapacity(self.count + additional);
        }

        // ---- ends (all O(1) amortized) -------------------------------------

        fn addLastAssumeCapacity(self: *Self, value: T) void {
            self.buf[(self.head + self.count) & (self.buf.len - 1)] = value;
            self.count += 1;
        }

        /// Adds a value to the back of the deque. O(1) amortized.
        pub fn addLast(self: *Self, value: T) Allocator.Error!void {
            try self.ensureCapacity(self.count + 1);
            self.addLastAssumeCapacity(value);
        }

        /// Adds a value to the front of the deque. O(1) amortized.
        pub fn addFirst(self: *Self, value: T) Allocator.Error!void {
            try self.ensureCapacity(self.count + 1);
            // head - 1, wrapping (buf.len is a power of two, so & mask).
            self.head = (self.head + self.buf.len - 1) & (self.buf.len - 1);
            self.buf[self.head] = value;
            self.count += 1;
        }

        /// Removes and returns the front element, or null if empty. O(1).
        pub fn removeFirst(self: *Self) ?T {
            if (self.count == 0) return null;
            const v = self.buf[self.head];
            self.head = (self.head + 1) & (self.buf.len - 1);
            self.count -= 1;
            return v;
        }

        /// Removes and returns the back element, or null if empty. O(1).
        pub fn removeLast(self: *Self) ?T {
            if (self.count == 0) return null;
            self.count -= 1;
            return self.buf[(self.head + self.count) & (self.buf.len - 1)];
        }

        /// Returns the front element without removing it, or null if empty.
        pub fn peekFirst(self: *const Self) ?T {
            if (self.count == 0) return null;
            return self.buf[self.head];
        }

        /// Returns the back element without removing it, or null if empty.
        pub fn peekLast(self: *const Self) ?T {
            if (self.count == 0) return null;
            return self.buf[(self.head + self.count - 1) & (self.buf.len - 1)];
        }

        pub fn len(self: *const Self) usize {
            return self.count;
        }
        pub fn isEmpty(self: *const Self) bool {
            return self.count == 0;
        }
        pub fn clear(self: *Self) void {
            self.head = 0;
            self.count = 0;
        }

        pub fn contains(self: *const Self, value: T) bool {
            const mask = self.buf.len -% 1;
            for (0..self.count) |i| {
                if (elemEql(T, self.buf[(self.head + i) & mask], value)) return true;
            }
            return false;
        }

        /// Returns a borrowed slice view of the items in front-to-back order,
        /// valid until the next mutation.
        ///
        /// Because the ring can wrap, this COMPACTS the live range to a single
        /// contiguous run at the buffer start (rotating in place, O(n) worst
        /// case) so it can hand back one slice. It therefore needs a mutable
        /// deque (`*Self`) and reorders internal storage; the observable
        /// front-to-back order is unchanged. Calling it without interleaved
        /// front mutations is O(1) after the first call (already compacted).
        pub fn slice(self: *Self) []const T {
            if (self.count != 0 and self.head != 0) {
                // Rotate the whole buffer left by `head`: the element at physical
                // `head` (logical front) moves to index 0, and every logical
                // element i lands at index i. Free slots collect at the tail.
                std.mem.rotate(T, self.buf, self.head);
                self.head = 0;
            }
            return self.buf[0..self.count];
        }

        /// Returns an owned copy of the items in front-to-back order. Caller frees.
        pub fn toOwnedSlice(self: *const Self, allocator: Allocator) Allocator.Error![]T {
            const out = try allocator.alloc(T, self.count);
            const mask = self.buf.len -% 1;
            for (0..self.count) |i| out[i] = self.buf[(self.head + i) & mask];
            return out;
        }

        /// Pull-based iterator yielding each element by value in front-to-back
        /// order (matching `forEach`). Non-allocating: indexes into the backing
        /// ring directly, resolving the wrap per step. The iterator borrows the
        /// deque; do not mutate while iterating.
        pub const Iterator = struct {
            buf: []const T,
            head: usize,
            count: usize,
            index: usize = 0,

            pub fn next(self: *Iterator) ?T {
                if (self.index >= self.count) return null;
                const item = self.buf[(self.head + self.index) & (self.buf.len - 1)];
                self.index += 1;
                return item;
            }
        };

        /// Returns a pull-based iterator over the elements in front-to-back
        /// order (same order as `forEach`). Non-allocating.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .buf = self.buf, .head = self.head, .count = self.count };
        }

        /// Pull-based MUTABLE iterator yielding a `*T` pointer to each element
        /// in front-to-back order, so callers can mutate elements in place.
        /// Non-allocating: indexes into the backing ring directly. Safe surface:
        /// a deque imposes no hash/order invariant on its elements, so
        /// overwriting an element through the pointer cannot corrupt structure.
        /// Same invalidation contract as `iterator()`: STRUCTURAL mutation of
        /// the deque (addFirst/addLast/removeFirst/removeLast/clear) during
        /// iteration is illegal and invalidates the iterator. `iterator()`
        /// remains the canonical immutable, value-yielding iterator.
        pub const MutIterator = struct {
            buf: []T,
            head: usize,
            count: usize,
            index: usize = 0,

            pub fn next(self: *MutIterator) ?*T {
                if (self.index >= self.count) return null;
                const ptr = &self.buf[(self.head + self.index) & (self.buf.len - 1)];
                self.index += 1;
                return ptr;
            }
        };

        /// Returns a pull-based mutable iterator yielding `*T` element pointers
        /// in front-to-back order (additive; see `MutIterator`). Non-allocating.
        pub fn mutIterator(self: *Self) MutIterator {
            return .{ .buf = self.buf, .head = self.head, .count = self.count };
        }

        pub fn anySatisfy(self: *const Self, context: anytype, comptime predicate: fn (@TypeOf(context), T) bool) bool {
            const mask = self.buf.len -% 1;
            for (0..self.count) |i| {
                if (predicate(context, self.buf[(self.head + i) & mask])) return true;
            }
            return false;
        }

        pub fn allSatisfy(self: *const Self, context: anytype, comptime predicate: fn (@TypeOf(context), T) bool) bool {
            const mask = self.buf.len -% 1;
            for (0..self.count) |i| {
                if (!predicate(context, self.buf[(self.head + i) & mask])) return false;
            }
            return true;
        }

        pub fn eql(self: *const Self, other: *const Self) bool {
            if (self.count != other.count) return false;
            const sm = self.buf.len -% 1;
            const om = other.buf.len -% 1;
            for (0..self.count) |i| {
                const a = self.buf[(self.head + i) & sm];
                const b = other.buf[(other.head + i) & om];
                if (!elemEql(T, a, b)) return false;
            }
            return true;
        }

        pub fn format(self: *const Self, writer: anytype) !void {
            const mask = self.buf.len -% 1;
            try writer.writeAll("[");
            for (0..self.count) |i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{any}", .{self.buf[(self.head + i) & mask]});
            }
            try writer.writeAll("]");
        }
    };
}

// ---------------------------------------------------------------------------
// Tests — ring-buffer specifics (wrap, compaction, growth-while-wrapped, and a
// FIFO drain that would be O(n^2) on a flat-array deque). General behavior
// (order, iterators, format, eql, immutable fromMutable) is covered by
// containers_test.zig / iterator_test.zig / immutable_test.zig.
// ---------------------------------------------------------------------------

const testing = std.testing;

fn collect(d: *ArrayDeque(i32), out: []i32) []i32 {
    var it = d.iterator();
    var i: usize = 0;
    while (it.next()) |v| : (i += 1) out[i] = v;
    return out[0..i];
}

test "ArrayDeque ring: wrapped layout preserves front-to-back order" {
    const a = testing.allocator;
    var d = ArrayDeque(i32).init(a);
    defer d.deinit();

    // Force a wrapped live range without triggering growth: one addLast then an
    // addFirst puts head at the top of the 8-slot buffer while element 1 sits at
    // index 0 — the live range straddles the wrap.
    try d.addLast(1);
    try d.addFirst(0); // buf[7]=0, buf[0]=1 ; head=7,count=2 (wrapped)
    try testing.expect(d.head != 0);

    var buf: [16]i32 = undefined;
    try testing.expectEqualSlices(i32, &[_]i32{ 0, 1 }, collect(&d, &buf));
    try testing.expectEqual(@as(?i32, 0), d.peekFirst());
    try testing.expectEqual(@as(?i32, 1), d.peekLast());

    // slice() compacts the wrapped ring to a contiguous run, order intact, and
    // resets head to 0; a second slice() is then a no-op.
    try testing.expectEqualSlices(i32, &[_]i32{ 0, 1 }, d.slice());
    try testing.expectEqual(@as(usize, 0), d.head);
    try testing.expectEqualSlices(i32, &[_]i32{ 0, 1 }, d.slice());
}

test "ArrayDeque ring: heavy interleaving at both ends stays ordered" {
    const a = testing.allocator;
    var d = ArrayDeque(i32).init(a);
    defer d.deinit();

    // Build 1..=6 by alternating ends: addLast pushes back, addFirst pushes front.
    try d.addLast(4); // [4]
    try d.addFirst(3); // [3,4]
    try d.addLast(5); // [3,4,5]
    try d.addFirst(2); // [2,3,4,5]
    try d.addLast(6); // [2,3,4,5,6]
    try d.addFirst(1); // [1,2,3,4,5,6]
    var buf: [16]i32 = undefined;
    try testing.expectEqualSlices(i32, &[_]i32{ 1, 2, 3, 4, 5, 6 }, collect(&d, &buf));

    // Drain from both ends, checking order each way.
    try testing.expectEqual(@as(?i32, 1), d.removeFirst());
    try testing.expectEqual(@as(?i32, 6), d.removeLast());
    try testing.expectEqual(@as(?i32, 2), d.removeFirst());
    try testing.expectEqual(@as(?i32, 5), d.removeLast());
    try testing.expectEqualSlices(i32, &[_]i32{ 3, 4 }, collect(&d, &buf));
}

test "ArrayDeque ring: growth while wrapped preserves order" {
    const a = testing.allocator;
    var d = ArrayDeque(i32).init(a);
    defer d.deinit();

    // Fill to capacity via addFirst so the head wraps to the top, then keep
    // pushing to force a realloc from a wrapped state; the copy must relay the
    // live range in logical order.
    var i: i32 = 0;
    while (i < 40) : (i += 1) try d.addFirst(i); // logical order: 39,38,...,0
    try testing.expectEqual(@as(usize, 40), d.len());

    var buf: [64]i32 = undefined;
    const got = collect(&d, &buf);
    try testing.expectEqual(@as(usize, 40), got.len);
    i = 0;
    while (i < 40) : (i += 1) try testing.expectEqual(@as(i32, 39 - i), got[@intCast(i)]);
}

test "ArrayDeque ring: large FIFO drain is O(n) and correct (D8)" {
    // A flat-array deque (removeFirst == orderedRemove(0)) would make this
    // O(n^2) ~ 10^10 element shifts and time out; the ring buffer completes in
    // O(n). Doubles as a correctness check across many growth doublings.
    const a = testing.allocator;
    var d = ArrayDeque(i32).init(a);
    defer d.deinit();

    const N: i32 = 100_000;
    var i: i32 = 0;
    while (i < N) : (i += 1) try d.addLast(i);
    try testing.expectEqual(@as(usize, @intCast(N)), d.len());

    i = 0;
    while (i < N) : (i += 1) {
        try testing.expectEqual(@as(?i32, i), d.removeFirst()); // FIFO order
    }
    try testing.expect(d.isEmpty());
    try testing.expectEqual(@as(?i32, null), d.removeFirst());

    // Reusable after full drain.
    try d.addLast(7);
    try testing.expectEqual(@as(?i32, 7), d.peekFirst());
}
