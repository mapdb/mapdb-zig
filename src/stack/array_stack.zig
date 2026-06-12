// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Generic LIFO stack. Single source for the 8 `<T>ArrayStack` per-type
//! wrappers.
//!
//! Backed by `std.ArrayListUnmanaged(T)`. The only element-type-dependent
//! logic is `contains` / `eql`, which compare float elements by bit pattern
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

/// LIFO stack of `T` values, backed by an ArrayList.
pub fn ArrayStack(comptime T: type) type {
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

        pub fn of(allocator: Allocator, values: []const T) Allocator.Error!Self {
            var stack = init(allocator);
            try stack.items.appendSlice(stack.allocator, values);
            return stack;
        }

        /// Pushes a value onto the top of the stack.
        pub fn push(self: *Self, value: T) Allocator.Error!void {
            try self.items.append(self.allocator, value);
        }

        /// Removes and returns the top element, or null if empty.
        pub fn pop(self: *Self) ?T {
            if (self.items.items.len == 0) return null;
            return self.items.pop();
        }

        /// Returns the top element without removing it, or null if empty.
        pub fn peek(self: *const Self) ?T {
            if (self.items.items.len == 0) return null;
            return self.items.items[self.items.items.len - 1];
        }

        /// Returns the element at the given depth from the top (0 = top).
        pub fn peekAt(self: *const Self, depth: usize) ?T {
            if (depth >= self.items.items.len) return null;
            return self.items.items[self.items.items.len - 1 - depth];
        }

        pub fn len(self: *const Self) usize {
            return self.items.items.len;
        }

        /// Alias for len() — matches Go/Java naming.
        pub fn size(self: *const Self) usize {
            return self.len();
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.items.items.len == 0;
        }

        pub fn clear(self: *Self) void {
            self.items.clearRetainingCapacity();
        }

        // ---- Fallible capacity reservation ----

        /// Ensures that `additional` more items can be pushed without a
        /// reallocation.
        pub fn ensureUnusedCapacity(self: *Self, additional: usize) Allocator.Error!void {
            return self.items.ensureUnusedCapacity(self.allocator, additional);
        }

        /// Ensures the stack's total capacity is at least `new_capacity`.
        pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) Allocator.Error!void {
            return self.items.ensureTotalCapacity(self.allocator, new_capacity);
        }

        pub fn contains(self: *const Self, value: T) bool {
            for (self.items.items) |item| {
                if (elemEql(T, item, value)) return true;
            }
            return false;
        }

        pub fn anySatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) bool {
            for (self.items.items) |item| {
                if (predicate(ctx, item)) return true;
            }
            return false;
        }

        pub fn allSatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) bool {
            for (self.items.items) |item| {
                if (!predicate(ctx, item)) return false;
            }
            return true;
        }

        // ---- Iteration ----

        /// Pull-based iterator yielding each element by value in bottom-to-top
        /// order (matching `forEach`). Non-allocating: indexes directly into the
        /// backing slice. The iterator borrows the stack; do not mutate while iterating.
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

        /// Returns a pull-based iterator over the elements in bottom-to-top
        /// order (same order as `forEach`). Non-allocating.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .items = self.items.items };
        }

        /// Pull-based MUTABLE iterator yielding a `*T` pointer to each element
        /// in bottom-to-top order, so callers can mutate elements in place.
        /// Non-allocating: indexes directly into the backing slice. Safe
        /// surface: a stack imposes no hash/order invariant on its elements, so
        /// overwriting an element through the pointer cannot corrupt structure.
        /// Same invalidation contract as `iterator()`: STRUCTURAL mutation of
        /// the stack (push/pop/clear) during iteration is illegal and
        /// invalidates the iterator. `iterator()` remains the canonical
        /// immutable, value-yielding iterator.
        pub const MutIterator = struct {
            items: []T,
            index: usize = 0,

            pub fn next(self: *MutIterator) ?*T {
                if (self.index >= self.items.len) return null;
                const ptr = &self.items[self.index];
                self.index += 1;
                return ptr;
            }
        };

        /// Returns a pull-based mutable iterator yielding `*T` element pointers
        /// in bottom-to-top order (additive; see `MutIterator`). Non-allocating.
        pub fn mutIterator(self: *Self) MutIterator {
            return .{ .items = self.items.items };
        }

        // ---- Functional Operations ----

        /// Returns a new stack with only elements satisfying the predicate.
        pub fn select(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) Allocator.Error!Self {
            var result = init(self.allocator);
            for (self.items.items) |item| {
                if (predicate(ctx, item)) try result.push(item);
            }
            return result;
        }

        /// Returns a new stack with elements NOT satisfying the predicate.
        pub fn reject(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) Allocator.Error!Self {
            var result = init(self.allocator);
            for (self.items.items) |item| {
                if (!predicate(ctx, item)) try result.push(item);
            }
            return result;
        }

        /// Returns the first element satisfying the predicate, or null.
        pub fn detect(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) ?T {
            for (self.items.items) |item| {
                if (predicate(ctx, item)) return item;
            }
            return null;
        }

        pub fn noneSatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) bool {
            for (self.items.items) |item| {
                if (predicate(ctx, item)) return false;
            }
            return true;
        }

        pub fn count(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) usize {
            var c: usize = 0;
            for (self.items.items) |item| {
                if (predicate(ctx, item)) c += 1;
            }
            return c;
        }

        pub fn injectInto(self: *const Self, ctx: *anyopaque, initial: T, f: *const fn (ctx: *anyopaque, T, T) T) T {
            var acc = initial;
            for (self.items.items) |item| acc = f(ctx, acc, item);
            return acc;
        }

        // ---- Conversion ----

        pub fn toSlice(self: *const Self) []const T {
            return self.items.items;
        }

        pub fn toImmutable(self: *const Self) Allocator.Error!ImmutableType(T) {
            return ImmutableType(T).fromMutable(self.allocator, self);
        }

        // ---- Fluent API ----

        pub fn with(self: *Self, value: T) Allocator.Error!*Self {
            try self.push(value);
            return self;
        }

        pub fn withAll(self: *Self, values: []const T) Allocator.Error!*Self {
            for (values) |val| try self.push(val);
            return self;
        }

        // ---- Formatting ----

        /// Formats as "[top, ..., bottom]" (top-to-bottom order).
        pub fn format(self: *const Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.writeAll("[");
            var i = self.items.items.len;
            var first = true;
            while (i > 0) {
                i -= 1;
                if (!first) try writer.writeAll(", ");
                try writer.print("{any}", .{self.items.items[i]});
                first = false;
            }
            try writer.writeAll("]");
        }

        // ---- Equality ----

        pub fn eql(self: *const Self, other: *const Self) bool {
            if (self.items.items.len != other.items.items.len) return false;
            for (self.items.items, other.items.items) |a, b| {
                if (!elemEql(T, a, b)) return false;
            }
            return true;
        }
    };
}

/// The immutable snapshot type for element type `T`, resolved through the
/// immutable aggregator (mirrors the per-type wrappers' direct
/// `Immutable<T>ArrayStack` reference without a static import cycle).
fn ImmutableType(comptime T: type) type {
    const immutable = @import("../immutable/immutable.zig");
    const token = switch (T) {
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
    return @field(immutable, "Immutable" ++ token ++ "ArrayStack");
}
