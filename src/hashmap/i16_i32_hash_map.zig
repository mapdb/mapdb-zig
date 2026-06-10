// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const ImmutableI16I32HashMap = @import("../immutable/immutable_i16_i32_hash_map.zig").ImmutableI16I32HashMap;

/// Hash map from `i16` keys to `i32` values.
///
/// Custom open-addressing with linear probing and Robin Hood backward-shift deletion.
/// Supports separate allocators for keys, values, and index buckets via AllocatorConfig.
pub const I16I32HashMap = struct {
    inner: OpenHashMap(i16, i32),
    config: AllocatorConfig,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) I16I32HashMap {
        return initWithConfig(AllocatorConfig.init(allocator));
    }

    /// Create with pre-allocated capacity.
    pub fn initWithCapacity(allocator: Allocator, capacity: usize) I16I32HashMap {
        return .{
            .inner = OpenHashMap(i16, i32).initCapacity(allocator, capacity) catch @panic("out of memory"),
            .config = AllocatorConfig.init(allocator),
        };
    }

    /// Create with fine-grained allocator control.
    pub fn initWithConfig(config: AllocatorConfig) I16I32HashMap {
        return .{
            .inner = OpenHashMap(i16, i32).init(
                config.keysAllocator(),
                config.valuesAllocator(),
                config.indexAllocator(),
            ) catch @panic("out of memory"),
            .config = config,
        };
    }

    pub fn deinit(self: *I16I32HashMap) void {
        self.inner.deinit();
    }

    // ---- Core Operations ----

    /// Inserts a key-value pair. Returns the old value if the key was already present.
    pub fn put(self: *I16I32HashMap, key: i16, value: i32) ?i32 {
        return self.inner.put(key, value) catch @panic("out of memory");
    }

    /// Returns the value for the key, or null.
    pub fn get(self: *const I16I32HashMap, key: i16) ?i32 {
        return self.inner.get(key);
    }

    /// Returns the value for the key, or the default.
    pub fn getOrDefault(self: *const I16I32HashMap, key: i16, default_value: i32) i32 {
        return self.get(key) orelse default_value;
    }

    /// Removes the key. Returns the old value if present.
    pub fn remove(self: *I16I32HashMap, key: i16) ?i32 {
        return self.inner.remove(key);
    }

    pub fn containsKey(self: *const I16I32HashMap, key: i16) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const I16I32HashMap, value: i32) bool {
        return self.inner.containsValue(value);
    }

    // ---- Entry API ----

    /// Entry provides atomic check-and-modify operations for a single key.
    pub const Entry = struct {
        map_ptr: *I16I32HashMap,
        key: i16,

        /// Inserts the default value if the key is absent. Returns the current value.
        pub fn orInsert(self: Entry, default_value: i32) i32 {
            if (self.map_ptr.get(self.key)) |existing| return existing;
            _ = self.map_ptr.put(self.key, default_value);
            return default_value;
        }

        /// Inserts the value from the function if the key is absent.
        pub fn orInsertWith(self: Entry, f: *const fn () i32) i32 {
            if (self.map_ptr.get(self.key)) |existing| return existing;
            const val = f();
            _ = self.map_ptr.put(self.key, val);
            return val;
        }

        /// Calls the function on a pointer to the value if the key is present.
        pub fn andModify(self: Entry, f: *const fn (*i32) void) Entry {
            if (self.map_ptr.inner.getPtr(self.key)) |val_ptr| {
                f(val_ptr);
            }
            return self;
        }
    };

    pub fn getEntry(self: *I16I32HashMap, key: i16) Entry {
        return .{ .map_ptr = self, .key = key };
    }

    pub fn len(self: *const I16I32HashMap) usize {
        return self.inner.len();
    }

    pub fn size(self: *const I16I32HashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const I16I32HashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn clear(self: *I16I32HashMap) void {
        self.inner.clear();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more entries can be put without triggering
    /// a rehash. Returns `error.OutOfMemory` if the allocator fails.
    pub fn ensureUnusedCapacity(self: *I16I32HashMap, additional: usize) Allocator.Error!void {
        return self.inner.ensureCapacity(additional);
    }

    /// Ensures the map's total capacity can fit at least `new_capacity`
    /// entries under the load factor without a rehash.
    pub fn ensureTotalCapacity(self: *I16I32HashMap, new_capacity: usize) Allocator.Error!void {
        if (new_capacity <= self.inner.len()) return;
        return self.inner.ensureCapacity(new_capacity - self.inner.len());
    }

    // ---- Iteration ----

    pub fn forEach(self: *const I16I32HashMap, f: *const fn (i16, i32) void) void {
        self.inner.forEach(f);
    }

    pub fn forEachKey(self: *const I16I32HashMap, f: *const fn (i16) void) void {
        self.inner.forEachKey(f);
    }

    pub fn forEachValue(self: *const I16I32HashMap, f: *const fn (i32) void) void {
        self.inner.forEachValue(f);
    }

    // ---- Functional Operations ----

    pub fn select(self: *const I16I32HashMap, predicate: *const fn (i16, i32) bool) I16I32HashMap {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return result;
    }

    pub fn reject(self: *const I16I32HashMap, predicate: *const fn (i16, i32) bool) I16I32HashMap {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (!predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return result;
    }

    pub fn detect(self: *const I16I32HashMap, predicate: *const fn (i16, i32) bool) ?struct { key: i16, value: i32 } {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    return .{ .key = self.inner.entries[i].key, .value = self.inner.entries[i].value };
            }
        }
        return null;
    }

    pub fn anySatisfy(self: *const I16I32HashMap, predicate: *const fn (i16, i32) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const I16I32HashMap, predicate: *const fn (i16, i32) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and !predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const I16I32HashMap, predicate: *const fn (i16, i32) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
        }
        return true;
    }

    pub fn count(self: *const I16I32HashMap, predicate: *const fn (i16, i32) bool) usize {
        var c: usize = 0;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) c += 1;
        }
        return c;
    }

    pub fn injectInto(self: *const I16I32HashMap, initial: i32, f: *const fn (i32, i16, i32) i32) i32 {
        var acc = initial;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) acc = f(acc, self.inner.entries[i].key, self.inner.entries[i].value);
        }
        return acc;
    }

    // ---- Key/Value Collection ----

    pub fn keysToSlice(self: *const I16I32HashMap, allocator: Allocator) []i16 {
        return self.inner.keysToSlice(allocator) catch @panic("out of memory");
    }

    pub fn valuesToSlice(self: *const I16I32HashMap, allocator: Allocator) []i32 {
        return self.inner.valuesToSlice(allocator) catch @panic("out of memory");
    }

    // ---- Numeric Value Operations ----

    pub fn sumOfValues(self: *const I16I32HashMap) i64 {
        var total: i64 = 0;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) total += @as(i64, @intCast(self.inner.entries[i].value));
        }
        return total;
    }

    pub fn addToValue(self: *I16I32HashMap, key: i16, delta: i32) i32 {
        if (self.inner.getPtr(key)) |val_ptr| {
            val_ptr.* +%= delta; // wrapping per spec Integer overflow contract
            return val_ptr.*;
        } else {
            _ = self.put(key, delta);
            return delta;
        }
    }

    // ---- Conversion ----

    pub fn toImmutable(self: *const I16I32HashMap) ImmutableI16I32HashMap {
        return ImmutableI16I32HashMap.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    pub fn withKeyValue(self: *I16I32HashMap, key: i16, value: i32) *I16I32HashMap {
        _ = self.put(key, value);
        return self;
    }

    pub fn withoutKey(self: *I16I32HashMap, key: i16) *I16I32HashMap {
        _ = self.remove(key);
        return self;
    }

    pub fn withoutAllKeys(self: *I16I32HashMap, keys: []const i16) *I16I32HashMap {
        for (keys) |key| _ = self.remove(key);
        return self;
    }

    // ---- Mutation Helpers ----

    pub fn updateValue(self: *I16I32HashMap, key: i16, initial: i32, f: *const fn (i32) i32) i32 {
        const current = self.get(key) orelse initial;
        const new_value = f(current);
        _ = self.put(key, new_value);
        return new_value;
    }

    // ---- Formatting ----

    pub fn format(self: *const I16I32HashMap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const I16I32HashMap, other: *const I16I32HashMap) bool {
        if (self.len() != other.len()) return false;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const other_val = other.get(self.inner.entries[i].key) orelse return false;
                if (!(self.inner.entries[i].value == other_val)) return false;
            }
        }
        return true;
    }
};

