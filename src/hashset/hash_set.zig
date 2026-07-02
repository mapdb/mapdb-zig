// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Generic hash set of unique `T` values. Single source for the 8 `<T>HashSet`
//! per-type wrappers.
//!
//! Backed by `OpenHashSet(T)` — O(1) average add/remove/contains. All element
//! equality and hashing (including bit-aware float handling and NaN/±0
//! semantics) is delegated to the hash table; this wrapper has no
//! element-type-dependent branches.

const std = @import("std");
const Allocator = std.mem.Allocator;
const OpenHashSet = @import("../hash_table.zig").OpenHashSet;
const pump = @import("../pump.zig");
const DupPolicy = pump.DupPolicy;

/// Hash set of unique `T` values.
///
/// Backed by OpenHashSet(T) — O(1) average add/remove/contains.
pub fn HashSet(comptime T: type) type {
    return struct {
        inner: OpenHashSet(T),
        allocator: Allocator,

        const Self = @This();

        // ---- Construction / Destruction ----

        pub fn init(allocator: Allocator) Allocator.Error!Self {
            return .{
                .inner = try OpenHashSet(T).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.inner.deinit();
        }

        pub fn of(allocator: Allocator, values: []const T) Allocator.Error!Self {
            var set = try init(allocator);
            for (values) |val| _ = try set.add(val);
            return set;
        }

        // ---- Data pump (bulk import) ----

        /// Effective error set of every pump entry point on this set.
        pub const BulkError = (error{ DuplicateKey, TooManyElements } || Allocator.Error);

        /// Bulk-loads a fresh `HashSet` from a value slice, pre-sizing the
        /// open-addressing table to fit every element at the load factor in one
        /// allocation (`cap = nextPow2(floor(4n/3)+1)`), then inserting via the
        /// normal probe. No mid-load rehash; the resulting slot layout is
        /// byte-identical to the same values added one-by-one. O(n).
        ///
        /// Input order is irrelevant (hash). On a duplicate value:
        /// `policy == .err` → `error.DuplicateKey`; `policy == .ignore` → keep
        /// the first occurrence, skip the rest. On any error nothing leaks.
        pub fn bulkLoad(allocator: Allocator, values: []const T, policy: DupPolicy) BulkError!Self {
            var self = Self{
                .inner = try OpenHashSet(T).initForElements(allocator, values.len),
                .allocator = allocator,
            };
            errdefer self.deinit();
            try self.bulkInsert(values, policy);
            return self;
        }

        /// Like `bulkLoad`, but `n` is an exact upper bound on the consumed
        /// source count and the table is sized for exactly `n` with a
        /// guaranteed zero mid-load rehash. Returns `error.TooManyElements` if
        /// the source exceeds `n`, even if extras would be ignored duplicates.
        pub fn bulkLoadExact(allocator: Allocator, values: []const T, n: usize, policy: DupPolicy) BulkError!Self {
            if (values.len > n) return error.TooManyElements;
            var self = Self{
                .inner = try OpenHashSet(T).initForElements(allocator, n),
                .allocator = allocator,
            };
            errdefer self.deinit();
            try self.bulkInsert(values, policy);
            return self;
        }

        fn bulkInsert(self: *Self, values: []const T, policy: DupPolicy) BulkError!void {
            for (values) |val| {
                const added = try self.inner.add(val);
                if (!added and policy == .err) return error.DuplicateKey;
            }
        }

        // ---- Core Operations ----

        /// Adds a value. Returns true if it was not already present.
        pub fn add(self: *Self, value: T) Allocator.Error!bool {
            return self.inner.add(value);
        }

        /// Adds all values from a slice.
        pub fn addAll(self: *Self, values: []const T) Allocator.Error!void {
            for (values) |val| _ = try self.add(val);
        }

        /// Removes a value. Returns true if it was present.
        pub fn remove(self: *Self, value: T) bool {
            return self.inner.remove(value);
        }

        pub fn contains(self: *const Self, value: T) bool {
            return self.inner.contains(value);
        }

        pub fn len(self: *const Self) usize {
            return self.inner.len();
        }

        /// Alias for len() — matches Go/Java naming.
        pub fn size(self: *const Self) usize {
            return self.len();
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.len() == 0;
        }

        pub fn clear(self: *Self) void {
            self.inner.clear();
        }

        // ---- Fallible capacity reservation ----

        /// Ensures that `additional` more entries can be added without
        /// triggering a rehash. Returns `error.OutOfMemory` if the allocator
        /// fails.
        pub fn ensureUnusedCapacity(self: *Self, additional: usize) Allocator.Error!void {
            return self.inner.ensureCapacity(additional);
        }

        /// Ensures the hash set's total capacity can fit at least `new_capacity`
        /// entries under the load factor without a rehash.
        pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) Allocator.Error!void {
            if (new_capacity <= self.inner.len()) return;
            return self.inner.ensureCapacity(new_capacity - self.inner.len());
        }

        // ---- Iteration ----

        const Entry = @import("../hash_table.zig").SetEntry(T);

        /// Pull-based iterator yielding each element by value in arbitrary
        /// (hash-table) order. Non-allocating: walks the inner table's occupied
        /// slots directly. The iterator borrows the set; do not mutate while iterating.
        pub const Iterator = struct {
            entries: []const Entry,
            index: usize = 0,

            pub fn next(self: *Iterator) ?T {
                while (self.index < self.entries.len) {
                    const e = self.entries[self.index];
                    self.index += 1;
                    if (e.occupied) return e.key;
                }
                return null;
            }
        };

        /// Returns a pull-based iterator over the elements in arbitrary order.
        /// Non-allocating.
        ///
        /// No `mutIterator()` is provided for sets (deliberate exclusion): a set
        /// element IS its own identity — its hash and slot are derived from the
        /// element itself — so mutating an element in place would leave it in
        /// the wrong bucket and silently corrupt the set. Remove the old element
        /// and add the new one instead.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .entries = self.inner.entries };
        }

        // ---- Functional Operations ----

        /// Returns a new set with only elements satisfying the predicate.
        pub fn select(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) Allocator.Error!Self {
            var result = try init(self.allocator);
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied) {
                    const value = self.inner.entries[i].key;
                    if (predicate(ctx, value)) _ = try result.add(value);
                }
            }
            return result;
        }

        /// Returns a new set with elements NOT satisfying the predicate.
        pub fn reject(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) Allocator.Error!Self {
            var result = try init(self.allocator);
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied) {
                    const value = self.inner.entries[i].key;
                    if (!predicate(ctx, value)) _ = try result.add(value);
                }
            }
            return result;
        }

        /// Returns the first element satisfying the predicate, or null.
        pub fn detect(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) ?T {
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied) {
                    const value = self.inner.entries[i].key;
                    if (predicate(ctx, value)) return value;
                }
            }
            return null;
        }

        /// Returns true if any element satisfies the predicate.
        pub fn anySatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) bool {
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied) {
                    const value = self.inner.entries[i].key;
                    if (predicate(ctx, value)) return true;
                }
            }
            return false;
        }

        /// Returns true if all elements satisfy the predicate.
        pub fn allSatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) bool {
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied) {
                    const value = self.inner.entries[i].key;
                    if (!predicate(ctx, value)) return false;
                }
            }
            return true;
        }

        /// Returns true if no element satisfies the predicate.
        pub fn noneSatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) bool {
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied) {
                    const value = self.inner.entries[i].key;
                    if (predicate(ctx, value)) return false;
                }
            }
            return true;
        }

        /// Returns the count of elements satisfying the predicate.
        pub fn count(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) usize {
            var c: usize = 0;
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied) {
                    const value = self.inner.entries[i].key;
                    if (predicate(ctx, value)) c += 1;
                }
            }
            return c;
        }

        // ---- Set Operations ----

        pub fn setUnion(self: *const Self, other: *const Self) Allocator.Error!Self {
            var result = try init(self.allocator);
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied) {
                    const value = self.inner.entries[i].key;
                    _ = try result.add(value);
                }
            }
            for (0..other.inner.capacity) |i| {
                if (other.inner.entries[i].occupied) {
                    const value = other.inner.entries[i].key;
                    _ = try result.add(value);
                }
            }
            return result;
        }

        pub fn intersect(self: *const Self, other: *const Self) Allocator.Error!Self {
            var result = try init(self.allocator);
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied) {
                    const value = self.inner.entries[i].key;
                    if (other.contains(value)) _ = try result.add(value);
                }
            }
            return result;
        }

        pub fn difference(self: *const Self, other: *const Self) Allocator.Error!Self {
            var result = try init(self.allocator);
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied) {
                    const value = self.inner.entries[i].key;
                    if (!other.contains(value)) _ = try result.add(value);
                }
            }
            return result;
        }

        pub fn symmetricDifference(self: *const Self, other: *const Self) Allocator.Error!Self {
            var result = try init(self.allocator);
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied) {
                    const value = self.inner.entries[i].key;
                    if (!other.contains(value)) _ = try result.add(value);
                }
            }
            for (0..other.inner.capacity) |i| {
                if (other.inner.entries[i].occupied) {
                    const value = other.inner.entries[i].key;
                    if (!self.contains(value)) _ = try result.add(value);
                }
            }
            return result;
        }

        // ---- Conversion ----

        /// Returns all elements as an allocated slice. Caller owns the slice.
        pub fn toSlice(self: *const Self, allocator: Allocator) Allocator.Error![]T {
            var buf: std.ArrayListUnmanaged(T) = .empty;
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied) {
                    const value = self.inner.entries[i].key;
                    try buf.append(allocator, value);
                }
            }
            return buf.toOwnedSlice(allocator);
        }

        /// Creates an immutable snapshot of this set.
        pub fn toImmutable(self: *const Self) Allocator.Error!ImmutableType(T) {
            return ImmutableType(T).fromMutable(self.allocator, self);
        }

        // ---- Fluent API ----

        /// Returns the set after adding a value (fluent).
        pub fn with(self: *Self, value: T) Allocator.Error!*Self {
            _ = try self.add(value);
            return self;
        }

        /// Returns the set after removing a value (fluent).
        pub fn without(self: *Self, value: T) *Self {
            _ = self.remove(value);
            return self;
        }

        /// Adds all values from a slice (fluent).
        pub fn withAll(self: *Self, values: []const T) Allocator.Error!*Self {
            try self.addAll(values);
            return self;
        }

        /// Removes all values from a slice (fluent).
        pub fn withoutAll(self: *Self, values: []const T) *Self {
            for (values) |val| _ = self.remove(val);
            return self;
        }

        // ---- Formatting ----

        /// Formats the set as "{v1, v2, v3}".
        pub fn format(self: *const Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.writeAll("{");
            var first = true;
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied) {
                    if (!first) try writer.writeAll(", ");
                    try writer.print("{any}", .{self.inner.entries[i].key});
                    first = false;
                }
            }
            try writer.writeAll("}");
        }

        // ---- Equality ----

        pub fn eql(self: *const Self, other: *const Self) bool {
            if (self.len() != other.len()) return false;
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied) {
                    const value = self.inner.entries[i].key;
                    if (!other.contains(value)) return false;
                }
            }
            return true;
        }
    };
}

/// The immutable snapshot type for element type `T`, resolved through the
/// immutable aggregator (mirrors the per-type wrappers' direct
/// `Immutable<T>HashSet` reference without a static import cycle).
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
        else => @compileError("unsupported hash set type: " ++ @typeName(T)),
    };
    return @field(immutable, "Immutable" ++ token ++ "HashSet");
}
