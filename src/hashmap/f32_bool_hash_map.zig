// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const ImmutableF32BoolHashMap = @import("../immutable/immutable_f32_bool_hash_map.zig").ImmutableF32BoolHashMap;

/// Hash map from `f32` keys to `bool` values.
///
/// Custom open-addressing with linear probing and Robin Hood backward-shift deletion.
/// Supports separate allocators for keys, values, and index buckets via AllocatorConfig.
pub const F32BoolHashMap = struct {
    inner: OpenHashMap(f32, bool),
    config: AllocatorConfig,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) F32BoolHashMap {
        return initWithConfig(AllocatorConfig.init(allocator));
    }

    /// Create with pre-allocated capacity.
    pub fn initWithCapacity(allocator: Allocator, capacity: usize) F32BoolHashMap {
        return .{
            .inner = OpenHashMap(f32, bool).initCapacity(allocator, capacity) catch @panic("out of memory"),
            .config = AllocatorConfig.init(allocator),
        };
    }

    /// Create with fine-grained allocator control.
    pub fn initWithConfig(config: AllocatorConfig) F32BoolHashMap {
        return .{
            .inner = OpenHashMap(f32, bool).init(
                config.keysAllocator(),
                config.valuesAllocator(),
                config.indexAllocator(),
            ) catch @panic("out of memory"),
            .config = config,
        };
    }

    pub fn deinit(self: *F32BoolHashMap) void {
        self.inner.deinit();
    }

    // ---- Core Operations ----

    /// Inserts a key-value pair. Returns the old value if the key was already present.
    pub fn put(self: *F32BoolHashMap, key: f32, value: bool) ?bool {
        return self.inner.put(key, value) catch @panic("out of memory");
    }

    /// Returns the value for the key, or null.
    pub fn get(self: *const F32BoolHashMap, key: f32) ?bool {
        return self.inner.get(key);
    }

    /// Returns the value for the key, or the default.
    pub fn getOrDefault(self: *const F32BoolHashMap, key: f32, default_value: bool) bool {
        return self.get(key) orelse default_value;
    }

    /// Removes the key. Returns the old value if present.
    pub fn remove(self: *F32BoolHashMap, key: f32) ?bool {
        return self.inner.remove(key);
    }

    pub fn containsKey(self: *const F32BoolHashMap, key: f32) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const F32BoolHashMap, value: bool) bool {
        return self.inner.containsValue(value);
    }

    // ---- Entry API ----

    /// Entry provides atomic check-and-modify operations for a single key.
    pub const Entry = struct {
        map_ptr: *F32BoolHashMap,
        key: f32,

        /// Inserts the default value if the key is absent. Returns the current value.
        pub fn orInsert(self: Entry, default_value: bool) bool {
            if (self.map_ptr.get(self.key)) |existing| return existing;
            _ = self.map_ptr.put(self.key, default_value);
            return default_value;
        }

        /// Inserts the value from the function if the key is absent.
        pub fn orInsertWith(self: Entry, f: *const fn () bool) bool {
            if (self.map_ptr.get(self.key)) |existing| return existing;
            const val = f();
            _ = self.map_ptr.put(self.key, val);
            return val;
        }

        /// Calls the function on a pointer to the value if the key is present.
        pub fn andModify(self: Entry, f: *const fn (*bool) void) Entry {
            if (self.map_ptr.inner.getPtr(self.key)) |val_ptr| {
                f(val_ptr);
            }
            return self;
        }
    };

    pub fn getEntry(self: *F32BoolHashMap, key: f32) Entry {
        return .{ .map_ptr = self, .key = key };
    }

    pub fn len(self: *const F32BoolHashMap) usize {
        return self.inner.len();
    }

    pub fn size(self: *const F32BoolHashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const F32BoolHashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn clear(self: *F32BoolHashMap) void {
        self.inner.clear();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more entries can be put without triggering
    /// a rehash. Returns `error.OutOfMemory` if the allocator fails.
    pub fn ensureUnusedCapacity(self: *F32BoolHashMap, additional: usize) Allocator.Error!void {
        return self.inner.ensureCapacity(additional);
    }

    /// Ensures the map's total capacity can fit at least `new_capacity`
    /// entries under the load factor without a rehash.
    pub fn ensureTotalCapacity(self: *F32BoolHashMap, new_capacity: usize) Allocator.Error!void {
        if (new_capacity <= self.inner.len()) return;
        return self.inner.ensureCapacity(new_capacity - self.inner.len());
    }

    // ---- Iteration ----

    pub fn forEach(self: *const F32BoolHashMap, f: *const fn (f32, bool) void) void {
        self.inner.forEach(f);
    }

    pub fn forEachKey(self: *const F32BoolHashMap, f: *const fn (f32) void) void {
        self.inner.forEachKey(f);
    }

    pub fn forEachValue(self: *const F32BoolHashMap, f: *const fn (bool) void) void {
        self.inner.forEachValue(f);
    }

    // ---- Functional Operations ----

    pub fn select(self: *const F32BoolHashMap, predicate: *const fn (f32, bool) bool) F32BoolHashMap {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return result;
    }

    pub fn reject(self: *const F32BoolHashMap, predicate: *const fn (f32, bool) bool) F32BoolHashMap {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (!predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return result;
    }

    pub fn detect(self: *const F32BoolHashMap, predicate: *const fn (f32, bool) bool) ?struct { key: f32, value: bool } {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    return .{ .key = self.inner.entries[i].key, .value = self.inner.entries[i].value };
            }
        }
        return null;
    }

    pub fn anySatisfy(self: *const F32BoolHashMap, predicate: *const fn (f32, bool) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const F32BoolHashMap, predicate: *const fn (f32, bool) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and !predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const F32BoolHashMap, predicate: *const fn (f32, bool) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
        }
        return true;
    }

    pub fn count(self: *const F32BoolHashMap, predicate: *const fn (f32, bool) bool) usize {
        var c: usize = 0;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) c += 1;
        }
        return c;
    }

    pub fn injectInto(self: *const F32BoolHashMap, initial: bool, f: *const fn (bool, f32, bool) bool) bool {
        var acc = initial;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) acc = f(acc, self.inner.entries[i].key, self.inner.entries[i].value);
        }
        return acc;
    }

    // ---- Key/Value Collection ----

    pub fn keysToSlice(self: *const F32BoolHashMap, allocator: Allocator) []f32 {
        return self.inner.keysToSlice(allocator) catch @panic("out of memory");
    }

    pub fn valuesToSlice(self: *const F32BoolHashMap, allocator: Allocator) []bool {
        return self.inner.valuesToSlice(allocator) catch @panic("out of memory");
    }

    // ---- Conversion ----

    pub fn toImmutable(self: *const F32BoolHashMap) ImmutableF32BoolHashMap {
        return ImmutableF32BoolHashMap.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    pub fn withKeyValue(self: *F32BoolHashMap, key: f32, value: bool) *F32BoolHashMap {
        _ = self.put(key, value);
        return self;
    }

    pub fn withoutKey(self: *F32BoolHashMap, key: f32) *F32BoolHashMap {
        _ = self.remove(key);
        return self;
    }

    pub fn withoutAllKeys(self: *F32BoolHashMap, keys: []const f32) *F32BoolHashMap {
        for (keys) |key| _ = self.remove(key);
        return self;
    }

    // ---- Mutation Helpers ----

    pub fn updateValue(self: *F32BoolHashMap, key: f32, initial: bool, f: *const fn (bool) bool) bool {
        const current = self.get(key) orelse initial;
        const new_value = f(current);
        _ = self.put(key, new_value);
        return new_value;
    }

    // ---- Formatting ----

    pub fn format(self: *const F32BoolHashMap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const F32BoolHashMap, other: *const F32BoolHashMap) bool {
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

test "F32BoolHashMap: put and get" {
    var m = F32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, true);
    _ = m.put(2.0, false);
    _ = m.put(3.0, true);
    try std.testing.expectEqual(@as(?bool, true), m.get(1.0));
    try std.testing.expectEqual(@as(?bool, null), m.get(99.0));
    try std.testing.expectEqual(@as(usize, 3), m.len());
}

test "F32BoolHashMap: put overwrite" {
    var m = F32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, true);
    const old = m.put(1.0, false);
    try std.testing.expectEqual(@as(?bool, true), old);
    try std.testing.expectEqual(@as(?bool, false), m.get(1.0));
}

