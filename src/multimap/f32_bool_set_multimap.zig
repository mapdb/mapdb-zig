// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;

/// Set multimap from `f32` keys to `bool` values.
///
/// Each key maps to a set of unique values (duplicates on put are ignored).
/// Backed by `AutoHashMapUnmanaged` for O(1) key lookup.
/// Float keys are stored as `u32` bit patterns for correct hashing/equality.
pub const F32BoolSetMultimap = struct {
    inner: std.AutoHashMapUnmanaged(u32, std.ArrayListUnmanaged(bool)),
    allocator: Allocator,
    total_size: usize,

    // ---- Construction / Destruction ----

    pub fn init(allocator: Allocator) F32BoolSetMultimap {
        return .{
            .inner = std.AutoHashMapUnmanaged(u32, std.ArrayListUnmanaged(bool)){},
            .allocator = allocator,
            .total_size = 0,
        };
    }

    pub fn deinit(self: *F32BoolSetMultimap) void {
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.inner.deinit(self.allocator);
    }

    // ---- Core Operations ----

    /// Adds a value to the set for the given key. Idempotent if the value is
    /// already present for this key (duplicate is silently dropped).
    pub fn put(self: *F32BoolSetMultimap, key: f32, value: bool) void {
        const map_key = @as(u32, @bitCast(key));
        const gop = self.inner.getOrPut(self.allocator, map_key) catch @panic("out of memory");
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayListUnmanaged(bool){};
        }
        for (gop.value_ptr.items) |existing| {
            if (existing == value) return;
        }
        gop.value_ptr.append(self.allocator, value) catch @panic("out of memory");
        self.total_size += 1;
    }

    /// Returns a slice of values for the given key. No allocation; the
    /// returned slice is a view into internal storage.
    pub fn get(self: *const F32BoolSetMultimap, key: f32) []const bool {
        const map_key = @as(u32, @bitCast(key));
        if (self.inner.getPtr(map_key)) |list_ptr| {
            return list_ptr.items;
        }
        return &[_]bool{};
    }

    /// Returns the number of values for the given key.
    pub fn getCount(self: *const F32BoolSetMultimap, key: f32) usize {
        const map_key = @as(u32, @bitCast(key));
        if (self.inner.getPtr(map_key)) |list_ptr| {
            return list_ptr.items.len;
        }
        return 0;
    }

    /// Removes all values for the given key. Returns the number of values removed.
    pub fn removeAll(self: *F32BoolSetMultimap, key: f32) usize {
        const map_key = @as(u32, @bitCast(key));
        const list_ptr = self.inner.getPtr(map_key) orelse return 0;
        const removed = list_ptr.items.len;
        list_ptr.deinit(self.allocator);
        self.total_size -= removed;
        _ = self.inner.remove(map_key);
        return removed;
    }

    /// Returns true if the multimap contains the given key.
    pub fn containsKey(self: *const F32BoolSetMultimap, key: f32) bool {
        const map_key = @as(u32, @bitCast(key));
        return self.inner.contains(map_key);
    }

    /// Returns true if the multimap contains the given key-value pair.
    pub fn containsKeyValue(self: *const F32BoolSetMultimap, key: f32, value: bool) bool {
        const vals = self.get(key);
        for (vals) |v| {
            if (v == value) return true;
        }
        return false;
    }

    /// Returns the number of distinct keys. O(1).
    pub fn keysCount(self: *const F32BoolSetMultimap) usize {
        return self.inner.count();
    }

    /// Returns the total number of values across all keys.
    pub fn size(self: *const F32BoolSetMultimap) usize {
        return self.total_size;
    }

    pub fn len(self: *const F32BoolSetMultimap) usize {
        return self.total_size;
    }

    pub fn isEmpty(self: *const F32BoolSetMultimap) bool {
        return self.total_size == 0;
    }

    pub fn clear(self: *F32BoolSetMultimap) void {
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
    pub fn ensureUnusedCapacity(self: *F32BoolSetMultimap, additional: usize) Allocator.Error!void {
        try self.inner.ensureUnusedCapacity(self.allocator, @intCast(additional));
    }

    /// Ensures the backing map's total capacity is at least `new_capacity`.
    pub fn ensureTotalCapacity(self: *F32BoolSetMultimap, new_capacity: usize) Allocator.Error!void {
        try self.inner.ensureTotalCapacity(self.allocator, @intCast(new_capacity));
    }

    // ---- Iteration ----

    /// Calls the function for each key-value pair.
    pub fn forEach(self: *const F32BoolSetMultimap, f: *const fn (f32, bool) void) void {
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            const key = @as(f32, @bitCast(entry.key_ptr.*));
            for (entry.value_ptr.items) |v| {
                f(key, v);
            }
        }
    }

    // ---- Functional Operations ----

    /// Returns a new multimap containing only pairs that satisfy the predicate.
    pub fn select(self: *const F32BoolSetMultimap, predicate: *const fn (f32, bool) bool) F32BoolSetMultimap {
        var result = F32BoolSetMultimap.init(self.allocator);
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            const key = @as(f32, @bitCast(entry.key_ptr.*));
            for (entry.value_ptr.items) |v| {
                if (predicate(key, v)) result.put(key, v);
            }
        }
        return result;
    }

    /// Returns a new multimap containing only pairs that do not satisfy the predicate.
    pub fn reject(self: *const F32BoolSetMultimap, predicate: *const fn (f32, bool) bool) F32BoolSetMultimap {
        var result = F32BoolSetMultimap.init(self.allocator);
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            const key = @as(f32, @bitCast(entry.key_ptr.*));
            for (entry.value_ptr.items) |v| {
                if (!predicate(key, v)) result.put(key, v);
            }
        }
        return result;
    }

    /// Returns true if any key-value pair satisfies the predicate.
    pub fn anySatisfy(self: *const F32BoolSetMultimap, predicate: *const fn (f32, bool) bool) bool {
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            const key = @as(f32, @bitCast(entry.key_ptr.*));
            for (entry.value_ptr.items) |v| {
                if (predicate(key, v)) return true;
            }
        }
        return false;
    }

    /// Returns true if all key-value pairs satisfy the predicate.
    pub fn allSatisfy(self: *const F32BoolSetMultimap, predicate: *const fn (f32, bool) bool) bool {
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            const key = @as(f32, @bitCast(entry.key_ptr.*));
            for (entry.value_ptr.items) |v| {
                if (!predicate(key, v)) return false;
            }
        }
        return true;
    }

    /// Returns true if no key-value pair satisfies the predicate.
    pub fn noneSatisfy(self: *const F32BoolSetMultimap, predicate: *const fn (f32, bool) bool) bool {
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            const key = @as(f32, @bitCast(entry.key_ptr.*));
            for (entry.value_ptr.items) |v| {
                if (predicate(key, v)) return false;
            }
        }
        return true;
    }

    /// Returns the number of key-value pairs that satisfy the predicate.
    pub fn count(self: *const F32BoolSetMultimap, predicate: *const fn (f32, bool) bool) usize {
        var c: usize = 0;
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            const key = @as(f32, @bitCast(entry.key_ptr.*));
            for (entry.value_ptr.items) |v| {
                if (predicate(key, v)) c += 1;
            }
        }
        return c;
    }

    // ---- Key/Value Collection ----

    /// Returns all unique keys as a slice. Caller must free.
    pub fn uniqueKeys(self: *const F32BoolSetMultimap, allocator: Allocator) []f32 {
        var result = std.ArrayListUnmanaged(f32){};
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            result.append(allocator, @as(f32, @bitCast(entry.key_ptr.*))) catch @panic("out of memory");
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    /// Returns all values as a slice. Caller must free.
    pub fn valuesToSlice(self: *const F32BoolSetMultimap, allocator: Allocator) []bool {
        var result = std.ArrayListUnmanaged(bool){};
        result.ensureTotalCapacity(allocator, self.total_size) catch @panic("out of memory");
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            result.appendSlice(allocator, entry.value_ptr.items) catch @panic("out of memory");
        }
        return result.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    // ---- Fluent API ----

    pub fn withKeyValue(self: *F32BoolSetMultimap, key: f32, value: bool) *F32BoolSetMultimap {
        self.put(key, value);
        return self;
    }

    // ---- Formatting ----

    pub fn format(self: *const F32BoolSetMultimap, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll("{");
        var first = true;
        var it = self.inner.iterator();
        while (it.next()) |entry| {
            const key = @as(f32, @bitCast(entry.key_ptr.*));
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

    pub fn eql(self: *const F32BoolSetMultimap, other: *const F32BoolSetMultimap) bool {
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

test "F32BoolSetMultimap: put and get" {
    var m = F32BoolSetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1.0, true);
    m.put(1.0, false);
    m.put(2.0, true);
    try std.testing.expectEqual(@as(usize, 3), m.size());
    try std.testing.expectEqual(@as(usize, 2), m.keysCount());
    try std.testing.expectEqual(@as(usize, 2), m.getCount(1.0));
    try std.testing.expectEqual(@as(usize, 1), m.getCount(2.0));
    try std.testing.expectEqual(@as(usize, 0), m.getCount(99.0));
}

test "F32BoolSetMultimap: get returns values" {
    var m = F32BoolSetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1.0, true);
    m.put(1.0, false);
    const vals = m.get(1.0);
    try std.testing.expectEqual(@as(usize, 2), vals.len);
}

test "F32BoolSetMultimap: get empty key" {
    var m = F32BoolSetMultimap.init(std.testing.allocator);
    defer m.deinit();
    const vals = m.get(99.0);
    try std.testing.expectEqual(@as(usize, 0), vals.len);
}

test "F32BoolSetMultimap: removeAll" {
    var m = F32BoolSetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1.0, true);
    m.put(1.0, false);
    m.put(2.0, true);
    const removed = m.removeAll(1.0);
    try std.testing.expectEqual(@as(usize, 2), removed);
    try std.testing.expectEqual(@as(usize, 1), m.size());
    try std.testing.expect(!m.containsKey(1.0));
}

test "F32BoolSetMultimap: containsKey and containsKeyValue" {
    var m = F32BoolSetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1.0, true);
    m.put(1.0, false);
    try std.testing.expect(m.containsKey(1.0));
    try std.testing.expect(!m.containsKey(99.0));
    try std.testing.expect(m.containsKeyValue(1.0, true));
    try std.testing.expect(m.containsKeyValue(1.0, false));
    // bool has only 2 distinct values; vv[2]=true equals vv[0]
}

