// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;

/// Sorted map from `f32` keys to `u21` values, backed by sorted ArrayLists.
pub const F32CharTreeMap = struct {
    keys: std.ArrayListUnmanaged(f32) = .empty,
    vals: std.ArrayListUnmanaged(u21) = .empty,
    config: AllocatorConfig,

    pub fn init(allocator: Allocator) F32CharTreeMap {
        return .{ .config = AllocatorConfig.init(allocator) };
    }

    pub fn initWithConfig(config: AllocatorConfig) F32CharTreeMap {
        return .{ .config = config };
    }

    pub fn deinit(self: *F32CharTreeMap) void {
        self.keys.deinit(self.config.keysAllocator());
        self.vals.deinit(self.config.valuesAllocator());
    }

    fn orderFn(a: f32, b: f32) std.math.Order {
        return (blk: {
            const a_bits: u32 = @bitCast(a);
            const b_bits: u32 = @bitCast(b);
            if (std.math.isNan(a) or std.math.isNan(b)) break :blk std.math.order(a_bits, b_bits);
            const ord = std.math.order(a, b);
            if (ord != .eq) break :blk ord;
            break :blk std.math.order(a_bits, b_bits);
        });
    }

    fn findIndex(self: *const F32CharTreeMap, key: f32) struct { index: usize, found: bool } {
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
    pub fn put(self: *F32CharTreeMap, key: f32, value: u21) ?u21 {
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

    pub fn get(self: *const F32CharTreeMap, key: f32) ?u21 {
        const result = self.findIndex(key);
        if (!result.found) return null;
        return self.vals.items[result.index];
    }

    pub fn remove(self: *F32CharTreeMap, key: f32) ?u21 {
        const result = self.findIndex(key);
        if (!result.found) return null;
        const old = self.vals.items[result.index];
        _ = self.keys.orderedRemove(result.index);
        _ = self.vals.orderedRemove(result.index);
        return old;
    }

    pub fn containsKey(self: *const F32CharTreeMap, key: f32) bool {
        return self.findIndex(key).found;
    }

    pub fn getOrDefault(self: *const F32CharTreeMap, key: f32, default_value: u21) u21 {
        return self.get(key) orelse default_value;
    }

    pub fn len(self: *const F32CharTreeMap) usize {
        return self.keys.items.len;
    }

    /// Alias for len() — matches Go/Java naming.
    pub fn size(self: *const F32CharTreeMap) usize {
        return self.len();
    }

    pub fn isEmpty(self: *const F32CharTreeMap) bool {
        return self.keys.items.len == 0;
    }

    pub fn clear(self: *F32CharTreeMap) void {
        self.keys.clearRetainingCapacity();
        self.vals.clearRetainingCapacity();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures both the keys and values buffers can hold `additional` more
    /// entries without reallocating. Returns `error.OutOfMemory` if the
    /// allocator fails.
    pub fn ensureUnusedCapacity(self: *F32CharTreeMap, additional: usize) Allocator.Error!void {
        try self.keys.ensureUnusedCapacity(self.config.keysAllocator(), additional);
        try self.vals.ensureUnusedCapacity(self.config.valuesAllocator(), additional);
    }

    /// Ensures both internal buffers' total capacity is at least
    /// `new_capacity`.
    pub fn ensureTotalCapacity(self: *F32CharTreeMap, new_capacity: usize) Allocator.Error!void {
        try self.keys.ensureTotalCapacity(self.config.keysAllocator(), new_capacity);
        try self.vals.ensureTotalCapacity(self.config.valuesAllocator(), new_capacity);
    }

    pub fn min(self: *const F32CharTreeMap) ?struct { key: f32, value: u21 } {
        if (self.keys.items.len == 0) return null;
        return .{ .key = self.keys.items[0], .value = self.vals.items[0] };
    }

    pub fn max(self: *const F32CharTreeMap) ?struct { key: f32, value: u21 } {
        if (self.keys.items.len == 0) return null;
        const last = self.keys.items.len - 1;
        return .{ .key = self.keys.items[last], .value = self.vals.items[last] };
    }

    pub fn keysSlice(self: *const F32CharTreeMap) []const f32 {
        return self.keys.items;
    }

    pub fn valuesSlice(self: *const F32CharTreeMap) []const u21 {
        return self.vals.items;
    }

    // ---- Iteration ----

    pub fn forEach(self: *const F32CharTreeMap, f: *const fn (f32, u21) void) void {
        for (self.keys.items, self.vals.items) |k, val| f(k, val);
    }

    pub fn forEachKey(self: *const F32CharTreeMap, f: *const fn (f32) void) void {
        for (self.keys.items) |k| f(k);
    }

    pub fn forEachValue(self: *const F32CharTreeMap, f: *const fn (u21) void) void {
        for (self.vals.items) |val| f(val);
    }

    // ---- Functional Operations ----

    pub fn select(self: *const F32CharTreeMap, predicate: *const fn (f32, u21) bool) F32CharTreeMap {
        var result = init(self.config.base);
        for (self.keys.items, self.vals.items) |k, val| {
            if (predicate(k, val)) _ = result.put(k, val);
        }
        return result;
    }

    pub fn reject(self: *const F32CharTreeMap, predicate: *const fn (f32, u21) bool) F32CharTreeMap {
        var result = init(self.config.base);
        for (self.keys.items, self.vals.items) |k, val| {
            if (!predicate(k, val)) _ = result.put(k, val);
        }
        return result;
    }

    pub fn detect(self: *const F32CharTreeMap, predicate: *const fn (f32, u21) bool) ?struct { key: f32, value: u21 } {
        for (self.keys.items, self.vals.items) |k, val| {
            if (predicate(k, val)) return .{ .key = k, .value = val };
        }
        return null;
    }

    pub fn anySatisfy(self: *const F32CharTreeMap, predicate: *const fn (f32, u21) bool) bool {
        for (self.keys.items, self.vals.items) |k, val| {
            if (predicate(k, val)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const F32CharTreeMap, predicate: *const fn (f32, u21) bool) bool {
        for (self.keys.items, self.vals.items) |k, val| {
            if (!predicate(k, val)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const F32CharTreeMap, predicate: *const fn (f32, u21) bool) bool {
        for (self.keys.items, self.vals.items) |k, val| {
            if (predicate(k, val)) return false;
        }
        return true;
    }

    pub fn count(self: *const F32CharTreeMap, predicate: *const fn (f32, u21) bool) usize {
        var c: usize = 0;
        for (self.keys.items, self.vals.items) |k, val| {
            if (predicate(k, val)) c += 1;
        }
        return c;
    }

    // ---- Range Operations ----

    /// Returns the entry with the smallest key >= the given key, or null.
    pub fn ceiling(self: *const F32CharTreeMap, key: f32) ?struct { key: f32, value: u21 } {
        const result = self.findIndex(key);
        if (result.found) return .{ .key = self.keys.items[result.index], .value = self.vals.items[result.index] };
        if (result.index < self.keys.items.len) return .{ .key = self.keys.items[result.index], .value = self.vals.items[result.index] };
        return null;
    }

    /// Returns the entry with the largest key <= the given key, or null.
    pub fn floor(self: *const F32CharTreeMap, key: f32) ?struct { key: f32, value: u21 } {
        const result = self.findIndex(key);
        if (result.found) return .{ .key = self.keys.items[result.index], .value = self.vals.items[result.index] };
        if (result.index > 0) return .{ .key = self.keys.items[result.index - 1], .value = self.vals.items[result.index - 1] };
        return null;
    }

    /// Returns keys in [from, to] inclusive as a slice view.
    pub fn rangeKeys(self: *const F32CharTreeMap, from: f32, to: f32) []const f32 {
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
    pub fn format(self: *const F32CharTreeMap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn withKeyValue(self: *F32CharTreeMap, key: f32, value: u21) *F32CharTreeMap {
        _ = self.put(key, value);
        return self;
    }

    pub fn withoutKey(self: *F32CharTreeMap, key: f32) *F32CharTreeMap {
        _ = self.remove(key);
        return self;
    }

    // ---- Equality ----

    pub fn eql(self: *const F32CharTreeMap, other: *const F32CharTreeMap) bool {
        if (self.keys.items.len != other.keys.items.len) return false;
        for (self.keys.items, self.vals.items, other.keys.items, other.vals.items) |k1, v1, k2, v2| {
            if (!(@as(u32, @bitCast(k1)) == @as(u32, @bitCast(k2)))) return false;
            if (!(v1 == v2)) return false;
        }
        return true;
    }
};

test "F32CharTreeMap: put and get" {
    var m = F32CharTreeMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 'a');
    _ = m.put(2.0, 'b');
    _ = m.put(3.0, 'c');
    try std.testing.expectEqual(@as(usize, 3), m.len());
    try std.testing.expectEqual(@as(?u21, 'a'), m.get(1.0));
    try std.testing.expectEqual(@as(?u21, null), m.get(99.0));
}

test "F32CharTreeMap: sorted keys" {
    var m = F32CharTreeMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(3.0, 'c');
    _ = m.put(1.0, 'a');
    _ = m.put(2.0, 'b');
    const keys = m.keysSlice();
    try std.testing.expectEqual(1.0, keys[0]);
    try std.testing.expectEqual(2.0, keys[1]);
    try std.testing.expectEqual(3.0, keys[2]);
}

test "F32CharTreeMap: min max" {
    var m = F32CharTreeMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(3.0, 'c');
    _ = m.put(1.0, 'a');
    const min_entry = m.min().?;
    try std.testing.expectEqual(1.0, min_entry.key);
    const max_entry = m.max().?;
    try std.testing.expectEqual(3.0, max_entry.key);
}

test "F32CharTreeMap: remove" {
    var m = F32CharTreeMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 'a');
    _ = m.put(2.0, 'b');
    const removed = m.remove(1.0);
    try std.testing.expectEqual(@as(?u21, 'a'), removed);
    try std.testing.expectEqual(@as(usize, 1), m.len());
}

test "F32CharTreeMap: clear" {
    var m = F32CharTreeMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(1.0, 'a');
    m.clear();
    try std.testing.expect(m.isEmpty());
}

test "F32CharTreeMap: eql" {
    var m1 = F32CharTreeMap.init(std.testing.allocator);
    defer m1.deinit();
    _ = m1.put(1.0, 'a');
    _ = m1.put(2.0, 'b');

    var m2 = F32CharTreeMap.init(std.testing.allocator);
    defer m2.deinit();
    _ = m2.put(2.0, 'b');
    _ = m2.put(1.0, 'a');
    try std.testing.expect(m1.eql(&m2));
}

test "F32CharTreeMap: ensureUnusedCapacity reserves both buffers" {
    var m = F32CharTreeMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(100);
    const kcap = m.keys.capacity;
    const vcap = m.vals.capacity;
    try std.testing.expect(kcap >= 100);
    try std.testing.expect(vcap >= 100);
    _ = m.put(1.0, 'a');
    _ = m.put(2.0, 'b');
    try std.testing.expectEqual(kcap, m.keys.capacity);
    try std.testing.expectEqual(vcap, m.vals.capacity);
}

test "F32CharTreeMap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: TreeMap.init doesn't allocate (Treap is node-based),
    // so the first alloc (ensureUnusedCapacity grow) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var m = F32CharTreeMap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(1024));
}
