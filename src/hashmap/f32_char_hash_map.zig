
const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const ImmutableF32CharHashMap = @import("../immutable/immutable_f32_char_hash_map.zig").ImmutableF32CharHashMap;

/// Hash map from `f32` keys to `u21` values.
///
/// Custom open-addressing with linear probing and Robin Hood backward-shift deletion.
/// Supports separate allocators for keys, values, and index buckets via AllocatorConfig.
pub const F32CharHashMap = struct {
    inner: OpenHashMap(f32, u21),
    config: AllocatorConfig,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) F32CharHashMap {
        return initWithConfig(AllocatorConfig.init(allocator));
    }

    /// Create with pre-allocated capacity.
    pub fn initWithCapacity(allocator: Allocator, capacity: usize) F32CharHashMap {
        return .{
            .inner = OpenHashMap(f32, u21).initCapacity(allocator, capacity) catch @panic("out of memory"),
            .config = AllocatorConfig.init(allocator),
        };
    }

    /// Create with fine-grained allocator control.
    pub fn initWithConfig(config: AllocatorConfig) F32CharHashMap {
        return .{
            .inner = OpenHashMap(f32, u21).init(
                config.keysAllocator(),
                config.valuesAllocator(),
                config.indexAllocator(),
            ) catch @panic("out of memory"),
            .config = config,
        };
    }

    pub fn deinit(self: *F32CharHashMap) void {
        self.inner.deinit();
    }

    // ---- Core Operations ----

    /// Inserts a key-value pair. Returns the old value if the key was already present.
    pub fn put(self: *F32CharHashMap, key: f32, value: u21) ?u21 {
        return self.inner.put(key, value) catch @panic("out of memory");
    }

    /// Returns the value for the key, or null.
    pub fn get(self: *const F32CharHashMap, key: f32) ?u21 {
        return self.inner.get(key);
    }

    /// Returns the value for the key, or the default.
    pub fn getOrDefault(self: *const F32CharHashMap, key: f32, default_value: u21) u21 {
        return self.get(key) orelse default_value;
    }

    /// Removes the key. Returns the old value if present.
    pub fn remove(self: *F32CharHashMap, key: f32) ?u21 {
        return self.inner.remove(key);
    }

    pub fn containsKey(self: *const F32CharHashMap, key: f32) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const F32CharHashMap, value: u21) bool {
        return self.inner.containsValue(value);
    }

    // ---- Entry API ----

    /// Entry provides atomic check-and-modify operations for a single key.
    pub const Entry = struct {
        map_ptr: *F32CharHashMap,
        key: f32,

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

    pub fn getEntry(self: *F32CharHashMap, key: f32) Entry {
        return .{ .map_ptr = self, .key = key };
    }

    pub fn len(self: *const F32CharHashMap) usize {
        return self.inner.len();
    }

    pub fn size(self: *const F32CharHashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const F32CharHashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn clear(self: *F32CharHashMap) void {
        self.inner.clear();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more entries can be put without triggering
    /// a rehash. Returns `error.OutOfMemory` if the allocator fails.
    pub fn ensureUnusedCapacity(self: *F32CharHashMap, additional: usize) Allocator.Error!void {
        return self.inner.ensureCapacity(additional);
    }

    /// Ensures the map's total capacity can fit at least `new_capacity`
    /// entries under the load factor without a rehash.
    pub fn ensureTotalCapacity(self: *F32CharHashMap, new_capacity: usize) Allocator.Error!void {
        if (new_capacity <= self.inner.len()) return;
        return self.inner.ensureCapacity(new_capacity - self.inner.len());
    }

    // ---- Iteration ----

    pub fn forEach(self: *const F32CharHashMap, f: *const fn (f32, u21) void) void {
        self.inner.forEach(f);
    }

    pub fn forEachKey(self: *const F32CharHashMap, f: *const fn (f32) void) void {
        self.inner.forEachKey(f);
    }

    pub fn forEachValue(self: *const F32CharHashMap, f: *const fn (u21) void) void {
        self.inner.forEachValue(f);
    }

    // ---- Functional Operations ----

    pub fn select(self: *const F32CharHashMap, predicate: *const fn (f32, u21) bool) F32CharHashMap {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return result;
    }

    pub fn reject(self: *const F32CharHashMap, predicate: *const fn (f32, u21) bool) F32CharHashMap {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (!predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return result;
    }

    pub fn detect(self: *const F32CharHashMap, predicate: *const fn (f32, u21) bool) ?struct { key: f32, value: u21 } {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    return .{ .key = self.inner.entries[i].key, .value = self.inner.entries[i].value };
            }
        }
        return null;
    }

    pub fn anySatisfy(self: *const F32CharHashMap, predicate: *const fn (f32, u21) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const F32CharHashMap, predicate: *const fn (f32, u21) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and !predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const F32CharHashMap, predicate: *const fn (f32, u21) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
        }
        return true;
    }

    pub fn count(self: *const F32CharHashMap, predicate: *const fn (f32, u21) bool) usize {
        var c: usize = 0;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) c += 1;
        }
        return c;
    }

    pub fn injectInto(self: *const F32CharHashMap, initial: u21, f: *const fn (u21, f32, u21) u21) u21 {
        var acc = initial;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) acc = f(acc, self.inner.entries[i].key, self.inner.entries[i].value);
        }
        return acc;
    }

    // ---- Key/Value Collection ----

    pub fn keysToSlice(self: *const F32CharHashMap, allocator: Allocator) []f32 {
        return self.inner.keysToSlice(allocator) catch @panic("out of memory");
    }

    pub fn valuesToSlice(self: *const F32CharHashMap, allocator: Allocator) []u21 {
        return self.inner.valuesToSlice(allocator) catch @panic("out of memory");
    }

    // ---- Conversion ----

    pub fn toImmutable(self: *const F32CharHashMap) ImmutableF32CharHashMap {
        return ImmutableF32CharHashMap.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    pub fn withKeyValue(self: *F32CharHashMap, key: f32, value: u21) *F32CharHashMap {
        _ = self.put(key, value);
        return self;
    }

    pub fn withoutKey(self: *F32CharHashMap, key: f32) *F32CharHashMap {
        _ = self.remove(key);
        return self;
    }

    pub fn withoutAllKeys(self: *F32CharHashMap, keys: []const f32) *F32CharHashMap {
        for (keys) |key| _ = self.remove(key);
        return self;
    }

    // ---- Mutation Helpers ----

    pub fn updateValue(self: *F32CharHashMap, key: f32, initial: u21, f: *const fn (u21) u21) u21 {
        const current = self.get(key) orelse initial;
        const new_value = f(current);
        _ = self.put(key, new_value);
        return new_value;
    }

    // ---- Formatting ----

    pub fn format(self: *const F32CharHashMap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const F32CharHashMap, other: *const F32CharHashMap) bool {
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

test "F32CharHashMap: put and get" {
    var m = F32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 'a');
    _ = m.put(2.0, 'b');
    _ = m.put(3.0, 'c');
    try std.testing.expectEqual(@as(?u21, 'a'), m.get(1.0));
    try std.testing.expectEqual(@as(?u21, null), m.get(99.0));
    try std.testing.expectEqual(@as(usize, 3), m.len());
}

test "F32CharHashMap: put overwrite" {
    var m = F32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 'a');
    const old = m.put(1.0, 'b');
    try std.testing.expectEqual(@as(?u21, 'a'), old);
    try std.testing.expectEqual(@as(?u21, 'b'), m.get(1.0));
}