// ---- Tests ----

test "I16I32HashMap: put and get" {
    var m = I16I32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1);
    _ = m.put(2, 2);
    _ = m.put(3, 3);
    try std.testing.expectEqual(@as(?i32, 1), m.get(1));
    try std.testing.expectEqual(@as(?i32, null), m.get(99));
    try std.testing.expectEqual(@as(usize, 3), m.len());
}

test "I16I32HashMap: put overwrite" {
    var m = I16I32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1);
    const old = m.put(1, 2);
    try std.testing.expectEqual(@as(?i32, 1), old);
    try std.testing.expectEqual(@as(?i32, 2), m.get(1));
}

test "I16I32HashMap: remove" {
    var m = I16I32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1);
    _ = m.put(2, 2);
    const removed = m.remove(1);
    try std.testing.expectEqual(@as(?i32, 1), removed);
    try std.testing.expectEqual(@as(usize, 1), m.len());
    try std.testing.expect(!m.containsKey(1));
}

test "I16I32HashMap: containsKey and containsValue" {
    var m = I16I32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1);
    try std.testing.expect(m.containsKey(1));
    try std.testing.expect(!m.containsKey(99));
    try std.testing.expect(m.containsValue(1));
    try std.testing.expect(!m.containsValue(99));
}

test "I16I32HashMap: getOrDefault" {
    var m = I16I32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1);
    try std.testing.expectEqual(1, m.getOrDefault(1, 3));
    try std.testing.expectEqual(3, m.getOrDefault(99, 3));
}

test "I16I32HashMap: clear" {
    var m = I16I32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1);
    m.clear();
    try std.testing.expect(m.isEmpty());
}

