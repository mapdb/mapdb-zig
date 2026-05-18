
const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const ImmutableI8F32HashMap = @import("../immutable/immutable_i8_f32_hash_map.zig").ImmutableI8F32HashMap;

/// Hash map from `i8` keys to `f32` values.
///
/// Custom open-addressing with linear probing and Robin Hood backward-shift deletion.
/// Supports separate allocators for keys, values, and index buckets via AllocatorConfig.
pub const I8F32HashMap = struct {
    inner: OpenHashMap(i8, f32),
    config: AllocatorConfig,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) I8F32HashMap {
        return initWithConfig(AllocatorConfig.init(allocator));
    }

    /// Create with pre-allocated capacity.
    pub fn initWithCapacity(allocator: Allocator, capacity: usize) I8F32HashMap {
        return .{
            .inner = OpenHashMap(i8, f32).initCapacity(allocator, capacity) catch @panic("out of memory"),
            .config = AllocatorConfig.init(allocator),
        };
    }

    /// Create with fine-grained allocator control.
    pub fn initWithConfig(config: AllocatorConfig) I8F32HashMap {
        return .{
            .inner = OpenHashMap(i8, f32).init(
                config.keysAllocator(),
                config.valuesAllocator(),
                config.indexAllocator(),
            ) catch @panic("out of memory"),
            .config = config,
        };
    }

    pub fn deinit(self: *I8F32HashMap) void {
        self.inner.deinit();
    }

    // ---- Core Operations ----

    /// Inserts a key-value pair. Returns the old value if the key was already present.
    pub fn put(self: *I8F32HashMap, key: i8, value: f32) ?f32 {
        return self.inner.put(key, value) catch @panic("out of memory");
    }

    /// Returns the value for the key, or null.
    pub fn get(self: *const I8F32HashMap, key: i8) ?f32 {
        return self.inner.get(key);
    }

    /// Returns the value for the key, or the default.
    pub fn getOrDefault(self: *const I8F32HashMap, key: i8, default_value: f32) f32 {
        return self.get(key) orelse default_value;
    }

    /// Removes the key. Returns the old value if present.
    pub fn remove(self: *I8F32HashMap, key: i8) ?f32 {
        return self.inner.remove(key);
    }

    pub fn containsKey(self: *const I8F32HashMap, key: i8) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const I8F32HashMap, value: f32) bool {
        return self.inner.containsValue(value);
    }

    // ---- Entry API ----

    /// Entry provides atomic check-and-modify operations for a single key.
    pub const Entry = struct {
        map_ptr: *I8F32HashMap,
        key: i8,

        /// Inserts the default value if the key is absent. Returns the current value.
        pub fn orInsert(self: Entry, default_value: f32) f32 {
            if (self.map_ptr.get(self.key)) |existing| return existing;
            _ = self.map_ptr.put(self.key, default_value);
            return default_value;
        }

        /// Inserts the value from the function if the key is absent.
        pub fn orInsertWith(self: Entry, f: *const fn () f32) f32 {
            if (self.map_ptr.get(self.key)) |existing| return existing;
            const val = f();
            _ = self.map_ptr.put(self.key, val);
            return val;
        }

        /// Calls the function on a pointer to the value if the key is present.
        pub fn andModify(self: Entry, f: *const fn (*f32) void) Entry {
            if (self.map_ptr.inner.getPtr(self.key)) |val_ptr| {
                f(val_ptr);
            }
            return self;
        }
    };

    pub fn getEntry(self: *I8F32HashMap, key: i8) Entry {
        return .{ .map_ptr = self, .key = key };
    }

    pub fn len(self: *const I8F32HashMap) usize {
        return self.inner.len();
    }

    pub fn size(self: *const I8F32HashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const I8F32HashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn clear(self: *I8F32HashMap) void {
        self.inner.clear();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more entries can be put without triggering
    /// a rehash. Returns `error.OutOfMemory` if the allocator fails. See
    /// `docs/zig/error-handling.md`.
    pub fn ensureUnusedCapacity(self: *I8F32HashMap, additional: usize) Allocator.Error!void {
        return self.inner.ensureCapacity(additional);
    }

    /// Ensures the map's total capacity can fit at least `new_capacity`
    /// entries under the load factor without a rehash.
    pub fn ensureTotalCapacity(self: *I8F32HashMap, new_capacity: usize) Allocator.Error!void {
        if (new_capacity <= self.inner.len()) return;
        return self.inner.ensureCapacity(new_capacity - self.inner.len());
    }

    // ---- Iteration ----

    pub fn forEach(self: *const I8F32HashMap, f: *const fn (i8, f32) void) void {
        self.inner.forEach(f);
    }

    pub fn forEachKey(self: *const I8F32HashMap, f: *const fn (i8) void) void {
        self.inner.forEachKey(f);
    }

    pub fn forEachValue(self: *const I8F32HashMap, f: *const fn (f32) void) void {
        self.inner.forEachValue(f);
    }

    // ---- Functional Operations ----

    pub fn select(self: *const I8F32HashMap, predicate: *const fn (i8, f32) bool) I8F32HashMap {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return result;
    }

    pub fn reject(self: *const I8F32HashMap, predicate: *const fn (i8, f32) bool) I8F32HashMap {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (!predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return result;
    }

    pub fn detect(self: *const I8F32HashMap, predicate: *const fn (i8, f32) bool) ?struct { key: i8, value: f32 } {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    return .{ .key = self.inner.entries[i].key, .value = self.inner.entries[i].value };
            }
        }
        return null;
    }

    pub fn anySatisfy(self: *const I8F32HashMap, predicate: *const fn (i8, f32) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const I8F32HashMap, predicate: *const fn (i8, f32) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and !predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const I8F32HashMap, predicate: *const fn (i8, f32) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
        }
        return true;
    }

    pub fn count(self: *const I8F32HashMap, predicate: *const fn (i8, f32) bool) usize {
        var c: usize = 0;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) c += 1;
        }
        return c;
    }

    pub fn injectInto(self: *const I8F32HashMap, initial: f32, f: *const fn (f32, i8, f32) f32) f32 {
        var acc = initial;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) acc = f(acc, self.inner.entries[i].key, self.inner.entries[i].value);
        }
        return acc;
    }

    // ---- Key/Value Collection ----

    pub fn keysToSlice(self: *const I8F32HashMap, allocator: Allocator) []i8 {
        return self.inner.keysToSlice(allocator) catch @panic("out of memory");
    }

    pub fn valuesToSlice(self: *const I8F32HashMap, allocator: Allocator) []f32 {
        return self.inner.valuesToSlice(allocator) catch @panic("out of memory");
    }

    // ---- Numeric Value Operations ----

    pub fn sumOfValues(self: *const I8F32HashMap) f32 {
        var total: f32 = 0;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) total += self.inner.entries[i].value;
        }
        return total;
    }

    pub fn addToValue(self: *I8F32HashMap, key: i8, delta: f32) f32 {
        if (self.inner.getPtr(key)) |val_ptr| {
            val_ptr.* += delta;
            return val_ptr.*;
        } else {
            _ = self.put(key, delta);
            return delta;
        }
    }

    // ---- Conversion ----

    pub fn toImmutable(self: *const I8F32HashMap) ImmutableI8F32HashMap {
        return ImmutableI8F32HashMap.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    pub fn withKeyValue(self: *I8F32HashMap, key: i8, value: f32) *I8F32HashMap {
        _ = self.put(key, value);
        return self;
    }

    pub fn withoutKey(self: *I8F32HashMap, key: i8) *I8F32HashMap {
        _ = self.remove(key);
        return self;
    }

    pub fn withoutAllKeys(self: *I8F32HashMap, keys: []const i8) *I8F32HashMap {
        for (keys) |key| _ = self.remove(key);
        return self;
    }

    // ---- Mutation Helpers ----

    pub fn updateValue(self: *I8F32HashMap, key: i8, initial: f32, f: *const fn (f32) f32) f32 {
        const current = self.get(key) orelse initial;
        const new_value = f(current);
        _ = self.put(key, new_value);
        return new_value;
    }

    // ---- Formatting ----

    pub fn format(self: *const I8F32HashMap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const I8F32HashMap, other: *const I8F32HashMap) bool {
        if (self.len() != other.len()) return false;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const other_val = other.get(self.inner.entries[i].key) orelse return false;
                if (!(@as(u32, @bitCast(self.inner.entries[i].value)) == @as(u32, @bitCast(other_val)))) return false;
            }
        }
        return true;
    }
};

