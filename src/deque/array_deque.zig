// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Generic double-ended queue. Single source for the 8 `<T>ArrayDeque` per-type
//! wrappers.
//!
//! Backed by `std.ArrayListUnmanaged(T)`. The only element-type-dependent logic
//! is `contains` / `eql`, which compare float elements by bit pattern
//! (NaN-aware, +0.0 / -0.0 distinct) and other types with `==`.

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

/// Double-ended queue of `T` values, backed by an `ArrayListUnmanaged`.
/// Back operations (addLast, removeLast) are O(1) amortized.
/// Front operations (addFirst, removeFirst) are O(n) due to shifting.
pub fn ArrayDeque(comptime T: type) type {
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
            var d = init(allocator);
            d.items.appendSlice(d.allocator, values) catch @panic("out of memory");
            return d;
        }

        /// Adds a value to the front of the deque. O(n) due to shift.
        pub fn addFirst(self: *Self, value: T) void {
            self.items.insert(self.allocator, 0, value) catch @panic("out of memory");
        }

        /// Adds a value to the back of the deque. O(1) amortized.
        pub fn addLast(self: *Self, value: T) void {
            self.items.append(self.allocator, value) catch @panic("out of memory");
        }

        /// Removes and returns the front element, or null if empty. O(n).
        pub fn removeFirst(self: *Self) ?T {
            if (self.items.items.len == 0) return null;
            return self.items.orderedRemove(0);
        }

        /// Removes and returns the back element, or null if empty. O(1).
        pub fn removeLast(self: *Self) ?T {
            return self.items.pop();
        }

        /// Returns the front element without removing it, or null if empty.
        pub fn peekFirst(self: *const Self) ?T {
            if (self.items.items.len == 0) return null;
            return self.items.items[0];
        }

        /// Returns the back element without removing it, or null if empty.
        pub fn peekLast(self: *const Self) ?T {
            if (self.items.items.len == 0) return null;
            return self.items.items[self.items.items.len - 1];
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

        /// Ensures capacity for `additional` more items.
        pub fn ensureUnusedCapacity(self: *Self, additional: usize) Allocator.Error!void {
            try self.items.ensureUnusedCapacity(self.allocator, additional);
        }

        pub fn contains(self: *const Self, value: T) bool {
            for (self.items.items) |v| {
                if (elemEql(T, v, value)) return true;
            }
            return false;
        }

        /// Returns a slice view of the items in front-to-back order. Valid until
        /// the next mutation.
        pub fn slice(self: *const Self) []const T {
            return self.items.items;
        }

        /// Returns an owned copy of the items in front-to-back order. Caller frees.
        pub fn toOwnedSlice(self: *const Self, allocator: Allocator) []T {
            const out = allocator.alloc(T, self.items.items.len) catch @panic("out of memory");
            @memcpy(out, self.items.items);
            return out;
        }

        pub fn forEach(self: *const Self, f: *const fn (T) void) void {
            for (self.items.items) |value| f(value);
        }

        pub fn anySatisfy(self: *const Self, predicate: *const fn (T) bool) bool {
            for (self.items.items) |value| {
                if (predicate(value)) return true;
            }
            return false;
        }

        pub fn allSatisfy(self: *const Self, predicate: *const fn (T) bool) bool {
            for (self.items.items) |value| {
                if (!predicate(value)) return false;
            }
            return true;
        }

        pub fn eql(self: *const Self, other: *const Self) bool {
            if (self.items.items.len != other.items.items.len) return false;
            for (self.items.items, other.items.items) |a, b| {
                if (!elemEql(T, a, b)) return false;
            }
            return true;
        }

        pub fn format(self: *const Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.writeAll("[");
            for (self.items.items, 0..) |value, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{any}", .{value});
            }
            try writer.writeAll("]");
        }
    };
}
