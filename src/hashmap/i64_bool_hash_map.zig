
const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const ImmutableI64BoolHashMap = @import("../immutable/immutable_i64_bool_hash_map.zig").ImmutableI64BoolHashMap;

/// Hash map from `i64` keys to `bool` values.
///
/// Custom open-addressing with linear probing and Robin Hood backward-shift deletion.
/// Supports separate allocators for keys, values, and index buckets via AllocatorConfig.
pub const I64BoolHashMap = struct {
    inner: OpenHashMap(i64, bool),
    config: AllocatorConfig,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) I64BoolHashMap {
        return initWithConfig(AllocatorConfig.init(allocator));
    }

    /// Create with pre-allocated capacity.
    pub fn initWithCapacity(allocator: Allocator, capacity: usize) I64BoolHashMap {
        return .{
            .inner = OpenHashMap(i64, bool).initCapacity(allocator, capacity) catch @panic("out of memory"),
            .config = AllocatorConfig.init(allocator),
        };
    }

    /// Create with fine-grained allocator control.
    pub fn initWithConfig(config: AllocatorConfig) I64BoolHashMap {
        return .{
            .inner = OpenHashMap(i64, bool).init(
                config.keysAllocator(),
                config.valuesAllocator(),
                config.indexAllocator(),
            ) catch @panic("out of memory"),
            .config = config,
        };
    }

    pub fn deinit(self: *I64BoolHashMap) void {
        self.inner.deinit();
    }

    // ---- Core Operations ----

    /// Inserts a key-value pair. Returns the old value if the key was already present.
    pub fn put(self: *I64BoolHashMap, key: i64, value: bool) ?bool {
        return self.inner.put(key, value) catch @panic("out of memory");
    }

    /// Returns the value for the key, or null.
    pub fn get(self: *const I64BoolHashMap, key: i64) ?bool {
        return self.inner.get(key);
    }

    /// Returns the value for the key, or the default.
    pub fn getOrDefault(self: *const I64BoolHashMap, key: i64, default_value: bool) bool {
        return self.get(key) orelse default_value;
    }

    /// Removes the key. Returns the old value if present.
    pub fn remove(self: *I64BoolHashMap, key: i64) ?bool {
        return self.inner.remove(key);
    }

    pub fn containsKey(self: *const I64BoolHashMap, key: i64) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const I64BoolHashMap, value: bool) bool {
        return self.inner.containsValue(value);
    }

    // ---- Entry API ----

    /// Entry provides atomic check-and-modify operations for a single key.
    pub const Entry = struct {
        map_ptr: *I64BoolHashMap,
        key: i64,

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

    pub fn getEntry(self: *I64BoolHashMap, key: i64) Entry {
        return .{ .map_ptr = self, .key = key };
    }

    pub fn len(self: *const I64BoolHashMap) usize {
        return self.inner.len();
    }

    pub fn size(self: *const I64BoolHashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const I64BoolHashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn clear(self: *I64BoolHashMap) void {
        self.inner.clear();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more entries can be put without triggering
    /// a rehash. Returns `error.OutOfMemory` if the allocator fails.
    pub fn ensureUnusedCapacity(self: *I64BoolHashMap, additional: usize) Allocator.Error!void {
        return self.inner.ensureCapacity(additional);
    }

    /// Ensures the map's total capacity can fit at least `new_capacity`
    /// entries under the load factor without a rehash.
    pub fn ensureTotalCapacity(self: *I64BoolHashMap, new_capacity: usize) Allocator.Error!void {
        if (new_capacity <= self.inner.len()) return;
        return self.inner.ensureCapacity(new_capacity - self.inner.len());
    }

    // ---- Iteration ----

    pub fn forEach(self: *const I64BoolHashMap, f: *const fn (i64, bool) void) void {
        self.inner.forEach(f);
    }

    pub fn forEachKey(self: *const I64BoolHashMap, f: *const fn (i64) void) void {
        self.inner.forEachKey(f);
    }

    pub fn forEachValue(self: *const I64BoolHashMap, f: *const fn (bool) void) void {
        self.inner.forEachValue(f);
    }

    // ---- Functional Operations ----

    pub fn select(self: *const I64BoolHashMap, predicate: *const fn (i64, bool) bool) I64BoolHashMap {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return result;
    }

    pub fn reject(self: *const I64BoolHashMap, predicate: *const fn (i64, bool) bool) I64BoolHashMap {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (!predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return result;
    }

    pub fn detect(self: *const I64BoolHashMap, predicate: *const fn (i64, bool) bool) ?struct { key: i64, value: bool } {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    return .{ .key = self.inner.entries[i].key, .value = self.inner.entries[i].value };
            }
        }
        return null;
    }

    pub fn anySatisfy(self: *const I64BoolHashMap, predicate: *const fn (i64, bool) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const I64BoolHashMap, predicate: *const fn (i64, bool) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and !predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const I64BoolHashMap, predicate: *const fn (i64, bool) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
        }
        return true;
    }

    pub fn count(self: *const I64BoolHashMap, predicate: *const fn (i64, bool) bool) usize {
        var c: usize = 0;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) c += 1;
        }
        return c;
    }

    pub fn injectInto(self: *const I64BoolHashMap, initial: bool, f: *const fn (bool, i64, bool) bool) bool {
        var acc = initial;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) acc = f(acc, self.inner.entries[i].key, self.inner.entries[i].value);
        }
        return acc;
    }

    // ---- Key/Value Collection ----

    pub fn keysToSlice(self: *const I64BoolHashMap, allocator: Allocator) []i64 {
        return self.inner.keysToSlice(allocator) catch @panic("out of memory");
    }

    pub fn valuesToSlice(self: *const I64BoolHashMap, allocator: Allocator) []bool {
        return self.inner.valuesToSlice(allocator) catch @panic("out of memory");
    }

    // ---- Conversion ----

    pub fn toImmutable(self: *const I64BoolHashMap) ImmutableI64BoolHashMap {
        return ImmutableI64BoolHashMap.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    pub fn withKeyValue(self: *I64BoolHashMap, key: i64, value: bool) *I64BoolHashMap {
        _ = self.put(key, value);
        return self;
    }

    pub fn withoutKey(self: *I64BoolHashMap, key: i64) *I64BoolHashMap {
        _ = self.remove(key);
        return self;
    }

    pub fn withoutAllKeys(self: *I64BoolHashMap, keys: []const i64) *I64BoolHashMap {
        for (keys) |key| _ = self.remove(key);
        return self;
    }

    // ---- Mutation Helpers ----

    pub fn updateValue(self: *I64BoolHashMap, key: i64, initial: bool, f: *const fn (bool) bool) bool {
        const current = self.get(key) orelse initial;
        const new_value = f(current);
        _ = self.put(key, new_value);
        return new_value;
    }

    // ---- Formatting ----

    pub fn format(self: *const I64BoolHashMap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const I64BoolHashMap, other: *const I64BoolHashMap) bool {
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

test "I64BoolHashMap: put and get" {
    var m = I64BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, true);
    _ = m.put(2, false);
    _ = m.put(3, true);
    try std.testing.expectEqual(@as(?bool, true), m.get(1));
    try std.testing.expectEqual(@as(?bool, null), m.get(99));
    try std.testing.expectEqual(@as(usize, 3), m.len());
}

test "I64BoolHashMap: put overwrite" {
    var m = I64BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, true);
    const old = m.put(1, false);
    try std.testing.expectEqual(@as(?bool, true), old);
    try std.testing.expectEqual(@as(?bool, false), m.get(1));
}

