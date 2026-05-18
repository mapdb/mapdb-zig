
const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const ImmutableF64I16HashMap = @import("../immutable/immutable_f64_i16_hash_map.zig").ImmutableF64I16HashMap;

/// Hash map from `f64` keys to `i16` values.
///
/// Custom open-addressing with linear probing and Robin Hood backward-shift deletion.
/// Supports separate allocators for keys, values, and index buckets via AllocatorConfig.
pub const F64I16HashMap = struct {
    inner: OpenHashMap(f64, i16),
    config: AllocatorConfig,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) F64I16HashMap {
        return initWithConfig(AllocatorConfig.init(allocator));
    }

    /// Create with pre-allocated capacity.
    pub fn initWithCapacity(allocator: Allocator, capacity: usize) F64I16HashMap {
        return .{
            .inner = OpenHashMap(f64, i16).initCapacity(allocator, capacity) catch @panic("out of memory"),
            .config = AllocatorConfig.init(allocator),
        };
    }

    /// Create with fine-grained allocator control.
    pub fn initWithConfig(config: AllocatorConfig) F64I16HashMap {
        return .{
            .inner = OpenHashMap(f64, i16).init(
                config.keysAllocator(),
                config.valuesAllocator(),
                config.indexAllocator(),
            ) catch @panic("out of memory"),
            .config = config,
        };
    }

    pub fn deinit(self: *F64I16HashMap) void {
        self.inner.deinit();
    }

    // ---- Core Operations ----

    /// Inserts a key-value pair. Returns the old value if the key was already present.
    pub fn put(self: *F64I16HashMap, key: f64, value: i16) ?i16 {
        return self.inner.put(key, value) catch @panic("out of memory");
    }

    /// Returns the value for the key, or null.
    pub fn get(self: *const F64I16HashMap, key: f64) ?i16 {
        return self.inner.get(key);
    }

    /// Returns the value for the key, or the default.
    pub fn getOrDefault(self: *const F64I16HashMap, key: f64, default_value: i16) i16 {
        return self.get(key) orelse default_value;
    }

    /// Removes the key. Returns the old value if present.
    pub fn remove(self: *F64I16HashMap, key: f64) ?i16 {
        return self.inner.remove(key);
    }

    pub fn containsKey(self: *const F64I16HashMap, key: f64) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const F64I16HashMap, value: i16) bool {
        return self.inner.containsValue(value);
    }

    // ---- Entry API ----

    /// Entry provides atomic check-and-modify operations for a single key.
    pub const Entry = struct {
        map_ptr: *F64I16HashMap,
        key: f64,

        /// Inserts the default value if the key is absent. Returns the current value.
        pub fn orInsert(self: Entry, default_value: i16) i16 {
            if (self.map_ptr.get(self.key)) |existing| return existing;
            _ = self.map_ptr.put(self.key, default_value);
            return default_value;
        }

        /// Inserts the value from the function if the key is absent.
        pub fn orInsertWith(self: Entry, f: *const fn () i16) i16 {
            if (self.map_ptr.get(self.key)) |existing| return existing;
            const val = f();
            _ = self.map_ptr.put(self.key, val);
            return val;
        }

        /// Calls the function on a pointer to the value if the key is present.
        pub fn andModify(self: Entry, f: *const fn (*i16) void) Entry {
            if (self.map_ptr.inner.getPtr(self.key)) |val_ptr| {
                f(val_ptr);
            }
            return self;
        }
    };

    pub fn getEntry(self: *F64I16HashMap, key: f64) Entry {
        return .{ .map_ptr = self, .key = key };
    }

    pub fn len(self: *const F64I16HashMap) usize {
        return self.inner.len();
    }

    pub fn size(self: *const F64I16HashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const F64I16HashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn clear(self: *F64I16HashMap) void {
        self.inner.clear();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more entries can be put without triggering
    /// a rehash. Returns `error.OutOfMemory` if the allocator fails. See
    /// `docs/zig/error-handling.md`.
    pub fn ensureUnusedCapacity(self: *F64I16HashMap, additional: usize) Allocator.Error!void {
        return self.inner.ensureCapacity(additional);
    }

    /// Ensures the map's total capacity can fit at least `new_capacity`
    /// entries under the load factor without a rehash.
    pub fn ensureTotalCapacity(self: *F64I16HashMap, new_capacity: usize) Allocator.Error!void {
        if (new_capacity <= self.inner.len()) return;
        return self.inner.ensureCapacity(new_capacity - self.inner.len());
    }

    // ---- Iteration ----

    pub fn forEach(self: *const F64I16HashMap, f: *const fn (f64, i16) void) void {
        self.inner.forEach(f);
    }

    pub fn forEachKey(self: *const F64I16HashMap, f: *const fn (f64) void) void {
        self.inner.forEachKey(f);
    }

    pub fn forEachValue(self: *const F64I16HashMap, f: *const fn (i16) void) void {
        self.inner.forEachValue(f);
    }

    // ---- Functional Operations ----

    pub fn select(self: *const F64I16HashMap, predicate: *const fn (f64, i16) bool) F64I16HashMap {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return result;
    }

    pub fn reject(self: *const F64I16HashMap, predicate: *const fn (f64, i16) bool) F64I16HashMap {
        var result = init(self.config.base);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (!predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    _ = result.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return result;
    }

    pub fn detect(self: *const F64I16HashMap, predicate: *const fn (f64, i16) bool) ?struct { key: f64, value: i16 } {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                if (predicate(self.inner.entries[i].key, self.inner.entries[i].value))
                    return .{ .key = self.inner.entries[i].key, .value = self.inner.entries[i].value };
            }
        }
        return null;
    }

    pub fn anySatisfy(self: *const F64I16HashMap, predicate: *const fn (f64, i16) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const F64I16HashMap, predicate: *const fn (f64, i16) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and !predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const F64I16HashMap, predicate: *const fn (f64, i16) bool) bool {
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) return false;
        }
        return true;
    }

    pub fn count(self: *const F64I16HashMap, predicate: *const fn (f64, i16) bool) usize {
        var c: usize = 0;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied and predicate(self.inner.entries[i].key, self.inner.entries[i].value)) c += 1;
        }
        return c;
    }

    pub fn injectInto(self: *const F64I16HashMap, initial: i16, f: *const fn (i16, f64, i16) i16) i16 {
        var acc = initial;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) acc = f(acc, self.inner.entries[i].key, self.inner.entries[i].value);
        }
        return acc;
    }

    // ---- Key/Value Collection ----

    pub fn keysToSlice(self: *const F64I16HashMap, allocator: Allocator) []f64 {
        return self.inner.keysToSlice(allocator) catch @panic("out of memory");
    }

    pub fn valuesToSlice(self: *const F64I16HashMap, allocator: Allocator) []i16 {
        return self.inner.valuesToSlice(allocator) catch @panic("out of memory");
    }

    // ---- Numeric Value Operations ----

    pub fn sumOfValues(self: *const F64I16HashMap) i64 {
        var total: i64 = 0;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) total += @as(i64, @intCast(self.inner.entries[i].value));
        }
        return total;
    }

    pub fn addToValue(self: *F64I16HashMap, key: f64, delta: i16) i16 {
        if (self.inner.getPtr(key)) |val_ptr| {
            val_ptr.* += delta;
            return val_ptr.*;
        } else {
            _ = self.put(key, delta);
            return delta;
        }
    }

    // ---- Conversion ----

    pub fn toImmutable(self: *const F64I16HashMap) ImmutableF64I16HashMap {
        return ImmutableF64I16HashMap.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    pub fn withKeyValue(self: *F64I16HashMap, key: f64, value: i16) *F64I16HashMap {
        _ = self.put(key, value);
        return self;
    }

    pub fn withoutKey(self: *F64I16HashMap, key: f64) *F64I16HashMap {
        _ = self.remove(key);
        return self;
    }

    pub fn withoutAllKeys(self: *F64I16HashMap, keys: []const f64) *F64I16HashMap {
        for (keys) |key| _ = self.remove(key);
        return self;
    }

    // ---- Mutation Helpers ----

    pub fn updateValue(self: *F64I16HashMap, key: f64, initial: i16, f: *const fn (i16) i16) i16 {
        const current = self.get(key) orelse initial;
        const new_value = f(current);
        _ = self.put(key, new_value);
        return new_value;
    }

    // ---- Formatting ----

    pub fn format(self: *const F64I16HashMap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const F64I16HashMap, other: *const F64I16HashMap) bool {
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

test "F64I16HashMap: put and get" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 1);
    _ = m.put(2.0, 2);
    _ = m.put(3.0, 3);
    try std.testing.expectEqual(@as(?i16, 1), m.get(1.0));
    try std.testing.expectEqual(@as(?i16, null), m.get(99.0));
    try std.testing.expectEqual(@as(usize, 3), m.len());
}

