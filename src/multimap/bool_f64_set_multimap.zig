
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Set multimap from `bool` keys to `f64` values.
///
/// Each key maps to a set of unique values (duplicates on put are ignored).
/// Backed by `AutoHashMapUnmanaged` for O(1) key lookup.
pub const BoolF64SetMultimap = struct {
    inner: std.AutoHashMapUnmanaged(bool, std.ArrayListUnmanaged(f64)),
    allocator: Allocator,
    total_size: usize,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) BoolF64SetMultimap {
        return .{
            .inner = std.AutoHashMapUnmanaged(bool, std.ArrayListUnmanaged(f64)){},
            .allocator = allocator,
            .total_size = 0,
        };
    }

    pub fn deinit(self: *BoolF64SetMultimap) void {
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.inner.deinit(self.allocator);
    }

    // ---- Core Operations ----

    /// Adds a value to the set for the given key. Idempotent if the value is
    /// already present for this key (duplicate is silently dropped).
    pub fn put(self: *BoolF64SetMultimap, key: bool, value: f64) void {
        const map_key = key;
        const gop = self.inner.getOrPut(self.allocator, map_key) catch @panic("out of memory");
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayListUnmanaged(f64){};
        }
        for (gop.value_ptr.items) |existing| {
            if (@as(u64, @bitCast(existing)) == @as(u64, @bitCast(value))) return;
        }
        gop.value_ptr.append(self.allocator, value) catch @panic("out of memory");
        self.total_size += 1;
    }

    /// Returns a slice of values for the given key. No allocation; the
    /// returned slice is a view into internal storage.
    pub fn get(self: *const BoolF64SetMultimap, key: bool) []const f64 {
        const map_key = key;
        if (self.inner.getPtr(map_key)) |list_ptr| {
            return list_ptr.items;
        }
        return &[_]f64{};
    }

    /// Returns the number of values for the given key.
    pub fn getCount(self: *const BoolF64SetMultimap, key: bool) usize {
        const map_key = key;
        if (self.inner.getPtr(map_key)) |list_ptr| {
            return list_ptr.items.len;
        }
        return 0;
    }

    /// Removes all values for the given key. Returns the number of values removed.
    pub fn removeAll(self: *BoolF64SetMultimap, key: bool) usize {
        const map_key = key;
        const list_ptr = self.inner.getPtr(map_key) orelse return 0;
        const removed = list_ptr.items.len;
        list_ptr.deinit(self.allocator);
        self.total_size -= removed;
        _ = self.inner.remove(map_key);
        return removed;
    }

    /// Returns true if the multimap contains the given key.
    pub fn containsKey(self: *const BoolF64SetMultimap, key: bool) bool {
        const map_key = key;
        return self.inner.contains(map_key);
    }

    /// Returns true if the multimap contains the given key-value pair.
    pub fn containsKeyValue(self: *const BoolF64SetMultimap, key: bool, value: f64) bool {
        const vals = self.get(key);
        for (vals) |v| {
            if (@as(u64, @bitCast(v)) == @as(u64, @bitCast(value))) return true;
        }
        return false;
    }

    /// Returns the number of distinct keys. O(1).
    pub fn keysCount(self: *const BoolF64SetMultimap) usize {
        return self.inner.count();
    }

    /// Returns the total number of values across all keys.
    pub fn size(self: *const BoolF64SetMultimap) usize {
        return self.total_size;
    }

    pub fn len(self: *const BoolF64SetMultimap) usize {
        return self.total_size;
    }

    pub fn isEmpty(self: *const BoolF64SetMultimap) bool {
        return self.total_size == 0;
    }

    pub fn clear(self: *BoolF64SetMultimap) void {
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.inner.clearRetainingCapacity();
        self.total_size = 0;
    }

    // ---- Fallible capacity reservation ----

    /// Ensures the backing map can hold `additional` more distinct keys
    /// without rehashing. Per-key value lists grow independently.
    /// Returns `error.OutOfMemory` if the allocator fails.
    pub fn ensureUnusedCapacity(self: *BoolF64SetMultimap, additional: usize) Allocator.Error!void {
        try self.inner.ensureUnusedCapacity(self.allocator, @intCast(additional));
    }

    /// Ensures the backing map's total capacity is at least `new_capacity`.
    pub fn ensureTotalCapacity(self: *BoolF64SetMultimap, new_capacity: usize) Allocator.Error!void {
        try self.inner.ensureTotalCapacity(self.allocator, @intCast(new_capacity));
    }

    // ---- Iteration ----

    /// Calls the function for each key-value pair.
    pub fn forEach(self: *const BoolF64SetMultimap, f: *const fn (bool, f64) void) void {
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            for (entry.value_ptr.items) |v| {
                f(key, v);
            }
        }
    }

    // ---- Functional Operations ----

    /// Returns a new multimap containing only pairs that satisfy the predicate.
    pub fn select(self: *const BoolF64SetMultimap, predicate: *const fn (bool, f64) bool) BoolF64SetMultimap {
        var result = BoolF64SetMultimap.init(self.allocator);
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            for (entry.value_ptr.items) |v| {
                if (predicate(key, v)) result.put(key, v);
            }
        }
        return result;
    }

    /// Returns a new multimap containing only pairs that do not satisfy the predicate.
    pub fn reject(self: *const BoolF64SetMultimap, predicate: *const fn (bool, f64) bool) BoolF64SetMultimap {
        var result = BoolF64SetMultimap.init(self.allocator);
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            for (entry.value_ptr.items) |v| {
                if (!predicate(key, v)) result.put(key, v);
            }
        }
        return result;
    }

    /// Returns true if any key-value pair satisfies the predicate.
    pub fn anySatisfy(self: *const BoolF64SetMultimap, predicate: *const fn (bool, f64) bool) bool {
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            for (entry.value_ptr.items) |v| {
                if (predicate(key, v)) return true;
            }
        }
        return false;
    }

    /// Returns true if all key-value pairs satisfy the predicate.
    pub fn allSatisfy(self: *const BoolF64SetMultimap, predicate: *const fn (bool, f64) bool) bool {
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            for (entry.value_ptr.items) |v| {
                if (!predicate(key, v)) return false;
            }
        }
        return true;
    }

    /// Returns true if no key-value pair satisfies the predicate.
    pub fn noneSatisfy(self: *const BoolF64SetMultimap, predicate: *const fn (bool, f64) bool) bool {
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            for (entry.value_ptr.items) |v| {
                if (predicate(key, v)) return false;
            }
        }
        return true;
    }

    /// Returns the number of key-value pairs that satisfy the predicate.
    pub fn count(self: *const BoolF64SetMultimap, predicate: *const fn (bool, f64) bool) usize {
        var c: usize = 0;
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            for (entry.value_ptr.items) |v| {
                if (predicate(key, v)) c += 1;
            }
        }
        return c;
    }

    // ---- Key/Value Collection ----

    /// Returns all unique keys as a slice. Caller must free.
    pub fn uniqueKeys(self: *const BoolF64SetMultimap, allocator: Allocator) []bool {
        var result = std.ArrayListUnmanaged(bool){};
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            result.append(allocator, entry.key_ptr.*) catch @panic("out of memory");
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    /// Returns all values as a slice. Caller must free.
    pub fn valuesToSlice(self: *const BoolF64SetMultimap, allocator: Allocator) []f64 {
        var result = std.ArrayListUnmanaged(f64){};
        result.ensureTotalCapacity(allocator, self.total_size) catch @panic("out of memory");
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            result.appendSlice(allocator, entry.value_ptr.items) catch @panic("out of memory");
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    // ---- Fluent API ----

    pub fn withKeyValue(self: *BoolF64SetMultimap, key: bool, value: f64) *BoolF64SetMultimap {
        self.put(key, value);
        return self;
    }

    // ---- Formatting ----

    pub fn format(self: *const BoolF64SetMultimap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll("{");
        var first = true;
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            for (entry.value_ptr.items) |v| {
                if (!first) try writer.writeAll(", ");
                try writer.print("{any}", .{key});
                try writer.writeAll("=");
                try writer.print("{any}", .{v});
                first = false;
            }
        }
        try writer.writeAll("}");
    }

    // ---- Equality ----

    pub fn eql(self: *const BoolF64SetMultimap, other: *const BoolF64SetMultimap) bool {
        if (self.total_size != other.total_size) return false;
        if (self.inner.count() != other.inner.count()) return false;
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            const other_list = other.inner.getPtr(entry.key_ptr.*) orelse return false;
            if (entry.value_ptr.items.len != other_list.items.len) return false;
            for (entry.value_ptr.items, other_list.items) |a, b| {
                if (!(@as(u64, @bitCast(a)) == @as(u64, @bitCast(b)))) return false;
            }
        }
        return true;
    }
};

