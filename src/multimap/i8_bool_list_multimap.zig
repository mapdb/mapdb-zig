
const std = @import("std");
const Allocator = std.mem.Allocator;

/// List multimap from `i8` keys to `bool` values.
///
/// Each key maps to a list of values, preserving insertion order per key.
/// Backed by `AutoHashMapUnmanaged` for O(1) key lookup.
pub const I8BoolListMultimap = struct {
    inner: std.AutoHashMapUnmanaged(i8, std.ArrayListUnmanaged(bool)),
    allocator: Allocator,
    total_size: usize,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) I8BoolListMultimap {
        return .{
            .inner = std.AutoHashMapUnmanaged(i8, std.ArrayListUnmanaged(bool)){},
            .allocator = allocator,
            .total_size = 0,
        };
    }

    pub fn deinit(self: *I8BoolListMultimap) void {
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.inner.deinit(self.allocator);
    }

    // ---- Core Operations ----

    /// Adds a value to the list for the given key.
    pub fn put(self: *I8BoolListMultimap, key: i8, value: bool) void {
        const map_key = key;
        const gop = self.inner.getOrPut(self.allocator, map_key) catch @panic("out of memory");
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayListUnmanaged(bool){};
        }
        gop.value_ptr.append(self.allocator, value) catch @panic("out of memory");
        self.total_size += 1;
    }

    /// Returns a slice of values for the given key. No allocation; the
    /// returned slice is a view into internal storage.
    pub fn get(self: *const I8BoolListMultimap, key: i8) []const bool {
        const map_key = key;
        if (self.inner.getPtr(map_key)) |list_ptr| {
            return list_ptr.items;
        }
        return &[_]bool{};
    }

    /// Returns the number of values for the given key.
    pub fn getCount(self: *const I8BoolListMultimap, key: i8) usize {
        const map_key = key;
        if (self.inner.getPtr(map_key)) |list_ptr| {
            return list_ptr.items.len;
        }
        return 0;
    }

    /// Removes all values for the given key. Returns the number of values removed.
    pub fn removeAll(self: *I8BoolListMultimap, key: i8) usize {
        const map_key = key;
        const list_ptr = self.inner.getPtr(map_key) orelse return 0;
        const removed = list_ptr.items.len;
        list_ptr.deinit(self.allocator);
        self.total_size -= removed;
        _ = self.inner.remove(map_key);
        return removed;
    }

    /// Returns true if the multimap contains the given key.
    pub fn containsKey(self: *const I8BoolListMultimap, key: i8) bool {
        const map_key = key;
        return self.inner.contains(map_key);
    }

    /// Returns true if the multimap contains the given key-value pair.
    pub fn containsKeyValue(self: *const I8BoolListMultimap, key: i8, value: bool) bool {
        const vals = self.get(key);
        for (vals) |v| {
            if (v == value) return true;
        }
        return false;
    }

    /// Returns the number of distinct keys. O(1).
    pub fn keysCount(self: *const I8BoolListMultimap) usize {
        return self.inner.count();
    }

    /// Returns the total number of values across all keys.
    pub fn size(self: *const I8BoolListMultimap) usize {
        return self.total_size;
    }

    pub fn len(self: *const I8BoolListMultimap) usize {
        return self.total_size;
    }

    pub fn isEmpty(self: *const I8BoolListMultimap) bool {
        return self.total_size == 0;
    }

    pub fn clear(self: *I8BoolListMultimap) void {
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
    pub fn ensureUnusedCapacity(self: *I8BoolListMultimap, additional: usize) Allocator.Error!void {
        try self.inner.ensureUnusedCapacity(self.allocator, @intCast(additional));
    }

    /// Ensures the backing map's total capacity is at least `new_capacity`.
    pub fn ensureTotalCapacity(self: *I8BoolListMultimap, new_capacity: usize) Allocator.Error!void {
        try self.inner.ensureTotalCapacity(self.allocator, @intCast(new_capacity));
    }

    // ---- Iteration ----

    /// Calls the function for each key-value pair.
    pub fn forEach(self: *const I8BoolListMultimap, f: *const fn (i8, bool) void) void {
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
    pub fn select(self: *const I8BoolListMultimap, predicate: *const fn (i8, bool) bool) I8BoolListMultimap {
        var result = I8BoolListMultimap.init(self.allocator);
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
    pub fn reject(self: *const I8BoolListMultimap, predicate: *const fn (i8, bool) bool) I8BoolListMultimap {
        var result = I8BoolListMultimap.init(self.allocator);
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
    pub fn anySatisfy(self: *const I8BoolListMultimap, predicate: *const fn (i8, bool) bool) bool {
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
    pub fn allSatisfy(self: *const I8BoolListMultimap, predicate: *const fn (i8, bool) bool) bool {
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
    pub fn noneSatisfy(self: *const I8BoolListMultimap, predicate: *const fn (i8, bool) bool) bool {
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
    pub fn count(self: *const I8BoolListMultimap, predicate: *const fn (i8, bool) bool) usize {
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
    pub fn uniqueKeys(self: *const I8BoolListMultimap, allocator: Allocator) []i8 {
        var result = std.ArrayListUnmanaged(i8){};
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            result.append(allocator, entry.key_ptr.*) catch @panic("out of memory");
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    /// Returns all values as a slice. Caller must free.
    pub fn valuesToSlice(self: *const I8BoolListMultimap, allocator: Allocator) []bool {
        var result = std.ArrayListUnmanaged(bool){};
        result.ensureTotalCapacity(allocator, self.total_size) catch @panic("out of memory");
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            result.appendSlice(allocator, entry.value_ptr.items) catch @panic("out of memory");
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    // ---- Fluent API ----

    pub fn withKeyValue(self: *I8BoolListMultimap, key: i8, value: bool) *I8BoolListMultimap {
        self.put(key, value);
        return self;
    }

    // ---- Formatting ----

    pub fn format(self: *const I8BoolListMultimap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const I8BoolListMultimap, other: *const I8BoolListMultimap) bool {
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

test "I8BoolListMultimap: put and get" {
    var m = I8BoolListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1, true);
    m.put(1, false);
    m.put(2, true);
    try std.testing.expectEqual(@as(usize, 3), m.size());
    try std.testing.expectEqual(@as(usize, 2), m.keysCount());
    try std.testing.expectEqual(@as(usize, 2), m.getCount(1));
    try std.testing.expectEqual(@as(usize, 1), m.getCount(2));
    try std.testing.expectEqual(@as(usize, 0), m.getCount(99));
}

test "I8BoolListMultimap: get returns values" {
    var m = I8BoolListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1, true);
    m.put(1, false);
    const vals = m.get(1);
    try std.testing.expectEqual(@as(usize, 2), vals.len);
}

test "I8BoolListMultimap: get empty key" {
    var m = I8BoolListMultimap.init(std.testing.allocator);
    defer m.deinit();
    const vals = m.get(99);
    try std.testing.expectEqual(@as(usize, 0), vals.len);
}

test "I8BoolListMultimap: removeAll" {
    var m = I8BoolListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1, true);
    m.put(1, false);
    m.put(2, true);
    const removed = m.removeAll(1);
    try std.testing.expectEqual(@as(usize, 2), removed);
    try std.testing.expectEqual(@as(usize, 1), m.size());
    try std.testing.expect(!m.containsKey(1));
}

test "I8BoolListMultimap: containsKey and containsKeyValue" {
    var m = I8BoolListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1, true);
    m.put(1, false);
    try std.testing.expect(m.containsKey(1));
    try std.testing.expect(!m.containsKey(99));
    try std.testing.expect(m.containsKeyValue(1, true));
    try std.testing.expect(m.containsKeyValue(1, false));
    // bool has only 2 distinct values; vv[2]=true equals vv[0]
}

test "I8BoolListMultimap: clear" {
    var m = I8BoolListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1, true);
    m.put(2, false);
    m.clear();
    try std.testing.expect(m.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), m.size());
}

test "I8BoolListMultimap: select" {
    var m = I8BoolListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1, true);
    m.put(2, false);
    var sel = m.select(struct {
        fn f(_: i8, v: bool) bool {
            return v == true;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expect(sel.size() >= 1);
}

test "I8BoolListMultimap: uniqueKeys and valuesToSlice" {
    var m = I8BoolListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1, true);
    m.put(1, false);
    m.put(2, true);
    const keys = m.uniqueKeys(std.testing.allocator);
    defer std.testing.allocator.free(keys);
    try std.testing.expectEqual(@as(usize, 2), keys.len);
    const vals = m.valuesToSlice(std.testing.allocator);
    defer std.testing.allocator.free(vals);
    try std.testing.expectEqual(@as(usize, 3), vals.len);
}

test "I8BoolListMultimap: fluent withKeyValue" {
    var m = I8BoolListMultimap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.withKeyValue(1, true).withKeyValue(1, false).withKeyValue(2, true);
    try std.testing.expectEqual(@as(usize, 3), m.size());
    try std.testing.expectEqual(@as(usize, 2), m.keysCount());
}

test "I8BoolListMultimap: eql" {
    var m1 = I8BoolListMultimap.init(std.testing.allocator);
    defer m1.deinit();
    m1.put(1, true);
    m1.put(1, false);
    var m2 = I8BoolListMultimap.init(std.testing.allocator);
    defer m2.deinit();
    m2.put(1, true);
    m2.put(1, false);
    try std.testing.expect(m1.eql(&m2));
}

test "I8BoolListMultimap: ensureUnusedCapacity reserves map slots" {
    var m = I8BoolListMultimap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(100);
    m.put(1, true);
    m.put(2, false);
    try std.testing.expectEqual(@as(usize, 2), m.size());
}

test "I8BoolListMultimap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: ListMultimap.init doesn't allocate (lazy backing),
    // so the first alloc (ensureUnusedCapacity grow) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var m = I8BoolListMultimap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(1024));
}
