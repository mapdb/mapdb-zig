
const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const ImmutableI32CharHashMap = @import("../immutable/immutable_i32_char_hash_map.zig").ImmutableI32CharHashMap;

/// Hash map from `i32` keys to `u21` values.
///
/// Custom open-addressing with linear probing and Robin Hood backward-shift deletion.
/// Supports separate allocators for keys, values, and index buckets via AllocatorConfig.
pub const I32CharHashMap = struct {
    inner: OpenHashMap(i32, u21),
    config: AllocatorConfig,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) I32CharHashMap {
        return initWithConfig(AllocatorConfig.init(allocator));
    }

    /// Create with pre-allocated capacity.
    pub fn initWithCapacity(allocator: Allocator, capacity: usize) I32CharHashMap {
        return .{
            .inner = OpenHashMap(i32, u21).initCapacity(allocator, capacity) catch @panic("out of memory"),
            .config = AllocatorConfig.init(allocator),
        };
    }

    /// Create with fine-grained allocator control.
    pub fn initWithConfig(config: AllocatorConfig) I32CharHashMap {
        return .{
            .inner = OpenHashMap(i32, u21).init(
                config.keysAllocator(),
                config.valuesAllocator(),
                config.indexAllocator(),
            ) catch @panic("out of memory"),
            .config = config,
        };
    }

    pub fn deinit(self: *I32CharHashMap) void {
        self.inner.deinit();
    }

    // ---- Core Operations ----

    /// Inserts a key-value pair. Returns the old value if the key was already present.
    pub fn put(self: *I32CharHashMap, key: i32, value: u21) ?u21 {
        return self.inner.put(key, value) catch @panic("out of memory");
    }

    /// Returns the value for the key, or null.
    pub fn get(self: *const I32CharHashMap, key: i32) ?u21 {
        return self.inner.get(key);
    }

    /// Returns the value for the key, or the default.
    pub fn getOrDefault(self: *const I32CharHashMap, key: i32, default_value: u21) u21 {
        return self.get(key) orelse default_value;
    }

    /// Removes the key. Returns the old value if present.
    pub fn remove(self: *I32CharHashMap, key: i32) ?u21 {
        return self.inner.remove(key);
    }

    pub fn containsKey(self: *const I32CharHashMap, key: i32) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const I32CharHashMap, value: u21) bool {
        return self.inner.containsValue(value);
    }

    // ---- Entry API ----

    /// Entry provides atomic check-and-modify operations for a single key.
    pub const Entry = struct {
        map_ptr: *I32CharHashMap,
        key: i32,

        /// Inserts the default value if the key is absent. Returns the current value.
        pub fn orInsert(self: Entry, default_value: u21) u21 {
            if (self.map_ptr.get(self.key)) |existing| return existing;
            _ = self.map_ptr.put(self.key, default_value);
            return default_value;
        }

        /// Inserts the value from the function if the key is absent.
        pub fn orInsertWith(self: Entry, f: *const fn () u21) u21 {
            if (self.map_ptr.get(self.key)) |existing| return existing;
            const val = f();
            _ = self.map_ptr.put(self.key, val);
            return val;
        }

        /// Calls the function on a pointer to the value if the key is present.
        pub fn andModify(self: Entry, f: *const fn (*u21) void) Entry {
            if (self.map_ptr.inner.getPtr(self.key)) |val_ptr| {
                f(val_ptr);
            }
            return self;
        }
    };

    pub fn getEntry(self: *I32CharHashMap, key: i32) Entry {
        return .{ .map_ptr = self, .key = key };
    }

    pub fn len(self: *const I32CharHashMap) usize {
        return self.inner.len();
    }

    pub fn size(self: *const I32CharHashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const I32CharHashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn clear(self: *I32CharHashMap) void {
        self.inner.clear();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more entries can be put without triggering
    /// a rehash. Returns `error.OutOfMemory` if the allocator fails.
    pub fn ensureUnusedCapacity(self: *I32CharHashMap, additional: usize) Allocator.Error!void {
        return self.inner.ensureCapacity(additional);
    }

    /// Ensures the map's total capacity can fit at least `new_capacity`
    /// entries under the load factor without a rehash.
    pub fn ensureTotalCapacity(self: *I32CharHashMap, new_capacity: usize) Allocator.Error!void {
        if (new_capacity <= self.inner.len()) return;
        return self.inner.ensureCapacity(new_capacity - self.inner.len());
    }

    // ---- Iteration ----

    pub fn forEach(self: *const I32CharHashMap, f: *const fn (i32, u21) void) void {
        self.inner.forEach(f);
    }

    pub fn forEachKey(self: *const I32CharHashMap, f: *const fn (i32) void) void {
        self.inner.forEachKey(f);
    }

    pub fn forEachValue(self: *const I32CharHashMap, f: *const fn (u21) void) void {
        self.inner.forEachValue(f);
    }

    // ---- Functional Operations ----

    pub fn select(self: *const I32CharHashMap, predicate: *const fn (i32, u21) bool) I32CharHashMap {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return result;
    }

    pub fn reject(self: *const I32CharHashMap, predicate: *const fn (i32, u21) bool) I32CharHashMap {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (!predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return result;
    }

    pub fn detect(self: *const I32CharHashMap, predicate: *const fn (i32, u21) bool) ?struct { key: i32, value: u21 } {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    return .{ .key = self.inner.entries[i].key, .value = self.inner.entries[i].value };
            }
        }
        return null;
    }

    pub fn anySatisfy(self: *const I32CharHashMap, predicate: *const fn (i32, u21) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const I32CharHashMap, predicate: *const fn (i32, u21) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and !predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const I32CharHashMap, predicate: *const fn (i32, u21) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
        }
        return true;
    }

    pub fn count(self: *const I32CharHashMap, predicate: *const fn (i32, u21) bool) usize {
        var c: usize = 0;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) c += 1;
        }
        return c;
    }

    pub fn injectInto(self: *const I32CharHashMap, initial: u21, f: *const fn (u21, i32, u21) u21) u21 {
        var acc = initial;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) acc = f(acc, self.inner.entries[i].key, self.inner.entries[i].value);
        }
        return acc;
    }

    // ---- Key/Value Collection ----

    pub fn keysToSlice(self: *const I32CharHashMap, allocator: Allocator) []i32 {
        return self.inner.keysToSlice(allocator) catch @panic("out of memory");
    }

    pub fn valuesToSlice(self: *const I32CharHashMap, allocator: Allocator) []u21 {
        return self.inner.valuesToSlice(allocator) catch @panic("out of memory");
    }

    // ---- Conversion ----

    pub fn toImmutable(self: *const I32CharHashMap) ImmutableI32CharHashMap {
        return ImmutableI32CharHashMap.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    pub fn withKeyValue(self: *I32CharHashMap, key: i32, value: u21) *I32CharHashMap {
        _ = self.put(key, value);
        return self;
    }

    pub fn withoutKey(self: *I32CharHashMap, key: i32) *I32CharHashMap {
        _ = self.remove(key);
        return self;
    }

    pub fn withoutAllKeys(self: *I32CharHashMap, keys: []const i32) *I32CharHashMap {
        for (keys) |key| _ = self.remove(key);
        return self;
    }

    // ---- Mutation Helpers ----

    pub fn updateValue(self: *I32CharHashMap, key: i32, initial: u21, f: *const fn (u21) u21) u21 {
        const current = self.get(key) orelse initial;
        const new_value = f(current);
        _ = self.put(key, new_value);
        return new_value;
    }

    // ---- Formatting ----

    pub fn format(self: *const I32CharHashMap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const I32CharHashMap, other: *const I32CharHashMap) bool {
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

test "I32CharHashMap: put and get" {
    var m = I32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 'a');
    _ = m.put(2, 'b');
    _ = m.put(3, 'c');
    try std.testing.expectEqual(@as(?u21, 'a'), m.get(1));
    try std.testing.expectEqual(@as(?u21, null), m.get(99));
    try std.testing.expectEqual(@as(usize, 3), m.len());
}

test "I32CharHashMap: put overwrite" {
    var m = I32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 'a');
    const old = m.put(1, 'b');
    try std.testing.expectEqual(@as(?u21, 'a'), old);
    try std.testing.expectEqual(@as(?u21, 'b'), m.get(1));
}

