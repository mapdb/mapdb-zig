// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Generic immutable LIFO stack. Single source for the 8 `Immutable<T>ArrayStack`
//! per-type wrappers.
//!
//! Persistent operations: `push()` and `pop()` return new immutable stacks
//! rather than modifying in place. `contains` / `eql` compare float elements by
//! bit pattern (NaN-aware, signed-zero distinct); other types compare with `==`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const stack = @import("../stack/stack.zig");

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
        else => @compileError("unsupported array stack type: " ++ @typeName(T)),
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
        else => @compileError("unsupported array stack type: " ++ @typeName(T)),
    };
}

fn MutableType(comptime T: type) type {
    const module = @field(stack, typeToken(T) ++ "_array_stack");
    return @field(module, typePascal(T) ++ "ArrayStack");
}

fn elemEql(comptime T: type, a: T, b: T) bool {
    if (@typeInfo(T) == .float) {
        const Bits = std.meta.Int(.unsigned, @bitSizeOf(T));
        return @as(Bits, @bitCast(a)) == @as(Bits, @bitCast(b));
    }
    return a == b;
}

/// Immutable LIFO stack of `T` values.
pub fn ImmutableArrayStack(comptime T: type) type {
    return struct {
        items: []const T,
        allocator: Allocator,

        const Self = @This();
        const Mutable = MutableType(T);

        pub fn of(allocator: Allocator, values: []const T) Allocator.Error!Self {
            const owned = try allocator.dupe(T, values);
            return .{ .items = owned, .allocator = allocator };
        }

        pub fn fromMutable(allocator: Allocator, mutable: *const Mutable) Allocator.Error!Self {
            return try of(allocator, mutable.items.items);
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
        }

        pub fn peek(self: *const Self) ?T {
            if (self.items.len == 0) return null;
            return self.items[self.items.len - 1];
        }

        pub fn len(self: *const Self) usize {
            return self.items.len;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.items.len == 0;
        }

        /// Pull-based iterator yielding each element by value in bottom-to-top
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

        /// Returns a pull-based iterator over the elements in bottom-to-top order.
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

        pub fn toSlice(self: *const Self) []const T {
            return self.items;
        }

        /// Returns a new immutable stack with the value pushed on top.
        pub fn push(self: *const Self, value: T) Allocator.Error!Self {
            const new_items = try self.allocator.alloc(T, self.items.len + 1);
            @memcpy(new_items[0..self.items.len], self.items);
            new_items[self.items.len] = value;
            return .{ .items = new_items, .allocator = self.allocator };
        }

        /// Returns a new immutable stack without the top element, and the popped value.
        /// Returns null if empty.
        pub fn pop(self: *const Self) Allocator.Error!?struct { stack: Self, value: T } {
            if (self.items.len == 0) return null;
            const top = self.items[self.items.len - 1];
            const new_items = try self.allocator.dupe(T, self.items[0 .. self.items.len - 1]);
            return .{
                .stack = .{ .items = new_items, .allocator = self.allocator },
                .value = top,
            };
        }

        pub fn toMutable(self: *const Self) Allocator.Error!Mutable {
            return try Mutable.of(self.allocator, self.items);
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
