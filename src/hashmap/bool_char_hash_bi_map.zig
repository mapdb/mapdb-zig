// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const CharBoolHashBiMap = @import("char_bool_hash_bi_map.zig").CharBoolHashBiMap;

/// Bidirectional hash map from `bool` keys to `u21` values.
///
/// Maintains two internal OpenHashMaps (forward and reverse) so that both
/// key-to-value and value-to-key lookups are O(1). Every mutation keeps both
/// maps in sync.
pub const BoolCharHashBiMap = struct {
    forward: OpenHashMap(bool, u21),
    reverse: OpenHashMap(u21, bool),
    config: AllocatorConfig,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) BoolCharHashBiMap {
        return initWithConfig(AllocatorConfig.init(allocator));
    }

    /// Create with fine-grained allocator control.
    pub fn initWithConfig(config: AllocatorConfig) BoolCharHashBiMap {
        return .{
            .forward = OpenHashMap(bool, u21).init(
                config.keysAllocator(),
                config.valuesAllocator(),
                config.indexAllocator(),
            ) catch @panic("out of memory"),
            .reverse = OpenHashMap(u21, bool).init(
                config.keysAllocator(),
                config.valuesAllocator(),
                config.indexAllocator(),
            ) catch @panic("out of memory"),
            .config = config,
        };
    }

    pub fn deinit(self: *BoolCharHashBiMap) void {
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
    pub fn put(self: *BoolCharHashBiMap, key: bool, value: u21) ?u21 {
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
    pub fn get(self: *const BoolCharHashBiMap, key: bool) ?u21 {
        return self.forward.get(key);
    }

    /// Returns the key for the given value (reverse lookup), or null.
    pub fn getKey(self: *const BoolCharHashBiMap, value: u21) ?bool {
        return self.reverse.get(value);
    }

    /// Removes the mapping for the given key and its reverse. Returns the old value if present.
    pub fn remove(self: *BoolCharHashBiMap, key: bool) ?u21 {
        const old_value = self.forward.remove(key);
        if (old_value) |ov| {
            _ = self.reverse.remove(ov);
        }
        return old_value;
    }

    /// Removes the mapping for the given value and its forward key. Returns the old key if present.
    pub fn removeValue(self: *BoolCharHashBiMap, value: u21) ?bool {
        const old_key = self.reverse.remove(value);
        if (old_key) |ok| {
            _ = self.forward.remove(ok);
        }
        return old_key;
    }

    pub fn containsKey(self: *const BoolCharHashBiMap, key: bool) bool {
        return self.forward.containsKey(key);
    }

    pub fn containsValue(self: *const BoolCharHashBiMap, value: u21) bool {
        return self.reverse.containsKey(value);
    }

    pub fn len(self: *const BoolCharHashBiMap) usize {
        return self.forward.len();
    }

    pub fn isEmpty(self: *const BoolCharHashBiMap) bool {
        return self.forward.isEmpty();
    }

    pub fn clear(self: *BoolCharHashBiMap) void {
        self.forward.clear();
        self.reverse.clear();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures both the forward and reverse maps can hold `additional`
    /// more entries without triggering a rehash. Returns
    /// `error.OutOfMemory` if the allocator fails.
    pub fn ensureUnusedCapacity(self: *BoolCharHashBiMap, additional: usize) Allocator.Error!void {
        try self.forward.ensureCapacity(additional);
        try self.reverse.ensureCapacity(additional);
    }

    /// Ensures both internal maps' total capacity covers at least
    /// `new_capacity` entries.
    pub fn ensureTotalCapacity(self: *BoolCharHashBiMap, new_capacity: usize) Allocator.Error!void {
        const cur = self.forward.len();
        if (new_capacity <= cur) return;
        try self.ensureUnusedCapacity(new_capacity - cur);
    }

    // ---- Iteration ----

    pub fn forEach(self: *const BoolCharHashBiMap, f: *const fn (bool, u21) void) void {
        self.forward.forEach(f);
    }

    pub fn forEachKey(self: *const BoolCharHashBiMap, f: *const fn (bool) void) void {
        self.forward.forEachKey(f);
    }

    pub fn forEachValue(self: *const BoolCharHashBiMap, f: *const fn (u21) void) void {
        self.forward.forEachValue(f);
    }

    // ---- Inverse ----

    /// Returns a new BiMap with keys and values swapped (value->key becomes key->value).
    /// The caller owns the returned map and must call deinit() on it.
    pub fn inverse(self: *const BoolCharHashBiMap) CharBoolHashBiMap {
        var result = CharBoolHashBiMap.init(self.config.base);
        for (0..self.forward.capacity) |i| {
            if (self.forward.entries[i].occupied) {
                _ = result.put(self.forward.entries[i].value, self.forward.entries[i].key);
            }
        }
        return result;
    }

    // ---- Formatting ----

    pub fn format(self: *const BoolCharHashBiMap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const BoolCharHashBiMap, other: *const BoolCharHashBiMap) bool {
        if (self.len() != other.len()) return false;
        for (0..self.forward.capacity) |i| {
            if (self.forward.entries[i].occupied) {
                const other_val = other.get(self.forward.entries[i].key) orelse return false;
                if (!(self.forward.entries[i].value == other_val)) return false;
            }
        }
        return true;
    }
};

// ---- Tests ----

test "BoolCharHashBiMap: put and get and getKey" {
    var m = BoolCharHashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 'a');
    _ = m.put(false, 'b');
    // forward lookup
    try std.testing.expectEqual(@as(?u21, 'a'), m.get(true));
    try std.testing.expectEqual(@as(?u21, 'b'), m.get(false));
    // reverse lookup
    try std.testing.expectEqual(@as(?bool, true), m.getKey('a'));
    try std.testing.expectEqual(@as(?bool, false), m.getKey('b'));

    // missing value
    try std.testing.expectEqual(@as(?bool, null), m.getKey('z'));
    try std.testing.expectEqual(@as(usize, 2), m.len());
}

test "BoolCharHashBiMap: put overwrite updates reverse" {
    var m = BoolCharHashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 'a');
    // overwrite key with new value
    const old = m.put(true, 'b');
    try std.testing.expectEqual(@as(?u21, 'a'), old);
    // forward should have new value
    try std.testing.expectEqual(@as(?u21, 'b'), m.get(true));
    // reverse for old value should be gone
    try std.testing.expectEqual(@as(?bool, null), m.getKey('a'));
    // reverse for new value should point to key
    try std.testing.expectEqual(@as(?bool, true), m.getKey('b'));
}

