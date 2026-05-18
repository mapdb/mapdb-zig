
const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const F64I32HashBiMap = @import("f64_i32_hash_bi_map.zig").F64I32HashBiMap;

/// Bidirectional hash map from `i32` keys to `f64` values.
///
/// Maintains two internal OpenHashMaps (forward and reverse) so that both
/// key-to-value and value-to-key lookups are O(1). Every mutation keeps both
/// maps in sync.
pub const I32F64HashBiMap = struct {
    forward: OpenHashMap(i32, f64),
    reverse: OpenHashMap(f64, i32),
    config: AllocatorConfig,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) I32F64HashBiMap {
        return initWithConfig(AllocatorConfig.init(allocator));
    }

    /// Create with fine-grained allocator control.
    pub fn initWithConfig(config: AllocatorConfig) I32F64HashBiMap {
        return .{
            .forward = OpenHashMap(i32, f64).init(
                config.keysAllocator(),
                config.valuesAllocator(),
                config.indexAllocator(),
            ) catch @panic("out of memory"),
            .reverse = OpenHashMap(f64, i32).init(
                config.keysAllocator(),
                config.valuesAllocator(),
                config.indexAllocator(),
            ) catch @panic("out of memory"),
            .config = config,
        };
    }

    pub fn deinit(self: *I32F64HashBiMap) void {
        self.forward.deinit();
        self.reverse.deinit();
    }

    // ---- Core Operations ----

    /// Inserts a bidirectional key-value mapping.
    /// If the key was already mapped to an old value, the old value is removed
    /// from the reverse map before inserting the new mapping.
    /// If the value was already mapped to an old key, the old key is removed
    /// from the forward map before inserting the new mapping.
    /// Returns the old value previously associated with the key, or null.
    pub fn put(self: *I32F64HashBiMap, key: i32, value: f64) ?f64 {
        // If this value already maps to a different key, remove the old key from forward.
        if (self.reverse.get(value)) |old_key| {
            if (!(old_key == key)) {
                _ = self.forward.remove(old_key);
            }
        }
        // If this key already maps to an old value, remove that old value from reverse.
        const old_value = self.forward.get(key);
        if (old_value) |ov| {
            _ = self.reverse.remove(ov);
        }
        _ = self.forward.put(key, value) catch @panic("out of memory");
        _ = self.reverse.put(value, key) catch @panic("out of memory");
        return old_value;
    }

    /// Returns the value for the given key (forward lookup), or null.
    pub fn get(self: *const I32F64HashBiMap, key: i32) ?f64 {
        return self.forward.get(key);
    }

    /// Returns the key for the given value (reverse lookup), or null.
    pub fn getKey(self: *const I32F64HashBiMap, value: f64) ?i32 {
        return self.reverse.get(value);
    }

    /// Removes the mapping for the given key and its reverse. Returns the old value if present.
    pub fn remove(self: *I32F64HashBiMap, key: i32) ?f64 {
        const old_value = self.forward.remove(key);
        if (old_value) |ov| {
            _ = self.reverse.remove(ov);
        }
        return old_value;
    }

    /// Removes the mapping for the given value and its forward key. Returns the old key if present.
    pub fn removeValue(self: *I32F64HashBiMap, value: f64) ?i32 {
        const old_key = self.reverse.remove(value);
        if (old_key) |ok| {
            _ = self.forward.remove(ok);
        }
        return old_key;
    }

    pub fn containsKey(self: *const I32F64HashBiMap, key: i32) bool {
        return self.forward.containsKey(key);
    }

    pub fn containsValue(self: *const I32F64HashBiMap, value: f64) bool {
        return self.reverse.containsKey(value);
    }

    pub fn len(self: *const I32F64HashBiMap) usize {
        return self.forward.len();
    }

    pub fn isEmpty(self: *const I32F64HashBiMap) bool {
        return self.forward.isEmpty();
    }

    pub fn clear(self: *I32F64HashBiMap) void {
        self.forward.clear();
        self.reverse.clear();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures both the forward and reverse maps can hold `additional`
    /// more entries without triggering a rehash. Returns
    /// `error.OutOfMemory` if the allocator fails.
    pub fn ensureUnusedCapacity(self: *I32F64HashBiMap, additional: usize) Allocator.Error!void {
        try self.forward.ensureCapacity(additional);
        try self.reverse.ensureCapacity(additional);
    }

    /// Ensures both internal maps' total capacity covers at least
    /// `new_capacity` entries.
    pub fn ensureTotalCapacity(self: *I32F64HashBiMap, new_capacity: usize) Allocator.Error!void {
        const cur = self.forward.len();
        if (new_capacity <= cur) return;
        try self.ensureUnusedCapacity(new_capacity - cur);
    }

    // ---- Iteration ----

    pub fn forEach(self: *const I32F64HashBiMap, f: *const fn (i32, f64) void) void {
        self.forward.forEach(f);
    }

    pub fn forEachKey(self: *const I32F64HashBiMap, f: *const fn (i32) void) void {
        self.forward.forEachKey(f);
    }

    pub fn forEachValue(self: *const I32F64HashBiMap, f: *const fn (f64) void) void {
        self.forward.forEachValue(f);
    }

    // ---- Inverse ----

    /// Returns a new BiMap with keys and values swapped (value->key becomes key->value).
    /// The caller owns the returned map and must call deinit() on it.
    pub fn inverse(self: *const I32F64HashBiMap) F64I32HashBiMap {
        var result = F64I32HashBiMap.init(self.config.base);
        for (0..self.forward.capacity) |i| {
            if (self.forward.entries[i].occupied) {
                _ = result.put(self.forward.entries[i].value, self.forward.entries[i].key);
            }
        }
        return result;
    }

    // ---- Formatting ----

    pub fn format(self: *const I32F64HashBiMap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll("{");
        var first = true;
        for (0..self.forward.capacity) |i| {
            if (self.forward.entries[i].occupied) {
                if (!first) try writer.writeAll(", ");
                try writer.print("{any}", .{self.forward.entries[i].key});
                try writer.writeAll("<->");
                try writer.print("{any}", .{self.forward.entries[i].value});
                first = false;
            }
        }
        try writer.writeAll("}");
    }

    // ---- Equality ----

    pub fn eql(self: *const I32F64HashBiMap, other: *const I32F64HashBiMap) bool {
        if (self.len() != other.len()) return false;
        for (0..self.forward.capacity) |i| {
            if (self.forward.entries[i].occupied) {
                const other_val = other.get(self.forward.entries[i].key) orelse return false;
                if (!(@as(u64, @bitCast(self.forward.entries[i].value)) == @as(u64, @bitCast(other_val)))) return false;
            }
        }
        return true;
    }
};