test "F64I16HashMap: put overwrite" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 1);
    const old = m.put(1.0, 2);
    try std.testing.expectEqual(@as(?i16, 1), old);
    try std.testing.expectEqual(@as(?i16, 2), m.get(1.0));
}

test "F64I16HashMap: remove" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 1);
    _ = m.put(2.0, 2);
    const removed = m.remove(1.0);
    try std.testing.expectEqual(@as(?i16, 1), removed);
    try std.testing.expectEqual(@as(usize, 1), m.len());
    try std.testing.expect(!m.containsKey(1.0));
}

test "F64I16HashMap: containsKey and containsValue" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 1);
    try std.testing.expect(m.containsKey(1.0));
    try std.testing.expect(!m.containsKey(99.0));
    try std.testing.expect(m.containsValue(1));
    try std.testing.expect(!m.containsValue(99));
}

test "F64I16HashMap: getOrDefault" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 1);
    try std.testing.expectEqual(1, m.getOrDefault(1.0, 3));
    try std.testing.expectEqual(3, m.getOrDefault(99.0, 3));
}

test "F64I16HashMap: clear" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 1);
    m.clear();
    try std.testing.expect(m.isEmpty());
}

test "F64I16HashMap: select and reject" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 1);
    _ = m.put(2.0, 2);
    _ = m.put(3.0, 3);
    var sel = m.select(struct {
        fn f(_: f64, v: i16) bool {
            return v > 1;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expectEqual(@as(usize, 2), sel.len());
    var rej = m.reject(struct {
        fn f(_: f64, v: i16) bool {
            return v > 1;
        }
    }.f);
    defer rej.deinit();
    try std.testing.expectEqual(@as(usize, 1), rej.len());
}

test "F64I16HashMap: anySatisfy allSatisfy noneSatisfy count" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 1);
    _ = m.put(2.0, 2);
    try std.testing.expect(m.anySatisfy(struct {
        fn f(_: f64, v: i16) bool {
            return v == 2;
        }
    }.f));
    try std.testing.expect(m.noneSatisfy(struct {
        fn f(_: f64, v: i16) bool {
            return v == 99;
        }
    }.f));
    try std.testing.expectEqual(@as(usize, 1), m.count(struct {
        fn f(_: f64, v: i16) bool {
            return v == 1;
        }
    }.f));
}