test "BoolCharHashBiMap: remove" {
    var m = BoolCharHashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 'a');
    _ = m.put(false, 'b');
    const removed = m.remove(true);
    try std.testing.expectEqual(@as(?u21, 'a'), removed);
    try std.testing.expectEqual(@as(usize, 1), m.len());
    try std.testing.expect(!m.containsKey(true));
    // reverse should also be cleaned up
    try std.testing.expectEqual(@as(?bool, null), m.getKey('a'));
}

test "BoolCharHashBiMap: removeValue" {
    var m = BoolCharHashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 'a');
    _ = m.put(false, 'b');
    const removed_key = m.removeValue('a');
    try std.testing.expectEqual(@as(?bool, true), removed_key);
    try std.testing.expectEqual(@as(usize, 1), m.len());
    try std.testing.expect(!m.containsValue('a'));
    try std.testing.expect(!m.containsKey(true));
}

test "BoolCharHashBiMap: containsKey and containsValue" {
    var m = BoolCharHashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 'a');
    try std.testing.expect(m.containsKey(true));

    try std.testing.expect(m.containsValue('a'));
    try std.testing.expect(!m.containsValue('z'));
}

test "BoolCharHashBiMap: clear" {
    var m = BoolCharHashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 'a');
    _ = m.put(false, 'b');
    m.clear();
    try std.testing.expect(m.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), m.len());
}

test "BoolCharHashBiMap: inverse" {
    var m = BoolCharHashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 'a');
    _ = m.put(false, 'b');
    var inv = m.inverse();
    defer inv.deinit();
    // inverse should have same count
    try std.testing.expectEqual(@as(usize, 2), inv.len());
    // inverse forward lookup: value -> key
    try std.testing.expectEqual(@as(?bool, true), inv.get('a'));
    try std.testing.expectEqual(@as(?bool, false), inv.get('b'));
}

test "BoolCharHashBiMap: display format" {
    var m = BoolCharHashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 'a');
    // Just verify formatting does not crash
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    m.format("", .{}, fbs.writer()) catch {};
    const output = fbs.getWritten();
    try std.testing.expect(output.len > 0);
}

test "BoolCharHashBiMap: eql" {
    var m1 = BoolCharHashBiMap.init(std.testing.allocator);
    defer m1.deinit();
    _ = m1.put(true, 'a');
    _ = m1.put(false, 'b');
    var m2 = BoolCharHashBiMap.init(std.testing.allocator);
    defer m2.deinit();
    _ = m2.put(false, 'b');
    _ = m2.put(true, 'a');
    try std.testing.expect(m1.eql(&m2));
}

test "BoolCharHashBiMap: ensureUnusedCapacity reserves both directions" {
    var m = BoolCharHashBiMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(500);
    const fwd = m.forward.capacity;
    const rev = m.reverse.capacity;
    try std.testing.expect(fwd >= 500);
    try std.testing.expect(rev >= 500);
    _ = m.put(true, 'a');
    _ = m.put(false, 'b');
    try std.testing.expectEqual(fwd, m.forward.capacity);
    try std.testing.expectEqual(rev, m.reverse.capacity);
}

test "BoolCharHashBiMap: ensureUnusedCapacity propagates allocator error" {
    // init allocates two tables (forward + reverse). Allow both, fail the
    // next alloc.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 2 });
    var m = BoolCharHashBiMap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(10_000));
}
