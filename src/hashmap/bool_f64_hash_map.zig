
const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const ImmutableBoolF64HashMap = @import("../immutable/immutable_bool_f64_hash_map.zig").ImmutableBoolF64HashMap;

/// Hash map from `bool` keys to `f64` values.
///
/// Custom open-addressing with linear probing and Robin Hood backward-shift deletion.
/// Supports separate allocators for keys, values, and index buckets via AllocatorConfig.
pub const BoolF64HashMap = struct {
    inner: OpenHashMap(bool, f64),
    config: AllocatorConfig,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) BoolF64HashMap {
        return initWithConfig(AllocatorConfig.init(allocator));
    }

    /// Create with pre-allocated capacity.
    pub fn initWithCapacity(allocator: Allocator, capacity: usize) BoolF64HashMap {
        return .{
            .inner = OpenHashMap(bool, f64).initCapacity(allocator, capacity) catch @panic("out of memory"),
            .config = AllocatorConfig.init(allocator),
        };
    }

    /// Create with fine-grained allocator control.
    pub fn initWithConfig(config: AllocatorConfig) BoolF64HashMap {
        return .{
            .inner = OpenHashMap(bool, f64).init(
                config.keysAllocator(),
                config.valuesAllocator(),
                config.indexAllocator(),
            ) catch @panic("out of memory"),
            .config = config,
        };
    }

    pub fn deinit(self: *BoolF64HashMap) void {
        self.inner.deinit();
    }

    // ---- Core Operations ----

    /// Inserts a key-value pair. Returns the old value if the key was already present.
    pub fn put(self: *BoolF64HashMap, key: bool, value: f64) ?f64 {
        return self.inner.put(key, value) catch @panic("out of memory");
    }

    /// Returns the value for the key, or null.
    pub fn get(self: *const BoolF64HashMap, key: bool) ?f64 {
        return self.inner.get(key);
    }

    /// Returns the value for the key, or the default.
    pub fn getOrDefault(self: *const BoolF64HashMap, key: bool, default_value: f64) f64 {
        return self.get(key) orelse default_value;
    }

    /// Removes the key. Returns the old value if present.
    pub fn remove(self: *BoolF64HashMap, key: bool) ?f64 {
        return self.inner.remove(key);
    }

    pub fn containsKey(self: *const BoolF64HashMap, key: bool) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const BoolF64HashMap, value: f64) bool {
        return self.inner.containsValue(value);
    }

    // ---- Entry API ----

    /// Entry provides atomic check-and-modify operations for a single key.
    pub const Entry = struct {
        map_ptr: *BoolF64HashMap,
        key: bool,

        /// Inserts the default value if the key is absent. Returns the current value.
        pub fn orInsert(self: Entry, default_value: f64) f64 {
            if (self.map_ptr.get(self.key)) |existing| return existing;
            _ = self.map_ptr.put(self.key, default_value);
            return default_value;
        }

        /// Inserts the value from the function if the key is absent.
        pub fn orInsertWith(self: Entry, f: *const fn () f64) f64 {
            if (self.map_ptr.get(self.key)) |existing| return existing;
            const val = f();
            _ = self.map_ptr.put(self.key, val);
            return val;
        }

        /// Calls the function on a pointer to the value if the key is present.
        pub fn andModify(self: Entry, f: *const fn (*f64) void) Entry {
            if (self.map_ptr.inner.getPtr(self.key)) |val_ptr| {
                f(val_ptr);
            }
            return self;
        }
    };

    pub fn getEntry(self: *BoolF64HashMap, key: bool) Entry {
        return .{ .map_ptr = self, .key = key };
    }

    pub fn len(self: *const BoolF64HashMap) usize {
        return self.inner.len();
    }

    pub fn size(self: *const BoolF64HashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const BoolF64HashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn clear(self: *BoolF64HashMap) void {
        self.inner.clear();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more entries can be put without triggering
    /// a rehash. Returns `error.OutOfMemory` if the allocator fails. See
    /// `docs/zig/error-handling.md`.
    pub fn ensureUnusedCapacity(self: *BoolF64HashMap, additional: usize) Allocator.Error!void {
        return self.inner.ensureCapacity(additional);
    }

    /// Ensures the map's total capacity can fit at least `new_capacity`
    /// entries under the load factor without a rehash.
    pub fn ensureTotalCapacity(self: *BoolF64HashMap, new_capacity: usize) Allocator.Error!void {
        if (new_capacity <= self.inner.len()) return;
        return self.inner.ensureCapacity(new_capacity - self.inner.len());
    }

    // ---- Iteration ----

    pub fn forEach(self: *const BoolF64HashMap, f: *const fn (bool, f64) void) void {
        self.inner.forEach(f);
    }

    pub fn forEachKey(self: *const BoolF64HashMap, f: *const fn (bool) void) void {
        self.inner.forEachKey(f);
    }

    pub fn forEachValue(self: *const BoolF64HashMap, f: *const fn (f64) void) void {
        self.inner.forEachValue(f);
    }

    // ---- Functional Operations ----

    pub fn select(self: *const BoolF64HashMap, predicate: *const fn (bool, f64) bool) BoolF64HashMap {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return result;
    }

    pub fn reject(self: *const BoolF64HashMap, predicate: *const fn (bool, f64) bool) BoolF64HashMap {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (!predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return result;
    }

    pub fn detect(self: *const BoolF64HashMap, predicate: *const fn (bool, f64) bool) ?struct { key: bool, value: f64 } {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    return .{ .key = self.inner.entries[i].key, .value = self.inner.entries[i].value };
            }
        }
        return null;
    }

    pub fn anySatisfy(self: *const BoolF64HashMap, predicate: *const fn (bool, f64) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const BoolF64HashMap, predicate: *const fn (bool, f64) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and !predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const BoolF64HashMap, predicate: *const fn (bool, f64) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
        }
        return true;
    }

    pub fn count(self: *const BoolF64HashMap, predicate: *const fn (bool, f64) bool) usize {
        var c: usize = 0;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) c += 1;
        }
        return c;
    }

    pub fn injectInto(self: *const BoolF64HashMap, initial: f64, f: *const fn (f64, bool, f64) f64) f64 {
        var acc = initial;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) acc = f(acc, self.inner.entries[i].key, self.inner.entries[i].value);
        }
        return acc;
    }

    // ---- Key/Value Collection ----

    pub fn keysToSlice(self: *const BoolF64HashMap, allocator: Allocator) []bool {
        return self.inner.keysToSlice(allocator) catch @panic("out of memory");
    }

    pub fn valuesToSlice(self: *const BoolF64HashMap, allocator: Allocator) []f64 {
        return self.inner.valuesToSlice(allocator) catch @panic("out of memory");
    }

    // ---- Numeric Value Operations ----

    pub fn sumOfValues(self: *const BoolF64HashMap) f64 {
        var total: f64 = 0;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) total += self.inner.entries[i].value;
        }
        return total;
    }

    pub fn addToValue(self: *BoolF64HashMap, key: bool, delta: f64) f64 {
        if (self.inner.getPtr(key)) |val_ptr| {
            val_ptr.* += delta;
            return val_ptr.*;
        } else {
            _ = self.put(key, delta);
            return delta;
        }
    }

    // ---- Conversion ----

    pub fn toImmutable(self: *const BoolF64HashMap) ImmutableBoolF64HashMap {
        return ImmutableBoolF64HashMap.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    pub fn withKeyValue(self: *BoolF64HashMap, key: bool, value: f64) *BoolF64HashMap {
        _ = self.put(key, value);
        return self;
    }

    pub fn withoutKey(self: *BoolF64HashMap, key: bool) *BoolF64HashMap {
        _ = self.remove(key);
        return self;
    }

    pub fn withoutAllKeys(self: *BoolF64HashMap, keys: []const bool) *BoolF64HashMap {
        for (keys) |key| _ = self.remove(key);
        return self;
    }

    // ---- Mutation Helpers ----

    pub fn updateValue(self: *BoolF64HashMap, key: bool, initial: f64, f: *const fn (f64) f64) f64 {
        const current = self.get(key) orelse initial;
        const new_value = f(current);
        _ = self.put(key, new_value);
        return new_value;
    }

    // ---- Formatting ----

    pub fn format(self: *const BoolF64HashMap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const BoolF64HashMap, other: *const BoolF64HashMap) bool {
        if (self.len() != other.len()) return false;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const other_val = other.get(self.inner.entries[i].key) orelse return false;
                if (!(@as(u64, @bitCast(self.inner.entries[i].value)) == @as(u64, @bitCast(other_val)))) return false;
            }
        }
        return true;
    }
};

