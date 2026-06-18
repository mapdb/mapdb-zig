// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

const std = @import("std");
const Allocator = std.mem.Allocator;
const float_order = @import("../float_order.zig");
const pump = @import("../pump.zig");
const DupPolicy = pump.DupPolicy;

/// Total-ordering comparator for tree-map keys of type `K`.
///
/// Branches at comptime on the key type, reproducing the per-type
/// `orderFn` of the original generated wrappers byte-for-byte:
///   * `f32`/`f64`: IEEE 754 totalOrder — see src/float_order.zig. A raw bit
///     compare is not a total order when NaN coexists with negatives.
///   * `bool`: explicit three-way (`false` < `true`).
///   * everything else (int / `u21` char): `std.math.order`.
fn keyOrder(comptime K: type, a: K, b: K) std.math.Order {
    return switch (@typeInfo(K)) {
        .float => switch (K) {
            f32 => float_order.totalCmpF32(a, b),
            f64 => float_order.totalCmpF64(a, b),
            else => @compileError("unsupported float key type: " ++ @typeName(K)),
        },
        .bool => if (a == b) std.math.Order.eq else if (!a and b) std.math.Order.lt else std.math.Order.gt,
        else => std.math.order(a, b),
    };
}

/// Bit-aware equality for a tree-map member of type `T`.
///
/// Float members (`f32`/`f64`) compare by reinterpreting to the same-width
/// unsigned integer so that `-0.0`/`+0.0` stay distinct and NaN payloads
/// compare by exact bits, matching the original wrappers. Non-float members
/// use plain `==`.
fn memberEql(comptime T: type, a: T, b: T) bool {
    return switch (@typeInfo(T)) {
        .float => switch (T) {
            f32 => @as(u32, @bitCast(a)) == @as(u32, @bitCast(b)),
            f64 => @as(u64, @bitCast(a)) == @as(u64, @bitCast(b)),
            else => @compileError("unsupported float type: " ++ @typeName(T)),
        },
        else => a == b,
    };
}

