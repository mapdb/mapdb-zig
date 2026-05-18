// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const I16BoolHashBiMap = @import("i16_bool_hash_bi_map.zig").I16BoolHashBiMap;

/// Bidirectional hash map from `bool` keys to `i16` values.
///
/// Maintains two internal OpenHashMaps (forward and reverse) so that both
/// key-to-value and value-to-key lookups are O(1). Every mutation keeps both
/// maps in sync.
pub const BoolI16HashBiMap = struct {
    forward: OpenHashMap(bool, i16),
    reverse: OpenHashMap(i16, bool),
    config: AllocatorConfig,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) BoolI16HashBiMap {
        return initWithConfig(AllocatorConfig.init(allocator));
    }

    /// Create with fine-grained allocator control.
    pub fn initWithConfig(config: AllocatorConfig) BoolI16HashBiMap {
        return .{
            .forward = OpenHashMap(bool, i16).init(
                config.keysAllocator(),
                config.valuesAllocator(),
                config.indexAllocator(),
            ) catch @panic("out of memory"),
            .reverse = OpenHashMap(i16, bool).init(
                config.keysAllocator(),
                config.valuesAllocator(),
                config.indexAllocator(),
            ) catch @panic("out of memory"),
            .config = config,
        };
    }

    pub fn deinit(self: *BoolI16HashBiMap) void {
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
    pub fn put(self: *BoolI16HashBiMap, key: bool, value: i16) ?i16 {
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
    pub fn get(self: *const BoolI16HashBiMap, key: bool) ?i16 {
        return self.forward.get(key);
    }

    /// Returns the key for the given value (reverse lookup), or null.
    pub fn getKey(self: *const BoolI16HashBiMap, value: i16) ?bool {
        return self.reverse.get(value);
    }

    /// Removes the mapping for the given key and its reverse. Returns the old value if present.
    pub fn remove(self: *BoolI16HashBiMap, key: bool) ?i16 {
        const old_value = self.forward.remove(key);
        if (old_value) |ov| {
            _ = self.reverse.remove(ov);
        }
        return old_value;
    }

    /// Removes the mapping for the given value and its forward key. Returns the old key if present.
    pub fn removeValue(self: *BoolI16HashBiMap, value: i16) ?bool {
        const old_key = self.reverse.remove(value);
        if (old_key) |ok| {
            _ = self.forward.remove(ok);
        }
        return old_key;
    }

    pub fn containsKey(self: *const BoolI16HashBiMap, key: bool) bool {
        return self.forward.containsKey(key);
    }

    pub fn containsValue(self: *const BoolI16HashBiMap, value: i16) bool {
        return self.reverse.containsKey(value);
    }

    pub fn len(self: *const BoolI16HashBiMap) usize {
        return self.forward.len();
    }

    pub fn isEmpty(self: *const BoolI16HashBiMap) bool {
        return self.forward.isEmpty();
    }

    pub fn clear(self: *BoolI16HashBiMap) void {
        self.forward.clear();
        self.reverse.clear();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures both the forward and reverse maps can hold `additional`
    /// more entries without triggering a rehash. Returns
    /// `error.OutOfMemory` if the allocator fails.
    pub fn ensureUnusedCapacity(self: *BoolI16HashBiMap, additional: usize) Allocator.Error!void {
        try self.forward.ensureCapacity(additional);
        try self.reverse.ensureCapacity(additional);
    }

    /// Ensures both internal maps' total capacity covers at least
    /// `new_capacity` entries.
    pub fn ensureTotalCapacity(self: *BoolI16HashBiMap, new_capacity: usize) Allocator.Error!void {
        const cur = self.forward.len();
        if (new_capacity <= cur) return;
        try self.ensureUnusedCapacity(new_capacity - cur);
    }

    // ---- Iteration ----

    pub fn forEach(self: *const BoolI16HashBiMap, f: *const fn (bool, i16) void) void {
        self.forward.forEach(f);
    }

    pub fn forEachKey(self: *const BoolI16HashBiMap, f: *const fn (bool) void) void {
        self.forward.forEachKey(f);
    }

    pub fn forEachValue(self: *const BoolI16HashBiMap, f: *const fn (i16) void) void {
        self.forward.forEachValue(f);
    }

    // ---- Inverse ----

    /// Returns a new BiMap with keys and values swapped (value->key becomes key->value).
    /// The caller owns the returned map and must call deinit() on it.
    pub fn inverse(self: *const BoolI16HashBiMap) I16BoolHashBiMap {
        var result = I16BoolHashBiMap.init(self.config.base);
        for (0..self.forward.capacity) |i| {
            if (self.forward.entries[i].occupied) {
                _ = result.put(self.forward.entries[i].value, self.forward.entries[i].key);
            }
        }
        return result;
    }

    // ---- Formatting ----

    pub fn format(self: *const BoolI16HashBiMap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const BoolI16HashBiMap, other: *const BoolI16HashBiMap) bool {
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

test "BoolI16HashBiMap: put and get and getKey" {
    var m = BoolI16HashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1);
    _ = m.put(false, 2);
    // forward lookup
    try std.testing.expectEqual(@as(?i16, 1), m.get(true));
    try std.testing.expectEqual(@as(?i16, 2), m.get(false));
    // reverse lookup
    try std.testing.expectEqual(@as(?bool, true), m.getKey(1));
    try std.testing.expectEqual(@as(?bool, false), m.getKey(2));

    // missing value
    try std.testing.expectEqual(@as(?bool, null), m.getKey(99));
    try std.testing.expectEqual(@as(usize, 2), m.len());
}

test "BoolI16HashBiMap: put overwrite updates reverse" {
    var m = BoolI16HashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1);
    // overwrite key with new value
    const old = m.put(true, 2);
    try std.testing.expectEqual(@as(?i16, 1), old);
    // forward should have new value
    try std.testing.expectEqual(@as(?i16, 2), m.get(true));
    // reverse for old value should be gone
    try std.testing.expectEqual(@as(?bool, null), m.getKey(1));
    // reverse for new value should point to key
    try std.testing.expectEqual(@as(?bool, true), m.getKey(2));
}

test "BoolI16HashBiMap: remove" {
    var m = BoolI16HashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1);
    _ = m.put(false, 2);
    const removed = m.remove(true);
    try std.testing.expectEqual(@as(?i16, 1), removed);
    try std.testing.expectEqual(@as(usize, 1), m.len());
    try std.testing.expect(!m.containsKey(true));
    // reverse should also be cleaned up
    try std.testing.expectEqual(@as(?bool, null), m.getKey(1));
}

test "BoolI16HashBiMap: removeValue" {
    var m = BoolI16HashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1);
    _ = m.put(false, 2);
    const removed_key = m.removeValue(1);
    try std.testing.expectEqual(@as(?bool, true), removed_key);
    try std.testing.expectEqual(@as(usize, 1), m.len());
    try std.testing.expect(!m.containsValue(1));
    try std.testing.expect(!m.containsKey(true));
}

