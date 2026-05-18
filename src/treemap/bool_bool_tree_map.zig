
const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;

/// Sorted map from `bool` keys to `bool` values, backed by sorted ArrayLists.
pub const BoolBoolTreeMap = struct {
    keys: std.ArrayListUnmanaged(bool) = .empty,
    vals: std.ArrayListUnmanaged(bool) = .empty,
    config: AllocatorConfig,

    pub fn init(allocator: Allocator) BoolBoolTreeMap {
        return .{ .config = AllocatorConfig.init(allocator) };
    }

    pub fn initWithConfig(config: AllocatorConfig) BoolBoolTreeMap {
        return .{ .config = config };
    }

    pub fn deinit(self: *BoolBoolTreeMap) void {
        self.keys.deinit(self.config.keysAllocator());
        self.vals.deinit(self.config.valuesAllocator());
    }

    fn orderFn(a: bool, b: bool) std.math.Order {
        return if (a == b) std.math.Order.eq else if (!a and b) std.math.Order.lt else std.math.Order.gt;
    }

    fn findIndex(self: *const BoolBoolTreeMap, key: bool) struct { index: usize, found: bool } {
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
    pub fn put(self: *BoolBoolTreeMap, key: bool, value: bool) ?bool {
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

    pub fn get(self: *const BoolBoolTreeMap, key: bool) ?bool {
        const result = self.findIndex(key);
        if (!result.found) return null;
        return self.vals.items[result.index];
    }

    pub fn remove(self: *BoolBoolTreeMap, key: bool) ?bool {
        const result = self.findIndex(key);
        if (!result.found) return null;
        const old = self.vals.items[result.index];
        _ = self.keys.orderedRemove(result.index);
        _ = self.vals.orderedRemove(result.index);
        return old;
    }

    pub fn containsKey(self: *const BoolBoolTreeMap, key: bool) bool {
        return self.findIndex(key).found;
    }

    pub fn getOrDefault(self: *const BoolBoolTreeMap, key: bool, default_value: bool) bool {
        return self.get(key) orelse default_value;
    }

    pub fn len(self: *const BoolBoolTreeMap) usize {
        return self.keys.items.len;
    }

    /// Alias for len() — matches Go/Java naming.
    pub fn size(self: *const BoolBoolTreeMap) usize {
        return self.len();
    }

    pub fn isEmpty(self: *const BoolBoolTreeMap) bool {
        return self.keys.items.len == 0;
    }

    pub fn clear(self: *BoolBoolTreeMap) void {
        self.keys.clearRetainingCapacity();
        self.vals.clearRetainingCapacity();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures both the keys and values buffers can hold `additional` more
    /// entries without reallocating. Returns `error.OutOfMemory` if the
    /// allocator fails.
    pub fn ensureUnusedCapacity(self: *BoolBoolTreeMap, additional: usize) Allocator.Error!void {
        try self.keys.ensureUnusedCapacity(self.config.keysAllocator(), additional);
        try self.vals.ensureUnusedCapacity(self.config.valuesAllocator(), additional);
    }

    /// Ensures both internal buffers' total capacity is at least
    /// `new_capacity`.
    pub fn ensureTotalCapacity(self: *BoolBoolTreeMap, new_capacity: usize) Allocator.Error!void {
        try self.keys.ensureTotalCapacity(self.config.keysAllocator(), new_capacity);
        try self.vals.ensureTotalCapacity(self.config.valuesAllocator(), new_capacity);
    }

    pub fn min(self: *const BoolBoolTreeMap) ?struct { key: bool, value: bool } {
        if (self.keys.items.len == 0) return null;
        return .{ .key = self.keys.items[0], .value = self.vals.items[0] };
    }

    pub fn max(self: *const BoolBoolTreeMap) ?struct { key: bool, value: bool } {
        if (self.keys.items.len == 0) return null;
        const last = self.keys.items.len - 1;
        return .{ .key = self.keys.items[last], .value = self.vals.items[last] };
    }

    pub fn keysSlice(self: *const BoolBoolTreeMap) []const bool {
        return self.keys.items;
    }

    pub fn valuesSlice(self: *const BoolBoolTreeMap) []const bool {
        return self.vals.items;
    }

    // ---- Iteration ----

    pub fn forEach(self: *const BoolBoolTreeMap, f: *const fn (bool, bool) void) void {
        for (self.keys.items, self.vals.items) |k, val| f(k, val);
    }

    pub fn forEachKey(self: *const BoolBoolTreeMap, f: *const fn (bool) void) void {
        for (self.keys.items) |k| f(k);
    }

    pub fn forEachValue(self: *const BoolBoolTreeMap, f: *const fn (bool) void) void {
        for (self.vals.items) |val| f(val);
    }

    // ---- Functional Operations ----

    pub fn select(self: *const BoolBoolTreeMap, predicate: *const fn (bool, bool) bool) BoolBoolTreeMap {
        var result = init(self.config.base);
        for (self.keys.items, self.vals.items) |k, val| {
            if (predicate(k, val)) _ = result.put(k, val);
        }
        return result;
    }

    pub fn reject(self: *const BoolBoolTreeMap, predicate: *const fn (bool, bool) bool) BoolBoolTreeMap {
        var result = init(self.config.base);
        for (self.keys.items, self.vals.items) |k, val| {
            if (!predicate(k, val)) _ = result.put(k, val);
        }
        return result;
    }

    pub fn detect(self: *const BoolBoolTreeMap, predicate: *const fn (bool, bool) bool) ?struct { key: bool, value: bool } {
        for (self.keys.items, self.vals.items) |k, val| {
            if (predicate(k, val)) return .{ .key = k, .value = val };
        }
        return null;
    }

    pub fn anySatisfy(self: *const BoolBoolTreeMap, predicate: *const fn (bool, bool) bool) bool {
        for (self.keys.items, self.vals.items) |k, val| {
            if (predicate(k, val)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const BoolBoolTreeMap, predicate: *const fn (bool, bool) bool) bool {
        for (self.keys.items, self.vals.items) |k, val| {
            if (!predicate(k, val)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const BoolBoolTreeMap, predicate: *const fn (bool, bool) bool) bool {
        for (self.keys.items, self.vals.items) |k, val| {
            if (predicate(k, val)) return false;
        }
        return true;
    }

    pub fn count(self: *const BoolBoolTreeMap, predicate: *const fn (bool, bool) bool) usize {
        var c: usize = 0;
        for (self.keys.items, self.vals.items) |k, val| {
            if (predicate(k, val)) c += 1;
        }
        return c;
    }

    // ---- Range Operations ----

    /// Returns the entry with the smallest key >= the given key, or null.
    pub fn ceiling(self: *const BoolBoolTreeMap, key: bool) ?struct { key: bool, value: bool } {
        const result = self.findIndex(key);
        if (result.found) return .{ .key = self.keys.items[result.index], .value = self.vals.items[result.index] };
        if (result.index < self.keys.items.len) return .{ .key = self.keys.items[result.index], .value = self.vals.items[result.index] };
        return null;
    }

    /// Returns the entry with the largest key <= the given key, or null.
    pub fn floor(self: *const BoolBoolTreeMap, key: bool) ?struct { key: bool, value: bool } {
        const result = self.findIndex(key);
        if (result.found) return .{ .key = self.keys.items[result.index], .value = self.vals.items[result.index] };
        if (result.index > 0) return .{ .key = self.keys.items[result.index - 1], .value = self.vals.items[result.index - 1] };
        return null;
    }

    /// Returns keys in [from, to] inclusive as a slice view.
    pub fn rangeKeys(self: *const BoolBoolTreeMap, from: bool, to: bool) []const bool {
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
    pub fn format(self: *const BoolBoolTreeMap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn withKeyValue(self: *BoolBoolTreeMap, key: bool, value: bool) *BoolBoolTreeMap {
        _ = self.put(key, value);
        return self;
    }

    pub fn withoutKey(self: *BoolBoolTreeMap, key: bool) *BoolBoolTreeMap {
        _ = self.remove(key);
        return self;
    }

    // ---- Equality ----

    pub fn eql(self: *const BoolBoolTreeMap, other: *const BoolBoolTreeMap) bool {
        if (self.keys.items.len != other.keys.items.len) return false;
        for (self.keys.items, self.vals.items, other.keys.items, other.vals.items) |k1, v1, k2, v2| {
            if (!(k1 == k2)) return false;
            if (!(v1 == v2)) return false;
        }
        return true;
    }
};

test "BoolBoolTreeMap: put and get" {
    var m = BoolBoolTreeMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, true);
    _ = m.put(false, false);

    try std.testing.expectEqual(@as(usize, 2), m.len());
    try std.testing.expectEqual(@as(?bool, true), m.get(true));
}

test "BoolBoolTreeMap: sorted keys" {
    var m = BoolBoolTreeMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, true);
    _ = m.put(false, false);
    try std.testing.expectEqual(@as(usize, 2), m.len());
}

test "BoolBoolTreeMap: min max" {
    var m = BoolBoolTreeMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, true);
    _ = m.put(false, false);
    try std.testing.expect(m.min() != null);
    try std.testing.expect(m.max() != null);
}

test "BoolBoolTreeMap: remove" {
    var m = BoolBoolTreeMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, true);
    _ = m.put(false, false);
    const removed = m.remove(true);
    try std.testing.expectEqual(@as(?bool, true), removed);
    try std.testing.expectEqual(@as(usize, 1), m.len());
}

test "BoolBoolTreeMap: clear" {
    var m = BoolBoolTreeMap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.put(true, true);
    m.clear();
    try std.testing.expect(m.isEmpty());
}

test "BoolBoolTreeMap: eql" {
    var m1 = BoolBoolTreeMap.init(std.testing.allocator);
    defer m1.deinit();
    _ = m1.put(true, true);
    _ = m1.put(false, false);

    var m2 = BoolBoolTreeMap.init(std.testing.allocator);
    defer m2.deinit();
    _ = m2.put(false, false);
    _ = m2.put(true, true);
    try std.testing.expect(m1.eql(&m2));
}

test "BoolBoolTreeMap: ensureUnusedCapacity reserves both buffers" {
    var m = BoolBoolTreeMap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(100);
    const kcap = m.keys.capacity;
    const vcap = m.vals.capacity;
    try std.testing.expect(kcap >= 100);
    try std.testing.expect(vcap >= 100);
    _ = m.put(true, true);
    _ = m.put(false, false);
    try std.testing.expectEqual(kcap, m.keys.capacity);
    try std.testing.expectEqual(vcap, m.vals.capacity);
}

test "BoolBoolTreeMap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: TreeMap.init doesn't allocate (Treap is node-based),
    // so the first alloc (ensureUnusedCapacity grow) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var m = BoolBoolTreeMap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(1024));
}