test "F32CharHashMap: remove" {
    var m = F32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 'a');
    _ = m.put(2.0, 'b');
    const removed = m.remove(1.0);
    try std.testing.expectEqual(@as(?u21, 'a'), removed);
    try std.testing.expectEqual(@as(usize, 1), m.len());
    try std.testing.expect(!m.containsKey(1.0));
}

test "F32CharHashMap: containsKey and containsValue" {
    var m = F32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 'a');
    try std.testing.expect(m.containsKey(1.0));
    try std.testing.expect(!m.containsKey(99.0));
    try std.testing.expect(m.containsValue('a'));
    try std.testing.expect(!m.containsValue('z'));
}

test "F32CharHashMap: getOrDefault" {
    var m = F32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 'a');
    try std.testing.expectEqual('a', m.getOrDefault(1.0, 'c'));
    try std.testing.expectEqual('c', m.getOrDefault(99.0, 'c'));
}

test "F32CharHashMap: clear" {
    var m = F32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 'a');
    m.clear();
    try std.testing.expect(m.isEmpty());
}

test "F32CharHashMap: select and reject" {
    var m = F32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 'a');
    _ = m.put(2.0, 'b');
    _ = m.put(3.0, 'c');
    var sel = m.select(struct {
        fn f(_: f32, v: u21) bool {
            return v > 'a';
        }
    }.f);
    defer sel.deinit();
    try std.testing.expectEqual(@as(usize, 2), sel.len());
    var rej = m.reject(struct {
        fn f(_: f32, v: u21) bool {
            return v > 'a';
        }
    }.f);
    defer rej.deinit();
    try std.testing.expectEqual(@as(usize, 1), rej.len());
}

