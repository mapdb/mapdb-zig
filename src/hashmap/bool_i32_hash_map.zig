
const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const ImmutableBoolI32HashMap = @import("../immutable/immutable_bool_i32_hash_map.zig").ImmutableBoolI32HashMap;

/// Hash map from `bool` keys to `i32` values.
///
/// Custom open-addressing with linear probing and Robin Hood backward-shift deletion.
/// Supports separate allocators for keys, values, and index buckets via AllocatorConfig.
pub const BoolI32HashMap = struct {
    inner: OpenHashMap(bool, i32),
    config: AllocatorConfig,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) BoolI32HashMap {
        return initWithConfig(AllocatorConfig.init(allocator));
    }

    /// Create with pre-allocated capacity.
    pub fn initWithCapacity(allocator: Allocator, capacity: usize) BoolI32HashMap {
        return .{
            .inner = OpenHashMap(bool, i32).initCapacity(allocator, capacity) catch @panic("out of memory"),
            .config = AllocatorConfig.init(allocator),
        };
    }

    /// Create with fine-grained allocator control.
    pub fn initWithConfig(config: AllocatorConfig) BoolI32HashMap {
        return .{
            .inner = OpenHashMap(bool, i32).init(
                config.keysAllocator(),
                config.valuesAllocator(),
                config.indexAllocator(),
            ) catch @panic("out of memory"),
            .config = config,
        };
    }

    pub fn deinit(self: *BoolI32HashMap) void {
        self.inner.deinit();
    }

    // ---- Core Operations ----

    /// Inserts a key-value pair. Returns the old value if the key was already present.
    pub fn put(self: *BoolI32HashMap, key: bool, value: i32) ?i32 {
        return self.inner.put(key, value) catch @panic("out of memory");
    }

    /// Returns the value for the key, or null.
    pub fn get(self: *const BoolI32HashMap, key: bool) ?i32 {
        return self.inner.get(key);
    }

    /// Returns the value for the key, or the default.
    pub fn getOrDefault(self: *const BoolI32HashMap, key: bool, default_value: i32) i32 {
        return self.get(key) orelse default_value;
    }

    /// Removes the key. Returns the old value if present.
    pub fn remove(self: *BoolI32HashMap, key: bool) ?i32 {
        return self.inner.remove(key);
    }

    pub fn containsKey(self: *const BoolI32HashMap, key: bool) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const BoolI32HashMap, value: i32) bool {
        return self.inner.containsValue(value);
    }

    // ---- Entry API ----

    /// Entry provides atomic check-and-modify operations for a single key.
    pub const Entry = struct {
        map_ptr: *BoolI32HashMap,
        key: bool,

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

    pub fn getEntry(self: *BoolI32HashMap, key: bool) Entry {
        return .{ .map_ptr = self, .key = key };
    }

    pub fn len(self: *const BoolI32HashMap) usize {
        return self.inner.len();
    }

    pub fn size(self: *const BoolI32HashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const BoolI32HashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn clear(self: *BoolI32HashMap) void {
        self.inner.clear();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more entries can be put without triggering
    /// a rehash. Returns `error.OutOfMemory` if the allocator fails. See
    /// `docs/zig/error-handling.md`.
    pub fn ensureUnusedCapacity(self: *BoolI32HashMap, additional: usize) Allocator.Error!void {
        return self.inner.ensureCapacity(additional);
    }

    /// Ensures the map's total capacity can fit at least `new_capacity`
    /// entries under the load factor without a rehash.
    pub fn ensureTotalCapacity(self: *BoolI32HashMap, new_capacity: usize) Allocator.Error!void {
        if (new_capacity <= self.inner.len()) return;
        return self.inner.ensureCapacity(new_capacity - self.inner.len());
    }

    // ---- Iteration ----

    pub fn forEach(self: *const BoolI32HashMap, f: *const fn (bool, i32) void) void {
        self.inner.forEach(f);
    }

    pub fn forEachKey(self: *const BoolI32HashMap, f: *const fn (bool) void) void {
        self.inner.forEachKey(f);
    }

    pub fn forEachValue(self: *const BoolI32HashMap, f: *const fn (i32) void) void {
        self.inner.forEachValue(f);
    }

    // ---- Functional Operations ----

    pub fn select(self: *const BoolI32HashMap, predicate: *const fn (bool, i32) bool) BoolI32HashMap {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return result;
    }

    pub fn reject(self: *const BoolI32HashMap, predicate: *const fn (bool, i32) bool) BoolI32HashMap {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (!predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return result;
    }

    pub fn detect(self: *const BoolI32HashMap, predicate: *const fn (bool, i32) bool) ?struct { key: bool, value: i32 } {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    return .{ .key = self.inner.entries[i].key, .value = self.inner.entries[i].value };
            }
        }
        return null;
    }

    pub fn anySatisfy(self: *const BoolI32HashMap, predicate: *const fn (bool, i32) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const BoolI32HashMap, predicate: *const fn (bool, i32) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and !predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const BoolI32HashMap, predicate: *const fn (bool, i32) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
        }
        return true;
    }

    pub fn count(self: *const BoolI32HashMap, predicate: *const fn (bool, i32) bool) usize {
        var c: usize = 0;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) c += 1;
        }
        return c;
    }

    pub fn injectInto(self: *const BoolI32HashMap, initial: i32, f: *const fn (i32, bool, i32) i32) i32 {
        var acc = initial;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) acc = f(acc, self.inner.entries[i].key, self.inner.entries[i].value);
        }
        return acc;
    }

    // ---- Key/Value Collection ----

    pub fn keysToSlice(self: *const BoolI32HashMap, allocator: Allocator) []bool {
        return self.inner.keysToSlice(allocator) catch @panic("out of memory");
    }

    pub fn valuesToSlice(self: *const BoolI32HashMap, allocator: Allocator) []i32 {
        return self.inner.valuesToSlice(allocator) catch @panic("out of memory");
    }

    // ---- Numeric Value Operations ----

    pub fn sumOfValues(self: *const BoolI32HashMap) i64 {
        var total: i64 = 0;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) total += @as(i64, @intCast(self.inner.entries[i].value));
        }
        return total;
    }

    pub fn addToValue(self: *BoolI32HashMap, key: bool, delta: i32) i32 {
        if (self.inner.getPtr(key)) |val_ptr| {
            val_ptr.* += delta;
            return val_ptr.*;
        } else {
            _ = self.put(key, delta);
            return delta;
        }
    }

    // ---- Conversion ----

    pub fn toImmutable(self: *const BoolI32HashMap) ImmutableBoolI32HashMap {
        return ImmutableBoolI32HashMap.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    pub fn withKeyValue(self: *BoolI32HashMap, key: bool, value: i32) *BoolI32HashMap {
        _ = self.put(key, value);
        return self;
    }

    pub fn withoutKey(self: *BoolI32HashMap, key: bool) *BoolI32HashMap {
        _ = self.remove(key);
        return self;
    }

    pub fn withoutAllKeys(self: *BoolI32HashMap, keys: []const bool) *BoolI32HashMap {
        for (keys) |key| _ = self.remove(key);
        return self;
    }

    // ---- Mutation Helpers ----

    pub fn updateValue(self: *BoolI32HashMap, key: bool, initial: i32, f: *const fn (i32) i32) i32 {
        const current = self.get(key) orelse initial;
        const new_value = f(current);
        _ = self.put(key, new_value);
        return new_value;
    }

    // ---- Formatting ----

    pub fn format(self: *const BoolI32HashMap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const BoolI32HashMap, other: *const BoolI32HashMap) bool {
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

test "BoolI32HashMap: put and get" {
    var m = BoolI32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1);
    _ = m.put(false, 2);

    try std.testing.expectEqual(@as(?i32, 1), m.get(true));

    try std.testing.expectEqual(@as(usize, 2), m.len());
}

test "BoolI32HashMap: put overwrite" {
    var m = BoolI32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1);
    const old = m.put(true, 2);
    try std.testing.expectEqual(@as(?i32, 1), old);
    try std.testing.expectEqual(@as(?i32, 2), m.get(true));
}