test "F32BoolHashMap: remove" {
    var m = F32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, true);
    _ = m.put(2.0, false);
    const removed = m.remove(1.0);
    try std.testing.expectEqual(@as(?bool, true), removed);
    try std.testing.expectEqual(@as(usize, 1), m.len());
    try std.testing.expect(!m.containsKey(1.0));
}

test "F32BoolHashMap: containsKey and containsValue" {
    var m = F32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, true);
    try std.testing.expect(m.containsKey(1.0));
    try std.testing.expect(!m.containsKey(99.0));
    try std.testing.expect(m.containsValue(true));
    try std.testing.expect(!m.containsValue(false));
}

test "F32BoolHashMap: getOrDefault" {
    var m = F32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, true);
    try std.testing.expectEqual(true, m.getOrDefault(1.0, true));
    try std.testing.expectEqual(true, m.getOrDefault(99.0, true));
}

test "F32BoolHashMap: clear" {
    var m = F32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, true);
    m.clear();
    try std.testing.expect(m.isEmpty());
}

test "F32BoolHashMap: select" {
    var m = F32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, true);
    _ = m.put(2.0, false);
    var sel = m.select(struct {
        fn f(_: f32, v: bool) bool {
            return v == true;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expect(sel.len() >= 1);
}

test "F32BoolHashMap: keysToSlice and valuesToSlice" {
    var m = F32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, true);
    _ = m.put(2.0, false);
    const keys = m.keysToSlice(std.testing.allocator);
    defer std.testing.allocator.free(keys);
    try std.testing.expectEqual(@as(usize, 2), keys.len);
    const vals = m.valuesToSlice(std.testing.allocator);
    defer std.testing.allocator.free(vals);
    try std.testing.expectEqual(@as(usize, 2), vals.len);
}

test "F32BoolHashMap: toImmutable" {
    var m = F32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, true);
    _ = m.put(2.0, false);
    var im = m.toImmutable();
    defer im.deinit();
    try std.testing.expectEqual(@as(usize, 2), im.len());
    _ = m.put(3.0, true);
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "F32BoolHashMap: fluent withKeyValue/withoutKey" {
    var m = F32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.withKeyValue(1.0, true).withKeyValue(2.0, false);
    try std.testing.expectEqual(@as(usize, 2), m.len());
    _ = m.withoutKey(1.0);
    try std.testing.expectEqual(@as(usize, 1), m.len());
}

test "F32BoolHashMap: eql" {
    var m1 = F32BoolHashMap.init(std.testing.allocator);
    defer m1.deinit();
    _ = m1.put(1.0, true);
    _ = m1.put(2.0, false);
    var m2 = F32BoolHashMap.init(std.testing.allocator);
    defer m2.deinit();
    _ = m2.put(2.0, false);
    _ = m2.put(1.0, true);
    try std.testing.expect(m1.eql(&m2));
}

test "F32BoolHashMap: resize" {
    var m = F32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        _ = m.put(@as(f32, @floatFromInt(i)), i % 3 == 0);
    }
    try std.testing.expect(m.len() > 0);
}