test "I16I32HashMap: select and reject" {
    var m = I16I32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1);
    _ = m.put(2, 2);
    _ = m.put(3, 3);
    var sel = m.select(struct {
        fn f(_: i16, v: i32) bool {
            return v > 1;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expectEqual(@as(usize, 2), sel.len());
    var rej = m.reject(struct {
        fn f(_: i16, v: i32) bool {
            return v > 1;
        }
    }.f);
    defer rej.deinit();
    try std.testing.expectEqual(@as(usize, 1), rej.len());
}

test "I16I32HashMap: anySatisfy allSatisfy noneSatisfy count" {
    var m = I16I32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1);
    _ = m.put(2, 2);
    try std.testing.expect(m.anySatisfy(struct {
        fn f(_: i16, v: i32) bool {
            return v == 2;
        }
    }.f));
    try std.testing.expect(m.noneSatisfy(struct {
        fn f(_: i16, v: i32) bool {
            return v == 99;
        }
    }.f));
    try std.testing.expectEqual(@as(usize, 1), m.count(struct {
        fn f(_: i16, v: i32) bool {
            return v == 1;
        }
    }.f));
}

test "I16I32HashMap: keysToSlice and valuesToSlice" {
    var m = I16I32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1);
    _ = m.put(2, 2);
    const keys = m.keysToSlice(std.testing.allocator);
    defer std.testing.allocator.free(keys);
    try std.testing.expectEqual(@as(usize, 2), keys.len);
    const vals = m.valuesToSlice(std.testing.allocator);
    defer std.testing.allocator.free(vals);
    try std.testing.expectEqual(@as(usize, 2), vals.len);
}

test "I16I32HashMap: sumOfValues" {
    var m = I16I32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1);
    _ = m.put(2, 2);
    const s = m.sumOfValues();
    try std.testing.expect(s > 0);
}

test "I16I32HashMap: addToValue" {
    var m = I16I32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.addToValue(1, 1);
    _ = m.addToValue(1, 2);
    // Value should be sum of the two adds
    try std.testing.expect(m.get(1) != null);
}

test "I16I32HashMap: toImmutable" {
    var m = I16I32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1);
    _ = m.put(2, 2);
    var im = m.toImmutable();
    defer im.deinit();
    try std.testing.expectEqual(@as(usize, 2), im.len());
    _ = m.put(3, 3);
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "I16I32HashMap: fluent withKeyValue/withoutKey" {
    var m = I16I32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.withKeyValue(1, 1).withKeyValue(2, 2);
    try std.testing.expectEqual(@as(usize, 2), m.len());
    _ = m.withoutKey(1);
    try std.testing.expectEqual(@as(usize, 1), m.len());
}

test "I16I32HashMap: eql" {
    var m1 = I16I32HashMap.init(std.testing.allocator);
    defer m1.deinit();
    _ = m1.put(1, 1);
    _ = m1.put(2, 2);
    var m2 = I16I32HashMap.init(std.testing.allocator);
    defer m2.deinit();
    _ = m2.put(2, 2);
    _ = m2.put(1, 1);
    try std.testing.expect(m1.eql(&m2));
}

test "I16I32HashMap: resize" {
    var m = I16I32HashMap.init(std.testing.allocator);
    defer m.deinit();
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        _ = m.put(@as(i16, @intCast(i)), @as(i32, @intCast(i)));
    }
    try std.testing.expect(m.len() > 0);
}

test "I16I32HashMap: entry orInsert" {
    var m = I16I32HashMap.init(std.testing.allocator);
    defer m.deinit();
    // Key absent — inserts default
    const v1 = m.getEntry(1).orInsert(1);
    try std.testing.expectEqual(1, v1);
    // Key present — returns existing
    _ = m.put(1, 2);
    const v2 = m.getEntry(1).orInsert(3);
    try std.testing.expectEqual(2, v2);
}

test "I16I32HashMap: entry andModify orInsert" {
    var m = I16I32HashMap.init(std.testing.allocator);
    defer m.deinit();
    // Key absent: andModify is no-op, orInsert inserts
    _ = m.getEntry(1).andModify(struct {
        fn f(_: *i32) void {}
    }.f).orInsert(1);
    try std.testing.expectEqual(@as(?i32, 1), m.get(1));
}

test "I16I32HashMap: ensureUnusedCapacity reserves and subsequent put does not resize" {
    var m = I16I32HashMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(500);
    const reserved = m.inner.capacity;
    try std.testing.expect(reserved >= 500);
    _ = m.put(1, 1);
    _ = m.put(2, 2);
    try std.testing.expectEqual(reserved, m.inner.capacity);
}

test "I16I32HashMap: ensureTotalCapacity is idempotent when capacity already sufficient" {
    var m = I16I32HashMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureTotalCapacity(500);
    const reserved = m.inner.capacity;
    try m.ensureTotalCapacity(10);
    try std.testing.expectEqual(reserved, m.inner.capacity);
}

test "I16I32HashMap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 1: HashMap.init allocates the backing hash table (1st alloc),
    // then ensureUnusedCapacity triggers a grow that fails (2nd alloc).
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var m = I16I32HashMap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(10_000));
}
