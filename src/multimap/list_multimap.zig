// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// The type actually stored as the backing `AutoHashMap` key. Float keys are
/// canonicalized to their unsigned bit pattern: Zig's `AutoHashMap` rejects
/// float keys at comptime, and the bit pattern also makes ±0 / NaN distinct.
/// Non-float keys are stored as-is.
fn MapKey(comptime K: type) type {
    return if (@typeInfo(K) == .float) std.meta.Int(.unsigned, @bitSizeOf(K)) else K;
}

/// Whether values of type `V` must be compared by bit pattern (floats) rather
/// than `==` for dedup / containment / equality. Matches the original per-type
/// wrappers, where only float-valued multimaps used `@bitCast` comparisons.
fn valueEql(comptime V: type, a: V, b: V) bool {
    if (@typeInfo(V) == .float) {
        const Bits = std.meta.Int(.unsigned, @bitSizeOf(V));
        return @as(Bits, @bitCast(a)) == @as(Bits, @bitCast(b));
    }
    return a == b;
}

/// List multimap from `K` keys to `V` values.
///
/// Each key maps to a list of values, preserving insertion order per key.
/// Backed by `AutoHashMapUnmanaged` for O(1) key lookup. Float keys are stored
/// as their bit pattern for correct hashing/equality.
pub fn ListMultimap(comptime K: type, comptime V: type) type {
    const MK = MapKey(K);

    return struct {
        inner: std.AutoHashMapUnmanaged(MK, std.ArrayListUnmanaged(V)),
        allocator: Allocator,
        total_size: usize,

        const Self = @This();

        /// Canonicalizes a `K` key into its backing-map key.
        fn mapKey(key: K) MK {
            return if (@typeInfo(K) == .float) @as(MK, @bitCast(key)) else key;
        }

        /// Restores a `K` key from its stored backing-map key.
        fn keyFromStored(stored: MK) K {
            return if (@typeInfo(K) == .float) @as(K, @bitCast(stored)) else stored;
        }

        // ---- Construction / Destruction ----

        pub fn init(allocator: Allocator) Self {
            return .{
                .inner = std.AutoHashMapUnmanaged(MK, std.ArrayListUnmanaged(V)){},
                .allocator = allocator,
                .total_size = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }
            self.inner.deinit(self.allocator);
        }

        // ---- Core Operations ----

        /// Adds a value to the list for the given key.
        pub fn put(self: *Self, key: K, value: V) Allocator.Error!void {
            const map_key = mapKey(key);
            const gop = try self.inner.getOrPut(self.allocator, map_key);
            if (!gop.found_existing) {
                gop.value_ptr.* = std.ArrayListUnmanaged(V){};
            }
            try gop.value_ptr.append(self.allocator, value);
            self.total_size += 1;
        }

        /// Returns a slice of values for the given key. No allocation; the
        /// returned slice is a view into internal storage.
        pub fn get(self: *const Self, key: K) []const V {
            const map_key = mapKey(key);
            if (self.inner.getPtr(map_key)) |list_ptr| {
                return list_ptr.items;
            }
            return &[_]V{};
        }

        /// Returns the number of values for the given key.
        pub fn getCount(self: *const Self, key: K) usize {
            const map_key = mapKey(key);
            if (self.inner.getPtr(map_key)) |list_ptr| {
                return list_ptr.items.len;
            }
            return 0;
        }

        /// Removes all values for the given key. Returns the number of values removed.
        pub fn removeAll(self: *Self, key: K) usize {
            const map_key = mapKey(key);
            const list_ptr = self.inner.getPtr(map_key) orelse return 0;
            const removed = list_ptr.items.len;
            list_ptr.deinit(self.allocator);
            self.total_size -= removed;
            _ = self.inner.remove(map_key);
            return removed;
        }

        /// Returns true if the multimap contains the given key.
        pub fn containsKey(self: *const Self, key: K) bool {
            const map_key = mapKey(key);
            return self.inner.contains(map_key);
        }

        /// Returns true if the multimap contains the given key-value pair.
        pub fn containsKeyValue(self: *const Self, key: K, value: V) bool {
            const vals = self.get(key);
            for (vals) |v| {
                if (valueEql(V, v, value)) return true;
            }
            return false;
        }

        /// Returns the number of distinct keys. O(1).
        pub fn keysCount(self: *const Self) usize {
            return self.inner.count();
        }

        /// Returns the total number of values across all keys.
        pub fn size(self: *const Self) usize {
            return self.total_size;
        }

        pub fn len(self: *const Self) usize {
            return self.total_size;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.total_size == 0;
        }

        pub fn clear(self: *Self) void {
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }
            self.inner.clearRetainingCapacity();
            self.total_size = 0;
        }

        // ---- Fallible capacity reservation ----

        /// Ensures the backing map can hold `additional` more distinct keys
        /// without rehashing. Per-key value lists grow independently.
        /// Returns `error.OutOfMemory` if the allocator fails.
        pub fn ensureUnusedCapacity(self: *Self, additional: usize) Allocator.Error!void {
            try self.inner.ensureUnusedCapacity(self.allocator, @intCast(additional));
        }

        /// Ensures the backing map's total capacity is at least `new_capacity`.
        pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) Allocator.Error!void {
            try self.inner.ensureTotalCapacity(self.allocator, @intCast(new_capacity));
        }

        // ---- Iteration ----

        /// An entry yielded by `Iterator` — key and value by value. One entry is
        /// yielded per (key, value) pair, matching `forEach`.
        pub const IterEntry = struct { key: K, value: V };

        const InnerIterator = std.AutoHashMapUnmanaged(MK, std.ArrayListUnmanaged(V)).Iterator;

        /// Pull-based iterator yielding one `{ key, value }` per (key, value)
        /// pair — i.e. each key repeated once per value in its list, in arbitrary
        /// key order with per-key insertion order preserved (matching `forEach`).
        /// Non-allocating: wraps the backing map's entry iterator plus a value
        /// index into the current key's value list. The iterator borrows the
        /// multimap; do not mutate while iterating.
        pub const Iterator = struct {
            inner: InnerIterator,
            current_key: K = undefined,
            current_values: []const V = &[_]V{},
            value_index: usize = 0,

            pub fn next(self: *Iterator) ?IterEntry {
                while (self.value_index >= self.current_values.len) {
                    const entry = self.inner.next() orelse return null;
                    self.current_key = keyFromStored(entry.key_ptr.*);
                    self.current_values = entry.value_ptr.items;
                    self.value_index = 0;
                }
                const v = self.current_values[self.value_index];
                self.value_index += 1;
                return .{ .key = self.current_key, .value = v };
            }
        };

        /// Returns a pull-based iterator yielding one `{ key, value }` per
        /// (key, value) pair (same pairs as `forEach`). Non-allocating.
        ///
        /// No `mutIterator()` is provided for multimaps (deliberate exclusion):
        /// the iterator flattens (key, value) pairs whose keys are identity, and
        /// a multimap's values live inside per-key nested collections rather
        /// than as standalone scalar slots. Mutate a key's value-collection
        /// through its own API after a normal lookup; keys are immutable.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .inner = self.inner.iterator() };
        }

        // ---- Functional Operations ----

        /// Returns a new multimap containing only pairs that satisfy the predicate.
        pub fn select(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, K, V) bool) Allocator.Error!Self {
            var result = Self.init(self.allocator);
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                const key = keyFromStored(entry.key_ptr.*);
                for (entry.value_ptr.items) |v| {
                    if (predicate(ctx, key, v)) try result.put(key, v);
                }
            }
            return result;
        }

        /// Returns a new multimap containing only pairs that do not satisfy the predicate.
        pub fn reject(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, K, V) bool) Allocator.Error!Self {
            var result = Self.init(self.allocator);
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                const key = keyFromStored(entry.key_ptr.*);
                for (entry.value_ptr.items) |v| {
                    if (!predicate(ctx, key, v)) try result.put(key, v);
                }
            }
            return result;
        }

        /// Returns true if any key-value pair satisfies the predicate.
        pub fn anySatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, K, V) bool) bool {
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                const key = keyFromStored(entry.key_ptr.*);
                for (entry.value_ptr.items) |v| {
                    if (predicate(ctx, key, v)) return true;
                }
            }
            return false;
        }

        /// Returns true if all key-value pairs satisfy the predicate.
        pub fn allSatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, K, V) bool) bool {
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                const key = keyFromStored(entry.key_ptr.*);
                for (entry.value_ptr.items) |v| {
                    if (!predicate(ctx, key, v)) return false;
                }
            }
            return true;
        }

        /// Returns true if no key-value pair satisfies the predicate.
        pub fn noneSatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, K, V) bool) bool {
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                const key = keyFromStored(entry.key_ptr.*);
                for (entry.value_ptr.items) |v| {
                    if (predicate(ctx, key, v)) return false;
                }
            }
            return true;
        }

        /// Returns the number of key-value pairs that satisfy the predicate.
        pub fn count(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, K, V) bool) usize {
            var c: usize = 0;
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                const key = keyFromStored(entry.key_ptr.*);
                for (entry.value_ptr.items) |v| {
                    if (predicate(ctx, key, v)) c += 1;
                }
            }
            return c;
        }

        // ---- Key/Value Collection ----

        /// Returns all unique keys as a slice. Caller must free.
        pub fn uniqueKeys(self: *const Self, allocator: Allocator) Allocator.Error![]K {
            var result = std.ArrayListUnmanaged(K){};
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                try result.append(allocator, keyFromStored(entry.key_ptr.*));
            }
            return result.toOwnedSlice(allocator);
        }

        /// Returns all values as a slice. Caller must free.
        pub fn valuesToSlice(self: *const Self, allocator: Allocator) Allocator.Error![]V {
            var result = std.ArrayListUnmanaged(V){};
            try result.ensureTotalCapacity(allocator, self.total_size);
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                try result.appendSlice(allocator, entry.value_ptr.items);
            }
            return result.toOwnedSlice(allocator);
        }

        // ---- Fluent API ----

        pub fn withKeyValue(self: *Self, key: K, value: V) Allocator.Error!*Self {
            try self.put(key, value);
            return self;
        }

        // ---- Formatting ----

        pub fn format(self: *const Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.writeAll("{");
            var first = true;
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                const key = keyFromStored(entry.key_ptr.*);
                for (entry.value_ptr.items) |v| {
                    if (!first) try writer.writeAll(", ");
                    try writer.print("{any}", .{key});
                    try writer.writeAll("=");
                    try writer.print("{any}", .{v});
                    first = false;
                }
            }
            try writer.writeAll("}");
        }

        // ---- Equality ----

        pub fn eql(self: *const Self, other: *const Self) bool {
            if (self.total_size != other.total_size) return false;
            if (self.inner.count() != other.inner.count()) return false;
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                const other_list = other.inner.getPtr(entry.key_ptr.*) orelse return false;
                if (entry.value_ptr.items.len != other_list.items.len) return false;
                for (entry.value_ptr.items, other_list.items) |a, b| {
                    if (!valueEql(V, a, b)) return false;
                }
            }
            return true;
        }
    };
}
