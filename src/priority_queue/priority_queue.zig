// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Aggregator + generic for the primitive min-heap priority queue.
//!
//! `PriorityQueue(T)` is a single-source generic backed by an
//! `ArrayListUnmanaged(T)`. The element-type-dependent logic preserved from the
//! per-type wrappers:
//!   * heap ordering: float elements use `float_order` total order (NaN/±0
//!     correct), `bool` uses `false` < `true`, other types use natural `<`.
//!   * `contains` compares float elements by bit pattern (NaN-aware, signed-zero
//!     distinct); other types compare with `==`.
//!
//! This module exposes the named `<T>PriorityQueue` aliases that the rest of the
//! project (and the cross-language validate harness) consume, and preserves the
//! historical per-file lowercase namespaces for backward compatibility (e.g.
//! `priority_queue.i32_priority_queue.I32PriorityQueue`).

const std = @import("std");
const Allocator = std.mem.Allocator;
const float_order = @import("../float_order.zig");

/// Bit-aware equality. Float members compare by reinterpreting to the same-width
/// unsigned integer; non-float members use plain `==`.
fn elemEql(comptime T: type, a: T, b: T) bool {
    if (@typeInfo(T) == .float) {
        const Bits = std.meta.Int(.unsigned, @bitSizeOf(T));
        return @as(Bits, @bitCast(a)) == @as(Bits, @bitCast(b));
    }
    return a == b;
}

/// `a < b` under the heap ordering: float total order (IEEE 754 totalOrder),
/// boolean ordering (`false` < `true`), or natural `<` for integers / `u21`.
fn elemLess(comptime T: type, a: T, b: T) bool {
    return switch (@typeInfo(T)) {
        .float => switch (T) {
            f32 => float_order.totalCmpF32(a, b) == .lt,
            f64 => float_order.totalCmpF64(a, b) == .lt,
            else => @compileError("unsupported float type: " ++ @typeName(T)),
        },
        .bool => !a and b,
        else => a < b,
    };
}

/// Primitive min-heap priority queue of `T` values, backed by an
/// `ArrayListUnmanaged`. O(log n) push/pop, O(1) peek.
pub fn PriorityQueue(comptime T: type) type {
    return struct {
        items: std.ArrayListUnmanaged(T) = .empty,
        allocator: Allocator,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit(self.allocator);
        }

        pub fn of(allocator: Allocator, values: []const T) Self {
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
        pub fn push(self: *Self, value: T) void {
            self.items.append(self.allocator, value) catch @panic("out of memory");
            self.siftUp(self.items.items.len - 1);
        }

        /// Removes and returns the smallest element, or null if empty. O(log n).
        pub fn pop(self: *Self) ?T {
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
        pub fn peek(self: *const Self) ?T {
            if (self.items.items.len == 0) return null;
            return self.items.items[0];
        }

        pub fn len(self: *const Self) usize {
            return self.items.items.len;
        }
        pub fn isEmpty(self: *const Self) bool {
            return self.items.items.len == 0;
        }
        pub fn clear(self: *Self) void {
            self.items.clearRetainingCapacity();
        }

        pub fn ensureUnusedCapacity(self: *Self, additional: usize) Allocator.Error!void {
            try self.items.ensureUnusedCapacity(self.allocator, additional);
        }

        pub fn contains(self: *const Self, value: T) bool {
            for (self.items.items) |v| {
                if (elemEql(T, v, value)) return true;
            }
            return false;
        }

        /// Returns a slice view of the internal heap array (NOT sorted).
        pub fn slice(self: *const Self) []const T {
            return self.items.items;
        }

        /// Drains the heap into a caller-owned slice in ascending order.
        pub fn drainSorted(self: *Self, allocator: Allocator) []T {
            const out = allocator.alloc(T, self.items.items.len) catch @panic("out of memory");
            var i: usize = 0;
            while (self.pop()) |v| : (i += 1) {
                out[i] = v;
            }
            return out;
        }

        fn siftUp(self: *Self, start: usize) void {
            var i = start;
            while (i > 0) {
                const parent = (i - 1) / 2;
                if (elemLess(T, self.items.items[i], self.items.items[parent])) {
                    const tmp = self.items.items[i];
                    self.items.items[i] = self.items.items[parent];
                    self.items.items[parent] = tmp;
                    i = parent;
                } else break;
            }
        }

        fn siftDown(self: *Self, start: usize) void {
            var i = start;
            const n = self.items.items.len;
            while (true) {
                const left = 2 * i + 1;
                if (left >= n) break;
                const right = left + 1;
                var best = left;
                if (right < n and elemLess(T, self.items.items[right], self.items.items[left])) {
                    best = right;
                }
                if (elemLess(T, self.items.items[best], self.items.items[i])) {
                    const tmp = self.items.items[best];
                    self.items.items[best] = self.items.items[i];
                    self.items.items[i] = tmp;
                    i = best;
                } else break;
            }
        }
    };
}

// ---- Named priority queue aliases ----

pub const BoolPriorityQueue = PriorityQueue(bool);
pub const CharPriorityQueue = PriorityQueue(u21);
pub const F32PriorityQueue = PriorityQueue(f32);
pub const F64PriorityQueue = PriorityQueue(f64);
pub const I8PriorityQueue = PriorityQueue(i8);
pub const I16PriorityQueue = PriorityQueue(i16);
pub const I32PriorityQueue = PriorityQueue(i32);
pub const I64PriorityQueue = PriorityQueue(i64);

// ---- Backward-compat per-file namespaces ----

pub const bool_priority_queue = struct {
    pub const BoolPriorityQueue = PriorityQueue(bool);
};
pub const char_priority_queue = struct {
    pub const CharPriorityQueue = PriorityQueue(u21);
};
pub const f32_priority_queue = struct {
    pub const F32PriorityQueue = PriorityQueue(f32);
};
pub const f64_priority_queue = struct {
    pub const F64PriorityQueue = PriorityQueue(f64);
};
pub const i8_priority_queue = struct {
    pub const I8PriorityQueue = PriorityQueue(i8);
};
pub const i16_priority_queue = struct {
    pub const I16PriorityQueue = PriorityQueue(i16);
};
pub const i32_priority_queue = struct {
    pub const I32PriorityQueue = PriorityQueue(i32);
};
pub const i64_priority_queue = struct {
    pub const I64PriorityQueue = PriorityQueue(i64);
};
