
const std = @import("std");
const Allocator = std.mem.Allocator;

/// List multimap from `u21` keys to `u21` values.
///
/// Each key maps to a list of values, preserving insertion order per key.
/// Backed by `AutoHashMapUnmanaged` for O(1) key lookup.
pub const CharCharListMultimap = struct {
    inner: std.AutoHashMapUnmanaged(u21, std.ArrayListUnmanaged(u21)),
    allocator: Allocator,
    total_size: usize,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) CharCharListMultimap {
        return .{
            .inner = std.AutoHashMapUnmanaged(u21, std.ArrayListUnmanaged(u21)){},
            .allocator = allocator,
            .total_size = 0,
        };
    }

    pub fn deinit(self: *CharCharListMultimap) void {
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.inner.deinit(self.allocator);
    }

    // ---- Core Operations ----

    /// Adds a value to the list for the given key.
    pub fn put(self: *CharCharListMultimap, key: u21, value: u21) void {
        const map_key = key;
        const gop = self.inner.getOrPut(self.allocator, map_key) catch @panic("out of memory");
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayListUnmanaged(u21){};
        }
        gop.value_ptr.append(self.allocator, value) catch @panic("out of memory");
        self.total_size += 1;
    }

    /// Returns a slice of values for the given key. No allocation; the
    /// returned slice is a view into internal storage.
    pub fn get(self: *const CharCharListMultimap, key: u21) []const u21 {
        const map_key = key;
        if (self.inner.getPtr(map_key)) |list_ptr| {
            return list_ptr.items;
        }
        return &[_]u21{};
    }

    /// Returns the number of values for the given key.
    pub fn getCount(self: *const CharCharListMultimap, key: u21) usize {
        const map_key = key;
        if (self.inner.getPtr(map_key)) |list_ptr| {
            return list_ptr.items.len;
        }
        return 0;
    }

    /// Removes all values for the given key. Returns the number of values removed.
    pub fn removeAll(self: *CharCharListMultimap, key: u21) usize {
        const map_key = key;
        const list_ptr = self.inner.getPtr(map_key) orelse return 0;
        const removed = list_ptr.items.len;
        list_ptr.deinit(self.allocator);
        self.total_size -= removed;
        _ = self.inner.remove(map_key);
        return removed;
    }

    /// Returns true if the multimap contains the given key.
    pub fn containsKey(self: *const CharCharListMultimap, key: u21) bool {
        const map_key = key;
        return self.inner.contains(map_key);
    }

    /// Returns true if the multimap contains the given key-value pair.
    pub fn containsKeyValue(self: *const CharCharListMultimap, key: u21, value: u21) bool {
        const vals = self.get(key);
        for (vals) |v| {
            if (v == value) return true;
        }
        return false;
    }

    /// Returns the number of distinct keys. O(1).
    pub fn keysCount(self: *const CharCharListMultimap) usize {
        return self.inner.count();
    }

    /// Returns the total number of values across all keys.
    pub fn size(self: *const CharCharListMultimap) usize {
        return self.total_size;
    }

    pub fn len(self: *const CharCharListMultimap) usize {
        return self.total_size;
    }

    pub fn isEmpty(self: *const CharCharListMultimap) bool {
        return self.total_size == 0;
    }

    pub fn clear(self: *CharCharListMultimap) void {
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
    pub fn ensureUnusedCapacity(self: *CharCharListMultimap, additional: usize) Allocator.Error!void {
        try self.inner.ensureUnusedCapacity(self.allocator, @intCast(additional));
    }

    /// Ensures the backing map's total capacity is at least `new_capacity`.
    pub fn ensureTotalCapacity(self: *CharCharListMultimap, new_capacity: usize) Allocator.Error!void {
        try self.inner.ensureTotalCapacity(self.allocator, @intCast(new_capacity));
    }

    // ---- Iteration ----

    /// Calls the function for each key-value pair.
    pub fn forEach(self: *const CharCharListMultimap, f: *const fn (u21, u21) void) void {
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
    pub fn select(self: *const CharCharListMultimap, predicate: *const fn (u21, u21) bool) CharCharListMultimap {
        var result = CharCharListMultimap.init(self.allocator);
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
    pub fn reject(self: *const CharCharListMultimap, predicate: *const fn (u21, u21) bool) CharCharListMultimap {
        var result = CharCharListMultimap.init(self.allocator);
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
    pub fn anySatisfy(self: *const CharCharListMultimap, predicate: *const fn (u21, u21) bool) bool {
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
    pub fn allSatisfy(self: *const CharCharListMultimap, predicate: *const fn (u21, u21) bool) bool {
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
    pub fn noneSatisfy(self: *const CharCharListMultimap, predicate: *const fn (u21, u21) bool) bool {
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
    pub fn count(self: *const CharCharListMultimap, predicate: *const fn (u21, u21) bool) usize {
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
    pub fn uniqueKeys(self: *const CharCharListMultimap, allocator: Allocator) []u21 {
        var result = std.ArrayListUnmanaged(u21){};
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            result.append(allocator, entry.key_ptr.*) catch @panic("out of memory");
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    /// Returns all values as a slice. Caller must free.
    pub fn valuesToSlice(self: *const CharCharListMultimap, allocator: Allocator) []u21 {
        var result = std.ArrayListUnmanaged(u21){};
        result.ensureTotalCapacity(allocator, self.total_size) catch @panic("out of memory");
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            result.appendSlice(allocator, entry.value_ptr.items) catch @panic("out of memory");
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    // ---- Fluent API ----

    pub fn withKeyValue(self: *CharCharListMultimap, key: u21, value: u21) *CharCharListMultimap {
        self.put(key, value);
        return self;
    }

    // ---- Formatting ----

    pub fn format(self: *const CharCharListMultimap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const CharCharListMultimap, other: *const CharCharListMultimap) bool {
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

test "CharCharListMultimap: put and get" {
    var m = CharCharListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put('a', 'a');
    m.put('a', 'b');
    m.put('b', 'c');
    try std.testing.expectEqual(@as(usize, 3), m.size());
    try std.testing.expectEqual(@as(usize, 2), m.keysCount());
    try std.testing.expectEqual(@as(usize, 2), m.getCount('a'));
    try std.testing.expectEqual(@as(usize, 1), m.getCount('b'));
    try std.testing.expectEqual(@as(usize, 0), m.getCount('z'));
}

test "CharCharListMultimap: get returns values" {
    var m = CharCharListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put('a', 'a');
    m.put('a', 'b');
    const vals = m.get('a');
    try std.testing.expectEqual(@as(usize, 2), vals.len);
}

test "CharCharListMultimap: get empty key" {
    var m = CharCharListMultimap.init(std.testing.allocator);
    defer m.deinit();
    const vals = m.get('z');
    try std.testing.expectEqual(@as(usize, 0), vals.len);
}

test "CharCharListMultimap: removeAll" {
    var m = CharCharListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put('a', 'a');
    m.put('a', 'b');
    m.put('b', 'c');
    const removed = m.removeAll('a');
    try std.testing.expectEqual(@as(usize, 2), removed);
    try std.testing.expectEqual(@as(usize, 1), m.size());
    try std.testing.expect(!m.containsKey('a'));
}

test "CharCharListMultimap: containsKey and containsKeyValue" {
    var m = CharCharListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put('a', 'a');
    m.put('a', 'b');
    try std.testing.expect(m.containsKey('a'));
    try std.testing.expect(!m.containsKey('z'));
    try std.testing.expect(m.containsKeyValue('a', 'a'));
    try std.testing.expect(m.containsKeyValue('a', 'b'));
    try std.testing.expect(!m.containsKeyValue('a', 'c'));
}

test "CharCharListMultimap: clear" {
    var m = CharCharListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put('a', 'a');
    m.put('b', 'b');
    m.clear();
    try std.testing.expect(m.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), m.size());
}

test "CharCharListMultimap: select and reject" {
    var m = CharCharListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put('a', 'a');
    m.put('a', 'b');
    m.put('b', 'c');
    var sel = m.select(struct {
        fn f(_: u21, v: u21) bool {
            return v > 'a';
        }
    }.f);
    defer sel.deinit();
    try std.testing.expectEqual(@as(usize, 2), sel.size());
    var rej = m.reject(struct {
        fn f(_: u21, v: u21) bool {
            return v > 'a';
        }
    }.f);
    defer rej.deinit();
    try std.testing.expectEqual(@as(usize, 1), rej.size());
}

test "CharCharListMultimap: anySatisfy noneSatisfy count" {
    var m = CharCharListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put('a', 'a');
    m.put('b', 'b');
    try std.testing.expect(m.anySatisfy(struct {
        fn f(_: u21, v: u21) bool {
            return v == 'b';
        }
    }.f));
    try std.testing.expect(m.noneSatisfy(struct {
        fn f(_: u21, v: u21) bool {
            return v == 'z';
        }
    }.f));
    try std.testing.expectEqual(@as(usize, 1), m.count(struct {
        fn f(_: u21, v: u21) bool {
            return v == 'a';
        }
    }.f));
}

test "CharCharListMultimap: uniqueKeys and valuesToSlice" {
    var m = CharCharListMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put('a', 'a');
    m.put('a', 'b');
    m.put('b', 'c');
    const keys = m.uniqueKeys(std.testing.allocator);
    defer std.testing.allocator.free(keys);
    try std.testing.expectEqual(@as(usize, 2), keys.len);
    const vals = m.valuesToSlice(std.testing.allocator);
    defer std.testing.allocator.free(vals);
    try std.testing.expectEqual(@as(usize, 3), vals.len);
}

test "CharCharListMultimap: fluent withKeyValue" {
    var m = CharCharListMultimap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.withKeyValue('a', 'a').withKeyValue('a', 'b').withKeyValue('b', 'c');
    try std.testing.expectEqual(@as(usize, 3), m.size());
    try std.testing.expectEqual(@as(usize, 2), m.keysCount());
}

test "CharCharListMultimap: eql" {
    var m1 = CharCharListMultimap.init(std.testing.allocator);
    defer m1.deinit();
    m1.put('a', 'a');
    m1.put('a', 'b');
    var m2 = CharCharListMultimap.init(std.testing.allocator);
    defer m2.deinit();
    m2.put('a', 'a');
    m2.put('a', 'b');
    try std.testing.expect(m1.eql(&m2));
}

test "CharCharListMultimap: ensureUnusedCapacity reserves map slots" {
    var m = CharCharListMultimap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(100);
    m.put('a', 'a');
    m.put('b', 'b');
    try std.testing.expectEqual(@as(usize, 2), m.size());
}

test "CharCharListMultimap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: ListMultimap.init doesn't allocate (lazy backing),
    // so the first alloc (ensureUnusedCapacity grow) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var m = CharCharListMultimap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(1024));
}
