// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const immutable = @import("../immutable/immutable.zig");

/// Lowercase file-token for a primitive type, used to build the immutable
/// module name (`immutable_<k>_<v>_hash_map`). Matches the project's filename
/// convention where `char` is backed by `u21`.
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
        else => @compileError("unsupported hash map type: " ++ @typeName(T)),
    };
}

/// PascalCase type-token for a primitive type, used to build the immutable
/// type name (`Immutable<K><V>HashMap`).
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

/// True for the six arithmetic value types that expose `sumOfValues` /
/// `addToValue`. `bool` and `char` (u21) intentionally do not.
fn isNumericValue(comptime V: type) bool {
    return V == i8 or V == i16 or V == i32 or V == i64 or V == f32 or V == f64;
}

/// The per-(K,V) immutable type that `toImmutable` produces. Selected from the
/// immutable aggregator by the project's naming convention (immutable remains
/// per-type this round).
fn ImmutableType(comptime K: type, comptime V: type) type {
    const module = @field(immutable, "immutable_" ++ typeToken(K) ++ "_" ++ typeToken(V) ++ "_hash_map");
    return @field(module, "Immutable" ++ typePascal(K) ++ typePascal(V) ++ "HashMap");
}

/// Hash map from `K` keys to `V` values.
///
/// Custom open-addressing with linear probing and Robin Hood backward-shift deletion.
/// Supports separate allocators for keys, values, and index buckets via AllocatorConfig.
pub fn HashMap(comptime K: type, comptime V: type) type {
    return struct {
        inner: OpenHashMap(K, V),
        config: AllocatorConfig,

        const Self = @This();

        // ---- Construction / Destruction ----

        pub fn init(allocator: Allocator) Self {
            return initWithConfig(AllocatorConfig.init(allocator));
        }

        /// Create with pre-allocated capacity.
        pub fn initWithCapacity(allocator: Allocator, capacity: usize) Self {
            return .{
                .inner = OpenHashMap(K, V).initCapacity(allocator, capacity) catch @panic("out of memory"),
                .config = AllocatorConfig.init(allocator),
            };
        }

        /// Create with fine-grained allocator control.
        pub fn initWithConfig(config: AllocatorConfig) Self {
            return .{
                .inner = OpenHashMap(K, V).init(
                    config.keysAllocator(),
                    config.valuesAllocator(),
                    config.indexAllocator(),
                ) catch @panic("out of memory"),
                .config = config,
            };
        }

        pub fn deinit(self: *Self) void {
            self.inner.deinit();
        }

        // ---- Core Operations ----

        /// Inserts a key-value pair. Returns the old value if the key was already present.
        pub fn put(self: *Self, key: K, value: V) ?V {
            return self.inner.put(key, value) catch @panic("out of memory");
        }

        /// Returns the value for the key, or null.
        pub fn get(self: *const Self, key: K) ?V {
            return self.inner.get(key);
        }

        /// Returns the value for the key, or the default.
        pub fn getOrDefault(self: *const Self, key: K, default_value: V) V {
            return self.get(key) orelse default_value;
        }

        /// Removes the key. Returns the old value if present.
        pub fn remove(self: *Self, key: K) ?V {
            return self.inner.remove(key);
        }

        pub fn containsKey(self: *const Self, key: K) bool {
            return self.inner.containsKey(key);
        }

        pub fn containsValue(self: *const Self, value: V) bool {
            return self.inner.containsValue(value);
        }

        // ---- Entry API ----

        /// Entry provides atomic check-and-modify operations for a single key.
        pub const Entry = struct {
            map_ptr: *Self,
            key: K,

            /// Inserts the default value if the key is absent. Returns the current value.
            pub fn orInsert(self: Entry, default_value: V) V {
                if (self.map_ptr.get(self.key)) |existing| return existing;
                _ = self.map_ptr.put(self.key, default_value);
                return default_value;
            }

            /// Inserts the value from the function if the key is absent.
            pub fn orInsertWith(self: Entry, f: *const fn () V) V {
                if (self.map_ptr.get(self.key)) |existing| return existing;
                const val = f();
                _ = self.map_ptr.put(self.key, val);
                return val;
            }

            /// Calls the function on a pointer to the value if the key is present.
            pub fn andModify(self: Entry, f: *const fn (*V) void) Entry {
                if (self.map_ptr.inner.getPtr(self.key)) |val_ptr| {
                    f(val_ptr);
                }
                return self;
            }
        };

        pub fn getEntry(self: *Self, key: K) Entry {
            return .{ .map_ptr = self, .key = key };
        }

        pub fn len(self: *const Self) usize {
            return self.inner.len();
        }

        pub fn size(self: *const Self) usize {
            return self.inner.len();
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.inner.isEmpty();
        }

        pub fn clear(self: *Self) void {
            self.inner.clear();
        }

        // ---- Fallible capacity reservation ----

        /// Ensures that `additional` more entries can be put without triggering
        /// a rehash. Returns `error.OutOfMemory` if the allocator fails.
        pub fn ensureUnusedCapacity(self: *Self, additional: usize) Allocator.Error!void {
            return self.inner.ensureCapacity(additional);
        }

        /// Ensures the map's total capacity can fit at least `new_capacity`
        /// entries under the load factor without a rehash.
        pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) Allocator.Error!void {
            if (new_capacity <= self.inner.len()) return;
            return self.inner.ensureCapacity(new_capacity - self.inner.len());
        }

        // ---- Iteration ----

        pub fn forEach(self: *const Self, f: *const fn (K, V) void) void {
            self.inner.forEach(f);
        }

        pub fn forEachKey(self: *const Self, f: *const fn (K) void) void {
            self.inner.forEachKey(f);
        }

        pub fn forEachValue(self: *const Self, f: *const fn (V) void) void {
            self.inner.forEachValue(f);
        }

        // ---- Functional Operations ----

        pub fn select(self: *const Self, predicate: *const fn (K, V) bool) Self {
            var result = init(self.config.base);
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied) {
                    if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                        _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
                }
            }
            return result;
        }

        pub fn reject(self: *const Self, predicate: *const fn (K, V) bool) Self {
            var result = init(self.config.base);
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied) {
                    if (!predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                        _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
                }
            }
            return result;
        }

        pub fn detect(self: *const Self, predicate: *const fn (K, V) bool) ?struct { key: K, value: V } {
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied) {
                    if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                        return .{ .key = self.inner.entries[i].key, .value = self.inner.entries[i].value };
                }
            }
            return null;
        }

        pub fn anySatisfy(self: *const Self, predicate: *const fn (K, V) bool) bool {
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return true;
            }
            return false;
        }

        pub fn allSatisfy(self: *const Self, predicate: *const fn (K, V) bool) bool {
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied and !predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
            }
            return true;
        }

        pub fn noneSatisfy(self: *const Self, predicate: *const fn (K, V) bool) bool {
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
            }
            return true;
        }

        pub fn count(self: *const Self, predicate: *const fn (K, V) bool) usize {
            var c: usize = 0;
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) c += 1;
            }
            return c;
        }

        pub fn injectInto(self: *const Self, initial: V, f: *const fn (V, K, V) V) V {
            var acc = initial;
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied) acc = f(acc, self.inner.entries[i].key, self.inner.entries[i].value);
            }
            return acc;
        }

        // ---- Key/Value Collection ----

        pub fn keysToSlice(self: *const Self, allocator: Allocator) []K {
            return self.inner.keysToSlice(allocator) catch @panic("out of memory");
        }

        pub fn valuesToSlice(self: *const Self, allocator: Allocator) []V {
            return self.inner.valuesToSlice(allocator) catch @panic("out of memory");
        }

        // ---- Numeric Value Operations ----
        // Only present for arithmetic value types (i8/i16/i32/i64/f32/f64).
        // `bool` and `char` value maps do not expose these, matching the
        // original per-type wrappers.

        // `pub const name = if (cond) <fn> else {}` keeps these decls present
        // only for numeric value types: for `bool`/`char` they collapse to
        // `void`, which is not callable — matching the original per-type
        // wrappers that simply omitted them. Zig 0.15 removed `usingnamespace`,
        // so this is the supported way to gate a method by comptime condition.

        /// Sum of all values. `i64` accumulator for integer values (wrapping
        /// avoided by widening), the float type itself for float values.
        pub const sumOfValues = if (isNumericValue(V)) struct {
            fn f(self: *const Self) if (@typeInfo(V) == .float) V else i64 {
                if (@typeInfo(V) == .float) {
                    var total: V = 0;
                    for (0..self.inner.capacity) |i| {
                        if (self.inner.entries[i].occupied) total += self.inner.entries[i].value;
                    }
                    return total;
                } else {
                    var total: i64 = 0;
                    for (0..self.inner.capacity) |i| {
                        if (self.inner.entries[i].occupied) total += @as(i64, @intCast(self.inner.entries[i].value));
                    }
                    return total;
                }
            }
        }.f else {};

        /// Adds `delta` to the value for `key` (inserting `delta` if absent).
        /// Integer values wrap on overflow per the spec; float values add.
        pub const addToValue = if (isNumericValue(V)) struct {
            fn f(self: *Self, key: K, delta: V) V {
                if (self.inner.getPtr(key)) |val_ptr| {
                    if (@typeInfo(V) == .float) {
                        val_ptr.* += delta;
                    } else {
                        val_ptr.* +%= delta; // wrapping per spec Integer overflow contract
                    }
                    return val_ptr.*;
                } else {
                    _ = self.put(key, delta);
                    return delta;
                }
            }
        }.f else {};

        // ---- Conversion ----

        pub fn toImmutable(self: *const Self) ImmutableType(K, V) {
            return ImmutableType(K, V).fromMutable(self.config.base, self);
        }

        // ---- Fluent API ----

        pub fn withKeyValue(self: *Self, key: K, value: V) *Self {
            _ = self.put(key, value);
            return self;
        }

        pub fn withoutKey(self: *Self, key: K) *Self {
            _ = self.remove(key);
            return self;
        }

        pub fn withoutAllKeys(self: *Self, keys: []const K) *Self {
            for (keys) |key| _ = self.remove(key);
            return self;
        }

        // ---- Mutation Helpers ----

        pub fn updateValue(self: *Self, key: K, initial: V, f: *const fn (V) V) V {
            const current = self.get(key) orelse initial;
            const new_value = f(current);
            _ = self.put(key, new_value);
            return new_value;
        }

        // ---- Formatting ----

        pub fn format(self: *const Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.writeAll("{");
            var first = true;
            for (0..self.inner.capacity) |i| {
                if (self.inner.entries[i].occupied) {
                    if (!first) try writer.writeAll(", ");
                    try writer.print("{any}", .{self.inner.entries[i].key});
                    try writer.writeAll("=");
                    try writer.print("{any}", .{self.inner.entries[i].value});
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