test "F64I16HashMap: keysToSlice and valuesToSlice" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 1);
    _ = m.put(2.0, 2);
    const keys = m.keysToSlice(std.testing.allocator);
    defer std.testing.allocator.free(keys);
    try std.testing.expectEqual(@as(usize, 2), keys.len);
    const vals = m.valuesToSlice(std.testing.allocator);
    defer std.testing.allocator.free(vals);
    try std.testing.expectEqual(@as(usize, 2), vals.len);
}

test "F64I16HashMap: sumOfValues" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 1);
    _ = m.put(2.0, 2);
    const s = m.sumOfValues();
    try std.testing.expect(s > 0);
}

test "F64I16HashMap: addToValue" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.addToValue(1.0, 1);
    _ = m.addToValue(1.0, 2);
    // Value should be sum of the two adds
    try std.testing.expect(m.get(1.0) != null);
}

test "F64I16HashMap: toImmutable" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 1);
    _ = m.put(2.0, 2);
    var im = m.toImmutable();
    defer im.deinit();
    try std.testing.expectEqual(@as(usize, 2), im.len());
    _ = m.put(3.0, 3);
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "F64I16HashMap: fluent withKeyValue/withoutKey" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.withKeyValue(1.0, 1).withKeyValue(2.0, 2);
    try std.testing.expectEqual(@as(usize, 2), m.len());
    _ = m.withoutKey(1.0);
    try std.testing.expectEqual(@as(usize, 1), m.len());
}

test "F64I16HashMap: eql" {
    var m1 = F64I16HashMap.init(std.testing.allocator);
    defer m1.deinit();
    _ = m1.put(1.0, 1);
    _ = m1.put(2.0, 2);
    var m2 = F64I16HashMap.init(std.testing.allocator);
    defer m2.deinit();
    _ = m2.put(2.0, 2);
    _ = m2.put(1.0, 1);
    try std.testing.expect(m1.eql(&m2));
}