test "BoolI32HashMap: remove" {
    var m = BoolI32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1);
    _ = m.put(false, 2);
    const removed = m.remove(true);
    try std.testing.expectEqual(@as(?i32, 1), removed);
    try std.testing.expectEqual(@as(usize, 1), m.len());
    try std.testing.expect(!m.containsKey(true));
}

test "BoolI32HashMap: containsKey and containsValue" {
    var m = BoolI32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1);
    try std.testing.expect(m.containsKey(true));
    try std.testing.expect(!m.containsKey(false));
    try std.testing.expect(m.containsValue(1));
    try std.testing.expect(!m.containsValue(99));
}

test "BoolI32HashMap: getOrDefault" {
    var m = BoolI32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1);
    try std.testing.expectEqual(1, m.getOrDefault(true, 3));
    try std.testing.expectEqual(3, m.getOrDefault(false, 3));
}

test "BoolI32HashMap: clear" {
    var m = BoolI32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1);
    m.clear();
    try std.testing.expect(m.isEmpty());
}

test "BoolI32HashMap: select" {
    var m = BoolI32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1);
    _ = m.put(false, 2);
    var sel = m.select(struct {
        fn f(_: bool, v: i32) bool {
            return v == 1;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expect(sel.len() >= 1);
}

test "BoolI32HashMap: keysToSlice and valuesToSlice" {
    var m = BoolI32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1);
    _ = m.put(false, 2);
    const keys = m.keysToSlice(std.testing.allocator);
    defer std.testing.allocator.free(keys);
    try std.testing.expectEqual(@as(usize, 2), keys.len);
    const vals = m.valuesToSlice(std.testing.allocator);
    defer std.testing.allocator.free(vals);
    try std.testing.expectEqual(@as(usize, 2), vals.len);
}

test "BoolI32HashMap: sumOfValues" {
    var m = BoolI32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1);
    _ = m.put(false, 2);
    const s = m.sumOfValues();
    try std.testing.expect(s > 0);
}

