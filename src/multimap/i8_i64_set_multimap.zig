
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Set multimap from `i8` keys to `i64` values.
///
/// Each key maps to a set of unique values (duplicates on put are ignored).
/// Backed by `AutoHashMapUnmanaged` for O(1) key lookup.
pub const I8I64SetMultimap = struct {
    inner: std.AutoHashMapUnmanaged(i8, std.ArrayListUnmanaged(i64)),
    allocator: Allocator,
    total_size: usize,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) I8I64SetMultimap {
        return .{
            .inner = std.AutoHashMapUnmanaged(i8, std.ArrayListUnmanaged(i64)){},
            .allocator = allocator,
            .total_size = 0,
        };
    }

    pub fn deinit(self: *I8I64SetMultimap) void {
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.inner.deinit(self.allocator);
    }

    // ---- Core Operations ----

    /// Adds a value to the set for the given key. Idempotent if the value is
    /// already present for this key (duplicate is silently dropped).
    pub fn put(self: *I8I64SetMultimap, key: i8, value: i64) void {
        const map_key = key;
        const gop = self.inner.getOrPut(self.allocator, map_key) catch @panic("out of memory");
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayListUnmanaged(i64){};
        }
        for (gop.value_ptr.items) |existing| {
            if (existing == value) return;
        }
        gop.value_ptr.append(self.allocator, value) catch @panic("out of memory");
        self.total_size += 1;
    }

    /// Returns a slice of values for the given key. No allocation; the
    /// returned slice is a view into internal storage.
    pub fn get(self: *const I8I64SetMultimap, key: i8) []const i64 {
        const map_key = key;
        if (self.inner.getPtr(map_key)) |list_ptr| {
            return list_ptr.items;
        }
        return &[_]i64{};
    }

    /// Returns the number of values for the given key.
    pub fn getCount(self: *const I8I64SetMultimap, key: i8) usize {
        const map_key = key;
        if (self.inner.getPtr(map_key)) |list_ptr| {
            return list_ptr.items.len;
        }
        return 0;
    }

    /// Removes all values for the given key. Returns the number of values removed.
    pub fn removeAll(self: *I8I64SetMultimap, key: i8) usize {
        const map_key = key;
        const list_ptr = self.inner.getPtr(map_key) orelse return 0;
        const removed = list_ptr.items.len;
        list_ptr.deinit(self.allocator);
        self.total_size -= removed;
        _ = self.inner.remove(map_key);
        return removed;
    }

    /// Returns true if the multimap contains the given key.
    pub fn containsKey(self: *const I8I64SetMultimap, key: i8) bool {
        const map_key = key;
        return self.inner.contains(map_key);
    }

    /// Returns true if the multimap contains the given key-value pair.
    pub fn containsKeyValue(self: *const I8I64SetMultimap, key: i8, value: i64) bool {
        const vals = self.get(key);
        for (vals) |v| {
            if (v == value) return true;
        }
        return false;
    }

    /// Returns the number of distinct keys. O(1).
    pub fn keysCount(self: *const I8I64SetMultimap) usize {
        return self.inner.count();
    }

    /// Returns the total number of values across all keys.
    pub fn size(self: *const I8I64SetMultimap) usize {
        return self.total_size;
    }

    pub fn len(self: *const I8I64SetMultimap) usize {
        return self.total_size;
    }

    pub fn isEmpty(self: *const I8I64SetMultimap) bool {
        return self.total_size == 0;
    }

    pub fn clear(self: *I8I64SetMultimap) void {
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
    pub fn ensureUnusedCapacity(self: *I8I64SetMultimap, additional: usize) Allocator.Error!void {
        try self.inner.ensureUnusedCapacity(self.allocator, @intCast(additional));
    }

    /// Ensures the backing map's total capacity is at least `new_capacity`.
    pub fn ensureTotalCapacity(self: *I8I64SetMultimap, new_capacity: usize) Allocator.Error!void {
        try self.inner.ensureTotalCapacity(self.allocator, @intCast(new_capacity));
    }

    // ---- Iteration ----

    /// Calls the function for each key-value pair.
    pub fn forEach(self: *const I8I64SetMultimap, f: *const fn (i8, i64) void) void {
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
    pub fn select(self: *const I8I64SetMultimap, predicate: *const fn (i8, i64) bool) I8I64SetMultimap {
        var result = I8I64SetMultimap.init(self.allocator);
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
    pub fn reject(self: *const I8I64SetMultimap, predicate: *const fn (i8, i64) bool) I8I64SetMultimap {
        var result = I8I64SetMultimap.init(self.allocator);
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
    pub fn anySatisfy(self: *const I8I64SetMultimap, predicate: *const fn (i8, i64) bool) bool {
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
    pub fn allSatisfy(self: *const I8I64SetMultimap, predicate: *const fn (i8, i64) bool) bool {
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
    pub fn noneSatisfy(self: *const I8I64SetMultimap, predicate: *const fn (i8, i64) bool) bool {
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
    pub fn count(self: *const I8I64SetMultimap, predicate: *const fn (i8, i64) bool) usize {
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
    pub fn uniqueKeys(self: *const I8I64SetMultimap, allocator: Allocator) []i8 {
        var result = std.ArrayListUnmanaged(i8){};
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            result.append(allocator, entry.key_ptr.*) catch @panic("out of memory");
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    /// Returns all values as a slice. Caller must free.
    pub fn valuesToSlice(self: *const I8I64SetMultimap, allocator: Allocator) []i64 {
        var result = std.ArrayListUnmanaged(i64){};
        result.ensureTotalCapacity(allocator, self.total_size) catch @panic("out of memory");
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            result.appendSlice(allocator, entry.value_ptr.items) catch @panic("out of memory");
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    // ---- Fluent API ----

    pub fn withKeyValue(self: *I8I64SetMultimap, key: i8, value: i64) *I8I64SetMultimap {
        self.put(key, value);
        return self;
    }

    // ---- Formatting ----

    pub fn format(self: *const I8I64SetMultimap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const I8I64SetMultimap, other: *const I8I64SetMultimap) bool {
        if (self.total_size != other.total_size) return false;
        if (self.inner.count() != other.inner.count()) return false;
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            const other_list = other.inner.getPtr(entry.key_ptr.*) orelse return false;
            if (entry.value_ptr.items.len != other_list.items.len) return false;
            for (entry.value_ptr.items, other_list.items) |a, b| {
                if (!(a == b)) return false;
            }
        }
        return true;
    }
};

// ---- Tests ----

test "I8I64SetMultimap: put and get" {
    var m = I8I64SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1, 1);
    m.put(1, 2);
    m.put(2, 3);
    try std.testing.expectEqual(@as(usize, 3), m.size());
    try std.testing.expectEqual(@as(usize, 2), m.keysCount());
    try std.testing.expectEqual(@as(usize, 2), m.getCount(1));
    try std.testing.expectEqual(@as(usize, 1), m.getCount(2));
    try std.testing.expectEqual(@as(usize, 0), m.getCount(99));
}

test "I8I64SetMultimap: get returns values" {
    var m = I8I64SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1, 1);
    m.put(1, 2);
    const vals = m.get(1);
    try std.testing.expectEqual(@as(usize, 2), vals.len);
}

test "I8I64SetMultimap: get empty key" {
    var m = I8I64SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    const vals = m.get(99);
    try std.testing.expectEqual(@as(usize, 0), vals.len);
}

test "I8I64SetMultimap: removeAll" {
    var m = I8I64SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1, 1);
    m.put(1, 2);
    m.put(2, 3);
    const removed = m.removeAll(1);
    try std.testing.expectEqual(@as(usize, 2), removed);
    try std.testing.expectEqual(@as(usize, 1), m.size());
    try std.testing.expect(!m.containsKey(1));
}

test "I8I64SetMultimap: containsKey and containsKeyValue" {
    var m = I8I64SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1, 1);
    m.put(1, 2);
    try std.testing.expect(m.containsKey(1));
    try std.testing.expect(!m.containsKey(99));
    try std.testing.expect(m.containsKeyValue(1, 1));
    try std.testing.expect(m.containsKeyValue(1, 2));
    try std.testing.expect(!m.containsKeyValue(1, 3));
}

test "I8I64SetMultimap: clear" {
    var m = I8I64SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1, 1);
    m.put(2, 2);
    m.clear();
    try std.testing.expect(m.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), m.size());
}

test "I8I64SetMultimap: select and reject" {
    var m = I8I64SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1, 1);
    m.put(1, 2);
    m.put(2, 3);
    var sel = m.select(struct {
        fn f(_: i8, v: i64) bool {
            return v > 1;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expectEqual(@as(usize, 2), sel.size());
    var rej = m.reject(struct {
        fn f(_: i8, v: i64) bool {
            return v > 1;
        }
    }.f);
    defer rej.deinit();
    try std.testing.expectEqual(@as(usize, 1), rej.size());
}

test "I8I64SetMultimap: anySatisfy noneSatisfy count" {
    var m = I8I64SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1, 1);
    m.put(2, 2);
    try std.testing.expect(m.anySatisfy(struct {
        fn f(_: i8, v: i64) bool {
            return v == 2;
        }
    }.f));
    try std.testing.expect(m.noneSatisfy(struct {
        fn f(_: i8, v: i64) bool {
            return v == 99;
        }
    }.f));
    try std.testing.expectEqual(@as(usize, 1), m.count(struct {
        fn f(_: i8, v: i64) bool {
            return v == 1;
        }
    }.f));
}

test "I8I64SetMultimap: uniqueKeys and valuesToSlice" {
    var m = I8I64SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1, 1);
    m.put(1, 2);
    m.put(2, 3);
    const keys = m.uniqueKeys(std.testing.allocator);
    defer std.testing.allocator.free(keys);
    try std.testing.expectEqual(@as(usize, 2), keys.len);
    const vals = m.valuesToSlice(std.testing.allocator);
    defer std.testing.allocator.free(vals);
    try std.testing.expectEqual(@as(usize, 3), vals.len);
}

test "I8I64SetMultimap: fluent withKeyValue" {
    var m = I8I64SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.withKeyValue(1, 1).withKeyValue(1, 2).withKeyValue(2, 3);
    try std.testing.expectEqual(@as(usize, 3), m.size());
    try std.testing.expectEqual(@as(usize, 2), m.keysCount());
}

test "I8I64SetMultimap: eql" {
    var m1 = I8I64SetMultimap.init(std.testing.allocator);
    defer m1.deinit();
    m1.put(1, 1);
    m1.put(1, 2);
    var m2 = I8I64SetMultimap.init(std.testing.allocator);
    defer m2.deinit();
    m2.put(1, 1);
    m2.put(1, 2);
    try std.testing.expect(m1.eql(&m2));
}

test "I8I64SetMultimap: ensureUnusedCapacity reserves map slots" {
    var m = I8I64SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(100);
    m.put(1, 1);
    m.put(2, 2);
    try std.testing.expectEqual(@as(usize, 2), m.size());
}

test "I8I64SetMultimap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: SetMultimap.init doesn't allocate (lazy backing),
    // so the first alloc (ensureUnusedCapacity grow) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var m = I8I64SetMultimap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(1024));
}