test "I64BoolHashMap: remove" {
    var m = I64BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, true);
    _ = m.put(2, false);
    const removed = m.remove(1);
    try std.testing.expectEqual(@as(?bool, true), removed);
    try std.testing.expectEqual(@as(usize, 1), m.len());
    try std.testing.expect(!m.containsKey(1));
}

test "I64BoolHashMap: containsKey and containsValue" {
    var m = I64BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, true);
    try std.testing.expect(m.containsKey(1));
    try std.testing.expect(!m.containsKey(99));
    try std.testing.expect(m.containsValue(true));
    try std.testing.expect(!m.containsValue(false));
}

test "I64BoolHashMap: getOrDefault" {
    var m = I64BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, true);
    try std.testing.expectEqual(true, m.getOrDefault(1, true));
    try std.testing.expectEqual(true, m.getOrDefault(99, true));
}

test "I64BoolHashMap: clear" {
    var m = I64BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, true);
    m.clear();
    try std.testing.expect(m.isEmpty());
}

test "I64BoolHashMap: select" {
    var m = I64BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, true);
    _ = m.put(2, false);
    var sel = m.select(struct {
        fn f(_: i64, v: bool) bool {
            return v == true;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expect(sel.len() >= 1);
}

test "I64BoolHashMap: keysToSlice and valuesToSlice" {
    var m = I64BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, true);
    _ = m.put(2, false);
    const keys = m.keysToSlice(std.testing.allocator);
    defer std.testing.allocator.free(keys);
    try std.testing.expectEqual(@as(usize, 2), keys.len);
    const vals = m.valuesToSlice(std.testing.allocator);
    defer std.testing.allocator.free(vals);
    try std.testing.expectEqual(@as(usize, 2), vals.len);
}

test "I64BoolHashMap: toImmutable" {
    var m = I64BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, true);
    _ = m.put(2, false);
    var im = m.toImmutable();
    defer im.deinit();
    try std.testing.expectEqual(@as(usize, 2), im.len());
    _ = m.put(3, true);
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "I64BoolHashMap: fluent withKeyValue/withoutKey" {
    var m = I64BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.withKeyValue(1, true).withKeyValue(2, false);
    try std.testing.expectEqual(@as(usize, 2), m.len());
    _ = m.withoutKey(1);
    try std.testing.expectEqual(@as(usize, 1), m.len());
}

test "I64BoolHashMap: eql" {
    var m1 = I64BoolHashMap.init(std.testing.allocator);
    defer m1.deinit();
    _ = m1.put(1, true);
    _ = m1.put(2, false);
    var m2 = I64BoolHashMap.init(std.testing.allocator);
    defer m2.deinit();
    _ = m2.put(2, false);
    _ = m2.put(1, true);
    try std.testing.expect(m1.eql(&m2));
}

test "I64BoolHashMap: resize" {
    var m = I64BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        _ = m.put(@as(i64, @intCast(i)), i % 3 == 0);
    }
    try std.testing.expect(m.len() > 0);
}

