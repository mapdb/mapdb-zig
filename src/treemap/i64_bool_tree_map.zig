// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;

/// Sorted map from `i64` keys to `bool` values, backed by sorted ArrayLists.
pub const I64BoolTreeMap = struct {
    keys: std.ArrayListUnmanaged(i64) = .empty,
    vals: std.ArrayListUnmanaged(bool) = .empty,
    config: AllocatorConfig,

    pub fn init(allocator: Allocator) I64BoolTreeMap {
        return .{ .config = AllocatorConfig.init(allocator) };
    }

    pub fn initWithConfig(config: AllocatorConfig) I64BoolTreeMap {
        return .{ .config = config };
    }

    pub fn deinit(self: *I64BoolTreeMap) void {
        self.keys.deinit(self.config.keysAllocator());
        self.vals.deinit(self.config.valuesAllocator());
    }

    fn orderFn(a: i64, b: i64) std.math.Order {
        return std.math.order(a, b);
    }

    fn findIndex(self: *const I64BoolTreeMap, key: i64) struct { index: usize, found: bool } {
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
    pub fn put(self: *I64BoolTreeMap, key: i64, value: bool) ?bool {
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

    pub fn get(self: *const I64BoolTreeMap, key: i64) ?bool {
        const result = self.findIndex(key);
        if (!result.found) return null;
        return self.vals.items[result.index];
    }

    pub fn remove(self: *I64BoolTreeMap, key: i64) ?bool {
        const result = self.findIndex(key);
        if (!result.found) return null;
        const old = self.vals.items[result.index];
        _ = self.keys.orderedRemove(result.index);
        _ = self.vals.orderedRemove(result.index);
        return old;
    }

    pub fn containsKey(self: *const I64BoolTreeMap, key: i64) bool {
        return self.findIndex(key).found;
    }

    pub fn getOrDefault(self: *const I64BoolTreeMap, key: i64, default_value: bool) bool {
        return self.get(key) orelse default_value;
    }

    pub fn len(self: *const I64BoolTreeMap) usize {
        return self.keys.items.len;
    }

    /// Alias for len() — matches Go/Java naming.
    pub fn size(self: *const I64BoolTreeMap) usize {
        return self.len();
    }

    pub fn isEmpty(self: *const I64BoolTreeMap) bool {
        return self.keys.items.len == 0;
    }

    pub fn clear(self: *I64BoolTreeMap) void {
        self.keys.clearRetainingCapacity();
        self.vals.clearRetainingCapacity();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures both the keys and values buffers can hold `additional` more
    /// entries without reallocating. Returns `error.OutOfMemory` if the
    /// allocator fails.
    pub fn ensureUnusedCapacity(self: *I64BoolTreeMap, additional: usize) Allocator.Error!void {
        try self.keys.ensureUnusedCapacity(self.config.keysAllocator(), additional);
        try self.vals.ensureUnusedCapacity(self.config.valuesAllocator(), additional);
    }

    /// Ensures both internal buffers' total capacity is at least
    /// `new_capacity`.
    pub fn ensureTotalCapacity(self: *I64BoolTreeMap, new_capacity: usize) Allocator.Error!void {
        try self.keys.ensureTotalCapacity(self.config.keysAllocator(), new_capacity);
        try self.vals.ensureTotalCapacity(self.config.valuesAllocator(), new_capacity);
    }

    pub fn min(self: *const I64BoolTreeMap) ?struct { key: i64, value: bool } {
        if (self.keys.items.len == 0) return null;
        return .{ .key = self.keys.items[0], .value = self.vals.items[0] };
    }

    pub fn max(self: *const I64BoolTreeMap) ?struct { key: i64, value: bool } {
        if (self.keys.items.len == 0) return null;
        const last = self.keys.items.len - 1;
        return .{ .key = self.keys.items[last], .value = self.vals.items[last] };
    }

    pub fn keysSlice(self: *const I64BoolTreeMap) []const i64 {
        return self.keys.items;
    }

    pub fn valuesSlice(self: *const I64BoolTreeMap) []const bool {
        return self.vals.items;
    }

    // ---- Iteration ----

    pub fn forEach(self: *const I64BoolTreeMap, f: *const fn (i64, bool) void) void {
        for (self.keys.items, self.vals.items) |k, val| f(k, val);
    }

    pub fn forEachKey(self: *const I64BoolTreeMap, f: *const fn (i64) void) void {
        for (self.keys.items) |k| f(k);
    }

    pub fn forEachValue(self: *const I64BoolTreeMap, f: *const fn (bool) void) void {
        for (self.vals.items) |val| f(val);
    }

    // ---- Functional Operations ----

    pub fn select(self: *const I64BoolTreeMap, predicate: *const fn (i64, bool) bool) I64BoolTreeMap {
        var result = init(self.config.base);
        for (self.keys.items, self.vals.items) |k, val| {
            if (predicate(k, val)) _ = result.put(k, val);
        }
        return result;
    }

    pub fn reject(self: *const I64BoolTreeMap, predicate: *const fn (i64, bool) bool) I64BoolTreeMap {
        var result = init(self.config.base);
        for (self.keys.items, self.vals.items) |k, val| {
            if (!predicate(k, val)) _ = result.put(k, val);
        }
        return result;
    }

    pub fn detect(self: *const I64BoolTreeMap, predicate: *const fn (i64, bool) bool) ?struct { key: i64, value: bool } {
        for (self.keys.items, self.vals.items) |k, val| {
            if (predicate(k, val)) return .{ .key = k, .value = val };
        }
        return null;
    }

    pub fn anySatisfy(self: *const I64BoolTreeMap, predicate: *const fn (i64, bool) bool) bool {
        for (self.keys.items, self.vals.items) |k, val| {
            if (predicate(k, val)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const I64BoolTreeMap, predicate: *const fn (i64, bool) bool) bool {
        for (self.keys.items, self.vals.items) |k, val| {
            if (!predicate(k, val)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const I64BoolTreeMap, predicate: *const fn (i64, bool) bool) bool {
        for (self.keys.items, self.vals.items) |k, val| {
            if (predicate(k, val)) return false;
        }
        return true;
    }

    pub fn count(self: *const I64BoolTreeMap, predicate: *const fn (i64, bool) bool) usize {
        var c: usize = 0;
        for (self.keys.items, self.vals.items) |k, val| {
            if (predicate(k, val)) c += 1;
        }
        return c;
    }

    // ---- Range Operations ----

    /// Returns the entry with the smallest key >= the given key, or null.
    pub fn ceiling(self: *const I64BoolTreeMap, key: i64) ?struct { key: i64, value: bool } {
        const result = self.findIndex(key);
        if (result.found) return .{ .key = self.keys.items[result.index], .value = self.vals.items[result.index] };
        if (result.index < self.keys.items.len) return .{ .key = self.keys.items[result.index], .value = self.vals.items[result.index] };
        return null;
    }

    /// Returns the entry with the largest key <= the given key, or null.
    pub fn floor(self: *const I64BoolTreeMap, key: i64) ?struct { key: i64, value: bool } {
        const result = self.findIndex(key);
        if (result.found) return .{ .key = self.keys.items[result.index], .value = self.vals.items[result.index] };
        if (result.index > 0) return .{ .key = self.keys.items[result.index - 1], .value = self.vals.items[result.index - 1] };
        return null;
    }

    /// Returns keys in [from, to] inclusive as a slice view.
    pub fn rangeKeys(self: *const I64BoolTreeMap, from: i64, to: i64) []const i64 {
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
    pub fn format(self: *const I64BoolTreeMap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn withKeyValue(self: *I64BoolTreeMap, key: i64, value: bool) *I64BoolTreeMap {
        _ = self.put(key, value);
        return self;
    }

    pub fn withoutKey(self: *I64BoolTreeMap, key: i64) *I64BoolTreeMap {
        _ = self.remove(key);
        return self;
    }

    // ---- Equality ----

    pub fn eql(self: *const I64BoolTreeMap, other: *const I64BoolTreeMap) bool {
        if (self.keys.items.len != other.keys.items.len) return false;
        for (self.keys.items, self.vals.items, other.keys.items, other.vals.items) |k1, v1, k2, v2| {
            if (!(k1 == k2)) return false;
            if (!(v1 == v2)) return false;
        }
        return true;
    }
};

test "I64BoolTreeMap: put and get" {
    var m = I64BoolTreeMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, true);
    _ = m.put(2, false);
    _ = m.put(3, true);
    try std.testing.expectEqual(@as(usize, 3), m.len());
    try std.testing.expectEqual(@as(?bool, true), m.get(1));
    try std.testing.expectEqual(@as(?bool, null), m.get(99));
}

test "I64BoolTreeMap: sorted keys" {
    var m = I64BoolTreeMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(3, true);
    _ = m.put(1, true);
    _ = m.put(2, false);
    const keys = m.keysSlice();
    try std.testing.expectEqual(1, keys[0]);
    try std.testing.expectEqual(2, keys[1]);
    try std.testing.expectEqual(3, keys[2]);
}

test "I64BoolTreeMap: min max" {
    var m = I64BoolTreeMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(3, true);
    _ = m.put(1, true);
    const min_entry = m.min().?;
    try std.testing.expectEqual(1, min_entry.key);
    const max_entry = m.max().?;
    try std.testing.expectEqual(3, max_entry.key);
}

test "I64BoolTreeMap: remove" {
    var m = I64BoolTreeMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, true);
    _ = m.put(2, false);
    const removed = m.remove(1);
    try std.testing.expectEqual(@as(?bool, true), removed);
    try std.testing.expectEqual(@as(usize, 1), m.len());
}

test "I64BoolTreeMap: clear" {
    var m = I64BoolTreeMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1, true);
    m.clear();
    try std.testing.expect(m.isEmpty());
}

test "I64BoolTreeMap: eql" {
    var m1 = I64BoolTreeMap.init(std.testing.allocator);
    defer m1.deinit();
    _ = m1.put(1, true);
    _ = m1.put(2, false);

    var m2 = I64BoolTreeMap.init(std.testing.allocator);
    defer m2.deinit();
    _ = m2.put(2, false);
    _ = m2.put(1, true);
    try std.testing.expect(m1.eql(&m2));
}

test "I64BoolTreeMap: ensureUnusedCapacity reserves both buffers" {
    var m = I64BoolTreeMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(100);
    const kcap = m.keys.capacity;
    const vcap = m.vals.capacity;
    try std.testing.expect(kcap >= 100);
    try std.testing.expect(vcap >= 100);
    _ = m.put(1, true);
    _ = m.put(2, false);
    try std.testing.expectEqual(kcap, m.keys.capacity);
    try std.testing.expectEqual(vcap, m.vals.capacity);
}

test "I64BoolTreeMap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: TreeMap.init doesn't allocate (Treap is node-based),
    // so the first alloc (ensureUnusedCapacity grow) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var m = I64BoolTreeMap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(1024));
}