test "F32CharHashMap: anySatisfy allSatisfy noneSatisfy count" {
    var m = F32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 'a');
    _ = m.put(2.0, 'b');
    try std.testing.expect(m.anySatisfy(struct {
        fn f(_: f32, v: u21) bool {
            return v == 'b';
        }
    }.f));
    try std.testing.expect(m.noneSatisfy(struct {
        fn f(_: f32, v: u21) bool {
            return v == 'z';
        }
    }.f));
    try std.testing.expectEqual(@as(usize, 1), m.count(struct {
        fn f(_: f32, v: u21) bool {
            return v == 'a';
        }
    }.f));
}

test "F32CharHashMap: keysToSlice and valuesToSlice" {
    var m = F32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 'a');
    _ = m.put(2.0, 'b');
    const keys = m.keysToSlice(std.testing.allocator);
    defer std.testing.allocator.free(keys);
    try std.testing.expectEqual(@as(usize, 2), keys.len);
    const vals = m.valuesToSlice(std.testing.allocator);
    defer std.testing.allocator.free(vals);
    try std.testing.expectEqual(@as(usize, 2), vals.len);
}

test "F32CharHashMap: toImmutable" {
    var m = F32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 'a');
    _ = m.put(2.0, 'b');
    var im = m.toImmutable();
    defer im.deinit();
    try std.testing.expectEqual(@as(usize, 2), im.len());
    _ = m.put(3.0, 'c');
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "F32CharHashMap: fluent withKeyValue/withoutKey" {
    var m = F32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.withKeyValue(1.0, 'a').withKeyValue(2.0, 'b');
    try std.testing.expectEqual(@as(usize, 2), m.len());
    _ = m.withoutKey(1.0);
    try std.testing.expectEqual(@as(usize, 1), m.len());
}

test "F32CharHashMap: eql" {
    var m1 = F32CharHashMap.init(std.testing.allocator);
    defer m1.deinit();
    _ = m1.put(1.0, 'a');
    _ = m1.put(2.0, 'b');
    var m2 = F32CharHashMap.init(std.testing.allocator);
    defer m2.deinit();
    _ = m2.put(2.0, 'b');
    _ = m2.put(1.0, 'a');
    try std.testing.expect(m1.eql(&m2));
}

test "F32CharHashMap: resize" {
    var m = F32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        _ = m.put(@as(f32, @floatFromInt(i)), @as(u21, @intCast(i % 26)) + 'A');
    }
    try std.testing.expect(m.len() > 0);
}