test "I32CharHashMap: remove" {
    var m = I32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 'a');
    _ = m.put(2, 'b');
    const removed = m.remove(1);
    try std.testing.expectEqual(@as(?u21, 'a'), removed);
    try std.testing.expectEqual(@as(usize, 1), m.len());
    try std.testing.expect(!m.containsKey(1));
}

test "I32CharHashMap: containsKey and containsValue" {
    var m = I32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 'a');
    try std.testing.expect(m.containsKey(1));
    try std.testing.expect(!m.containsKey(99));
    try std.testing.expect(m.containsValue('a'));
    try std.testing.expect(!m.containsValue('z'));
}

test "I32CharHashMap: getOrDefault" {
    var m = I32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 'a');
    try std.testing.expectEqual('a', m.getOrDefault(1, 'c'));
    try std.testing.expectEqual('c', m.getOrDefault(99, 'c'));
}

test "I32CharHashMap: clear" {
    var m = I32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 'a');
    m.clear();
    try std.testing.expect(m.isEmpty());
}

test "I32CharHashMap: select and reject" {
    var m = I32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 'a');
    _ = m.put(2, 'b');
    _ = m.put(3, 'c');
    var sel = m.select(struct {
        fn f(_: i32, v: u21) bool {
            return v > 'a';
        }
    }.f);
    defer sel.deinit();
    try std.testing.expectEqual(@as(usize, 2), sel.len());
    var rej = m.reject(struct {
        fn f(_: i32, v: u21) bool {
            return v > 'a';
        }
    }.f);
    defer rej.deinit();
    try std.testing.expectEqual(@as(usize, 1), rej.len());
}

