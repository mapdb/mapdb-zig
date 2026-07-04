// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Generic resizable array-backed list. Single source for the 8 `<T>ArrayList`
//! per-type wrappers.
//!
//! Backed by `std.ArrayListUnmanaged(T)` — no boxing, contiguous memory layout.
//! The element-type-dependent logic preserved from the per-type wrappers:
//!   * `contains` / `indexOf` / `eql` compare float elements by bit pattern
//!     (NaN-aware, +0.0 / -0.0 distinct); other types compare with `==`.
//!   * `min` / `max` / `sort` / `binarySearch` order float elements through
//!     `float_order` total order; `bool` uses boolean ordering
//!     (`false` < `true`); other types use `std.math.order`.
//!   * `sum` returns the float type for float elements (plain `+=`), and an
//!     `i64` widening accumulator for `bool` / `char` / integer elements.

const std = @import("std");
const Allocator = std.mem.Allocator;
const float_order = @import("../float_order.zig");

/// Bit-aware equality. Float members compare by reinterpreting to the same-width
/// unsigned integer (so `-0.0`/`+0.0` stay distinct and NaN payloads compare by
/// exact bits); non-float members use plain `==`.
fn elemEql(comptime T: type, a: T, b: T) bool {
    if (@typeInfo(T) == .float) {
        const Bits = std.meta.Int(.unsigned, @bitSizeOf(T));
        return @as(Bits, @bitCast(a)) == @as(Bits, @bitCast(b));
    }
    return a == b;
}

/// Total-ordering comparator for elements of type `T`: float total order
/// (IEEE 754 totalOrder), boolean ordering (`false` < `true`), or
/// `std.math.order` for integers / `u21` chars.
fn elemOrder(comptime T: type, a: T, b: T) std.math.Order {
    return switch (@typeInfo(T)) {
        .float => switch (T) {
            f32 => float_order.totalCmpF32(a, b),
            f64 => float_order.totalCmpF64(a, b),
            else => @compileError("unsupported float type: " ++ @typeName(T)),
        },
        .bool => if (a == b) std.math.Order.eq else if (!a and b) std.math.Order.lt else std.math.Order.gt,
        else => std.math.order(a, b),
    };
}