test "BoolI32HashMap: addToValue" {
    var m = BoolI32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.addToValue(true, 1);
    _ = m.addToValue(true, 2);
    // Value should be sum of the two adds
    try std.testing.expect(m.get(true) != null);
}

test "BoolI32HashMap: toImmutable" {
    var m = BoolI32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1);
    _ = m.put(false, 2);
    var im = m.toImmutable();
    defer im.deinit();
    try std.testing.expectEqual(@as(usize, 2), im.len());
    _ = m.put(true, 3);
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "BoolI32HashMap: fluent withKeyValue/withoutKey" {
    var m = BoolI32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.withKeyValue(true, 1).withKeyValue(false, 2);
    try std.testing.expectEqual(@as(usize, 2), m.len());
    _ = m.withoutKey(true);
    try std.testing.expectEqual(@as(usize, 1), m.len());
}

test "BoolI32HashMap: eql" {
    var m1 = BoolI32HashMap.init(std.testing.allocator);
    defer m1.deinit();
    _ = m1.put(true, 1);
    _ = m1.put(false, 2);
    var m2 = BoolI32HashMap.init(std.testing.allocator);
    defer m2.deinit();
    _ = m2.put(false, 2);
    _ = m2.put(true, 1);
    try std.testing.expect(m1.eql(&m2));
}

test "BoolI32HashMap: resize" {
    var m = BoolI32HashMap.init(std.testing.allocator);
    defer m.deinit();
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        _ = m.put(i % 2 == 0, @as(i32, @intCast(i)));
    }
    try std.testing.expect(m.len() > 0);
}

test "BoolI32HashMap: entry orInsert" {
    var m = BoolI32HashMap.init(std.testing.allocator);
    defer m.deinit();
    // Key absent — inserts default
    const v1 = m.getEntry(true).orInsert(1);
    try std.testing.expectEqual(1, v1);
    // Key present — returns existing
    _ = m.put(true, 2);
    const v2 = m.getEntry(true).orInsert(3);
    try std.testing.expectEqual(2, v2);
}

test "BoolI32HashMap: entry andModify orInsert" {
    var m = BoolI32HashMap.init(std.testing.allocator);
    defer m.deinit();
    // Key absent: andModify is no-op, orInsert inserts
    _ = m.getEntry(true).andModify(struct {
        fn f(_: *i32) void {}
    }.f).orInsert(1);
    try std.testing.expectEqual(@as(?i32, 1), m.get(true));
}

test "BoolI32HashMap: ensureUnusedCapacity reserves and subsequent put does not resize" {
    var m = BoolI32HashMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(500);
    const reserved = m.inner.capacity;
    try std.testing.expect(reserved >= 500);
    _ = m.put(true, 1);
    _ = m.put(false, 2);
    try std.testing.expectEqual(reserved, m.inner.capacity);
}

test "BoolI32HashMap: ensureTotalCapacity is idempotent when capacity already sufficient" {
    var m = BoolI32HashMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureTotalCapacity(500);
    const reserved = m.inner.capacity;
    try m.ensureTotalCapacity(10);
    try std.testing.expectEqual(reserved, m.inner.capacity);
}

test "BoolI32HashMap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 1: HashMap.init allocates the backing hash table (1st alloc),
    // then ensureUnusedCapacity triggers a grow that fails (2nd alloc).
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var m = BoolI32HashMap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(10_000));
}