test "F32BoolHashMap: entry orInsert" {
    var m = F32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    // Key absent — inserts default
    const v1 = m.getEntry(1.0).orInsert(true);
    try std.testing.expectEqual(true, v1);
    // Key present — returns existing
    _ = m.put(1.0, false);
    const v2 = m.getEntry(1.0).orInsert(true);
    try std.testing.expectEqual(false, v2);
}

test "F32BoolHashMap: entry andModify orInsert" {
    var m = F32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    // Key absent: andModify is no-op, orInsert inserts
    _ = m.getEntry(1.0).andModify(struct {
        fn f(_: *bool) void {}
    }.f).orInsert(true);
    try std.testing.expectEqual(@as(?bool, true), m.get(1.0));
}

test "F32BoolHashMap: ensureUnusedCapacity reserves and subsequent put does not resize" {
    var m = F32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(500);
    const reserved = m.inner.capacity;
    try std.testing.expect(reserved >= 500);
    _ = m.put(1.0, true);
    _ = m.put(2.0, false);
    try std.testing.expectEqual(reserved, m.inner.capacity);
}

test "F32BoolHashMap: ensureTotalCapacity is idempotent when capacity already sufficient" {
    var m = F32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureTotalCapacity(500);
    const reserved = m.inner.capacity;
    try m.ensureTotalCapacity(10);
    try std.testing.expectEqual(reserved, m.inner.capacity);
}

