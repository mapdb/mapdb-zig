
const std = @import("std");
const Allocator = std.mem.Allocator;

/// List multimap from `u21` keys to `bool` values.
///
/// Each key maps to a list of values, preserving insertion order per key.
/// Backed by `AutoHashMapUnmanaged` for O(1) key lookup.
pub const CharBoolListMultimap = struct {
    inner: std.AutoHashMapUnmanaged(u21, std.ArrayListUnmanaged(bool)),
    allocator: Allocator,
    total_size: usize,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) CharBoolListMultimap {
        return .{
            .inner = std.AutoHashMapUnmanaged(u21, std.ArrayListUnmanaged(bool)){},
            .allocator = allocator,
            .total_size = 0,
        };
    }

    pub fn deinit(self: *CharBoolListMultimap) void {
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.inner.deinit(self.allocator);
    }

    // ---- Core Operations ----

    /// Adds a value to the list for the given key.
    pub fn put(self: *CharBoolListMultimap, key: u21, value: bool) void {
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
    pub fn get(self: *const CharBoolListMultimap, key: u21) []const bool {
        const map_key = key;
        if (self.inner.getPtr(map_key)) |list_ptr| {
            return list_ptr.items;
        }
        return &[_]bool{};
    }

    /// Returns the number of values for the given key.
    pub fn getCount(self: *const CharBoolListMultimap, key: u21) usize {
        const map_key = key;
        if (self.inner.getPtr(map_key)) |list_ptr| {
            return list_ptr.items.len;
        }
        return 0;
    }

    /// Removes all values for the given key. Returns the number of values removed.
    pub fn removeAll(self: *CharBoolListMultimap, key: u21) usize {
        const map_key = key;
        const list_ptr = self.inner.getPtr(map_key) orelse return 0;
        const removed = list_ptr.items.len;
        list_ptr.deinit(self.allocator);
        self.total_size -= removed;
        _ = self.inner.remove(map_key);
        return removed;
    }

    /// Returns true if the multimap contains the given key.
    pub fn containsKey(self: *const CharBoolListMultimap, key: u21) bool {
        const map_key = key;
        return self.inner.contains(map_key);
    }

    /// Returns true if the multimap contains the given key-value pair.
    pub fn containsKeyValue(self: *const CharBoolListMultimap, key: u21, value: bool) bool {
        const vals = self.get(key);
        for (vals) |v| {
            if (v == value) return true;
        }
        return false;
    }

    /// Returns the number of distinct keys. O(1).
    pub fn keysCount(self: *const CharBoolListMultimap) usize {
        return self.inner.count();
    }

    /// Returns the total number of values across all keys.
    pub fn size(self: *const CharBoolListMultimap) usize {
        return self.total_size;
    }

    pub fn len(self: *const CharBoolListMultimap) usize {
        return self.total_size;
    }

    pub fn isEmpty(self: *const CharBoolListMultimap) bool {
        return self.total_size == 0;
    }

    pub fn clear(self: *CharBoolListMultimap) void {
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
    pub fn ensureUnusedCapacity(self: *CharBoolListMultimap, additional: usize) Allocator.Error!void {
        try self.inner.ensureUnusedCapacity(self.allocator, @intCast(additional));
    }

    /// Ensures the backing map's total capacity is at least `new_capacity`.
    pub fn ensureTotalCapacity(self: *CharBoolListMultimap, new_capacity: usize) Allocator.Error!void {
        try self.inner.ensureTotalCapacity(self.allocator, @intCast(new_capacity));
    }

    // ---- Iteration ----

    /// Calls the function for each key-value pair.
    pub fn forEach(self: *const CharBoolListMultimap, f: *const fn (u21, bool) void) void {
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
    pub fn select(self: *const CharBoolListMultimap, predicate: *const fn (u21, bool) bool) CharBoolListMultimap {
        var result = CharBoolListMultimap.init(self.allocator);
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
    pub fn reject(self: *const CharBoolListMultimap, predicate: *const fn (u21, bool) bool) CharBoolListMultimap {
        var result = CharBoolListMultimap.init(self.allocator);
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
    pub fn anySatisfy(self: *const CharBoolListMultimap, predicate: *const fn (u21, bool) bool) bool {
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
    pub fn allSatisfy(self: *const CharBoolListMultimap, predicate: *const fn (u21, bool) bool) bool {
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
    pub fn noneSatisfy(self: *const CharBoolListMultimap, predicate: *const fn (u21, bool) bool) bool {
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
    pub fn count(self: *const CharBoolListMultimap, predicate: *const fn (u21, bool) bool) usize {
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
    pub fn uniqueKeys(self: *const CharBoolListMultimap, allocator: Allocator) []u21 {
        var result = std.ArrayListUnmanaged(u21){};
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            result.append(allocator, entry.key_ptr.*) catch @panic("out of memory");
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    /// Returns all values as a slice. Caller must free.
    pub fn valuesToSlice(self: *const CharBoolListMultimap, allocator: Allocator) []bool {
        var result = std.ArrayListUnmanaged(bool){};
        result.ensureTotalCapacity(allocator, self.total_size) catch @panic("out of memory");
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            result.appendSlice(allocator, entry.value_ptr.items) catch @panic("out of memory");
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    // ---- Fluent API ----

    pub fn withKeyValue(self: *CharBoolListMultimap, key: u21, value: bool) *CharBoolListMultimap {
        self.put(key, value);
        return self;
    }

    // ---- Formatting ----

    pub fn format(self: *const CharBoolListMultimap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const CharBoolListMultimap, other: *const CharBoolListMultimap) bool {
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

test "CharBoolListMultimap: put and get" {
    var m = CharBoolListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put('a', true);
    m.put('a', false);
    m.put('b', true);
    try std.testing.expectEqual(@as(usize, 3), m.size());
    try std.testing.expectEqual(@as(usize, 2), m.keysCount());
    try std.testing.expectEqual(@as(usize, 2), m.getCount('a'));
    try std.testing.expectEqual(@as(usize, 1), m.getCount('b'));
    try std.testing.expectEqual(@as(usize, 0), m.getCount('z'));
}

test "CharBoolListMultimap: get returns values" {
    var m = CharBoolListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put('a', true);
    m.put('a', false);
    const vals = m.get('a');
    try std.testing.expectEqual(@as(usize, 2), vals.len);
}

test "CharBoolListMultimap: get empty key" {
    var m = CharBoolListMultimap.init(std.testing.allocator);
    defer m.deinit();
    const vals = m.get('z');
    try std.testing.expectEqual(@as(usize, 0), vals.len);
}

test "CharBoolListMultimap: removeAll" {
    var m = CharBoolListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put('a', true);
    m.put('a', false);
    m.put('b', true);
    const removed = m.removeAll('a');
    try std.testing.expectEqual(@as(usize, 2), removed);
    try std.testing.expectEqual(@as(usize, 1), m.size());
    try std.testing.expect(!m.containsKey('a'));
}

test "CharBoolListMultimap: containsKey and containsKeyValue" {
    var m = CharBoolListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put('a', true);
    m.put('a', false);
    try std.testing.expect(m.containsKey('a'));
    try std.testing.expect(!m.containsKey('z'));
    try std.testing.expect(m.containsKeyValue('a', true));
    try std.testing.expect(m.containsKeyValue('a', false));
    // bool has only 2 distinct values; vv[2]=true equals vv[0]
}

test "CharBoolListMultimap: clear" {
    var m = CharBoolListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put('a', true);
    m.put('b', false);
    m.clear();
    try std.testing.expect(m.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), m.size());
}

test "CharBoolListMultimap: select" {
    var m = CharBoolListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put('a', true);
    m.put('b', false);
    var sel = m.select(struct {
        fn f(_: u21, v: bool) bool {
            return v == true;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expect(sel.size() >= 1);
}

test "CharBoolListMultimap: uniqueKeys and valuesToSlice" {
    var m = CharBoolListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put('a', true);
    m.put('a', false);
    m.put('b', true);
    const keys = m.uniqueKeys(std.testing.allocator);
    defer std.testing.allocator.free(keys);
    try std.testing.expectEqual(@as(usize, 2), keys.len);
    const vals = m.valuesToSlice(std.testing.allocator);
    defer std.testing.allocator.free(vals);
    try std.testing.expectEqual(@as(usize, 3), vals.len);
}

test "CharBoolListMultimap: fluent withKeyValue" {
    var m = CharBoolListMultimap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.withKeyValue('a', true).withKeyValue('a', false).withKeyValue('b', true);
    try std.testing.expectEqual(@as(usize, 3), m.size());
    try std.testing.expectEqual(@as(usize, 2), m.keysCount());
}

test "CharBoolListMultimap: eql" {
    var m1 = CharBoolListMultimap.init(std.testing.allocator);
    defer m1.deinit();
    m1.put('a', true);
    m1.put('a', false);
    var m2 = CharBoolListMultimap.init(std.testing.allocator);
    defer m2.deinit();
    m2.put('a', true);
    m2.put('a', false);
    try std.testing.expect(m1.eql(&m2));
}

test "CharBoolListMultimap: ensureUnusedCapacity reserves map slots" {
    var m = CharBoolListMultimap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(100);
    m.put('a', true);
    m.put('b', false);
    try std.testing.expectEqual(@as(usize, 2), m.size());
}

test "CharBoolListMultimap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: ListMultimap.init doesn't allocate (lazy backing),
    // so the first alloc (ensureUnusedCapacity grow) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var m = CharBoolListMultimap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(1024));
}