test "F32CharHashMap: entry orInsert" {
    var m = F32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    // Key absent — inserts default
    const v1 = m.getEntry(1.0).orInsert('a');
    try std.testing.expectEqual('a', v1);
    // Key present — returns existing
    _ = m.put(1.0, 'b');
    const v2 = m.getEntry(1.0).orInsert('c');
    try std.testing.expectEqual('b', v2);
}

test "F32CharHashMap: entry andModify orInsert" {
    var m = F32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    // Key absent: andModify is no-op, orInsert inserts
    _ = m.getEntry(1.0).andModify(struct {
        fn f(_: *u21) void {}
    }.f).orInsert('a');
    try std.testing.expectEqual(@as(?u21, 'a'), m.get(1.0));
}

test "F32CharHashMap: ensureUnusedCapacity reserves and subsequent put does not resize" {
    var m = F32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(500);
    const reserved = m.inner.capacity;
    try std.testing.expect(reserved >= 500);
    _ = m.put(1.0, 'a');
    _ = m.put(2.0, 'b');
    try std.testing.expectEqual(reserved, m.inner.capacity);
}

test "F32CharHashMap: ensureTotalCapacity is idempotent when capacity already sufficient" {
    var m = F32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureTotalCapacity(500);
    const reserved = m.inner.capacity;
    try m.ensureTotalCapacity(10);
    try std.testing.expectEqual(reserved, m.inner.capacity);
}

test "F32CharHashMap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 1: HashMap.init allocates the backing hash table (1st alloc),
    // then ensureUnusedCapacity triggers a grow that fails (2nd alloc).
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var m = F32CharHashMap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(10_000));
}

// ---- NaN / IEEE-754 edge-case tests (locks in bit-level keyEql from hash_table.zig) ----
// See docs/float-nan-semantics-audit.md.

test "F32CharHashMap: NaN key findable" {
    var m = F32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    const nan_key = std.math.nan(f32);
    _ = m.put(nan_key, 'a');
    try std.testing.expect(m.containsKey(nan_key));
    try std.testing.expectEqual(@as(?u21, 'a'), m.get(nan_key));
}

test "F32CharHashMap: NaN key replaces, does not duplicate" {
    var m = F32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    const nan_key = std.math.nan(f32);
    _ = m.put(nan_key, 'a');
    _ = m.put(nan_key, 'b');
    _ = m.put(nan_key, 'c');
    try std.testing.expectEqual(@as(usize, 1), m.len());
    try std.testing.expectEqual(@as(?u21, 'c'), m.get(nan_key));
}

test "F32CharHashMap: NaN key remove" {
    var m = F32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    const nan_key = std.math.nan(f32);
    _ = m.put(nan_key, 'a');
    _ = m.remove(nan_key);
    try std.testing.expectEqual(@as(usize, 0), m.len());
    try std.testing.expect(!m.containsKey(nan_key));
}

test "F32CharHashMap: -0.0 distinct from +0.0" {
    var m = F32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    const pos_zero: f32 = @as(f32, 0.0);
    const neg_zero: f32 = @as(f32, -0.0);
    _ = m.put(pos_zero, 'a');
    _ = m.put(neg_zero, 'b');
    try std.testing.expectEqual(@as(usize, 2), m.len());
    try std.testing.expectEqual(@as(?u21, 'a'), m.get(pos_zero));
    try std.testing.expectEqual(@as(?u21, 'b'), m.get(neg_zero));
}

test "F32CharHashMap: +/-Infinity keys" {
    var m = F32CharHashMap.init(std.testing.allocator);
    defer m.deinit();
    const pos_inf = std.math.inf(f32);
    const neg_inf = -std.math.inf(f32);
    _ = m.put(pos_inf, 'a');
    _ = m.put(neg_inf, 'b');
    try std.testing.expectEqual(@as(usize, 2), m.len());
    try std.testing.expect(m.containsKey(pos_inf));
    try std.testing.expect(m.containsKey(neg_inf));
    try std.testing.expectEqual(@as(?u21, 'a'), m.get(pos_inf));
    try std.testing.expectEqual(@as(?u21, 'b'), m.get(neg_inf));
}