// ---- Tests ----

test "BoolF64SetMultimap: put and get" {
    var m = BoolF64SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(true, 1.0);
    m.put(true, 2.0);
    m.put(false, 3.0);
    try std.testing.expectEqual(@as(usize, 3), m.size());
    try std.testing.expectEqual(@as(usize, 2), m.keysCount());
    try std.testing.expectEqual(@as(usize, 2), m.getCount(true));
    try std.testing.expectEqual(@as(usize, 1), m.getCount(false));
    // bool has only 2 distinct values; both are used as keys above
}

test "BoolF64SetMultimap: get returns values" {
    var m = BoolF64SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(true, 1.0);
    m.put(true, 2.0);
    const vals = m.get(true);
    try std.testing.expectEqual(@as(usize, 2), vals.len);
}

test "BoolF64SetMultimap: get empty key" {
    var m = BoolF64SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    const vals = m.get(false);
    try std.testing.expectEqual(@as(usize, 0), vals.len);
}

test "BoolF64SetMultimap: removeAll" {
    var m = BoolF64SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(true, 1.0);
    m.put(true, 2.0);
    m.put(false, 3.0);
    const removed = m.removeAll(true);
    try std.testing.expectEqual(@as(usize, 2), removed);
    try std.testing.expectEqual(@as(usize, 1), m.size());
    try std.testing.expect(!m.containsKey(true));
}