/// Sorted map from `K` keys to `V` values, backed by two sorted ArrayLists
/// (keys + values) kept in lock-step and binary-searched via `keyOrder`.
///
/// The key ordering is type-dependent: float keys use the IEEE 754 totalOrder
/// (NaN and ±0 handled correctly), `bool` uses `false` < `true`, and all other
/// key types use natural integer order. Float *values* compare by exact bits
/// in `eql`.
pub fn TreeMap(comptime K: type, comptime V: type) type {
    return struct {
        keys: std.ArrayListUnmanaged(K) = .empty,
        vals: std.ArrayListUnmanaged(V) = .empty,
        allocator: Allocator,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            self.keys.deinit(self.allocator);
            self.vals.deinit(self.allocator);
        }

        fn orderFn(a: K, b: K) std.math.Order {
            return keyOrder(K, a, b);
        }

        fn findIndex(self: *const Self, key: K) struct { index: usize, found: bool } {
            var lo: usize = 0;
            var hi: usize = self.keys.items.len;
            while (lo < hi) {
                const mid = lo + (hi - lo) / 2;
                const ord = orderFn(self.keys.items[mid], key);
                if (ord == .lt) {
                    lo = mid + 1;
                } else if (ord == .gt) {
                    hi = mid;
                } else {
                    return .{ .index = mid, .found = true };
                }
            }
            return .{ .index = lo, .found = false };
        }

        /// Inserts a key-value pair. Returns the old value if the key existed.
        pub fn put(self: *Self, key: K, value: V) Allocator.Error!?V {
            const result = self.findIndex(key);
            if (result.found) {
                const old = self.vals.items[result.index];
                self.vals.items[result.index] = value;
                return old;
            }
            try self.keys.ensureUnusedCapacity(self.allocator, 1);
            try self.vals.ensureUnusedCapacity(self.allocator, 1);
            try self.keys.insert(self.allocator, result.index, key);
            self.vals.insert(self.allocator, result.index, value) catch |err| {
                _ = self.keys.orderedRemove(result.index);
                return err;
            };
            return null;
        }

        pub fn get(self: *const Self, key: K) ?V {
            const result = self.findIndex(key);
            if (!result.found) return null;
            return self.vals.items[result.index];
        }

        pub fn remove(self: *Self, key: K) ?V {
            const result = self.findIndex(key);
            if (!result.found) return null;
            const old = self.vals.items[result.index];
            _ = self.keys.orderedRemove(result.index);
            _ = self.vals.orderedRemove(result.index);
            return old;
        }

        pub fn containsKey(self: *const Self, key: K) bool {
            return self.findIndex(key).found;
        }

        pub fn getOrDefault(self: *const Self, key: K, default_value: V) V {
            return self.get(key) orelse default_value;
        }

        pub fn len(self: *const Self) usize {
            return self.keys.items.len;
        }

        /// Alias for len() — matches Go/Java naming.
        pub fn size(self: *const Self) usize {
            return self.len();
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.keys.items.len == 0;
        }

        pub fn clear(self: *Self) void {
            self.keys.clearRetainingCapacity();
            self.vals.clearRetainingCapacity();
        }

        // ---- Fallible capacity reservation ----

        /// Ensures both the keys and values buffers can hold `additional` more
        /// entries without reallocating. Returns `error.OutOfMemory` if the
        /// allocator fails.
        pub fn ensureUnusedCapacity(self: *Self, additional: usize) Allocator.Error!void {
            try self.keys.ensureUnusedCapacity(self.allocator, additional);
            try self.vals.ensureUnusedCapacity(self.allocator, additional);
        }

        /// Ensures both internal buffers' total capacity is at least
        /// `new_capacity`.
        pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) Allocator.Error!void {
            try self.keys.ensureTotalCapacity(self.allocator, new_capacity);
            try self.vals.ensureTotalCapacity(self.allocator, new_capacity);
        }

        pub fn min(self: *const Self) ?struct { key: K, value: V } {
            if (self.keys.items.len == 0) return null;
            return .{ .key = self.keys.items[0], .value = self.vals.items[0] };
        }

        pub fn max(self: *const Self) ?struct { key: K, value: V } {
            if (self.keys.items.len == 0) return null;
            const last = self.keys.items.len - 1;
            return .{ .key = self.keys.items[last], .value = self.vals.items[last] };
        }

        pub fn keysSlice(self: *const Self) []const K {
            return self.keys.items;
        }

        pub fn valuesSlice(self: *const Self) []const V {
            return self.vals.items;
        }

        // ---- Iteration ----

        /// An entry yielded by `Iterator` — key and value by value.
        pub const IterEntry = struct { key: K, value: V };

        /// Pull-based iterator yielding `{ key, value }` entries in ascending
        /// sorted key order. Non-allocating: indexes the parallel sorted
        /// keys/values backing slices. The iterator borrows the map; do not
        /// mutate while iterating.
        pub const Iterator = struct {
            keys: []const K,
            vals: []const V,
            index: usize = 0,

            pub fn next(self: *Iterator) ?IterEntry {
                if (self.index >= self.keys.len) return null;
                const e = IterEntry{ .key = self.keys[self.index], .value = self.vals[self.index] };
                self.index += 1;
                return e;
            }
        };

        /// Returns a pull-based iterator over `{ key, value }` entries in
        /// ascending sorted key order. Non-allocating.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .keys = self.keys.items, .vals = self.vals.items };
        }

        /// An entry yielded by `MutIterator` — the key by value, the value as a
        /// `*V` pointer. The KEY is yielded by value on purpose: mutating a key
        /// in place would break the sorted-key ordering invariant, so only the
        /// value is exposed mutably.
        pub const MutEntry = struct { key: K, value_ptr: *V };

        /// Pull-based MUTABLE iterator yielding `{ key, value_ptr }` in
        /// ascending sorted key order, so callers can mutate VALUES in place
        /// through `value_ptr`. Non-allocating: indexes the parallel sorted
        /// keys/values backing slices. Safe surface: the value is not part of
        /// the ordering key, so writing through `value_ptr` cannot break the
        /// sort. Keys are immutable by construction (yielded by value). Same
        /// invalidation contract as `iterator()`: STRUCTURAL mutation of the
        /// map (put/remove/clear) during iteration is illegal and invalidates
        /// the iterator. `iterator()` remains the canonical immutable,
        /// value-yielding iterator.
        pub const MutIterator = struct {
            keys: []const K,
            vals: []V,
            index: usize = 0,

            pub fn next(self: *MutIterator) ?MutEntry {
                if (self.index >= self.keys.len) return null;
                const e = MutEntry{ .key = self.keys[self.index], .value_ptr = &self.vals[self.index] };
                self.index += 1;
                return e;
            }
        };

        /// Returns a pull-based mutable iterator yielding `{ key, value_ptr }`
        /// entries in ascending sorted key order (additive; see `MutIterator`).
        /// Non-allocating.
        pub fn mutIterator(self: *Self) MutIterator {
            return .{ .keys = self.keys.items, .vals = self.vals.items };
        }

        pub fn forEachKey(self: *const Self, ctx: *anyopaque, f: *const fn (ctx: *anyopaque, K) void) void {
            for (self.keys.items) |k| f(ctx, k);
        }

        pub fn forEachValue(self: *const Self, ctx: *anyopaque, f: *const fn (ctx: *anyopaque, V) void) void {
            for (self.vals.items) |val| f(ctx, val);
        }

        // ---- Functional Operations ----

        pub fn select(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, K, V) bool) Allocator.Error!Self {
            var result = init(self.allocator);
            for (self.keys.items, self.vals.items) |k, val| {
                if (predicate(ctx, k, val)) _ = try result.put(k, val);
            }
            return result;
        }

        pub fn reject(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, K, V) bool) Allocator.Error!Self {
            var result = init(self.allocator);
            for (self.keys.items, self.vals.items) |k, val| {
                if (!predicate(ctx, k, val)) _ = try result.put(k, val);
            }
            return result;
        }

        pub fn detect(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, K, V) bool) ?struct { key: K, value: V } {
            for (self.keys.items, self.vals.items) |k, val| {
                if (predicate(ctx, k, val)) return .{ .key = k, .value = val };
            }
            return null;
        }

        pub fn anySatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, K, V) bool) bool {
            for (self.keys.items, self.vals.items) |k, val| {
                if (predicate(ctx, k, val)) return true;
            }
            return false;
        }

        pub fn allSatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, K, V) bool) bool {
            for (self.keys.items, self.vals.items) |k, val| {
                if (!predicate(ctx, k, val)) return false;
            }
            return true;
        }

        pub fn noneSatisfy(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, K, V) bool) bool {
            for (self.keys.items, self.vals.items) |k, val| {
                if (predicate(ctx, k, val)) return false;
            }
            return true;
        }

        pub fn count(self: *const Self, ctx: *anyopaque, predicate: *const fn (ctx: *anyopaque, K, V) bool) usize {
            var c: usize = 0;
            for (self.keys.items, self.vals.items) |k, val| {
                if (predicate(ctx, k, val)) c += 1;
            }
            return c;
        }

        // ---- Range Operations ----

        /// Returns the entry with the smallest key >= the given key, or null.
        pub fn ceiling(self: *const Self, key: K) ?struct { key: K, value: V } {
            const result = self.findIndex(key);
            if (result.found) return .{ .key = self.keys.items[result.index], .value = self.vals.items[result.index] };
            if (result.index < self.keys.items.len) return .{ .key = self.keys.items[result.index], .value = self.vals.items[result.index] };
            return null;
        }

        /// Returns the entry with the largest key <= the given key, or null.
        pub fn floor(self: *const Self, key: K) ?struct { key: K, value: V } {
            const result = self.findIndex(key);
            if (result.found) return .{ .key = self.keys.items[result.index], .value = self.vals.items[result.index] };
            if (result.index > 0) return .{ .key = self.keys.items[result.index - 1], .value = self.vals.items[result.index - 1] };
            return null;
        }

        /// Returns keys in [from, to] inclusive as a slice view.
        pub fn rangeKeys(self: *const Self, from: K, to: K) []const K {
            const lo = self.findIndex(from).index;
            var hi = lo;
            while (hi < self.keys.items.len) {
                if (orderFn(self.keys.items[hi], to) == .gt) break;
                hi += 1;
            }
            if (lo >= hi) return self.keys.items[0..0];
            return self.keys.items[lo..hi];
        }

        // ---- Formatting ----

        /// Formats as "{k1=v1, k2=v2}" in sorted key order.
        pub fn format(self: *const Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.writeAll("{");
            for (self.keys.items, self.vals.items, 0..) |k, v, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{any}", .{k});
                try writer.writeAll("=");
                try writer.print("{any}", .{v});
            }
            try writer.writeAll("}");
        }

        // ---- Fluent API ----

        pub fn withKeyValue(self: *Self, key: K, value: V) Allocator.Error!*Self {
            _ = try self.put(key, value);
            return self;
        }

        pub fn withoutKey(self: *Self, key: K) *Self {
            _ = self.remove(key);
            return self;
        }

        // ---- Data pump (bulk import) ----

        /// Effective error set of every pump entry point on this map.
        pub const BulkError = (error{ NotSorted, DuplicateKey } || Allocator.Error);

        /// Streaming builder for a fresh `TreeMap` from ascending key/value
        /// input. This is the canonical home of the ordered-pump algorithm;
        /// `fromSorted` is a thin wrapper over it.
        ///
        /// Each `put` validates that the new key is strictly greater than the
        /// previous one under `keyOrder` (the collection's own comparator —
        /// IEEE-754 total order for floats, `false < true` for bool), then
        /// `appendAssumeCapacity`-style appends — no per-element binary-search or
        /// array shift. The result is byte-identical to the same pairs inserted
        /// one-by-one with sorted `put`, but built in O(n).
        ///
        /// Lifecycle: `init` → `put`* / `putAll` → `create`. After any error the
        /// Sink is POISONED: every subsequent `put`/`create` returns
        /// `error.PumpPoisoned`, and the partially-built map is freed. `create`
        /// is once-only (a second call returns `error.PumpPoisoned`). If the
        /// Sink is dropped without `create` after a successful run, call
        /// `deinit` to free the in-progress map.
        pub const Sink = struct {
            map: Self,
            last_key: ?K = null,
            policy: DupPolicy,
            poisoned: bool = false,
            done: bool = false,

            pub const Error = (BulkError || error{PumpPoisoned});

            pub fn init(allocator: Allocator, policy: DupPolicy) Sink {
                return .{ .map = Self.init(allocator), .policy = policy };
            }

            /// Frees the in-progress map. Only needed if `create` was never
            /// called (a successful `create` moves ownership to the caller).
            pub fn deinit(self: *Sink) void {
                self.map.deinit();
            }

            fn poison(self: *Sink) void {
                self.poisoned = true;
                self.map.deinit();
                self.map = Self.init(self.map.allocator);
            }

            /// Appends one ascending key/value pair. Returns `error.NotSorted`
            /// if `key` is not strictly greater than the previous key (and
            /// `error.DuplicateKey` on an equal key when `policy == .err`).
            pub fn put(self: *Sink, key: K, value: V) Error!void {
                if (self.poisoned or self.done) return error.PumpPoisoned;
                if (self.last_key) |prev| {
                    switch (orderFn(prev, key)) {
                        .lt => {},
                        .eq => {
                            if (self.policy == .err) {
                                self.poison();
                                return error.DuplicateKey;
                            }
                            // .ignore: keep first, skip this duplicate.
                            return;
                        },
                        .gt => {
                            self.poison();
                            return error.NotSorted;
                        },
                    }
                }
                self.map.keys.ensureUnusedCapacity(self.map.allocator, 1) catch |e| {
                    self.poison();
                    return e;
                };
                self.map.vals.ensureUnusedCapacity(self.map.allocator, 1) catch |e| {
                    self.poison();
                    return e;
                };
                self.map.keys.appendAssumeCapacity(key);
                self.map.vals.appendAssumeCapacity(value);
                self.last_key = key;
            }

            /// Convenience: `put` every pair from parallel `keys`/`vals` slices.
            pub fn putAll(self: *Sink, keys: []const K, vals: []const V) Error!void {
                std.debug.assert(keys.len == vals.len);
                for (keys, vals) |k, v| try self.put(k, v);
            }

            /// Finishes the build and returns the fresh map by value (move).
            /// Once-only: a second call (or a call after an error) returns
            /// `error.PumpPoisoned`.
            pub fn create(self: *Sink) Error!Self {
                if (self.poisoned or self.done) return error.PumpPoisoned;
                self.done = true;
                const out = self.map;
                self.map = Self.init(self.map.allocator);
                return out;
            }
        };

        /// Bulk-loads a fresh `TreeMap` from presorted (strictly ascending)
        /// parallel key/value slices in O(n): reserve once, then two bulk
        /// appends, validating order with the map's own `keyOrder`.
        ///
        /// `keys[i]` must be strictly less than `keys[i+1]`. A descending pair is
        /// `error.NotSorted`; an equal pair is `error.DuplicateKey` when
        /// `policy == .err`, else the first of the run is kept. On any error
        /// nothing leaks (the partial map is freed) and no map is returned.
        pub fn fromSorted(
            allocator: Allocator,
            keys: []const K,
            vals: []const V,
            policy: DupPolicy,
        ) BulkError!Self {
            std.debug.assert(keys.len == vals.len);
            var sink = Sink.init(allocator, policy);
            // Reserve up front so the common no-duplicate path never reallocates.
            sink.map.ensureUnusedCapacity(keys.len) catch |e| {
                sink.deinit();
                return e;
            };
            sink.putAll(keys, vals) catch |e| switch (e) {
                error.PumpPoisoned => unreachable, // fresh sink, single pass
                else => |narrow| return narrow,
            };
            return sink.create() catch unreachable;
        }

        // ---- Equality ----

        pub fn eql(self: *const Self, other: *const Self) bool {
            if (self.keys.items.len != other.keys.items.len) return false;
            for (self.keys.items, self.vals.items, other.keys.items, other.vals.items) |k1, v1, k2, v2| {
                if (!memberEql(K, k1, k2)) return false;
                if (!memberEql(V, v1, v2)) return false;
            }
            return true;
        }
    };
}
