// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

const std = @import("std");
const Allocator = std.mem.Allocator;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const pump = @import("../pump.zig");
const DupPolicy = pump.DupPolicy;

/// Bit-pattern equality for any value type. For floats this compares raw bits
/// (so `+0`/`-0` differ and bit-identical NaNs match), matching the original
/// per-type wrappers; for non-floats it is plain `==`.
fn bitsEqual(comptime T: type, a: T, b: T) bool {
    if (@typeInfo(T) == .float) {
        const Bits = std.meta.Int(.unsigned, @bitSizeOf(T));
        return @as(Bits, @bitCast(a)) == @as(Bits, @bitCast(b));
    }
    return a == b;
}

/// Bidirectional hash map from `K` keys to `V` values.
///
/// Maintains two internal OpenHashMaps (forward and reverse) so that both
/// key-to-value and value-to-key lookups are O(1). Every mutation keeps both
/// maps in sync.
pub fn HashBiMap(comptime K: type, comptime V: type) type {
    return struct {
        forward: OpenHashMap(K, V),
        reverse: OpenHashMap(V, K),
        allocator: Allocator,

        const Self = @This();

        // ---- Construction / Destruction ----

        /// Infallible: both backing tables allocate lazily on first `put`.
        pub fn init(allocator: Allocator) Self {
            return .{
                .forward = OpenHashMap(K, V).init(allocator),
                .reverse = OpenHashMap(V, K).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.forward.deinit();
            self.reverse.deinit();
        }

        // ---- Data pump (bulk import) ----

        /// Effective error set of every pump entry point on this bimap. A BiMap
        /// must stay a bijection, so BOTH a duplicate key and a duplicate value
        /// are errors.
        pub const BulkError = (error{ DuplicateKey, DuplicateValue } || Allocator.Error);

        /// Bulk-loads a fresh `HashBiMap` from parallel key/value slices,
        /// pre-sizing both internal tables in one allocation each, then inserting
        /// the bijection. O(n). Input order is irrelevant (hash).
        ///
        /// Conflict handling, since a bimap must remain a bijection:
        ///   * a duplicate KEY → `error.DuplicateKey`;
        ///   * a duplicate VALUE → `error.DuplicateValue`.
        /// The duplicate policy is accepted for API symmetry but intentionally
        /// ignored: BiMap duplicate keys/values are always errors, even for an
        /// identical `(key, value)` replay. On any error nothing leaks and no
        /// table is left half-updated.
        pub fn bulkLoad(
            allocator: Allocator,
            keys: []const K,
            vals: []const V,
            policy: DupPolicy,
        ) BulkError!Self {
            std.debug.assert(keys.len == vals.len);
            var self = init(allocator);
            errdefer self.deinit();
            try self.forward.ensureCapacity(keys.len);
            try self.reverse.ensureCapacity(keys.len);
            _ = policy;
            for (keys, vals) |k, v| {
                const dup_key = self.forward.containsKey(k);
                const dup_val = self.reverse.containsKey(v);
                if (dup_key or dup_val) {
                    // Report the key conflict first to mirror put-loop order.
                    return if (dup_key) error.DuplicateKey else error.DuplicateValue;
                }
                // Both sides are free — insert into both, keeping them in lock-step.
                _ = try self.forward.put(k, v);
                _ = try self.reverse.put(v, k);
            }
            return self;
        }

        // ---- Core Operations ----

        /// Inserts a bidirectional key-value mapping.
        /// If the key was already mapped to an old value, the old value is removed
        /// from the reverse map before inserting the new mapping.
        /// If the value was already mapped to an old key, the old key is removed
        /// from the forward map before inserting the new mapping.
        /// Returns the old value previously associated with the key, or null.
        pub fn put(self: *Self, key: K, value: V) Allocator.Error!?V {
            try self.forward.ensureCapacity(1);
            try self.reverse.ensureCapacity(1);

            // If this value already maps to a different key, remove the old key from forward.
            if (self.reverse.get(value)) |old_key| {
                if (!bitsEqual(K, old_key, key)) {
                    _ = self.forward.remove(old_key);
                }
            }
            // If this key already maps to an old value, remove that old value from reverse.
            const old_value = self.forward.get(key);
            if (old_value) |ov| {
                _ = self.reverse.remove(ov);
            }
            _ = try self.forward.put(key, value);
            _ = try self.reverse.put(value, key);
            return old_value;
        }

        /// Returns the value for the given key (forward lookup), or null.
        pub fn get(self: *const Self, key: K) ?V {
            return self.forward.get(key);
        }

        /// Returns the key for the given value (reverse lookup), or null.
        pub fn getKey(self: *const Self, value: V) ?K {
            return self.reverse.get(value);
        }

        /// Removes the mapping for the given key and its reverse. Returns the old value if present.
        pub fn remove(self: *Self, key: K) ?V {
            const old_value = self.forward.remove(key);
            if (old_value) |ov| {
                _ = self.reverse.remove(ov);
            }
            return old_value;
        }

        /// Removes the mapping for the given value and its forward key. Returns the old key if present.
        pub fn removeValue(self: *Self, value: V) ?K {
            const old_key = self.reverse.remove(value);
            if (old_key) |ok| {
                _ = self.forward.remove(ok);
            }
            return old_key;
        }

        pub fn containsKey(self: *const Self, key: K) bool {
            return self.forward.containsKey(key);
        }

        pub fn containsValue(self: *const Self, value: V) bool {
            return self.reverse.containsKey(value);
        }

        pub fn len(self: *const Self) usize {
            return self.forward.len();
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.forward.isEmpty();
        }

        pub fn clear(self: *Self) void {
            self.forward.clear();
            self.reverse.clear();
        }

        // ---- Fallible capacity reservation ----

        /// Ensures both the forward and reverse maps can hold `additional`
        /// more entries without triggering a rehash. Returns
        /// `error.OutOfMemory` if the allocator fails.
        pub fn ensureUnusedCapacity(self: *Self, additional: usize) Allocator.Error!void {
            try self.forward.ensureCapacity(additional);
            try self.reverse.ensureCapacity(additional);
        }

        /// Ensures both internal maps' total capacity covers at least
        /// `new_capacity` entries.
        pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) Allocator.Error!void {
            const cur = self.forward.len();
            if (new_capacity <= cur) return;
            try self.ensureUnusedCapacity(new_capacity - cur);
        }

        // ---- Iteration ----

        /// An entry yielded by `Iterator` — key and value by value.
        pub const IterEntry = struct { key: K, value: V };

        const InnerEntry = @import("../hash_table.zig").MapEntry(K, V);

        /// Pull-based iterator yielding `{ key, value }` entries in arbitrary
        /// (hash-table) order, walking the forward map. Non-allocating: walks the
        /// inner table's occupied slots directly. The iterator borrows the bimap;
        /// do not mutate while iterating.
        pub const Iterator = struct {
            entries: []const InnerEntry,
            index: usize = 0,

            pub fn next(self: *Iterator) ?IterEntry {
                while (self.index < self.entries.len) {
                    const e = self.entries[self.index];
                    self.index += 1;
                    if (e.occupied) return .{ .key = e.key, .value = e.value };
                }
                return null;
            }
        };

        /// Returns a pull-based iterator over `{ key, value }` (forward) entries
        /// in arbitrary order. Non-allocating.
        ///
        /// No `mutIterator()` is provided for bi-maps (deliberate exclusion):
        /// unlike a plain map, a bi-map value IS a key in the inverse index, so
        /// the value is identity on the reverse side. Mutating a value in place
        /// would leave the inverse index pointing at a stale key and break the
        /// bijection. Use `put` (which maintains both directions) instead.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .entries = self.forward.entries };
        }

        pub fn forEachKey(self: *const Self, context: anytype, comptime f: fn (@TypeOf(context), K) void) void {
            self.forward.forEachKey(context, f);
        }

        pub fn forEachValue(self: *const Self, context: anytype, comptime f: fn (@TypeOf(context), V) void) void {
            self.forward.forEachValue(context, f);
        }

        // ---- Inverse ----

        /// Returns a new BiMap with keys and values swapped (value->key becomes key->value).
        /// The caller owns the returned map and must call deinit() on it.
        pub fn inverse(self: *const Self) Allocator.Error!HashBiMap(V, K) {
            var result = HashBiMap(V, K).init(self.allocator);
            errdefer result.deinit();
            for (0..self.forward.capacity) |i| {
                if (self.forward.entries[i].occupied) {
                    _ = try result.put(self.forward.entries[i].value, self.forward.entries[i].key);
                }
            }
            return result;
        }

        // ---- Formatting ----

        pub fn format(self: *const Self, writer: anytype) !void {
            try writer.writeAll("{");
            var first = true;
            for (0..self.forward.capacity) |i| {
                if (self.forward.entries[i].occupied) {
                    if (!first) try writer.writeAll(", ");
                    try writer.print("{any}", .{self.forward.entries[i].key});
                    try writer.writeAll("<->");
                    try writer.print("{any}", .{self.forward.entries[i].value});
                    first = false;
                }
            }
            try writer.writeAll("}");
        }

        // ---- Equality ----

        pub fn eql(self: *const Self, other: *const Self) bool {
            if (self.len() != other.len()) return false;
            for (0..self.forward.capacity) |i| {
                if (self.forward.entries[i].occupied) {
                    const other_val = other.get(self.forward.entries[i].key) orelse return false;
                    if (!bitsEqual(V, self.forward.entries[i].value, other_val)) return false;
                }
            }
            return true;
        }
    };
}
