// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Generic immutable deque. Single source for the 8 `Immutable<T>ArrayDeque`
//! per-type wrappers.
//!
//! Backed by an owned allocated slice. All "mutating" operations return new
//! immutable deques. `contains` / `eql` compare float elements by bit pattern
//! (NaN-aware, signed-zero distinct); other types compare with `==`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const deque = @import("../deque/deque.zig");

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
        else => @compileError("unsupported array deque type: " ++ @typeName(T)),
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
        else => @compileError("unsupported array deque type: " ++ @typeName(T)),
    };
}

fn MutableType(comptime T: type) type {
    const module = @field(deque, typeToken(T) ++ "_array_deque");
    return @field(module, typePascal(T) ++ "ArrayDeque");
}

fn elemEql(comptime T: type, a: T, b: T) bool {
    if (@typeInfo(T) == .float) {
        const Bits = std.meta.Int(.unsigned, @bitSizeOf(T));
        return @as(Bits, @bitCast(a)) == @as(Bits, @bitCast(b));
    }
    return a == b;
}

/// Immutable deque of `T` values, backed by an owned allocated slice.
pub fn ImmutableArrayDeque(comptime T: type) type {
    return struct {
        items: []const T,
        allocator: Allocator,

        const Self = @This();
        const Mutable = MutableType(T);

        pub fn fromSlice(allocator: Allocator, values: []const T) Allocator.Error!Self {
            const owned = try allocator.dupe(T, values);
            return .{ .items = owned, .allocator = allocator };
        }

        pub fn fromMutable(allocator: Allocator, mutable: *const Mutable) Allocator.Error!Self {
            return try fromSlice(allocator, mutable.items.items);
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
        }

        pub fn peekFirst(self: *const Self) ?T {
            if (self.items.len == 0) return null;
            return self.items[0];
        }

        pub fn peekLast(self: *const Self) ?T {
            if (self.items.len == 0) return null;
            return self.items[self.items.len - 1];
        }

        pub fn len(self: *const Self) usize {
            return self.items.len;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.items.len == 0;
        }

        /// Pull-based iterator yielding each element by value in front-to-back
        /// order. Non-allocating: indexes directly into the owned backing slice.
        pub const Iterator = struct {
            items: []const T,
            index: usize = 0,

            pub fn next(self: *Iterator) ?T {
                if (self.index >= self.items.len) return null;
                const item = self.items[self.index];
                self.index += 1;
                return item;
            }
        };

        /// Returns a pull-based iterator over the elements in front-to-back order.
        /// Non-allocating.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .items = self.items };
        }

        pub fn contains(self: *const Self, value: T) bool {
            for (self.items) |item| {
                if (elemEql(T, item, value)) return true;
            }
            return false;
        }

        /// Borrowed view into internal storage; invalidated by any structural
        /// mutation; do not free.
        pub fn slice(self: *const Self) []const T {
            return self.items;
        }

        /// Returns a new immutable deque with `value` prepended at the front.
        pub fn withFirst(self: *const Self, value: T) Allocator.Error!Self {
            const new_items = try self.allocator.alloc(T, self.items.len + 1);
            new_items[0] = value;
            @memcpy(new_items[1..], self.items);
            return .{ .items = new_items, .allocator = self.allocator };
        }

        /// Returns a new immutable deque with `value` appended at the back.
        pub fn withLast(self: *const Self, value: T) Allocator.Error!Self {
            const new_items = try self.allocator.alloc(T, self.items.len + 1);
            @memcpy(new_items[0..self.items.len], self.items);
            new_items[self.items.len] = value;
            return .{ .items = new_items, .allocator = self.allocator };
        }

        /// Returns a new deque without the front element, and the removed value.
        pub fn withoutFirst(self: *const Self) Allocator.Error!?struct { deque: Self, value: T } {
            if (self.items.len == 0) return null;
            const first = self.items[0];
            const new_items = try self.allocator.dupe(T, self.items[1..]);
            return .{
                .deque = .{ .items = new_items, .allocator = self.allocator },
                .value = first,
            };
        }

        /// Returns a new deque without the back element, and the removed value.
        pub fn withoutLast(self: *const Self) Allocator.Error!?struct { deque: Self, value: T } {
            if (self.items.len == 0) return null;
            const last = self.items[self.items.len - 1];
            const new_items = try self.allocator.dupe(T, self.items[0 .. self.items.len - 1]);
            return .{
                .deque = .{ .items = new_items, .allocator = self.allocator },
                .value = last,
            };
        }

        pub fn forEach(self: *const Self, context: anytype, comptime f: fn (@TypeOf(context), T) void) void {
            for (self.items) |value| f(context, value);
        }

        pub fn toMutable(self: *const Self) Allocator.Error!Mutable {
            return try Mutable.fromSlice(self.allocator, self.items);
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
