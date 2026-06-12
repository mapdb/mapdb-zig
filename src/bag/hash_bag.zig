// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Generic hash bag (multiset) with occurrence counting. Single source for the
//! 8 `<T>HashBag` per-type wrappers.
//!
//! Backed by `OpenHashMap(T, usize)` mapping each distinct value to its count.
//! All element equality and hashing (including bit-aware float handling and
//! NaN/±0 semantics) is delegated to the hash table; this wrapper has no
//! element-type-dependent branches.

const std = @import("std");
const Allocator = std.mem.Allocator;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;

/// Bag (multiset) of `T` values with occurrence counting.
///
/// Backed by OpenHashMap(T, usize).
pub fn HashBag(comptime T: type) type {
    return struct {
        counts: OpenHashMap(T, usize),
        size: usize,
        allocator: Allocator,

        const Self = @This();

        /// (value, count) pair returned by `topOccurrences`.
        pub const OccurrenceEntry = struct { value: T, count: usize };

        pub fn init(allocator: Allocator) Allocator.Error!Self {
            return .{
                .counts = try OpenHashMap(T, usize).init(allocator),
                .size = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.counts.deinit();
        }

        pub fn of(allocator: Allocator, values: []const T) Allocator.Error!Self {
            var bag = try init(allocator);
            for (values) |val| {
                try bag.add(val);
            }
            return bag;
        }

        /// Add one occurrence of the value.
        pub fn add(self: *Self, value: T) Allocator.Error!void {
            if (self.counts.getPtr(value)) |count_ptr| {
                count_ptr.* += 1;
            } else {
                _ = try self.counts.put(value, 1);
            }
            self.size += 1;
        }

        /// Remove one occurrence. Returns true if the value was present.
        pub fn remove(self: *Self, value: T) bool {
            if (self.counts.getPtr(value)) |count_ptr| {
                count_ptr.* -= 1;
                if (count_ptr.* == 0) {
                    _ = self.counts.remove(value);
                }
                self.size -= 1;
                return true;
            }
            return false;
        }

        /// Remove all occurrences of the value. Returns true if present.
        pub fn removeAll(self: *Self, value: T) bool {
            if (self.counts.getPtr(value)) |count_ptr| {
                self.size -= count_ptr.*;
                _ = self.counts.remove(value);
                return true;
            }
            return false;
        }

        /// Returns the number of occurrences of the value.
        pub fn occurrencesOf(self: *const Self, value: T) usize {
            return self.counts.get(value) orelse 0;
        }

        pub fn contains(self: *const Self, value: T) bool {
            return self.occurrencesOf(value) > 0;
        }

        /// Total number of elements (counting duplicates).
        pub fn totalSize(self: *const Self) usize {
            return self.size;
        }

        /// Number of distinct values.
        pub fn sizeDistinct(self: *const Self) usize {
            return self.counts.len();
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.size == 0;
        }

        pub fn clear(self: *Self) void {
            self.counts.clear();
            self.size = 0;
        }

        // ---- Fallible capacity reservation ----

        /// Ensures the internal count-map can hold `additional` more distinct
        /// values without triggering a rehash. Returns `error.OutOfMemory` on
        /// allocator failure. Note that the count is bounded by distinct
        /// values, not total occurrences.
        pub fn ensureUnusedCapacity(self: *Self, additional: usize) Allocator.Error!void {
            return self.counts.ensureCapacity(additional);
        }

        /// Ensures the internal count-map's total capacity can fit at least
        /// `new_capacity` distinct values.
        pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) Allocator.Error!void {
            const cur = self.counts.len();
            if (new_capacity <= cur) return;
            return self.counts.ensureCapacity(new_capacity - cur);
        }

        pub fn len(self: *const Self) usize {
            return self.size;
        }

        /// Add multiple occurrences of a value.
        pub fn addOccurrences(self: *Self, value: T, n: usize) Allocator.Error!void {
            var i: usize = 0;
            while (i < n) : (i += 1) try self.add(value);
        }

        /// Remove up to n occurrences. Returns number actually removed.
        pub fn removeOccurrences(self: *Self, value: T, n: usize) usize {
            var removed: usize = 0;
            var i: usize = 0;
            while (i < n) : (i += 1) {
                if (self.remove(value)) {
                    removed += 1;
                } else break;
            }
            return removed;
        }

        // ---- Iteration ----

        const InnerEntry = @import("../hash_table.zig").MapEntry(T, usize);

        /// Pull-based iterator yielding each element by value, repeated once per
        /// occurrence (matching `forEach`), in arbitrary (hash-table) order.
        /// Non-allocating: walks the inner count-map's occupied slots directly,
        /// tracking how many occurrences of the current value remain to be
        /// yielded. The iterator borrows the bag; do not mutate while iterating.
        pub const Iterator = struct {
            entries: []const InnerEntry,
            index: usize = 0,
            remaining: usize = 0,
            current: T = undefined,

            pub fn next(self: *Iterator) ?T {
                if (self.remaining > 0) {
                    self.remaining -= 1;
                    return self.current;
                }
                while (self.index < self.entries.len) {
                    const e = self.entries[self.index];
                    self.index += 1;
                    if (e.occupied and e.value > 0) {
                        self.current = e.key;
                        self.remaining = e.value - 1;
                        return e.key;
                    }
                }
                return null;
            }
        };

        /// Returns a pull-based iterator yielding each element repeated by its
        /// occurrence count (same elements as `forEach`), in arbitrary order.
        /// Non-allocating.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .entries = self.counts.entries };
        }

        /// Calls f(ctx, value, count) for each distinct value.
        pub fn forEachWithOccurrences(self: *const Self, ctx: *anyopaque, f: *const fn (ctx: *anyopaque, T, usize) void) void {
            for (0..self.counts.capacity) |i| {
                if (self.counts.entries[i].occupied) {
                    f(ctx, self.counts.entries[i].key, self.counts.entries[i].value);
                }
            }
        }

        // ---- Functional Operations ----

        /// Returns a new bag with only elements satisfying the predicate (preserving counts).
        pub fn select(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) Allocator.Error!Self {
            var result = try init(self.allocator);
            for (0..self.counts.capacity) |i| {
                if (self.counts.entries[i].occupied) {
                    if (predicate(ctx, self.counts.entries[i].key)) try result.addOccurrences(self.counts.entries[i].key, self.counts.entries[i].value);
                }
            }
            return result;
        }

        /// Returns a new bag with elements NOT satisfying the predicate.
        pub fn reject(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) Allocator.Error!Self {
            var result = try init(self.allocator);
            for (0..self.counts.capacity) |i| {
                if (self.counts.entries[i].occupied) {
                    if (!predicate(ctx, self.counts.entries[i].key)) try result.addOccurrences(self.counts.entries[i].key, self.counts.entries[i].value);
                }
            }
            return result;
        }

        /// Returns the first distinct value satisfying the predicate, or null.
        pub fn detect(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) ?T {
            for (0..self.counts.capacity) |i| {
                if (self.counts.entries[i].occupied) {
                    if (predicate(ctx, self.counts.entries[i].key)) return self.counts.entries[i].key;
                }
            }
            return null;
        }

        pub fn anySatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) bool {
            return self.detect(ctx, predicate) != null;
        }

        pub fn allSatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) bool {
            for (0..self.counts.capacity) |i| {
                if (self.counts.entries[i].occupied) {
                    if (!predicate(ctx, self.counts.entries[i].key)) return false;
                }
            }
            return true;
        }

        pub fn noneSatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, T) bool) bool {
            return self.detect(ctx, predicate) == null;
        }

        // ---- Conversion ----

        /// Returns all elements (with duplicates) as an allocated slice.
        pub fn toSlice(self: *const Self, allocator: Allocator) Allocator.Error![]T {
            var buf: std.ArrayListUnmanaged(T) = .empty;
            for (0..self.counts.capacity) |i| {
                if (self.counts.entries[i].occupied) {
                    var j: usize = 0;
                    while (j < self.counts.entries[i].value) : (j += 1) try buf.append(allocator, self.counts.entries[i].key);
                }
            }
            return buf.toOwnedSlice(allocator);
        }

        /// Creates an immutable snapshot of this bag.
        pub fn toImmutable(self: *const Self) Allocator.Error!ImmutableType(T) {
            return ImmutableType(T).fromMutable(self.allocator, self);
        }

        // ---- Fluent API ----

        pub fn with(self: *Self, value: T) Allocator.Error!*Self {
            try self.add(value);
            return self;
        }

        pub fn without(self: *Self, value: T) *Self {
            _ = self.remove(value);
            return self;
        }

        pub fn withAll(self: *Self, values: []const T) Allocator.Error!*Self {
            for (values) |val| try self.add(val);
            return self;
        }

        pub fn withoutAll(self: *Self, values: []const T) *Self {
            for (values) |val| _ = self.removeAll(val);
            return self;
        }

        // ---- Advanced ----

        /// Returns the top n values by occurrence count as (value, count) pairs.
        /// Caller owns the returned slice.
        pub fn topOccurrences(self: *const Self, allocator: Allocator, n: usize) Allocator.Error![]OccurrenceEntry {
            const Entry = OccurrenceEntry;
            var buf: std.ArrayListUnmanaged(Entry) = .empty;
            for (0..self.counts.capacity) |i| {
                if (self.counts.entries[i].occupied) {
                    try buf.append(allocator, .{ .value = self.counts.entries[i].key, .count = self.counts.entries[i].value });
                }
            }
            // Sort by count descending
            std.mem.sort(Entry, buf.items, {}, struct {
                pub fn f(_: void, a: Entry, b: Entry) bool {
                    return a.count > b.count;
                }
            }.f);
            const limit = @min(n, buf.items.len);
            const result = try allocator.alloc(Entry, limit);
            @memcpy(result, buf.items[0..limit]);
            buf.deinit(allocator);
            return result;
        }

        // ---- Formatting ----

        /// Formats as "{v1x2, v2x1}".
        pub fn format(self: *const Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.writeAll("{");
            var first = true;
            for (0..self.counts.capacity) |i| {
                if (self.counts.entries[i].occupied) {
                    if (!first) try writer.writeAll(", ");
                    try writer.print("{any}", .{self.counts.entries[i].key});
                    try writer.writeAll("x");
                    try writer.print("{any}", .{self.counts.entries[i].value});
                    first = false;
                }
            }
            try writer.writeAll("}");
        }

        // ---- Equality ----

        pub fn eql(self: *const Self, other: *const Self) bool {
            if (self.size != other.size) return false;
            if (self.counts.len() != other.counts.len()) return false;
            for (0..self.counts.capacity) |i| {
                if (self.counts.entries[i].occupied) {
                    if (other.occurrencesOf(self.counts.entries[i].key) != self.counts.entries[i].value) return false;
                }
            }
            return true;
        }
    };
}

/// The immutable snapshot type for element type `T`, resolved through the
/// immutable aggregator (mirrors the per-type wrappers' direct
/// `Immutable<T>HashBag` reference without a static import cycle).
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
        else => @compileError("unsupported hash bag type: " ++ @typeName(T)),
    };
    return @field(immutable, "Immutable" ++ token ++ "HashBag");
}