// ---- Tests ----

test "BoolF64HashMap: put and get" {
    var m = BoolF64HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1.0);
    _ = m.put(false, 2.0);

    try std.testing.expectEqual(@as(?f64, 1.0), m.get(true));

    try std.testing.expectEqual(@as(usize, 2), m.len());
}

test "BoolF64HashMap: put overwrite" {
    var m = BoolF64HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1.0);
    const old = m.put(true, 2.0);
    try std.testing.expectEqual(@as(?f64, 1.0), old);
    try std.testing.expectEqual(@as(?f64, 2.0), m.get(true));
}

test "BoolF64HashMap: remove" {
    var m = BoolF64HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1.0);
    _ = m.put(false, 2.0);
    const removed = m.remove(true);
    try std.testing.expectEqual(@as(?f64, 1.0), removed);
    try std.testing.expectEqual(@as(usize, 1), m.len());
    try std.testing.expect(!m.containsKey(true));
}

test "BoolF64HashMap: containsKey and containsValue" {
    var m = BoolF64HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1.0);
    try std.testing.expect(m.containsKey(true));
    try std.testing.expect(!m.containsKey(false));
    try std.testing.expect(m.containsValue(1.0));
    try std.testing.expect(!m.containsValue(99.0));
}

test "BoolF64HashMap: getOrDefault" {
    var m = BoolF64HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1.0);
    try std.testing.expectEqual(1.0, m.getOrDefault(true, 3.0));
    try std.testing.expectEqual(3.0, m.getOrDefault(false, 3.0));
}

