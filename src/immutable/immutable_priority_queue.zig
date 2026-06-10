// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Generic immutable min-heap priority queue. Single source for the 8
//! `Immutable<T>PriorityQueue` per-type wrappers.
//!
//! Backed by an owned heap-ordered slice. All heap ordering (including float
//! total-order for f32 / f64) is delegated to the production mutable
//! `<T>PriorityQueue`; this wrapper never compares elements with raw `<`.
//! `contains` / `eql` compare float elements by bit pattern (NaN-aware,
//! signed-zero distinct); other types compare with `==`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const priority_queue = @import("../priority_queue/priority_queue.zig");

fn typeToken(comptime T: type) []const u8 {
    return switch (T) {
        bool => "bool",
        u21 => "char",
        i8 => "i8",
        i16 => "i16",
        i32 => "i32",
        i64 => "i64",
        f32 => "f32",
        f64 => "f64",
        else => @compileError("unsupported priority queue type: " ++ @typeName(T)),
    };
}

fn typePascal(comptime T: type) []const u8 {
    return switch (T) {
        bool => "Bool",
        u21 => "Char",
        i8 => "I8",
        i16 => "I16",
        i32 => "I32",
        i64 => "I64",
        f32 => "F32",
        f64 => "F64",
        else => @compileError("unsupported priority queue type: " ++ @typeName(T)),
    };
}

fn MutableType(comptime T: type) type {
    const module = @field(priority_queue, typeToken(T) ++ "_priority_queue");
    return @field(module, typePascal(T) ++ "PriorityQueue");
}

fn elemEql(comptime T: type, a: T, b: T) bool {
    if (@typeInfo(T) == .float) {
        const Bits = std.meta.Int(.unsigned, @bitSizeOf(T));
        return @as(Bits, @bitCast(a)) == @as(Bits, @bitCast(b));
    }
    return a == b;
}

/// Immutable min-heap priority queue of `T` values, backed by an owned
/// heap-ordered slice. All "mutating" operations return new immutable queues.
pub fn ImmutablePriorityQueue(comptime T: type) type {
    return struct {
        items: []const T,
        allocator: Allocator,

        const Self = @This();
        const Mutable = MutableType(T);

        /// Heapifies `values` (copy) and wraps the result. O(n).
        pub fn of(allocator: Allocator, values: []const T) Self {
            var tmp = Mutable.of(allocator, values);
            defer tmp.deinit();
            const owned = allocator.dupe(T, tmp.slice()) catch @panic("out of memory");
            return .{ .items = owned, .allocator = allocator };
        }

        pub fn fromMutable(allocator: Allocator, mutable: *const Mutable) Self {
            const owned = allocator.dupe(T, mutable.slice()) catch @panic("out of memory");
            return .{ .items = owned, .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
        }

        /// Returns the smallest element without removing it, or null if empty.
        pub fn peek(self: *const Self) ?T {
            if (self.items.len == 0) return null;
            return self.items[0];
        }

        pub fn len(self: *const Self) usize {
            return self.items.len;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.items.len == 0;
        }

        pub fn contains(self: *const Self, value: T) bool {
            for (self.items) |item| {
                if (elemEql(T, item, value)) return true;
            }
            return false;
        }

        /// Returns a slice view of the internal heap array (NOT sorted).
        pub fn slice(self: *const Self) []const T {
            return self.items;
        }

        /// Returns a new immutable queue with `value` inserted. O(n) due to copy.
        pub fn push(self: *const Self, value: T) Self {
            var m = self.toMutable();
            defer m.deinit();
            m.push(value);
            const owned = self.allocator.dupe(T, m.slice()) catch @panic("out of memory");
            return .{ .items = owned, .allocator = self.allocator };
        }

        /// Returns a new queue without the smallest element, and the removed value.
        pub fn pop(self: *const Self) ?struct { queue: Self, value: T } {
            if (self.items.len == 0) return null;
            var m = self.toMutable();
            defer m.deinit();
            const top = m.pop().?;
            const owned = self.allocator.dupe(T, m.slice()) catch @panic("out of memory");
            return .{
                .queue = .{ .items = owned, .allocator = self.allocator },
                .value = top,
            };
        }

        pub fn toMutable(self: *const Self) Mutable {
            return Mutable.of(self.allocator, self.items);
        }

        pub fn eql(self: *const Self, other: *const Self) bool {
            if (self.items.len != other.items.len) return false;
            for (self.items, other.items) |a, b| {
                if (!elemEql(T, a, b)) return false;
            }
            return true;
        }
    };
}
