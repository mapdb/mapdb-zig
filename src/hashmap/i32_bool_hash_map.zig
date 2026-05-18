
const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const ImmutableI32BoolHashMap = @import("../immutable/immutable_i32_bool_hash_map.zig").ImmutableI32BoolHashMap;

/// Hash map from `i32` keys to `bool` values.
///
/// Custom open-addressing with linear probing and Robin Hood backward-shift deletion.
/// Supports separate allocators for keys, values, and index buckets via AllocatorConfig.
pub const I32BoolHashMap = struct {
    inner: OpenHashMap(i32, bool),
    config: AllocatorConfig,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) I32BoolHashMap {
        return initWithConfig(AllocatorConfig.init(allocator));
    }

    /// Create with pre-allocated capacity.
    pub fn initWithCapacity(allocator: Allocator, capacity: usize) I32BoolHashMap {
        return .{
            .inner = OpenHashMap(i32, bool).initCapacity(allocator, capacity) catch @panic("out of memory"),
            .config = AllocatorConfig.init(allocator),
        };
    }

    /// Create with fine-grained allocator control.
    pub fn initWithConfig(config: AllocatorConfig) I32BoolHashMap {
        return .{
            .inner = OpenHashMap(i32, bool).init(
                config.keysAllocator(),
                config.valuesAllocator(),
                config.indexAllocator(),
            ) catch @panic("out of memory"),
            .config = config,
        };
    }

    pub fn deinit(self: *I32BoolHashMap) void {
        self.inner.deinit();
    }

    // ---- Core Operations ----

    /// Inserts a key-value pair. Returns the old value if the key was already present.
    pub fn put(self: *I32BoolHashMap, key: i32, value: bool) ?bool {
        return self.inner.put(key, value) catch @panic("out of memory");
    }

    /// Returns the value for the key, or null.
    pub fn get(self: *const I32BoolHashMap, key: i32) ?bool {
        return self.inner.get(key);
    }

    /// Returns the value for the key, or the default.
    pub fn getOrDefault(self: *const I32BoolHashMap, key: i32, default_value: bool) bool {
        return self.get(key) orelse default_value;
    }

    /// Removes the key. Returns the old value if present.
    pub fn remove(self: *I32BoolHashMap, key: i32) ?bool {
        return self.inner.remove(key);
    }

    pub fn containsKey(self: *const I32BoolHashMap, key: i32) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const I32BoolHashMap, value: bool) bool {
        return self.inner.containsValue(value);
    }

    // ---- Entry API ----

    /// Entry provides atomic check-and-modify operations for a single key.
    pub const Entry = struct {
        map_ptr: *I32BoolHashMap,
        key: i32,

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

    pub fn getEntry(self: *I32BoolHashMap, key: i32) Entry {
        return .{ .map_ptr = self, .key = key };
    }

    pub fn len(self: *const I32BoolHashMap) usize {
        return self.inner.len();
    }

    pub fn size(self: *const I32BoolHashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const I32BoolHashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn clear(self: *I32BoolHashMap) void {
        self.inner.clear();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more entries can be put without triggering
    /// a rehash. Returns `error.OutOfMemory` if the allocator fails. See
    /// `docs/zig/error-handling.md`.
    pub fn ensureUnusedCapacity(self: *I32BoolHashMap, additional: usize) Allocator.Error!void {
        return self.inner.ensureCapacity(additional);
    }

    /// Ensures the map's total capacity can fit at least `new_capacity`
    /// entries under the load factor without a rehash.
    pub fn ensureTotalCapacity(self: *I32BoolHashMap, new_capacity: usize) Allocator.Error!void {
        if (new_capacity <= self.inner.len()) return;
        return self.inner.ensureCapacity(new_capacity - self.inner.len());
    }

    // ---- Iteration ----

    pub fn forEach(self: *const I32BoolHashMap, f: *const fn (i32, bool) void) void {
        self.inner.forEach(f);
    }

    pub fn forEachKey(self: *const I32BoolHashMap, f: *const fn (i32) void) void {
        self.inner.forEachKey(f);
    }

    pub fn forEachValue(self: *const I32BoolHashMap, f: *const fn (bool) void) void {
        self.inner.forEachValue(f);
    }

    // ---- Functional Operations ----

    pub fn select(self: *const I32BoolHashMap, predicate: *const fn (i32, bool) bool) I32BoolHashMap {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return result;
    }

    pub fn reject(self: *const I32BoolHashMap, predicate: *const fn (i32, bool) bool) I32BoolHashMap {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (!predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return result;
    }

    pub fn detect(self: *const I32BoolHashMap, predicate: *const fn (i32, bool) bool) ?struct { key: i32, value: bool } {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    return .{ .key = self.inner.entries[i].key, .value = self.inner.entries[i].value };
            }
        }
        return null;
    }

    pub fn anySatisfy(self: *const I32BoolHashMap, predicate: *const fn (i32, bool) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const I32BoolHashMap, predicate: *const fn (i32, bool) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and !predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const I32BoolHashMap, predicate: *const fn (i32, bool) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
        }
        return true;
    }

    pub fn count(self: *const I32BoolHashMap, predicate: *const fn (i32, bool) bool) usize {
        var c: usize = 0;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) c += 1;
        }
        return c;
    }

    pub fn injectInto(self: *const I32BoolHashMap, initial: bool, f: *const fn (bool, i32, bool) bool) bool {
        var acc = initial;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) acc = f(acc, self.inner.entries[i].key, self.inner.entries[i].value);
        }
        return acc;
    }

    // ---- Key/Value Collection ----

    pub fn keysToSlice(self: *const I32BoolHashMap, allocator: Allocator) []i32 {
        return self.inner.keysToSlice(allocator) catch @panic("out of memory");
    }

    pub fn valuesToSlice(self: *const I32BoolHashMap, allocator: Allocator) []bool {
        return self.inner.valuesToSlice(allocator) catch @panic("out of memory");
    }

    // ---- Conversion ----

    pub fn toImmutable(self: *const I32BoolHashMap) ImmutableI32BoolHashMap {
        return ImmutableI32BoolHashMap.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    pub fn withKeyValue(self: *I32BoolHashMap, key: i32, value: bool) *I32BoolHashMap {
        _ = self.put(key, value);
        return self;
    }

    pub fn withoutKey(self: *I32BoolHashMap, key: i32) *I32BoolHashMap {
        _ = self.remove(key);
        return self;
    }

    pub fn withoutAllKeys(self: *I32BoolHashMap, keys: []const i32) *I32BoolHashMap {
        for (keys) |key| _ = self.remove(key);
        return self;
    }

    // ---- Mutation Helpers ----

    pub fn updateValue(self: *I32BoolHashMap, key: i32, initial: bool, f: *const fn (bool) bool) bool {
        const current = self.get(key) orelse initial;
        const new_value = f(current);
        _ = self.put(key, new_value);
        return new_value;
    }

    // ---- Formatting ----

    pub fn format(self: *const I32BoolHashMap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const I32BoolHashMap, other: *const I32BoolHashMap) bool {
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

test "I32BoolHashMap: put and get" {
    var m = I32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, true);
    _ = m.put(2, false);
    _ = m.put(3, true);
    try std.testing.expectEqual(@as(?bool, true), m.get(1));
    try std.testing.expectEqual(@as(?bool, null), m.get(99));
    try std.testing.expectEqual(@as(usize, 3), m.len());
}

test "I32BoolHashMap: put overwrite" {
    var m = I32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, true);
    const old = m.put(1, false);
    try std.testing.expectEqual(@as(?bool, true), old);
    try std.testing.expectEqual(@as(?bool, false), m.get(1));
}

