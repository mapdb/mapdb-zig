// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;

/// Set multimap from `bool` keys to `u21` values.
///
/// Each key maps to a set of unique values (duplicates on put are ignored).
/// Backed by `AutoHashMapUnmanaged` for O(1) key lookup.
pub const BoolCharSetMultimap = struct {
    inner: std.AutoHashMapUnmanaged(bool, std.ArrayListUnmanaged(u21)),
    allocator: Allocator,
    total_size: usize,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) BoolCharSetMultimap {
        return .{
            .inner = std.AutoHashMapUnmanaged(bool, std.ArrayListUnmanaged(u21)){},
            .allocator = allocator,
            .total_size = 0,
        };
    }

    pub fn deinit(self: *BoolCharSetMultimap) void {
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.inner.deinit(self.allocator);
    }

    // ---- Core Operations ----

    /// Adds a value to the set for the given key. Idempotent if the value is
    /// already present for this key (duplicate is silently dropped).
    pub fn put(self: *BoolCharSetMultimap, key: bool, value: u21) void {
        const map_key = key;
        const gop = self.inner.getOrPut(self.allocator, map_key) catch @panic("out of memory");
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayListUnmanaged(u21){};
        }
        for (gop.value_ptr.items) |existing| {
            if (existing == value) return;
        }
        gop.value_ptr.append(self.allocator, value) catch @panic("out of memory");
        self.total_size += 1;
    }

    /// Returns a slice of values for the given key. No allocation; the
    /// returned slice is a view into internal storage.
    pub fn get(self: *const BoolCharSetMultimap, key: bool) []const u21 {
        const map_key = key;
        if (self.inner.getPtr(map_key)) |list_ptr| {
            return list_ptr.items;
        }
        return &[_]u21{};
    }

    /// Returns the number of values for the given key.
    pub fn getCount(self: *const BoolCharSetMultimap, key: bool) usize {
        const map_key = key;
        if (self.inner.getPtr(map_key)) |list_ptr| {
            return list_ptr.items.len;
        }
        return 0;
    }

    /// Removes all values for the given key. Returns the number of values removed.
    pub fn removeAll(self: *BoolCharSetMultimap, key: bool) usize {
        const map_key = key;
        const list_ptr = self.inner.getPtr(map_key) orelse return 0;
        const removed = list_ptr.items.len;
        list_ptr.deinit(self.allocator);
        self.total_size -= removed;
        _ = self.inner.remove(map_key);
        return removed;
    }

    /// Returns true if the multimap contains the given key.
    pub fn containsKey(self: *const BoolCharSetMultimap, key: bool) bool {
        const map_key = key;
        return self.inner.contains(map_key);
    }

    /// Returns true if the multimap contains the given key-value pair.
    pub fn containsKeyValue(self: *const BoolCharSetMultimap, key: bool, value: u21) bool {
        const vals = self.get(key);
        for (vals) |v| {
            if (v == value) return true;
        }
        return false;
    }

    /// Returns the number of distinct keys. O(1).
    pub fn keysCount(self: *const BoolCharSetMultimap) usize {
        return self.inner.count();
    }

    /// Returns the total number of values across all keys.
    pub fn size(self: *const BoolCharSetMultimap) usize {
        return self.total_size;
    }

    pub fn len(self: *const BoolCharSetMultimap) usize {
        return self.total_size;
    }

    pub fn isEmpty(self: *const BoolCharSetMultimap) bool {
        return self.total_size == 0;
    }

    pub fn clear(self: *BoolCharSetMultimap) void {
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
    pub fn ensureUnusedCapacity(self: *BoolCharSetMultimap, additional: usize) Allocator.Error!void {
        try self.inner.ensureUnusedCapacity(self.allocator, @intCast(additional));
    }

    /// Ensures the backing map's total capacity is at least `new_capacity`.
    pub fn ensureTotalCapacity(self: *BoolCharSetMultimap, new_capacity: usize) Allocator.Error!void {
        try self.inner.ensureTotalCapacity(self.allocator, @intCast(new_capacity));
    }

    // ---- Iteration ----

    /// Calls the function for each key-value pair.
    pub fn forEach(self: *const BoolCharSetMultimap, f: *const fn (bool, u21) void) void {
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
    pub fn select(self: *const BoolCharSetMultimap, predicate: *const fn (bool, u21) bool) BoolCharSetMultimap {
        var result = BoolCharSetMultimap.init(self.allocator);
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
    pub fn reject(self: *const BoolCharSetMultimap, predicate: *const fn (bool, u21) bool) BoolCharSetMultimap {
        var result = BoolCharSetMultimap.init(self.allocator);
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
    pub fn anySatisfy(self: *const BoolCharSetMultimap, predicate: *const fn (bool, u21) bool) bool {
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
    pub fn allSatisfy(self: *const BoolCharSetMultimap, predicate: *const fn (bool, u21) bool) bool {
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
    pub fn noneSatisfy(self: *const BoolCharSetMultimap, predicate: *const fn (bool, u21) bool) bool {
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
    pub fn count(self: *const BoolCharSetMultimap, predicate: *const fn (bool, u21) bool) usize {
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
    pub fn uniqueKeys(self: *const BoolCharSetMultimap, allocator: Allocator) []bool {
        var result = std.ArrayListUnmanaged(bool){};
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            result.append(allocator, entry.key_ptr.*) catch @panic("out of memory");
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    /// Returns all values as a slice. Caller must free.
    pub fn valuesToSlice(self: *const BoolCharSetMultimap, allocator: Allocator) []u21 {
        var result = std.ArrayListUnmanaged(u21){};
        result.ensureTotalCapacity(allocator, self.total_size) catch @panic("out of memory");
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            result.appendSlice(allocator, entry.value_ptr.items) catch @panic("out of memory");
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    // ---- Fluent API ----

    pub fn withKeyValue(self: *BoolCharSetMultimap, key: bool, value: u21) *BoolCharSetMultimap {
        self.put(key, value);
        return self;
    }

    // ---- Formatting ----

    pub fn format(self: *const BoolCharSetMultimap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const BoolCharSetMultimap, other: *const BoolCharSetMultimap) bool {
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

test "BoolCharSetMultimap: put and get" {
    var m = BoolCharSetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(true, 'a');
    m.put(true, 'b');
    m.put(false, 'c');
    try std.testing.expectEqual(@as(usize, 3), m.size());
    try std.testing.expectEqual(@as(usize, 2), m.keysCount());
    try std.testing.expectEqual(@as(usize, 2), m.getCount(true));
    try std.testing.expectEqual(@as(usize, 1), m.getCount(false));
    // bool has only 2 distinct values; both are used as keys above
}

test "BoolCharSetMultimap: get returns values" {
    var m = BoolCharSetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(true, 'a');
    m.put(true, 'b');
    const vals = m.get(true);
    try std.testing.expectEqual(@as(usize, 2), vals.len);
}

test "BoolCharSetMultimap: get empty key" {
    var m = BoolCharSetMultimap.init(std.testing.allocator);
    defer m.deinit();
    const vals = m.get(false);
    try std.testing.expectEqual(@as(usize, 0), vals.len);
}

test "BoolCharSetMultimap: removeAll" {
    var m = BoolCharSetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(true, 'a');
    m.put(true, 'b');
    m.put(false, 'c');
    const removed = m.removeAll(true);
    try std.testing.expectEqual(@as(usize, 2), removed);
    try std.testing.expectEqual(@as(usize, 1), m.size());
    try std.testing.expect(!m.containsKey(true));
}

test "BoolCharSetMultimap: containsKey and containsKeyValue" {
    var m = BoolCharSetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(true, 'a');
    m.put(true, 'b');
    try std.testing.expect(m.containsKey(true));
    // bool has only 2 distinct values; kMiss=false is kv[1]
    try std.testing.expect(m.containsKeyValue(true, 'a'));
    try std.testing.expect(m.containsKeyValue(true, 'b'));
    try std.testing.expect(!m.containsKeyValue(true, 'c'));
}

test "BoolCharSetMultimap: clear" {
    var m = BoolCharSetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(true, 'a');
    m.put(false, 'b');
    m.clear();
    try std.testing.expect(m.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), m.size());
}

test "BoolCharSetMultimap: select" {
    var m = BoolCharSetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(true, 'a');
    m.put(false, 'b');
    var sel = m.select(struct {
        fn f(_: bool, v: u21) bool {
            return v == 'a';
        }
    }.f);
    defer sel.deinit();
    try std.testing.expect(sel.size() >= 1);
}

test "BoolCharSetMultimap: uniqueKeys and valuesToSlice" {
    var m = BoolCharSetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(true, 'a');
    m.put(true, 'b');
    m.put(false, 'c');
    const keys = m.uniqueKeys(std.testing.allocator);
    defer std.testing.allocator.free(keys);
    try std.testing.expectEqual(@as(usize, 2), keys.len);
    const vals = m.valuesToSlice(std.testing.allocator);
    defer std.testing.allocator.free(vals);
    try std.testing.expectEqual(@as(usize, 3), vals.len);
}

test "BoolCharSetMultimap: fluent withKeyValue" {
    var m = BoolCharSetMultimap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.withKeyValue(true, 'a').withKeyValue(true, 'b').withKeyValue(false, 'c');
    try std.testing.expectEqual(@as(usize, 3), m.size());
    try std.testing.expectEqual(@as(usize, 2), m.keysCount());
}

test "BoolCharSetMultimap: eql" {
    var m1 = BoolCharSetMultimap.init(std.testing.allocator);
    defer m1.deinit();
    m1.put(true, 'a');
    m1.put(true, 'b');
    var m2 = BoolCharSetMultimap.init(std.testing.allocator);
    defer m2.deinit();
    m2.put(true, 'a');
    m2.put(true, 'b');
    try std.testing.expect(m1.eql(&m2));
}

test "BoolCharSetMultimap: ensureUnusedCapacity reserves map slots" {
    var m = BoolCharSetMultimap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(100);
    m.put(true, 'a');
    m.put(false, 'b');
    try std.testing.expectEqual(@as(usize, 2), m.size());
}

test "BoolCharSetMultimap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: SetMultimap.init doesn't allocate (lazy backing),
    // so the first alloc (ensureUnusedCapacity grow) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var m = BoolCharSetMultimap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(1024));
}