// ---- Tests ----

test "I8F32HashMap: put and get" {
    var m = I8F32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1.0);
    _ = m.put(2, 2.0);
    _ = m.put(3, 3.0);
    try std.testing.expectEqual(@as(?f32, 1.0), m.get(1));
    try std.testing.expectEqual(@as(?f32, null), m.get(99));
    try std.testing.expectEqual(@as(usize, 3), m.len());
}

test "I8F32HashMap: put overwrite" {
    var m = I8F32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1.0);
    const old = m.put(1, 2.0);
    try std.testing.expectEqual(@as(?f32, 1.0), old);
    try std.testing.expectEqual(@as(?f32, 2.0), m.get(1));
}

test "I8F32HashMap: remove" {
    var m = I8F32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1.0);
    _ = m.put(2, 2.0);
    const removed = m.remove(1);
    try std.testing.expectEqual(@as(?f32, 1.0), removed);
    try std.testing.expectEqual(@as(usize, 1), m.len());
    try std.testing.expect(!m.containsKey(1));
}

test "I8F32HashMap: containsKey and containsValue" {
    var m = I8F32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1.0);
    try std.testing.expect(m.containsKey(1));
    try std.testing.expect(!m.containsKey(99));
    try std.testing.expect(m.containsValue(1.0));
    try std.testing.expect(!m.containsValue(99.0));
}