test "BoolF64HashMap: clear" {
    var m = BoolF64HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1.0);
    m.clear();
    try std.testing.expect(m.isEmpty());
}

test "BoolF64HashMap: select" {
    var m = BoolF64HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1.0);
    _ = m.put(false, 2.0);
    var sel = m.select(struct {
        fn f(_: bool, v: f64) bool {
            return v == 1.0;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expect(sel.len() >= 1);
}

test "BoolF64HashMap: keysToSlice and valuesToSlice" {
    var m = BoolF64HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1.0);
    _ = m.put(false, 2.0);
    const keys = m.keysToSlice(std.testing.allocator);
    defer std.testing.allocator.free(keys);
    try std.testing.expectEqual(@as(usize, 2), keys.len);
    const vals = m.valuesToSlice(std.testing.allocator);
    defer std.testing.allocator.free(vals);
    try std.testing.expectEqual(@as(usize, 2), vals.len);
}

test "BoolF64HashMap: sumOfValues" {
    var m = BoolF64HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1.0);
    _ = m.put(false, 2.0);
    const s = m.sumOfValues();
    try std.testing.expect(s > 0);
}

test "BoolF64HashMap: addToValue" {
    var m = BoolF64HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.addToValue(true, 1.0);
    _ = m.addToValue(true, 2.0);
    // Value should be sum of the two adds
    try std.testing.expect(m.get(true) != null);
}

test "BoolF64HashMap: toImmutable" {
    var m = BoolF64HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1.0);
    _ = m.put(false, 2.0);
    var im = m.toImmutable();
    defer im.deinit();
    try std.testing.expectEqual(@as(usize, 2), im.len());
    _ = m.put(true, 3.0);
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "BoolF64HashMap: fluent withKeyValue/withoutKey" {
    var m = BoolF64HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.withKeyValue(true, 1.0).withKeyValue(false, 2.0);
    try std.testing.expectEqual(@as(usize, 2), m.len());
    _ = m.withoutKey(true);
    try std.testing.expectEqual(@as(usize, 1), m.len());
}

test "BoolF64HashMap: eql" {
    var m1 = BoolF64HashMap.init(std.testing.allocator);
    defer m1.deinit();
    _ = m1.put(true, 1.0);
    _ = m1.put(false, 2.0);
    var m2 = BoolF64HashMap.init(std.testing.allocator);
    defer m2.deinit();
    _ = m2.put(false, 2.0);
    _ = m2.put(true, 1.0);
    try std.testing.expect(m1.eql(&m2));
}

test "BoolF64HashMap: resize" {
    var m = BoolF64HashMap.init(std.testing.allocator);
    defer m.deinit();
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        _ = m.put(i % 2 == 0, @as(f64, @floatFromInt(i)));
    }
    try std.testing.expect(m.len() > 0);
}

test "BoolF64HashMap: entry orInsert" {
    var m = BoolF64HashMap.init(std.testing.allocator);
    defer m.deinit();
    // Key absent — inserts default
    const v1 = m.getEntry(true).orInsert(1.0);
    try std.testing.expectEqual(1.0, v1);
    // Key present — returns existing
    _ = m.put(true, 2.0);
    const v2 = m.getEntry(true).orInsert(3.0);
    try std.testing.expectEqual(2.0, v2);
}

test "BoolF64HashMap: entry andModify orInsert" {
    var m = BoolF64HashMap.init(std.testing.allocator);
    defer m.deinit();
    // Key absent: andModify is no-op, orInsert inserts
    _ = m.getEntry(true).andModify(struct {
        fn f(_: *f64) void {}
    }.f).orInsert(1.0);
    try std.testing.expectEqual(@as(?f64, 1.0), m.get(true));
}

test "BoolF64HashMap: ensureUnusedCapacity reserves and subsequent put does not resize" {
    var m = BoolF64HashMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(500);
    const reserved = m.inner.capacity;
    try std.testing.expect(reserved >= 500);
    _ = m.put(true, 1.0);
    _ = m.put(false, 2.0);
    try std.testing.expectEqual(reserved, m.inner.capacity);
}

test "BoolF64HashMap: ensureTotalCapacity is idempotent when capacity already sufficient" {
    var m = BoolF64HashMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureTotalCapacity(500);
    const reserved = m.inner.capacity;
    try m.ensureTotalCapacity(10);
    try std.testing.expectEqual(reserved, m.inner.capacity);
}

test "BoolF64HashMap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 1: HashMap.init allocates the backing hash table (1st alloc),
    // then ensureUnusedCapacity triggers a grow that fails (2nd alloc).
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var m = BoolF64HashMap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(10_000));
}