test "F64I16HashMap: resize" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        _ = m.put(@as(f64, @floatFromInt(i)), @as(i16, @intCast(i)));
    }
    try std.testing.expect(m.len() > 0);
}

test "F64I16HashMap: entry orInsert" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    // Key absent — inserts default
    const v1 = m.getEntry(1.0).orInsert(1);
    try std.testing.expectEqual(1, v1);
    // Key present — returns existing
    _ = m.put(1.0, 2);
    const v2 = m.getEntry(1.0).orInsert(3);
    try std.testing.expectEqual(2, v2);
}

test "F64I16HashMap: entry andModify orInsert" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    // Key absent: andModify is no-op, orInsert inserts
    _ = m.getEntry(1.0).andModify(struct {
        fn f(_: *i16) void {}
    }.f).orInsert(1);
    try std.testing.expectEqual(@as(?i16, 1), m.get(1.0));
}

test "F64I16HashMap: ensureUnusedCapacity reserves and subsequent put does not resize" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(500);
    const reserved = m.inner.capacity;
    try std.testing.expect(reserved >= 500);
    _ = m.put(1.0, 1);
    _ = m.put(2.0, 2);
    try std.testing.expectEqual(reserved, m.inner.capacity);
}

test "F64I16HashMap: ensureTotalCapacity is idempotent when capacity already sufficient" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureTotalCapacity(500);
    const reserved = m.inner.capacity;
    try m.ensureTotalCapacity(10);
    try std.testing.expectEqual(reserved, m.inner.capacity);
}

test "F64I16HashMap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 1: HashMap.init allocates the backing hash table (1st alloc),
    // then ensureUnusedCapacity triggers a grow that fails (2nd alloc).
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var m = F64I16HashMap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(10_000));
}

// ---- NaN / IEEE-754 edge-case tests (locks in bit-level keyEql from hash_table.zig) ----
// See docs/float-nan-semantics-audit.md.

test "F64I16HashMap: NaN key findable" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    const nan_key = std.math.nan(f64);
    _ = m.put(nan_key, 1);
    try std.testing.expect(m.containsKey(nan_key));
    try std.testing.expectEqual(@as(?i16, 1), m.get(nan_key));
}

test "F64I16HashMap: NaN key replaces, does not duplicate" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    const nan_key = std.math.nan(f64);
    _ = m.put(nan_key, 1);
    _ = m.put(nan_key, 2);
    _ = m.put(nan_key, 3);
    try std.testing.expectEqual(@as(usize, 1), m.len());
    try std.testing.expectEqual(@as(?i16, 3), m.get(nan_key));
}

test "F64I16HashMap: NaN key remove" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    const nan_key = std.math.nan(f64);
    _ = m.put(nan_key, 1);
    _ = m.remove(nan_key);
    try std.testing.expectEqual(@as(usize, 0), m.len());
    try std.testing.expect(!m.containsKey(nan_key));
}

test "F64I16HashMap: -0.0 distinct from +0.0" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    const pos_zero: f64 = @as(f64, 0.0);
    const neg_zero: f64 = @as(f64, -0.0);
    _ = m.put(pos_zero, 1);
    _ = m.put(neg_zero, 2);
    try std.testing.expectEqual(@as(usize, 2), m.len());
    try std.testing.expectEqual(@as(?i16, 1), m.get(pos_zero));
    try std.testing.expectEqual(@as(?i16, 2), m.get(neg_zero));
}

test "F64I16HashMap: +/-Infinity keys" {
    var m = F64I16HashMap.init(std.testing.allocator);
    defer m.deinit();
    const pos_inf = std.math.inf(f64);
    const neg_inf = -std.math.inf(f64);
    _ = m.put(pos_inf, 1);
    _ = m.put(neg_inf, 2);
    try std.testing.expectEqual(@as(usize, 2), m.len());
    try std.testing.expect(m.containsKey(pos_inf));
    try std.testing.expect(m.containsKey(neg_inf));
    try std.testing.expectEqual(@as(?i16, 1), m.get(pos_inf));
    try std.testing.expectEqual(@as(?i16, 2), m.get(neg_inf));
}