test "I32CharHashMap: anySatisfy allSatisfy noneSatisfy count" {
    var m = I32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 'a');
    _ = m.put(2, 'b');
    try std.testing.expect(m.anySatisfy(struct {
        fn f(_: i32, v: u21) bool {
            return v == 'b';
        }
    }.f));
    try std.testing.expect(m.noneSatisfy(struct {
        fn f(_: i32, v: u21) bool {
            return v == 'z';
        }
    }.f));
    try std.testing.expectEqual(@as(usize, 1), m.count(struct {
        fn f(_: i32, v: u21) bool {
            return v == 'a';
        }
    }.f));
}

test "I32CharHashMap: keysToSlice and valuesToSlice" {
    var m = I32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 'a');
    _ = m.put(2, 'b');
    const keys = m.keysToSlice(std.testing.allocator);
    defer std.testing.allocator.free(keys);
    try std.testing.expectEqual(@as(usize, 2), keys.len);
    const vals = m.valuesToSlice(std.testing.allocator);
    defer std.testing.allocator.free(vals);
    try std.testing.expectEqual(@as(usize, 2), vals.len);
}

test "I32CharHashMap: toImmutable" {
    var m = I32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 'a');
    _ = m.put(2, 'b');
    var im = m.toImmutable();
    defer im.deinit();
    try std.testing.expectEqual(@as(usize, 2), im.len());
    _ = m.put(3, 'c');
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "I32CharHashMap: fluent withKeyValue/withoutKey" {
    var m = I32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.withKeyValue(1, 'a').withKeyValue(2, 'b');
    try std.testing.expectEqual(@as(usize, 2), m.len());
    _ = m.withoutKey(1);
    try std.testing.expectEqual(@as(usize, 1), m.len());
}

test "I32CharHashMap: eql" {
    var m1 = I32CharHashMap.init(std.testing.allocator);
    defer m1.deinit();
    _ = m1.put(1, 'a');
    _ = m1.put(2, 'b');
    var m2 = I32CharHashMap.init(std.testing.allocator);
    defer m2.deinit();
    _ = m2.put(2, 'b');
    _ = m2.put(1, 'a');
    try std.testing.expect(m1.eql(&m2));
}

test "I32CharHashMap: resize" {
    var m = I32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        _ = m.put(@as(i32, @intCast(i)), @as(u21, @intCast(i % 26)) + 'A');
    }
    try std.testing.expect(m.len() > 0);
}

test "I32CharHashMap: entry orInsert" {
    var m = I32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    // Key absent — inserts default
    const v1 = m.getEntry(1).orInsert('a');
    try std.testing.expectEqual('a', v1);
    // Key present — returns existing
    _ = m.put(1, 'b');
    const v2 = m.getEntry(1).orInsert('c');
    try std.testing.expectEqual('b', v2);
}

test "I32CharHashMap: entry andModify orInsert" {
    var m = I32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    // Key absent: andModify is no-op, orInsert inserts
    _ = m.getEntry(1).andModify(struct {
        fn f(_: *u21) void {}
    }.f).orInsert('a');
    try std.testing.expectEqual(@as(?u21, 'a'), m.get(1));
}

test "I32CharHashMap: ensureUnusedCapacity reserves and subsequent put does not resize" {
    var m = I32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(500);
    const reserved = m.inner.capacity;
    try std.testing.expect(reserved >= 500);
    _ = m.put(1, 'a');
    _ = m.put(2, 'b');
    try std.testing.expectEqual(reserved, m.inner.capacity);
}

test "I32CharHashMap: ensureTotalCapacity is idempotent when capacity already sufficient" {
    var m = I32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureTotalCapacity(500);
    const reserved = m.inner.capacity;
    try m.ensureTotalCapacity(10);
    try std.testing.expectEqual(reserved, m.inner.capacity);
}

test "I32CharHashMap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 1: HashMap.init allocates the backing hash table (1st alloc),
    // then ensureUnusedCapacity triggers a grow that fails (2nd alloc).
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var m = I32CharHashMap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(10_000));
}