test "BoolI16HashBiMap: containsKey and containsValue" {
    var m = BoolI16HashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1);
    try std.testing.expect(m.containsKey(true));

    try std.testing.expect(m.containsValue(1));
    try std.testing.expect(!m.containsValue(99));
}

test "BoolI16HashBiMap: clear" {
    var m = BoolI16HashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1);
    _ = m.put(false, 2);
    m.clear();
    try std.testing.expect(m.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), m.len());
}

test "BoolI16HashBiMap: inverse" {
    var m = BoolI16HashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1);
    _ = m.put(false, 2);
    var inv = m.inverse();
    defer inv.deinit();
    // inverse should have same count
    try std.testing.expectEqual(@as(usize, 2), inv.len());
    // inverse forward lookup: value -> key
    try std.testing.expectEqual(@as(?bool, true), inv.get(1));
    try std.testing.expectEqual(@as(?bool, false), inv.get(2));
}

test "BoolI16HashBiMap: display format" {
    var m = BoolI16HashBiMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, 1);
    // Just verify formatting does not crash
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    m.format("", .{}, fbs.writer()) catch {};
    const output = fbs.getWritten();
    try std.testing.expect(output.len > 0);
}

test "BoolI16HashBiMap: eql" {
    var m1 = BoolI16HashBiMap.init(std.testing.allocator);
    defer m1.deinit();
    _ = m1.put(true, 1);
    _ = m1.put(false, 2);
    var m2 = BoolI16HashBiMap.init(std.testing.allocator);
    defer m2.deinit();
    _ = m2.put(false, 2);
    _ = m2.put(true, 1);
    try std.testing.expect(m1.eql(&m2));
}

test "BoolI16HashBiMap: ensureUnusedCapacity reserves both directions" {
    var m = BoolI16HashBiMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(500);
    const fwd = m.forward.capacity;
    const rev = m.reverse.capacity;
    try std.testing.expect(fwd >= 500);
    try std.testing.expect(rev >= 500);
    _ = m.put(true, 1);
    _ = m.put(false, 2);
    try std.testing.expectEqual(fwd, m.forward.capacity);
    try std.testing.expectEqual(rev, m.reverse.capacity);
}

test "BoolI16HashBiMap: ensureUnusedCapacity propagates allocator error" {
    // init allocates two tables (forward + reverse). Allow both, fail the
    // next alloc.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 2 });
    var m = BoolI16HashBiMap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(10_000));
}
