// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;

/// Sorted map from `u21` keys to `i16` values, backed by sorted ArrayLists.
pub const CharI16TreeMap = struct {
    keys: std.ArrayListUnmanaged(u21) = .empty,
    vals: std.ArrayListUnmanaged(i16) = .empty,
    config: AllocatorConfig,

    pub fn init(allocator: Allocator) CharI16TreeMap {
        return .{ .config = AllocatorConfig.init(allocator) };
    }

    pub fn initWithConfig(config: AllocatorConfig) CharI16TreeMap {
        return .{ .config = config };
    }

    pub fn deinit(self: *CharI16TreeMap) void {
        self.keys.deinit(self.config.keysAllocator());
        self.vals.deinit(self.config.valuesAllocator());
    }

    fn orderFn(a: u21, b: u21) std.math.Order {
        return std.math.order(a, b);
    }

    fn findIndex(self: *const CharI16TreeMap, key: u21) struct { index: usize, found: bool } {
        var lo: usize = 0;
        var hi: usize = self.keys.items.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const ord = orderFn(self.keys.items[mid], key);
            if (ord == .lt) {
                lo = mid + 1;
            } else if (ord == .gt) {
                hi = mid;
            } else {
                return .{ .index = mid, .found = true };
            }
        }
        return .{ .index = lo, .found = false };
    }

    /// Inserts a key-value pair. Returns the old value if the key existed.
    pub fn put(self: *CharI16TreeMap, key: u21, value: i16) ?i16 {
        const result = self.findIndex(key);
        if (result.found) {
            const old = self.vals.items[result.index];
            self.vals.items[result.index] = value;
            return old;
        }
        self.keys.insert(self.config.keysAllocator(), result.index, key) catch @panic("out of memory");
        self.vals.insert(self.config.valuesAllocator(), result.index, value) catch @panic("out of memory");
        return null;
    }

    pub fn get(self: *const CharI16TreeMap, key: u21) ?i16 {
        const result = self.findIndex(key);
        if (!result.found) return null;
        return self.vals.items[result.index];
    }

    pub fn remove(self: *CharI16TreeMap, key: u21) ?i16 {
        const result = self.findIndex(key);
        if (!result.found) return null;
        const old = self.vals.items[result.index];
        _ = self.keys.orderedRemove(result.index);
        _ = self.vals.orderedRemove(result.index);
        return old;
    }

    pub fn containsKey(self: *const CharI16TreeMap, key: u21) bool {
        return self.findIndex(key).found;
    }

    pub fn getOrDefault(self: *const CharI16TreeMap, key: u21, default_value: i16) i16 {
        return self.get(key) orelse default_value;
    }

    pub fn len(self: *const CharI16TreeMap) usize {
        return self.keys.items.len;
    }

    /// Alias for len() — matches Go/Java naming.
    pub fn size(self: *const CharI16TreeMap) usize {
        return self.len();
    }

    pub fn isEmpty(self: *const CharI16TreeMap) bool {
        return self.keys.items.len == 0;
    }

    pub fn clear(self: *CharI16TreeMap) void {
        self.keys.clearRetainingCapacity();
        self.vals.clearRetainingCapacity();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures both the keys and values buffers can hold `additional` more
    /// entries without reallocating. Returns `error.OutOfMemory` if the
    /// allocator fails.
    pub fn ensureUnusedCapacity(self: *CharI16TreeMap, additional: usize) Allocator.Error!void {
        try self.keys.ensureUnusedCapacity(self.config.keysAllocator(), additional);
        try self.vals.ensureUnusedCapacity(self.config.valuesAllocator(), additional);
    }

    /// Ensures both internal buffers' total capacity is at least
    /// `new_capacity`.
    pub fn ensureTotalCapacity(self: *CharI16TreeMap, new_capacity: usize) Allocator.Error!void {
        try self.keys.ensureTotalCapacity(self.config.keysAllocator(), new_capacity);
        try self.vals.ensureTotalCapacity(self.config.valuesAllocator(), new_capacity);
    }

    pub fn min(self: *const CharI16TreeMap) ?struct { key: u21, value: i16 } {
        if (self.keys.items.len == 0) return null;
        return .{ .key = self.keys.items[0], .value = self.vals.items[0] };
    }

    pub fn max(self: *const CharI16TreeMap) ?struct { key: u21, value: i16 } {
        if (self.keys.items.len == 0) return null;
        const last = self.keys.items.len - 1;
        return .{ .key = self.keys.items[last], .value = self.vals.items[last] };
    }

    pub fn keysSlice(self: *const CharI16TreeMap) []const u21 {
        return self.keys.items;
    }

    pub fn valuesSlice(self: *const CharI16TreeMap) []const i16 {
        return self.vals.items;
    }

    // ---- Iteration ----

    pub fn forEach(self: *const CharI16TreeMap, f: *const fn (u21, i16) void) void {
        for (self.keys.items, self.vals.items) |k, val| f(k, val);
    }

    pub fn forEachKey(self: *const CharI16TreeMap, f: *const fn (u21) void) void {
        for (self.keys.items) |k| f(k);
    }

    pub fn forEachValue(self: *const CharI16TreeMap, f: *const fn (i16) void) void {
        for (self.vals.items) |val| f(val);
    }

    // ---- Functional Operations ----

    pub fn select(self: *const CharI16TreeMap, predicate: *const fn (u21, i16) bool) CharI16TreeMap {
        var result = init(self.config.base);
        for (self.keys.items, self.vals.items) |k, val| {
            if (predicate(k, val)) _ = result.put(k, val);
        }
        return result;
    }

    pub fn reject(self: *const CharI16TreeMap, predicate: *const fn (u21, i16) bool) CharI16TreeMap {
        var result = init(self.config.base);
        for (self.keys.items, self.vals.items) |k, val| {
            if (!predicate(k, val)) _ = result.put(k, val);
        }
        return result;
    }

    pub fn detect(self: *const CharI16TreeMap, predicate: *const fn (u21, i16) bool) ?struct { key: u21, value: i16 } {
        for (self.keys.items, self.vals.items) |k, val| {
            if (predicate(k, val)) return .{ .key = k, .value = val };
        }
        return null;
    }

    pub fn anySatisfy(self: *const CharI16TreeMap, predicate: *const fn (u21, i16) bool) bool {
        for (self.keys.items, self.vals.items) |k, val| {
            if (predicate(k, val)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const CharI16TreeMap, predicate: *const fn (u21, i16) bool) bool {
        for (self.keys.items, self.vals.items) |k, val| {
            if (!predicate(k, val)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const CharI16TreeMap, predicate: *const fn (u21, i16) bool) bool {
        for (self.keys.items, self.vals.items) |k, val| {
            if (predicate(k, val)) return false;
        }
        return true;
    }

    pub fn count(self: *const CharI16TreeMap, predicate: *const fn (u21, i16) bool) usize {
        var c: usize = 0;
        for (self.keys.items, self.vals.items) |k, val| {
            if (predicate(k, val)) c += 1;
        }
        return c;
    }

    // ---- Range Operations ----

    /// Returns the entry with the smallest key >= the given key, or null.
    pub fn ceiling(self: *const CharI16TreeMap, key: u21) ?struct { key: u21, value: i16 } {
        const result = self.findIndex(key);
        if (result.found) return .{ .key = self.keys.items[result.index], .value = self.vals.items[result.index] };
        if (result.index < self.keys.items.len) return .{ .key = self.keys.items[result.index], .value = self.vals.items[result.index] };
        return null;
    }

    /// Returns the entry with the largest key <= the given key, or null.
    pub fn floor(self: *const CharI16TreeMap, key: u21) ?struct { key: u21, value: i16 } {
        const result = self.findIndex(key);
        if (result.found) return .{ .key = self.keys.items[result.index], .value = self.vals.items[result.index] };
        if (result.index > 0) return .{ .key = self.keys.items[result.index - 1], .value = self.vals.items[result.index - 1] };
        return null;
    }

    /// Returns keys in [from, to] inclusive as a slice view.
    pub fn rangeKeys(self: *const CharI16TreeMap, from: u21, to: u21) []const u21 {
        const lo = self.findIndex(from).index;
        var hi = lo;
        while (hi < self.keys.items.len) {
            if (orderFn(self.keys.items[hi], to) == .gt) break;
            hi += 1;
        }
        if (lo >= hi) return self.keys.items[0..0];
        return self.keys.items[lo..hi];
    }

    // ---- Formatting ----

    /// Formats as "{k1=v1, k2=v2}" in sorted key order.
    pub fn format(self: *const CharI16TreeMap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll("{");
        for (self.keys.items, self.vals.items, 0..) |k, v, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{any}", .{k});
            try writer.writeAll("=");
            try writer.print("{any}", .{v});
        }
        try writer.writeAll("}");
    }

    // ---- Fluent API ----

    pub fn withKeyValue(self: *CharI16TreeMap, key: u21, value: i16) *CharI16TreeMap {
        _ = self.put(key, value);
        return self;
    }

    pub fn withoutKey(self: *CharI16TreeMap, key: u21) *CharI16TreeMap {
        _ = self.remove(key);
        return self;
    }

    // ---- Equality ----

    pub fn eql(self: *const CharI16TreeMap, other: *const CharI16TreeMap) bool {
        if (self.keys.items.len != other.keys.items.len) return false;
        for (self.keys.items, self.vals.items, other.keys.items, other.vals.items) |k1, v1, k2, v2| {
            if (!(k1 == k2)) return false;
            if (!(v1 == v2)) return false;
        }
        return true;
    }
};

test "CharI16TreeMap: put and get" {
    var m = CharI16TreeMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put('a', 1);
    _ = m.put('b', 2);
    _ = m.put('c', 3);
    try std.testing.expectEqual(@as(usize, 3), m.len());
    try std.testing.expectEqual(@as(?i16, 1), m.get('a'));
    try std.testing.expectEqual(@as(?i16, null), m.get('z'));
}

test "CharI16TreeMap: sorted keys" {
    var m = CharI16TreeMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put('c', 3);
    _ = m.put('a', 1);
    _ = m.put('b', 2);
    const keys = m.keysSlice();
    try std.testing.expectEqual('a', keys[0]);
    try std.testing.expectEqual('b', keys[1]);
    try std.testing.expectEqual('c', keys[2]);
}

test "CharI16TreeMap: min max" {
    var m = CharI16TreeMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put('c', 3);
    _ = m.put('a', 1);
    const min_entry = m.min().?;
    try std.testing.expectEqual('a', min_entry.key);
    const max_entry = m.max().?;
    try std.testing.expectEqual('c', max_entry.key);
}

test "CharI16TreeMap: remove" {
    var m = CharI16TreeMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put('a', 1);
    _ = m.put('b', 2);
    const removed = m.remove('a');
    try std.testing.expectEqual(@as(?i16, 1), removed);
    try std.testing.expectEqual(@as(usize, 1), m.len());
}

test "CharI16TreeMap: clear" {
    var m = CharI16TreeMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put('a', 1);
    m.clear();
    try std.testing.expect(m.isEmpty());
}

test "CharI16TreeMap: eql" {
    var m1 = CharI16TreeMap.init(std.testing.allocator);
    defer m1.deinit();
    _ = m1.put('a', 1);
    _ = m1.put('b', 2);

    var m2 = CharI16TreeMap.init(std.testing.allocator);
    defer m2.deinit();
    _ = m2.put('b', 2);
    _ = m2.put('a', 1);
    try std.testing.expect(m1.eql(&m2));
}

test "CharI16TreeMap: ensureUnusedCapacity reserves both buffers" {
    var m = CharI16TreeMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(100);
    const kcap = m.keys.capacity;
    const vcap = m.vals.capacity;
    try std.testing.expect(kcap >= 100);
    try std.testing.expect(vcap >= 100);
    _ = m.put('a', 1);
    _ = m.put('b', 2);
    try std.testing.expectEqual(kcap, m.keys.capacity);
    try std.testing.expectEqual(vcap, m.vals.capacity);
}

test "CharI16TreeMap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: TreeMap.init doesn't allocate (Treap is node-based),
    // so the first alloc (ensureUnusedCapacity grow) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var m = CharI16TreeMap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(1024));
}