test "I64BoolHashMap: entry orInsert" {
    var m = I64BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    // Key absent — inserts default
    const v1 = m.getEntry(1).orInsert(true);
    try std.testing.expectEqual(true, v1);
    // Key present — returns existing
    _ = m.put(1, false);
    const v2 = m.getEntry(1).orInsert(true);
    try std.testing.expectEqual(false, v2);
}

test "I64BoolHashMap: entry andModify orInsert" {
    var m = I64BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    // Key absent: andModify is no-op, orInsert inserts
    _ = m.getEntry(1).andModify(struct {
        fn f(_: *bool) void {}
    }.f).orInsert(true);
    try std.testing.expectEqual(@as(?bool, true), m.get(1));
}

test "I64BoolHashMap: ensureUnusedCapacity reserves and subsequent put does not resize" {
    var m = I64BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(500);
    const reserved = m.inner.capacity;
    try std.testing.expect(reserved >= 500);
    _ = m.put(1, true);
    _ = m.put(2, false);
    try std.testing.expectEqual(reserved, m.inner.capacity);
}

test "I64BoolHashMap: ensureTotalCapacity is idempotent when capacity already sufficient" {
    var m = I64BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureTotalCapacity(500);
    const reserved = m.inner.capacity;
    try m.ensureTotalCapacity(10);
    try std.testing.expectEqual(reserved, m.inner.capacity);
}

test "I64BoolHashMap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 1: HashMap.init allocates the backing hash table (1st alloc),
    // then ensureUnusedCapacity triggers a grow that fails (2nd alloc).
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var m = I64BoolHashMap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(10_000));
}