test "I32BoolHashMap: remove" {
    var m = I32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, true);
    _ = m.put(2, false);
    const removed = m.remove(1);
    try std.testing.expectEqual(@as(?bool, true), removed);
    try std.testing.expectEqual(@as(usize, 1), m.len());
    try std.testing.expect(!m.containsKey(1));
}

test "I32BoolHashMap: containsKey and containsValue" {
    var m = I32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, true);
    try std.testing.expect(m.containsKey(1));
    try std.testing.expect(!m.containsKey(99));
    try std.testing.expect(m.containsValue(true));
    try std.testing.expect(!m.containsValue(false));
}

test "I32BoolHashMap: getOrDefault" {
    var m = I32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, true);
    try std.testing.expectEqual(true, m.getOrDefault(1, true));
    try std.testing.expectEqual(true, m.getOrDefault(99, true));
}

test "I32BoolHashMap: clear" {
    var m = I32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, true);
    m.clear();
    try std.testing.expect(m.isEmpty());
}

test "I32BoolHashMap: select" {
    var m = I32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, true);
    _ = m.put(2, false);
    var sel = m.select(struct {
        fn f(_: i32, v: bool) bool {
            return v == true;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expect(sel.len() >= 1);
}

test "I32BoolHashMap: keysToSlice and valuesToSlice" {
    var m = I32BoolHashMap.init(std.testing.allocator);
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

test "I32BoolHashMap: toImmutable" {
    var m = I32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, true);
    _ = m.put(2, false);
    var im = m.toImmutable();
    defer im.deinit();
    try std.testing.expectEqual(@as(usize, 2), im.len());
    _ = m.put(3, true);
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "I32BoolHashMap: fluent withKeyValue/withoutKey" {
    var m = I32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.withKeyValue(1, true).withKeyValue(2, false);
    try std.testing.expectEqual(@as(usize, 2), m.len());
    _ = m.withoutKey(1);
    try std.testing.expectEqual(@as(usize, 1), m.len());
}

test "I32BoolHashMap: eql" {
    var m1 = I32BoolHashMap.init(std.testing.allocator);
    defer m1.deinit();
    _ = m1.put(1, true);
    _ = m1.put(2, false);
    var m2 = I32BoolHashMap.init(std.testing.allocator);
    defer m2.deinit();
    _ = m2.put(2, false);
    _ = m2.put(1, true);
    try std.testing.expect(m1.eql(&m2));
}

test "I32BoolHashMap: resize" {
    var m = I32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        _ = m.put(@as(i32, @intCast(i)), i % 3 == 0);
    }
    try std.testing.expect(m.len() > 0);
}

test "I32BoolHashMap: entry orInsert" {
    var m = I32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    // Key absent — inserts default
    const v1 = m.getEntry(1).orInsert(true);
    try std.testing.expectEqual(true, v1);
    // Key present — returns existing
    _ = m.put(1, false);
    const v2 = m.getEntry(1).orInsert(true);
    try std.testing.expectEqual(false, v2);
}

test "I32BoolHashMap: entry andModify orInsert" {
    var m = I32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    // Key absent: andModify is no-op, orInsert inserts
    _ = m.getEntry(1).andModify(struct {
        fn f(_: *bool) void {}
    }.f).orInsert(true);
    try std.testing.expectEqual(@as(?bool, true), m.get(1));
}

test "I32BoolHashMap: ensureUnusedCapacity reserves and subsequent put does not resize" {
    var m = I32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(500);
    const reserved = m.inner.capacity;
    try std.testing.expect(reserved >= 500);
    _ = m.put(1, true);
    _ = m.put(2, false);
    try std.testing.expectEqual(reserved, m.inner.capacity);
}

test "I32BoolHashMap: ensureTotalCapacity is idempotent when capacity already sufficient" {
    var m = I32BoolHashMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureTotalCapacity(500);
    const reserved = m.inner.capacity;
    try m.ensureTotalCapacity(10);
    try std.testing.expectEqual(reserved, m.inner.capacity);
}

test "I32BoolHashMap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 1: HashMap.init allocates the backing hash table (1st alloc),
    // then ensureUnusedCapacity triggers a grow that fails (2nd alloc).
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var m = I32BoolHashMap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(10_000));
}