test "BoolF64SetMultimap: containsKey and containsKeyValue" {
    var m = BoolF64SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(true, 1.0);
    m.put(true, 2.0);
    try std.testing.expect(m.containsKey(true));
    // bool has only 2 distinct values; kMiss=false is kv[1]
    try std.testing.expect(m.containsKeyValue(true, 1.0));
    try std.testing.expect(m.containsKeyValue(true, 2.0));
    try std.testing.expect(!m.containsKeyValue(true, 3.0));
}

test "BoolF64SetMultimap: clear" {
    var m = BoolF64SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(true, 1.0);
    m.put(false, 2.0);
    m.clear();
    try std.testing.expect(m.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), m.size());
}

test "BoolF64SetMultimap: select" {
    var m = BoolF64SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(true, 1.0);
    m.put(false, 2.0);
    var sel = m.select(struct {
        fn f(_: bool, v: f64) bool {
            return v == 1.0;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expect(sel.size() >= 1);
}

test "BoolF64SetMultimap: uniqueKeys and valuesToSlice" {
    var m = BoolF64SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(true, 1.0);
    m.put(true, 2.0);
    m.put(false, 3.0);
    const keys = m.uniqueKeys(std.testing.allocator);
    defer std.testing.allocator.free(keys);
    try std.testing.expectEqual(@as(usize, 2), keys.len);
    const vals = m.valuesToSlice(std.testing.allocator);
    defer std.testing.allocator.free(vals);
    try std.testing.expectEqual(@as(usize, 3), vals.len);
}

test "BoolF64SetMultimap: fluent withKeyValue" {
    var m = BoolF64SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.withKeyValue(true, 1.0).withKeyValue(true, 2.0).withKeyValue(false, 3.0);
    try std.testing.expectEqual(@as(usize, 3), m.size());
    try std.testing.expectEqual(@as(usize, 2), m.keysCount());
}

test "BoolF64SetMultimap: eql" {
    var m1 = BoolF64SetMultimap.init(std.testing.allocator);
    defer m1.deinit();
    m1.put(true, 1.0);
    m1.put(true, 2.0);
    var m2 = BoolF64SetMultimap.init(std.testing.allocator);
    defer m2.deinit();
    m2.put(true, 1.0);
    m2.put(true, 2.0);
    try std.testing.expect(m1.eql(&m2));
}

test "BoolF64SetMultimap: ensureUnusedCapacity reserves map slots" {
    var m = BoolF64SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(100);
    m.put(true, 1.0);
    m.put(false, 2.0);
    try std.testing.expectEqual(@as(usize, 2), m.size());
}

test "BoolF64SetMultimap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: SetMultimap.init doesn't allocate (lazy backing),
    // so the first alloc (ensureUnusedCapacity grow) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var m = BoolF64SetMultimap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(1024));
}