test "F32BoolSetMultimap: clear" {
    var m = F32BoolSetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1.0, true);
    m.put(2.0, false);
    m.clear();
    try std.testing.expect(m.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), m.size());
}

test "F32BoolSetMultimap: select" {
    var m = F32BoolSetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1.0, true);
    m.put(2.0, false);
    var sel = m.select(struct {
        fn f(_: f32, v: bool) bool {
            return v == true;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expect(sel.size() >= 1);
}

test "F32BoolSetMultimap: uniqueKeys and valuesToSlice" {
    var m = F32BoolSetMultimap.init(std.testing.allocator);
    defer m.deinit();
    m.put(1.0, true);
    m.put(1.0, false);
    m.put(2.0, true);
    const keys = m.uniqueKeys(std.testing.allocator);
    defer std.testing.allocator.free(keys);
    try std.testing.expectEqual(@as(usize, 2), keys.len);
    const vals = m.valuesToSlice(std.testing.allocator);
    defer std.testing.allocator.free(vals);
    try std.testing.expectEqual(@as(usize, 3), vals.len);
}

test "F32BoolSetMultimap: fluent withKeyValue" {
    var m = F32BoolSetMultimap.init(std.testing.allocator);
    defer m.deinit();
    _ = m.withKeyValue(1.0, true).withKeyValue(1.0, false).withKeyValue(2.0, true);
    try std.testing.expectEqual(@as(usize, 3), m.size());
    try std.testing.expectEqual(@as(usize, 2), m.keysCount());
}

test "F32BoolSetMultimap: eql" {
    var m1 = F32BoolSetMultimap.init(std.testing.allocator);
    defer m1.deinit();
    m1.put(1.0, true);
    m1.put(1.0, false);
    var m2 = F32BoolSetMultimap.init(std.testing.allocator);
    defer m2.deinit();
    m2.put(1.0, true);
    m2.put(1.0, false);
    try std.testing.expect(m1.eql(&m2));
}

test "F32BoolSetMultimap: ensureUnusedCapacity reserves map slots" {
    var m = F32BoolSetMultimap.init(std.testing.allocator);
    defer m.deinit();
    try m.ensureUnusedCapacity(100);
    m.put(1.0, true);
    m.put(2.0, false);
    try std.testing.expectEqual(@as(usize, 2), m.size());
}

test "F32BoolSetMultimap: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: SetMultimap.init doesn't allocate (lazy backing),
    // so the first alloc (ensureUnusedCapacity grow) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var m = F32BoolSetMultimap.init(failing.allocator());
    defer m.deinit();
    try std.testing.expectError(error.OutOfMemory, m.ensureUnusedCapacity(1024));
}