// ---- Tests ----

test "I32F64HashBiMap: put and get and getKey" {
    var m = I32F64HashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1.0);
    _ = m.put(2, 2.0);
    // forward lookup
    try std.testing.expectEqual(@as(?f64, 1.0), m.get(1));
    try std.testing.expectEqual(@as(?f64, 2.0), m.get(2));
    // reverse lookup
    try std.testing.expectEqual(@as(?i32, 1), m.getKey(1.0));
    try std.testing.expectEqual(@as(?i32, 2), m.getKey(2.0));
    // missing key
    try std.testing.expectEqual(@as(?f64, null), m.get(99));
    // missing value
    try std.testing.expectEqual(@as(?i32, null), m.getKey(99.0));
    try std.testing.expectEqual(@as(usize, 2), m.len());
}

test "I32F64HashBiMap: put overwrite updates reverse" {
    var m = I32F64HashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1.0);
    // overwrite key with new value
    const old = m.put(1, 2.0);
    try std.testing.expectEqual(@as(?f64, 1.0), old);
    // forward should have new value
    try std.testing.expectEqual(@as(?f64, 2.0), m.get(1));
    // reverse for old value should be gone
    try std.testing.expectEqual(@as(?i32, null), m.getKey(1.0));
    // reverse for new value should point to key
    try std.testing.expectEqual(@as(?i32, 1), m.getKey(2.0));
}

test "I32F64HashBiMap: remove" {
    var m = I32F64HashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1.0);
    _ = m.put(2, 2.0);
    const removed = m.remove(1);
    try std.testing.expectEqual(@as(?f64, 1.0), removed);
    try std.testing.expectEqual(@as(usize, 1), m.len());
    try std.testing.expect(!m.containsKey(1));
    // reverse should also be cleaned up
    try std.testing.expectEqual(@as(?i32, null), m.getKey(1.0));
}

test "I32F64HashBiMap: removeValue" {
    var m = I32F64HashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1.0);
    _ = m.put(2, 2.0);
    const removed_key = m.removeValue(1.0);
    try std.testing.expectEqual(@as(?i32, 1), removed_key);
    try std.testing.expectEqual(@as(usize, 1), m.len());
    try std.testing.expect(!m.containsValue(1.0));
    try std.testing.expect(!m.containsKey(1));
}

test "I32F64HashBiMap: containsKey and containsValue" {
    var m = I32F64HashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1.0);
    try std.testing.expect(m.containsKey(1));
    try std.testing.expect(!m.containsKey(99));
    try std.testing.expect(m.containsValue(1.0));
    try std.testing.expect(!m.containsValue(99.0));
}

test "I32F64HashBiMap: clear" {
    var m = I32F64HashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1.0);
    _ = m.put(2, 2.0);
    m.clear();
    try std.testing.expect(m.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), m.len());
}

test "I32F64HashBiMap: inverse" {
    var m = I32F64HashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1.0);
    _ = m.put(2, 2.0);
    var inv = m.inverse();
    defer inv.deinit();
    // inverse should have same count
    try std.testing.expectEqual(@as(usize, 2), inv.len());
    // inverse forward lookup: value -> key
    try std.testing.expectEqual(@as(?i32, 1), inv.get(1.0));
    try std.testing.expectEqual(@as(?i32, 2), inv.get(2.0));
}

test "I32F64HashBiMap: display format" {
    var m = I32F64HashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, 1.0);
    // Just verify formatting does not crash
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    m.format("", .{}, fbs.writer()) catch {};
    const output = fbs.getWritten();
    try std.testing.expect(output.len > 0);
}

test "I32F64HashBiMap: eql" {
    var m1 = I32F64HashBiMap.init(std.testing.allocator);
    defer m1.deinit();
    _ = m1.put(1, 1.0);
    _ = m1.put(2, 2.0);
    var m2 = I32F64HashBiMap.init(std.testing.allocator);
    defer m2.deinit();
    _ = m2.put(2, 2.0);
    _ = m2.put(1, 1.0);
    try std.testing.expect(m1.eql(&m2));
}

test "I32F64HashBiMap: ensureUnusedCapacity reserves both directions" {
    var m = I32F64HashBiMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(500);
    const fwd = m.forward.capacity;
    const rev = m.reverse.capacity;
    try std.testing.expect(fwd >= 500);
    try std.testing.expect(rev >= 500);
    _ = m.put(1, 1.0);
    _ = m.put(2, 2.0);
    try std.testing.expectEqual(fwd, m.forward.capacity);
    try std.testing.expectEqual(rev, m.reverse.capacity);
}

test "I32F64HashBiMap: ensureUnusedCapacity propagates allocator error" {
    // init allocates two tables (forward + reverse). Allow both, fail the
    // next alloc.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 2 });
    var m = I32F64HashBiMap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(10_000));
}
