// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;

/// Set multimap from `bool` keys to `i32` values.
///
/// Each key maps to a set of unique values (duplicates on put are ignored).
/// Backed by `AutoHashMapUnmanaged` for O(1) key lookup.
pub const BoolI32SetMultimap = struct {
    inner: std.AutoHashMapUnmanaged(bool, std.ArrayListUnmanaged(i32)),
    allocator: Allocator,
    total_size: usize,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) BoolI32SetMultimap {
        return .{
            .inner = std.AutoHashMapUnmanaged(bool, std.ArrayListUnmanaged(i32)){},
            .allocator = allocator,
            .total_size = 0,
        };
    }

    pub fn deinit(self: *BoolI32SetMultimap) void {
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.inner.deinit(self.allocator);
    }

    // ---- Core Operations ----

    /// Adds a value to the set for the given key. Idempotent if the value is
    /// already present for this key (duplicate is silently dropped).
    pub fn put(self: *BoolI32SetMultimap, key: bool, value: i32) void {
        const map_key = key;
        const gop = self.inner.getOrPut(self.allocator, map_key) catch @panic("out of memory");
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayListUnmanaged(i32){};
        }
        for (gop.value_ptr.items) |existing| {
            if (existing == value) return;
        }
        gop.value_ptr.append(self.allocator, value) catch @panic("out of memory");
        self.total_size += 1;
    }

    /// Returns a slice of values for the given key. No allocation; the
    /// returned slice is a view into internal storage.
    pub fn get(self: *const BoolI32SetMultimap, key: bool) []const i32 {
        const map_key = key;
        if (self.inner.getPtr(map_key)) |list_ptr| {
            return list_ptr.items;
        }
        return &[_]i32{};
    }

    /// Returns the number of values for the given key.
    pub fn getCount(self: *const BoolI32SetMultimap, key: bool) usize {
        const map_key = key;
        if (self.inner.getPtr(map_key)) |list_ptr| {
            return list_ptr.items.len;
        }
        return 0;
    }

    /// Removes all values for the given key. Returns the number of values removed.
    pub fn removeAll(self: *BoolI32SetMultimap, key: bool) usize {
        const map_key = key;
        const list_ptr = self.inner.getPtr(map_key) orelse return 0;
        const removed = list_ptr.items.len;
        list_ptr.deinit(self.allocator);
        self.total_size -= removed;
        _ = self.inner.remove(map_key);
        return removed;
    }

    /// Returns true if the multimap contains the given key.
    pub fn containsKey(self: *const BoolI32SetMultimap, key: bool) bool {
        const map_key = key;
        return self.inner.contains(map_key);
    }

    /// Returns true if the multimap contains the given key-value pair.
    pub fn containsKeyValue(self: *const BoolI32SetMultimap, key: bool, value: i32) bool {
        const vals = self.get(key);
        for (vals) |v| {
            if (v == value) return true;
        }
        return false;
    }

    /// Returns the number of distinct keys. O(1).
    pub fn keysCount(self: *const BoolI32SetMultimap) usize {
        return self.inner.count();
    }

    /// Returns the total number of values across all keys.
    pub fn size(self: *const BoolI32SetMultimap) usize {
        return self.total_size;
    }

    pub fn len(self: *const BoolI32SetMultimap) usize {
        return self.total_size;
    }

    pub fn isEmpty(self: *const BoolI32SetMultimap) bool {
        return self.total_size == 0;
    }

    pub fn clear(self: *BoolI32SetMultimap) void {
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
    pub fn ensureUnusedCapacity(self: *BoolI32SetMultimap, additional: usize) Allocator.Error!void {
        try self.inner.ensureUnusedCapacity(self.allocator, @intCast(additional));
    }

    /// Ensures the backing map's total capacity is at least `new_capacity`.
    pub fn ensureTotalCapacity(self: *BoolI32SetMultimap, new_capacity: usize) Allocator.Error!void {
        try self.inner.ensureTotalCapacity(self.allocator, @intCast(new_capacity));
    }

    // ---- Iteration ----

    /// Calls the function for each key-value pair.
    pub fn forEach(self: *const BoolI32SetMultimap, f: *const fn (bool, i32) void) void {
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
    pub fn select(self: *const BoolI32SetMultimap, predicate: *const fn (bool, i32) bool) BoolI32SetMultimap {
        var result = BoolI32SetMultimap.init(self.allocator);
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
    pub fn reject(self: *const BoolI32SetMultimap, predicate: *const fn (bool, i32) bool) BoolI32SetMultimap {
        var result = BoolI32SetMultimap.init(self.allocator);
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
    pub fn anySatisfy(self: *const BoolI32SetMultimap, predicate: *const fn (bool, i32) bool) bool {
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
    pub fn allSatisfy(self: *const BoolI32SetMultimap, predicate: *const fn (bool, i32) bool) bool {
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
    pub fn noneSatisfy(self: *const BoolI32SetMultimap, predicate: *const fn (bool, i32) bool) bool {
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
    pub fn count(self: *const BoolI32SetMultimap, predicate: *const fn (bool, i32) bool) usize {
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
    pub fn uniqueKeys(self: *const BoolI32SetMultimap, allocator: Allocator) []bool {
        var result = std.ArrayListUnmanaged(bool){};
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            result.append(allocator, entry.key_ptr.*) catch @panic("out of memory");
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    /// Returns all values as a slice. Caller must free.
    pub fn valuesToSlice(self: *const BoolI32SetMultimap, allocator: Allocator) []i32 {
        var result = std.ArrayListUnmanaged(i32){};
        result.ensureTotalCapacity(allocator, self.total_size) catch @panic("out of memory");
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            result.appendSlice(allocator, entry.value_ptr.items) catch @panic("out of memory");
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    // ---- Fluent API ----

    pub fn withKeyValue(self: *BoolI32SetMultimap, key: bool, value: i32) *BoolI32SetMultimap {
        self.put(key, value);
        return self;
    }

    // ---- Formatting ----

    pub fn format(self: *const BoolI32SetMultimap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const BoolI32SetMultimap, other: *const BoolI32SetMultimap) bool {
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

test "BoolI32SetMultimap: put and get" {
    var m = BoolI32SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(true, 1);
    m.put(true, 2);
    m.put(false, 3);
    try std.testing.expectEqual(@as(usize, 3), m.size());
    try std.testing.expectEqual(@as(usize, 2), m.keysCount());
    try std.testing.expectEqual(@as(usize, 2), m.getCount(true));
    try std.testing.expectEqual(@as(usize, 1), m.getCount(false));
    // bool has only 2 distinct values; both are used as keys above
}

test "BoolI32SetMultimap: get returns values" {
    var m = BoolI32SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(true, 1);
    m.put(true, 2);
    const vals = m.get(true);
    try std.testing.expectEqual(@as(usize, 2), vals.len);
}

test "BoolI32SetMultimap: get empty key" {
    var m = BoolI32SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    const vals = m.get(false);
    try std.testing.expectEqual(@as(usize, 0), vals.len);
}

test "BoolI32SetMultimap: removeAll" {
    var m = BoolI32SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(true, 1);
    m.put(true, 2);
    m.put(false, 3);
    const removed = m.removeAll(true);
    try std.testing.expectEqual(@as(usize, 2), removed);
    try std.testing.expectEqual(@as(usize, 1), m.size());
    try std.testing.expect(!m.containsKey(true));
}

test "BoolI32SetMultimap: containsKey and containsKeyValue" {
    var m = BoolI32SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(true, 1);
    m.put(true, 2);
    try std.testing.expect(m.containsKey(true));
    // bool has only 2 distinct values; kMiss=false is kv[1]
    try std.testing.expect(m.containsKeyValue(true, 1));
    try std.testing.expect(m.containsKeyValue(true, 2));
    try std.testing.expect(!m.containsKeyValue(true, 3));
}

test "BoolI32SetMultimap: clear" {
    var m = BoolI32SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(true, 1);
    m.put(false, 2);
    m.clear();
    try std.testing.expect(m.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), m.size());
}

test "BoolI32SetMultimap: select" {
    var m = BoolI32SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(true, 1);
    m.put(false, 2);
    var sel = m.select(struct {
        fn f(_: bool, v: i32) bool {
            return v == 1;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expect(sel.size() >= 1);
}

test "BoolI32SetMultimap: uniqueKeys and valuesToSlice" {
    var m = BoolI32SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(true, 1);
    m.put(true, 2);
    m.put(false, 3);
    const keys = m.uniqueKeys(std.testing.allocator);
    defer std.testing.allocator.free(keys);
    try std.testing.expectEqual(@as(usize, 2), keys.len);
    const vals = m.valuesToSlice(std.testing.allocator);
    defer std.testing.allocator.free(vals);
    try std.testing.expectEqual(@as(usize, 3), vals.len);
}

test "BoolI32SetMultimap: fluent withKeyValue" {
    var m = BoolI32SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.withKeyValue(true, 1).withKeyValue(true, 2).withKeyValue(false, 3);
    try std.testing.expectEqual(@as(usize, 3), m.size());
    try std.testing.expectEqual(@as(usize, 2), m.keysCount());
}

test "BoolI32SetMultimap: eql" {
    var m1 = BoolI32SetMultimap.init(std.testing.allocator);
    defer m1.deinit();
    m1.put(true, 1);
    m1.put(true, 2);
    var m2 = BoolI32SetMultimap.init(std.testing.allocator);
    defer m2.deinit();
    m2.put(true, 1);
    m2.put(true, 2);
    try std.testing.expect(m1.eql(&m2));
}

test "BoolI32SetMultimap: ensureUnusedCapacity reserves map slots" {
    var m = BoolI32SetMultimap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(100);
    m.put(true, 1);
    m.put(false, 2);
    try std.testing.expectEqual(@as(usize, 2), m.size());
}

test "BoolI32SetMultimap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: SetMultimap.init doesn't allocate (lazy backing),
    // so the first alloc (ensureUnusedCapacity grow) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var m = BoolI32SetMultimap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(1024));
}