/// Resizable array-backed list of `T` values.
///
/// Specialized for `T` — no boxing, contiguous memory layout.
pub fn ArrayList(comptime T: type) type {
    return struct {
        items: std.ArrayListUnmanaged(T) = .empty,
        allocator: Allocator,

        const Self = @This();

        /// Sum accumulator type: the float type itself for float elements,
        /// `i64` (widening) for `bool` / `char` / integer elements.
        const SumType = if (@typeInfo(T) == .float) T else i64;

        /// Create with an allocator for all internal structures.
        pub fn init(allocator: Allocator) Self {
            return .{ .allocator = allocator };
        }

        /// Release all allocated memory.
        pub fn deinit(self: *Self) void {
            self.items.deinit(self.allocator);
        }

        /// Create a list from a slice of values.
        pub fn of(allocator: Allocator, values: []const T) Allocator.Error!Self {
            var list = init(allocator);
            try list.items.appendSlice(list.allocator, values);
            return list;
        }

        /// Appends a value to the end of the list.
        pub fn push(self: *Self, value: T) Allocator.Error!void {
            try self.items.append(self.allocator, value);
        }

        /// Appends all values from a slice.
        pub fn pushAll(self: *Self, values: []const T) Allocator.Error!void {
            try self.items.appendSlice(self.allocator, values);
        }

        /// Returns the element at the given index, or null if out of bounds.
        /// This is the bounds-checked accessor; `set`/`removeAtIndex` instead
        /// assert their index as a precondition (see D5).
        pub fn get(self: *const Self, index: usize) ?T {
            if (index >= self.items.items.len) return null;
            return self.items.items[index];
        }

        /// Sets the element at the given index. Returns the old value.
        /// Asserts `index < len()` as a precondition — an out-of-bounds index is
        /// a safety-checked panic in Debug/ReleaseSafe and UB in ReleaseFast
        /// (this differs from `get`, which returns null out of bounds; use `get`
        /// when the index may be invalid).
        pub fn set(self: *Self, index: usize, value: T) T {
            std.debug.assert(index < self.items.items.len);
            const old = self.items.items[index];
            self.items.items[index] = value;
            return old;
        }

        /// Removes and returns the element at the given index.
        /// Asserts `index < len()` as a precondition (same contract as `set`;
        /// see D5) — out-of-bounds is a checked panic / ReleaseFast UB.
        pub fn removeAtIndex(self: *Self, index: usize) T {
            std.debug.assert(index < self.items.items.len);
            return self.items.orderedRemove(index);
        }

        /// Removes the first occurrence of the value. Returns true if found.
        pub fn remove(self: *Self, value: T) bool {
            if (self.indexOf(value)) |idx| {
                _ = self.items.orderedRemove(idx);
                return true;
            }
            return false;
        }

        /// Returns true if the list contains the given value.
        pub fn contains(self: *const Self, value: T) bool {
            for (self.items.items) |item| {
                if (elemEql(T, item, value)) return true;
            }
            return false;
        }

        /// Returns the index of the first occurrence, or null if not found.
        pub fn indexOf(self: *const Self, value: T) ?usize {
            for (self.items.items, 0..) |item, i| {
                if (elemEql(T, item, value)) return i;
            }
            return null;
        }

        /// Returns the number of elements.
        pub fn len(self: *const Self) usize {
            return self.items.items.len;
        }

        /// Alias for len() — matches Go/Java naming.
        pub fn size(self: *const Self) usize {
            return self.len();
        }

        /// Returns true if the list is empty.
        pub fn isEmpty(self: *const Self) bool {
            return self.items.items.len == 0;
        }

        /// Alias for push() — matches Go/Java Add naming.
        pub fn add(self: *Self, value: T) Allocator.Error!void {
            try self.push(value);
        }

        /// Alias for pushAll() — matches Go/Java AddAll naming.
        pub fn addAll(self: *Self, values: []const T) Allocator.Error!void {
            try self.pushAll(values);
        }

        /// Removes all elements.
        pub fn clear(self: *Self) void {
            self.items.clearRetainingCapacity();
        }

        // ---- Fallible capacity reservation ----

        /// Ensures that `additional` more items can be appended without a
        /// reallocation. Returns `error.OutOfMemory` if the allocator fails.
        /// Pair this with the infallible `push` / `with` methods to get an
        /// opt-in allocation-failure handling path.
        pub fn ensureUnusedCapacity(self: *Self, additional: usize) Allocator.Error!void {
            return self.items.ensureUnusedCapacity(self.allocator, additional);
        }

        /// Ensures the list's total capacity is at least `new_capacity`.
        /// Idempotent. Returns `error.OutOfMemory` if the allocator fails.
        pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) Allocator.Error!void {
            return self.items.ensureTotalCapacity(self.allocator, new_capacity);
        }

        /// Returns a new list with only elements satisfying the predicate.
        pub fn select(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) Allocator.Error!Self {
            var result = init(self.allocator);
            errdefer result.deinit();
            for (self.items.items) |item| {
                if (predicate(ctx, item)) try result.push(item);
            }
            return result;
        }

        /// Returns a new list with elements NOT satisfying the predicate.
        pub fn reject(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) Allocator.Error!Self {
            var result = init(self.allocator);
            errdefer result.deinit();
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

        /// Returns true if any element satisfies the predicate.
        pub fn anySatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) bool {
            for (self.items.items) |item| {
                if (predicate(ctx, item)) return true;
            }
            return false;
        }

        /// Returns true if all elements satisfy the predicate.
        pub fn allSatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) bool {
            for (self.items.items) |item| {
                if (!predicate(ctx, item)) return false;
            }
            return true;
        }

        /// Returns true if no element satisfies the predicate.
        pub fn noneSatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) bool {
            for (self.items.items) |item| {
                if (predicate(ctx, item)) return false;
            }
            return true;
        }

        /// Returns the count of elements satisfying the predicate.
        pub fn count(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) usize {
            var c: usize = 0;
            for (self.items.items) |item| {
                if (predicate(ctx, item)) c += 1;
            }
            return c;
        }

        /// Returns the sum of all elements. Float elements sum in their own
        /// type; `bool` / `char` / integer elements sum into an `i64`
        /// accumulator with **two's-complement wraparound** on overflow, matching
        /// the Java and Go originals (which wrap silently). This is deliberate:
        /// a trapping `+=` (Zig's default) would panic in safe builds and be UB
        /// in ReleaseFast where the ports wrap — a cross-language behavior
        /// divergence. Pinned by the cross-language validation suite (D4).
        pub fn sum(self: *const Self) SumType {
            if (@typeInfo(T) == .float) {
                var total: T = 0;
                for (self.items.items) |item| {
                    total += item;
                }
                return total;
            } else if (T == bool) {
                var total: i64 = 0;
                for (self.items.items) |item| {
                    total +%= @as(i64, if (item) 1 else 0);
                }
                return total;
            } else {
                var total: i64 = 0;
                for (self.items.items) |item| {
                    // Width-safe widen to i64: signed and sub-64-bit unsigned
                    // types widen losslessly; a 64-bit unsigned element is
                    // reinterpreted (two's-complement) so keys > maxInt(i64)
                    // never trap (the D1 cast trap, avoided here too).
                    const w: i64 = switch (@typeInfo(T)) {
                        .int => |info| if (info.signedness == .unsigned and info.bits >= 64)
                            // 64-bit-and-wider unsigned: reduce to the low 64
                            // bits (two's-complement wrap at the i64 accumulator
                            // width) instead of @intCast-trapping. @truncate is
                            // the identity for u64 and the low-64 fold for u128+,
                            // so ArrayList(u128).sum() compiles and wraps.
                            @bitCast(@as(u64, @truncate(item)))
                        else
                            @intCast(item),
                        else => @intCast(item),
                    };
                    total +%= w;
                }
                return total;
            }
        }

        /// Returns the minimum element, or null if empty.
        pub fn min(self: *const Self) ?T {
            if (self.items.items.len == 0) return null;
            var result = self.items.items[0];
            for (self.items.items[1..]) |item| {
                if (elemOrder(T, item, result) == .lt) result = item;
            }
            return result;
        }

        /// Returns the maximum element, or null if empty.
        pub fn max(self: *const Self) ?T {
            if (self.items.items.len == 0) return null;
            var result = self.items.items[0];
            for (self.items.items[1..]) |item| {
                if (elemOrder(T, item, result) == .gt) result = item;
            }
            return result;
        }

        /// Sorts the list in ascending order.
        pub fn sort(self: *Self) void {
            std.mem.sort(T, self.items.items, {}, struct {
                pub fn f(_: void, a: T, b: T) bool {
                    return elemOrder(T, a, b) == .lt;
                }
            }.f);
        }

        /// Returns a new list with elements in reverse order.
        pub fn reversed(self: *const Self) Allocator.Error!Self {
            var result = init(self.allocator);
            errdefer result.deinit();
            var i = self.items.items.len;
            while (i > 0) {
                i -= 1;
                try result.push(self.items.items[i]);
            }
            return result;
        }

        /// Borrowed view into internal storage; invalidated by any structural
        /// mutation; do not free.
        pub fn slice(self: *const Self) []const T {
            return self.items.items;
        }

        // ---- Iteration ----

        /// Pull-based iterator yielding each element by value in insertion
        /// order. Non-allocating: indexes directly into the backing slice.
        /// The iterator borrows the list; do not mutate the list while iterating.
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
        /// Non-allocating. Use this instead of a push-based forEach.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .items = self.items.items };
        }

        /// Pull-based MUTABLE iterator yielding a `*T` pointer to each element
        /// in insertion order, so callers can mutate elements in place.
        /// Non-allocating: indexes directly into the backing slice. Safe
        /// surface: a list imposes no hash/order invariant on its elements, so
        /// overwriting an element through the pointer cannot corrupt structure.
        /// Same invalidation contract as `iterator()`: STRUCTURAL mutation of
        /// the list (push/insert/remove/clear/sort) during iteration is illegal
        /// and invalidates the iterator. `iterator()` remains the canonical
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
        /// in insertion order (additive; see `MutIterator`). Non-allocating.
        pub fn mutIterator(self: *Self) MutIterator {
            return .{ .items = self.items.items };
        }

        /// Calls f(ctx, index, value) for each element.
        pub fn forEachWithIndex(self: *const Self, ctx: *anyopaque, f: *const fn (ctx: *anyopaque, usize, T) void) void {
            for (self.items.items, 0..) |item, i| f(ctx, i, item);
        }

        // ---- Advanced Operations ----

        /// Fold/reduce over all elements.
        pub fn injectInto(self: *const Self, ctx: *anyopaque, initial: T, f: *const fn (ctx: *anyopaque, T, T) T) T {
            var acc = initial;
            for (self.items.items) |item| acc = f(ctx, acc, item);
            return acc;
        }

        /// Returns a new list with duplicate elements removed (preserving first occurrence order).
        pub fn distinct(self: *const Self) Allocator.Error!Self {
            var result = init(self.allocator);
            errdefer result.deinit();
            for (self.items.items) |item| {
                if (!result.contains(item)) try result.push(item);
            }
            return result;
        }

        /// Binary search on a sorted list. Returns the index if found, null otherwise.
        pub fn binarySearch(self: *const Self, value: T) ?usize {
            var lo: usize = 0;
            var hi: usize = self.items.items.len;
            while (lo < hi) {
                const mid = lo + (hi - lo) / 2;
                const ord = elemOrder(T, self.items.items[mid], value);
                if (ord == .lt) {
                    lo = mid + 1;
                } else if (ord == .gt) {
                    hi = mid;
                } else {
                    return mid;
                }
            }
            return null;
        }

        // ---- Conversion ----

        /// Creates an immutable snapshot of this list.
        pub fn toImmutable(self: *const Self) Allocator.Error!ImmutableType(T) {
            return ImmutableType(T).fromMutable(self.allocator, self);
        }

        // ---- Fluent API ----

        /// Appends a value (fluent).
        pub fn with(self: *Self, value: T) Allocator.Error!*Self {
            try self.push(value);
            return self;
        }

        /// Removes the first occurrence (fluent).
        pub fn without(self: *Self, value: T) *Self {
            _ = self.remove(value);
            return self;
        }

        /// Appends all values (fluent).
        pub fn withAll(self: *Self, values: []const T) Allocator.Error!*Self {
            try self.pushAll(values);
            return self;
        }

        /// Removes all occurrences of each value (fluent).
        pub fn withoutAll(self: *Self, values: []const T) *Self {
            for (values) |val| _ = self.remove(val);
            return self;
        }

        // ---- Equality ----

        /// Formats the list as "[v1, v2, v3]".
        pub fn format(self: *const Self, writer: anytype) !void {
            try writer.writeAll("[");
            for (self.items.items, 0..) |item, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{any}", .{item});
            }
            try writer.writeAll("]");
        }

        /// Returns true if two lists have equal elements in the same order.
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
/// immutable aggregator's lowercase namespaces (mirrors the per-type wrappers'
/// direct `Immutable<T>ArrayList` reference without a static import cycle).
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
        else => @compileError("unsupported array list type: " ++ @typeName(T)),
    };
    return @field(immutable, "Immutable" ++ token ++ "ArrayList");
}