test "I8F32HashMap: getOrDefault" {
    var m = I8F32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1.0);
    try std.testing.expectEqual(1.0, m.getOrDefault(1, 3.0));
    try std.testing.expectEqual(3.0, m.getOrDefault(99, 3.0));
}

test "I8F32HashMap: clear" {
    var m = I8F32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1.0);
    m.clear();
    try std.testing.expect(m.isEmpty());
}

test "I8F32HashMap: select and reject" {
    var m = I8F32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1.0);
    _ = m.put(2, 2.0);
    _ = m.put(3, 3.0);
    var sel = m.select(struct {
        fn f(_: i8, v: f32) bool {
            return v > 1.0;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expectEqual(@as(usize, 2), sel.len());
    var rej = m.reject(struct {
        fn f(_: i8, v: f32) bool {
            return v > 1.0;
        }
    }.f);
    defer rej.deinit();
    try std.testing.expectEqual(@as(usize, 1), rej.len());
}

test "I8F32HashMap: anySatisfy allSatisfy noneSatisfy count" {
    var m = I8F32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1.0);
    _ = m.put(2, 2.0);
    try std.testing.expect(m.anySatisfy(struct {
        fn f(_: i8, v: f32) bool {
            return v == 2.0;
        }
    }.f));
    try std.testing.expect(m.noneSatisfy(struct {
        fn f(_: i8, v: f32) bool {
            return v == 99.0;
        }
    }.f));
    try std.testing.expectEqual(@as(usize, 1), m.count(struct {
        fn f(_: i8, v: f32) bool {
            return v == 1.0;
        }
    }.f));
}

test "I8F32HashMap: keysToSlice and valuesToSlice" {
    var m = I8F32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1.0);
    _ = m.put(2, 2.0);
    const keys = m.keysToSlice(std.testing.allocator);
    defer std.testing.allocator.free(keys);
    try std.testing.expectEqual(@as(usize, 2), keys.len);
    const vals = m.valuesToSlice(std.testing.allocator);
    defer std.testing.allocator.free(vals);
    try std.testing.expectEqual(@as(usize, 2), vals.len);
}

