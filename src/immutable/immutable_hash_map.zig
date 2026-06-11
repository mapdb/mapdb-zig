// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Generic immutable hash map. Single source for the 64 `Immutable<K><V>HashMap`
//! per-type wrappers that previously lived one-file-per-(K, V).
//!
//! Backed by a snapshot of the production `OpenHashMap(K, V)`. All operations
//! are read-only. The wrapper delegates hashing / key-equality to
//! `OpenHashMap` (which is already NaN/±0-correct for float keys); the only
//! value-type-dependent logic here is `eql`, which compares float *values* by
//! bit pattern so that identical-bit NaNs compare equal and +0.0 / -0.0 differ.

const std = @import("std");
const Allocator = std.mem.Allocator;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const hashmap = @import("../hashmap/hashmap.zig");

/// PascalCase type-token for a primitive type, used to resolve the mutable
/// `<K><V>HashMap` source type from the hashmap aggregator.
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
        else => @compileError("unsupported hash map type: " ++ @typeName(T)),
    };
}

/// The production mutable `HashMap(K, V)` named alias (e.g. `I32I32HashMap`).
fn MutableType(comptime K: type, comptime V: type) type {
    return @field(hashmap, typePascal(K) ++ typePascal(V) ++ "HashMap");
}

/// Immutable hash map from `K` keys to `V` values.
///
/// Backed by a snapshot of the internal hash map. All operations are read-only.
pub fn ImmutableHashMap(comptime K: type, comptime V: type) type {
    return struct {
        inner: OpenHashMap(K, V),
        allocator: Allocator,

        const Self = @This();
        const Mutable = MutableType(K, V);

        pub fn fromMutable(allocator: Allocator, mutable: *const Mutable) Self {
            var inner = OpenHashMap(K, V).init(allocator, allocator, allocator) catch @panic("out of memory");
            for (0..mutable.inner.capacity) |i| {
                if (mutable.inner.entries[i].occupied) {
                    _ = inner.put(mutable.inner.entries[i].key, mutable.inner.entries[i].value) catch @panic("out of memory");
                }
            }
            return .{ .inner = inner, .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            self.inner.deinit();
        }

        pub fn get(self: *const Self, key: K) ?V {
            return self.inner.get(key);
        }

        pub fn getOrDefault(self: *const Self, key: K, default_value: V) V {
            return self.get(key) orelse default_value;
        }

        pub fn containsKey(self: *const Self, key: K) bool {
            return self.inner.containsKey(key);
        }

        pub fn containsValue(self: *const Self, value: V) bool {
            return self.inner.containsValue(value);
        }

        pub fn len(self: *const Self) usize {
            return self.inner.len();
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.inner.isEmpty();
        }

        /// An entry yielded by `Iterator` — key and value by value.
        pub const IterEntry = struct { key: K, value: V };

        const InnerEntry = @import("../hash_table.zig").MapEntry(K, V);

        /// Pull-based iterator yielding `{ key, value }` entries in arbitrary
        /// (hash-table) order. Non-allocating: walks the inner snapshot table's
        /// occupied slots directly.
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

        /// Returns a pull-based iterator over `{ key, value }` entries in
        /// arbitrary order. Non-allocating.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .entries = self.inner.entries };
        }

        pub fn toMutable(self: *const Self) Mutable {
            var mutable = Mutable.init(self.allocator);
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied) {
                    _ = mutable.put(self.inner.entries[i].key, self.inner.entries[i].value);
                }
            }
            return mutable;
        }

        pub fn eql(self: *const Self, other: *const Self) bool {
            if (self.len() != other.len()) return false;
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied) {
                    const other_val = other.get(self.inner.entries[i].key) orelse return false;
                    if (@typeInfo(V) == .float) {
                        const Bits = std.meta.Int(.unsigned, @bitSizeOf(V));
                        if (!(@as(Bits, @bitCast(self.inner.entries[i].value)) == @as(Bits, @bitCast(other_val)))) return false;
                    } else {
                        if (!(self.inner.entries[i].value == other_val)) return false;
                    }
                }
            }
            return true;
        }
    };
}
