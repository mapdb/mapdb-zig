// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Generic immutable array list. Single source for the 8 `Immutable<T>ArrayList`
//! per-type wrappers.
//!
//! Backed by an owned allocated slice. All operations are read-only. The
//! element-type-dependent logic preserved from the per-type wrappers:
//!   * `contains` / `indexOf` / `eql` compare float elements by bit pattern
//!     (NaN-aware, +0.0 / -0.0 distinct); other types compare with `==`.
//!   * `min` / `max` order float elements through `float_order` total order;
//!     bool uses boolean ordering; other types use `std.math.order`.
//!   * `sum` returns the float type for float elements (plain `+=`), and an
//!     `i64` widening accumulator for `bool` / `char` / integer elements.

const std = @import("std");
const Allocator = std.mem.Allocator;
const float_order = @import("../float_order.zig");
const arraylist = @import("../arraylist/arraylist.zig");

/// Lowercase file-token for a primitive type (matches the project's filename
/// convention where `char` is backed by `u21`).
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
        else => @compileError("unsupported array list type: " ++ @typeName(T)),
    };
}

/// PascalCase type-token.
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
        else => @compileError("unsupported array list type: " ++ @typeName(T)),
    };
}

/// The production mutable `<T>ArrayList` source type.
fn MutableType(comptime T: type) type {
    const module = @field(arraylist, typeToken(T) ++ "_array_list");
    return @field(module, typePascal(T) ++ "ArrayList");
}

/// Bit-equality for floats (NaN-aware, signed-zero distinct), `==` otherwise.
fn elemEql(comptime T: type, a: T, b: T) bool {
    if (@typeInfo(T) == .float) {
        const Bits = std.meta.Int(.unsigned, @bitSizeOf(T));
        return @as(Bits, @bitCast(a)) == @as(Bits, @bitCast(b));
    }
    return a == b;
}

/// Immutable list of `T` values, backed by an owned allocated slice.
///
/// All operations are read-only. To modify, call `toMutable()` to get
/// an independent mutable copy. The caller must call `deinit()` when done.
pub fn ImmutableArrayList(comptime T: type) type {
    return struct {
        items: []const T,
        allocator: Allocator,

        const Self = @This();
        const Mutable = MutableType(T);

        /// Create from a slice by copying it. Caller retains ownership of the input.
        pub fn fromSlice(allocator: Allocator, values: []const T) Allocator.Error!Self {
            const owned = try allocator.dupe(T, values);
            return .{ .items = owned, .allocator = allocator };
        }

        /// Create from a mutable list by taking a snapshot.
        pub fn fromMutable(allocator: Allocator, mutable: *const Mutable) Allocator.Error!Self {
            return try fromSlice(allocator, mutable.items.items);
        }

        /// Release the owned slice.
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
        }

        pub fn get(self: *const Self, index: usize) ?T {
            if (index >= self.items.len) return null;
            return self.items[index];
        }

        pub fn len(self: *const Self) usize {
            return self.items.len;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.items.len == 0;
        }

        /// Pull-based iterator yielding each element by value in insertion order.
        /// Non-allocating: indexes directly into the owned backing slice.
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

        /// Returns a pull-based iterator over the elements in insertion order.
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

        pub fn indexOf(self: *const Self, value: T) ?usize {
            for (self.items, 0..) |item, i| {
                if (elemEql(T, item, value)) return i;
            }
            return null;
        }

        /// Borrowed view into internal storage; invalidated by any structural
        /// mutation; do not free.
        pub fn slice(self: *const Self) []const T {
            return self.items;
        }

        /// Returns the sum of all elements. Float elements sum in their own type;
        /// `bool` / `char` / integer elements sum into an `i64` accumulator.
        pub fn sum(self: *const Self) if (@typeInfo(T) == .float) T else i64 {
            if (@typeInfo(T) == .float) {
                var total: T = 0;
                for (self.items) |item| total += item;
                return total;
            } else if (T == bool) {
                var total: i64 = 0;
                for (self.items) |item| total += @as(i64, if (item) 1 else 0);
                return total;
            } else {
                var total: i64 = 0;
                for (self.items) |item| total += @as(i64, @intCast(item));
                return total;
            }
        }

        /// Returns the minimum element, or null if empty.
        pub fn min(self: *const Self) ?T {
            if (self.items.len == 0) return null;
            var result = self.items[0];
            for (self.items[1..]) |item| {
                if (elemLess(T, item, result)) result = item;
            }
            return result;
        }

        /// Returns the maximum element, or null if empty.
        pub fn max(self: *const Self) ?T {
            if (self.items.len == 0) return null;
            var result = self.items[0];
            for (self.items[1..]) |item| {
                if (elemLess(T, result, item)) result = item;
            }
            return result;
        }

        pub fn anySatisfy(self: *const Self, predicate: *const fn (T) bool) bool {
            for (self.items) |item| {
                if (predicate(item)) return true;
            }
            return false;
        }

        pub fn allSatisfy(self: *const Self, predicate: *const fn (T) bool) bool {
            for (self.items) |item| {
                if (!predicate(item)) return false;
            }
            return true;
        }

        pub fn noneSatisfy(self: *const Self, predicate: *const fn (T) bool) bool {
            for (self.items) |item| {
                if (predicate(item)) return false;
            }
            return true;
        }

        /// Create an independent mutable copy.
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

/// `a < b` under the element type's ordering: float total order, boolean
/// ordering (false < true), or `std.math.order` for integers / chars.
fn elemLess(comptime T: type, a: T, b: T) bool {
    if (@typeInfo(T) == .float) {
        const cmp = if (T == f32) float_order.totalCmpF32(a, b) else float_order.totalCmpF64(a, b);
        return cmp == .lt;
    } else if (T == bool) {
        return !a and b;
    } else {
        return std.math.order(a, b) == .lt;
    }
}