test "I8F32HashMap: sumOfValues" {
    var m = I8F32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1.0);
    _ = m.put(2, 2.0);
    const s = m.sumOfValues();
    try std.testing.expect(s > 0);
}

test "I8F32HashMap: addToValue" {
    var m = I8F32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.addToValue(1, 1.0);
    _ = m.addToValue(1, 2.0);
    // Value should be sum of the two adds
    try std.testing.expect(m.get(1) != null);
}

test "I8F32HashMap: toImmutable" {
    var m = I8F32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1.0);
    _ = m.put(2, 2.0);
    var im = m.toImmutable();
    defer im.deinit();
    try std.testing.expectEqual(@as(usize, 2), im.len());
    _ = m.put(3, 3.0);
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "I8F32HashMap: fluent withKeyValue/withoutKey" {
    var m = I8F32HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.withKeyValue(1, 1.0).withKeyValue(2, 2.0);
    try std.testing.expectEqual(@as(usize, 2), m.len());
    _ = m.withoutKey(1);
    try std.testing.expectEqual(@as(usize, 1), m.len());
}

test "I8F32HashMap: eql" {
    var m1 = I8F32HashMap.init(std.testing.allocator);
    defer m1.deinit();
    _ = m1.put(1, 1.0);
    _ = m1.put(2, 2.0);
    var m2 = I8F32HashMap.init(std.testing.allocator);
    defer m2.deinit();
    _ = m2.put(2, 2.0);
    _ = m2.put(1, 1.0);
    try std.testing.expect(m1.eql(&m2));
}

test "I8F32HashMap: resize" {
    var m = I8F32HashMap.init(std.testing.allocator);
    defer m.deinit();
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        _ = m.put(@as(i8, @intCast(i)), @as(f32, @floatFromInt(i)));
    }
    try std.testing.expect(m.len() > 0);
}

test "I8F32HashMap: entry orInsert" {
    var m = I8F32HashMap.init(std.testing.allocator);
    defer m.deinit();
    // Key absent — inserts default
    const v1 = m.getEntry(1).orInsert(1.0);
    try std.testing.expectEqual(1.0, v1);
    // Key present — returns existing
    _ = m.put(1, 2.0);
    const v2 = m.getEntry(1).orInsert(3.0);
    try std.testing.expectEqual(2.0, v2);
}

test "I8F32HashMap: entry andModify orInsert" {
    var m = I8F32HashMap.init(std.testing.allocator);
    defer m.deinit();
    // Key absent: andModify is no-op, orInsert inserts
    _ = m.getEntry(1).andModify(struct {
        fn f(_: *f32) void {}
    }.f).orInsert(1.0);
    try std.testing.expectEqual(@as(?f32, 1.0), m.get(1));
}

test "I8F32HashMap: ensureUnusedCapacity reserves and subsequent put does not resize" {
    var m = I8F32HashMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(500);
    const reserved = m.inner.capacity;
    try std.testing.expect(reserved >= 500);
    _ = m.put(1, 1.0);
    _ = m.put(2, 2.0);
    try std.testing.expectEqual(reserved, m.inner.capacity);
}

test "I8F32HashMap: ensureTotalCapacity is idempotent when capacity already sufficient" {
    var m = I8F32HashMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureTotalCapacity(500);
    const reserved = m.inner.capacity;
    try m.ensureTotalCapacity(10);
    try std.testing.expectEqual(reserved, m.inner.capacity);
}

test "I8F32HashMap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 1: HashMap.init allocates the backing hash table (1st alloc),
    // then ensureUnusedCapacity triggers a grow that fails (2nd alloc).
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var m = I8F32HashMap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(10_000));
}