test "F32BoolHashMap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 1: HashMap.init allocates the backing hash table (1st alloc),
    // then ensureUnusedCapacity triggers a grow that fails (2nd alloc).
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var m = F32BoolHashMap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(10_000));
}

// ---- NaN / IEEE-754 edge-case tests (locks in bit-level keyEql from hash_table.zig) ----
// See docs/float-nan-semantics-audit.md.

test "F32BoolHashMap: NaN key findable" {
    var m = F32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    const nan_key = std.math.nan(f32);
    _ = m.put(nan_key, true);
    try std.testing.expect(m.containsKey(nan_key));
    try std.testing.expectEqual(@as(?bool, true), m.get(nan_key));
}

test "F32BoolHashMap: NaN key replaces, does not duplicate" {
    var m = F32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    const nan_key = std.math.nan(f32);
    _ = m.put(nan_key, true);
    _ = m.put(nan_key, false);
    _ = m.put(nan_key, true);
    try std.testing.expectEqual(@as(usize, 1), m.len());
    try std.testing.expectEqual(@as(?bool, true), m.get(nan_key));
}

test "F32BoolHashMap: NaN key remove" {
    var m = F32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    const nan_key = std.math.nan(f32);
    _ = m.put(nan_key, true);
    _ = m.remove(nan_key);
    try std.testing.expectEqual(@as(usize, 0), m.len());
    try std.testing.expect(!m.containsKey(nan_key));
}

test "F32BoolHashMap: -0.0 distinct from +0.0" {
    var m = F32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    const pos_zero: f32 = @as(f32, 0.0);
    const neg_zero: f32 = @as(f32, -0.0);
    _ = m.put(pos_zero, true);
    _ = m.put(neg_zero, false);
    try std.testing.expectEqual(@as(usize, 2), m.len());
    try std.testing.expectEqual(@as(?bool, true), m.get(pos_zero));
    try std.testing.expectEqual(@as(?bool, false), m.get(neg_zero));
}

test "F32BoolHashMap: +/-Infinity keys" {
    var m = F32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    const pos_inf = std.math.inf(f32);
    const neg_inf = -std.math.inf(f32);
    _ = m.put(pos_inf, true);
    _ = m.put(neg_inf, false);
    try std.testing.expectEqual(@as(usize, 2), m.len());
    try std.testing.expect(m.containsKey(pos_inf));
    try std.testing.expect(m.containsKey(neg_inf));
    try std.testing.expectEqual(@as(?bool, true), m.get(pos_inf));
    try std.testing.expectEqual(@as(?bool, false), m.get(neg_inf));
}
