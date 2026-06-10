// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

// Open-addressing hash table with linear probing and Robin Hood backward-shift deletion.
//
// Uses interleaved Entry structs for cache locality — key, value, and occupied
// flag sit in the same cache line, minimizing memory loads per probe.

const std = @import("std");
const Allocator = std.mem.Allocator;

const DEFAULT_CAPACITY: usize = 16;

fn hashKey(comptime K: type, key: K) u64 {
    const raw: u64 = switch (@typeInfo(K)) {
        .int, .comptime_int => @bitCast(@as(i64, @intCast(key))),
        .float => if (K == f32)
            @as(u64, @as(u32, @bitCast(key)))
        else
            @as(u64, @bitCast(key)),
        .bool => if (key) @as(u64, 1) else 0,
        else => @compileError("unsupported key type for hash table: " ++ @typeName(K)),
    };
    // 64-bit Fibonacci hash (golden-ratio multiply). The 32-bit
    // constant 0x9E3779B9 gives poor distribution on i64 keys; the
    // 64-bit form below mixes the full width.
    return raw *% 0x9E3779B97F4A7C15;
}

fn keyEql(comptime K: type, a: K, b: K) bool {
    if (K == f32) return @as(u32, @bitCast(a)) == @as(u32, @bitCast(b));
    if (K == f64) return @as(u64, @bitCast(a)) == @as(u64, @bitCast(b));
    return a == b;
}

// ---------------------------------------------------------------------------
// OpenHashMap
// ---------------------------------------------------------------------------

pub fn MapEntry(comptime K: type, comptime V: type) type {
    return struct {
        key: K,
        value: V,
        occupied: bool,
    };
}

pub fn OpenHashMap(comptime K: type, comptime V: type) type {
    const Entry = MapEntry(K, V);

    return struct {
        const Self = @This();

        entries: []Entry,
        size: usize,
        capacity: usize,
        alloc: Allocator,

        pub fn init(
            keys_alloc: Allocator,
            values_alloc: Allocator,
            index_alloc: Allocator,
        ) Allocator.Error!Self {
            // Use first allocator for the unified entries array
            _ = values_alloc;
            _ = index_alloc;
            return initCapacity(keys_alloc, DEFAULT_CAPACITY);
        }

        pub fn initCapacity(alloc: Allocator, requested: usize) Allocator.Error!Self {
            const cap = nextPow2(@max(requested, DEFAULT_CAPACITY));
            const entries = try alloc.alloc(Entry, cap);
            for (entries) |*e| {
                e.* = .{ .key = defaultVal(K), .value = defaultVal(V), .occupied = false };
            }
            return .{
                .entries = entries,
                .size = 0,
                .capacity = cap,
                .alloc = alloc,
            };
        }

        pub fn deinit(self: *Self) void {
            self.alloc.free(self.entries);
            self.* = undefined;
        }

        inline fn mask(self: *const Self) usize {
            return self.capacity - 1;
        }

        inline fn needsResize(self: *const Self) bool {
            // Strictly below 0.75: grow once (size+1)/capacity would reach 0.75,
            // i.e. use >= so the 12th insert into a capacity-16 table resizes.
            // Consistent with ensureCapacity's strict form below.
            return (self.size + 1) * 4 >= self.capacity * 3;
        }

        fn resize(self: *Self) Allocator.Error!void {
            try self.growTo(self.capacity * 2);
        }

        /// Rehash all entries into a freshly allocated buffer of size `new_cap`.
        /// Caller must guarantee `new_cap` is a power of two and fits every live
        /// entry under the 0.75 load factor. No-op if `new_cap <= self.capacity`.
        fn growTo(self: *Self, new_cap: usize) Allocator.Error!void {
            if (new_cap <= self.capacity) return;
            const old = self.entries;
            const old_cap = self.capacity;

            self.entries = try self.alloc.alloc(Entry, new_cap);
            for (self.entries) |*e| {
                e.* = .{ .key = defaultVal(K), .value = defaultVal(V), .occupied = false };
            }
            self.capacity = new_cap;
            self.size = 0;

            for (0..old_cap) |i| {
                if (old[i].occupied) {
                    self.insertNoResize(old[i].key, old[i].value);
                }
            }
            self.alloc.free(old);
        }

        /// Infallible insertion used by growTo for rehashing into a buffer that
        /// is already guaranteed to fit every live entry.
        fn insertNoResize(self: *Self, key: K, value: V) void {
            const m = self.mask();
            var idx = @as(usize, @intCast(hashKey(K, key) & m));
            while (true) {
                if (!self.entries[idx].occupied) {
                    self.entries[idx] = .{ .key = key, .value = value, .occupied = true };
                    self.size += 1;
                    return;
                }
                idx = (idx + 1) & m;
            }
        }

        /// Grow the backing table so that `additional` more entries can be put
        /// without triggering a resize. Idempotent: a no-op when the current
        /// capacity already covers the request.
        ///
        /// This is the hook that the generated wrappers expose as
        /// `ensureUnusedCapacity` / `ensureTotalCapacity`, enabling a "reserve
        /// fallibly, then put infallibly" usage pattern.
        pub fn ensureCapacity(self: *Self, additional: usize) Allocator.Error!void {
            const needed = self.size + additional;
            // Keep load factor strictly below 0.75. needsResize() resizes when
            // (size+1)*4 >= capacity*3, so an insert reaching `needed` entries
            // stays in place iff capacity*3 > needed*4, i.e. capacity > needed*4/3.
            // (needed*4)/3 + 1 is an integer strictly greater than needed*4/3.
            const required = (needed * 4) / 3 + 1;
            if (required <= self.capacity) return;
            const new_cap = nextPow2(@max(required, DEFAULT_CAPACITY));
            try self.growTo(new_cap);
        }

        fn rehashFrom(self: *Self, deleted: usize) void {
            const m = self.mask();
            var gap = deleted;
            var idx = (deleted + 1) & m;
            while (self.entries[idx].occupied) {
                const ideal = @as(usize, @intCast(hashKey(K, self.entries[idx].key) & m));
                const dist_current = (idx -% ideal) & m;
                const dist_gap = (gap -% ideal) & m;
                if (dist_current > dist_gap) {
                    self.entries[gap] = self.entries[idx];
                    self.entries[idx] = .{ .key = defaultVal(K), .value = defaultVal(V), .occupied = false };
                    gap = idx;
                }
                idx = (idx + 1) & m;
                if (idx == deleted) break;
            }
        }

        pub fn put(self: *Self, key: K, value: V) Allocator.Error!?V {
            if (self.needsResize()) try self.resize();
            const m = self.mask();
            var idx = @as(usize, @intCast(hashKey(K, key) & m));
            while (true) {
                if (!self.entries[idx].occupied) {
                    self.entries[idx] = .{ .key = key, .value = value, .occupied = true };
                    self.size += 1;
                    return null;
                }
                if (keyEql(K, self.entries[idx].key, key)) {
                    const old = self.entries[idx].value;
                    self.entries[idx].value = value;
                    return old;
                }
                idx = (idx + 1) & m;
            }
        }

        pub fn get(self: *const Self, key: K) ?V {
            if (self.size == 0) return null;
            const m = self.mask();
            var idx = @as(usize, @intCast(hashKey(K, key) & m));
            while (true) {
                if (!self.entries[idx].occupied) return null;
                if (keyEql(K, self.entries[idx].key, key)) return self.entries[idx].value;
                idx = (idx + 1) & m;
            }
        }

        pub fn getPtr(self: *Self, key: K) ?*V {
            if (self.size == 0) return null;
            const m = self.mask();
            var idx = @as(usize, @intCast(hashKey(K, key) & m));
            while (true) {
                if (!self.entries[idx].occupied) return null;
                if (keyEql(K, self.entries[idx].key, key)) return &self.entries[idx].value;
                idx = (idx + 1) & m;
            }
        }

        pub fn remove(self: *Self, key: K) ?V {
            if (self.size == 0) return null;
            const m = self.mask();
            var idx = @as(usize, @intCast(hashKey(K, key) & m));
            while (true) {
                if (!self.entries[idx].occupied) return null;
                if (keyEql(K, self.entries[idx].key, key)) {
                    const old = self.entries[idx].value;
                    self.entries[idx] = .{ .key = defaultVal(K), .value = defaultVal(V), .occupied = false };
                    self.size -= 1;
                    self.rehashFrom(idx);
                    return old;
                }
                idx = (idx + 1) & m;
            }
        }

        pub fn containsKey(self: *const Self, key: K) bool {
            return self.get(key) != null;
        }

        pub fn containsValue(self: *const Self, value: V) bool {
            for (0..self.capacity) |i| {
                if (self.entries[i].occupied and valEql(V, self.entries[i].value, value)) return true;
            }
            return false;
        }

        pub fn len(self: *const Self) usize {
            return self.size;
        }
        pub fn isEmpty(self: *const Self) bool {
            return self.size == 0;
        }

        pub fn clear(self: *Self) void {
            for (self.entries) |*e| {
                e.* = .{ .key = defaultVal(K), .value = defaultVal(V), .occupied = false };
            }
            self.size = 0;
        }

        pub fn forEach(self: *const Self, f: *const fn (K, V) void) void {
            for (0..self.capacity) |i| {
                if (self.entries[i].occupied) f(self.entries[i].key, self.entries[i].value);
            }
        }

        pub fn forEachKey(self: *const Self, f: *const fn (K) void) void {
            for (0..self.capacity) |i| {
                if (self.entries[i].occupied) f(self.entries[i].key);
            }
        }

        pub fn forEachValue(self: *const Self, f: *const fn (V) void) void {
            for (0..self.capacity) |i| {
                if (self.entries[i].occupied) f(self.entries[i].value);
            }
        }

        pub fn keysToSlice(self: *const Self, allocator: Allocator) Allocator.Error![]K {
            const result = try allocator.alloc(K, self.size);
            var idx: usize = 0;
            for (0..self.capacity) |i| {
                if (self.entries[i].occupied) {
                    result[idx] = self.entries[i].key;
                    idx += 1;
                }
            }
            return result;
        }

        pub fn valuesToSlice(self: *const Self, allocator: Allocator) Allocator.Error![]V {
            const result = try allocator.alloc(V, self.size);
            var idx: usize = 0;
            for (0..self.capacity) |i| {
                if (self.entries[i].occupied) {
                    result[idx] = self.entries[i].value;
                    idx += 1;
                }
            }
            return result;
        }
    };
}

// ---------------------------------------------------------------------------
// OpenHashSet
// ---------------------------------------------------------------------------

pub fn SetEntry(comptime K: type) type {
    return struct {
        key: K,
        occupied: bool,
    };
}

pub fn OpenHashSet(comptime K: type) type {
    const Entry = SetEntry(K);

    return struct {
        const Self = @This();

        entries: []Entry,
        size: usize,
        capacity: usize,
        alloc: Allocator,

        pub fn init(
            keys_alloc: Allocator,
            index_alloc: Allocator,
        ) Allocator.Error!Self {
            _ = index_alloc;
            return initCapacity(keys_alloc, DEFAULT_CAPACITY);
        }

        pub fn initCapacity(alloc: Allocator, requested: usize) Allocator.Error!Self {
            const cap = nextPow2(@max(requested, DEFAULT_CAPACITY));
            const entries = try alloc.alloc(Entry, cap);
            for (entries) |*e| {
                e.* = .{ .key = defaultVal(K), .occupied = false };
            }
            return .{
                .entries = entries,
                .size = 0,
                .capacity = cap,
                .alloc = alloc,
            };
        }

        pub fn deinit(self: *Self) void {
            self.alloc.free(self.entries);
            self.* = undefined;
        }

        inline fn mask(self: *const Self) usize {
            return self.capacity - 1;
        }

        inline fn needsResize(self: *const Self) bool {
            // Strictly below 0.75: grow once (size+1)/capacity would reach 0.75,
            // i.e. use >= so the 12th insert into a capacity-16 table resizes.
            // Consistent with ensureCapacity's strict form below.
            return (self.size + 1) * 4 >= self.capacity * 3;
        }

        fn resize(self: *Self) Allocator.Error!void {
            try self.growTo(self.capacity * 2);
        }

        fn growTo(self: *Self, new_cap: usize) Allocator.Error!void {
            if (new_cap <= self.capacity) return;
            const old = self.entries;
            const old_cap = self.capacity;
            self.entries = try self.alloc.alloc(Entry, new_cap);
            for (self.entries) |*e| {
                e.* = .{ .key = defaultVal(K), .occupied = false };
            }
            self.capacity = new_cap;
            self.size = 0;
            for (0..old_cap) |i| {
                if (old[i].occupied) self.insertNoResize(old[i].key);
            }
            self.alloc.free(old);
        }

        fn insertNoResize(self: *Self, value: K) void {
            const m = self.mask();
            var idx = @as(usize, @intCast(hashKey(K, value) & m));
            while (true) {
                if (!self.entries[idx].occupied) {
                    self.entries[idx] = .{ .key = value, .occupied = true };
                    self.size += 1;
                    return;
                }
                idx = (idx + 1) & m;
            }
        }

        /// Grow the backing table so that `additional` more entries can be
        /// added without triggering a resize. Idempotent: a no-op when the
        /// current capacity already covers the request. See the companion
        /// method on `OpenHashMap` for the motivation.
        pub fn ensureCapacity(self: *Self, additional: usize) Allocator.Error!void {
            const needed = self.size + additional;
            const required = (needed * 4) / 3 + 1;
            if (required <= self.capacity) return;
            const new_cap = nextPow2(@max(required, DEFAULT_CAPACITY));
            try self.growTo(new_cap);
        }

        fn rehashFrom(self: *Self, deleted: usize) void {
            const m = self.mask();
            var gap = deleted;
            var idx = (deleted + 1) & m;
            while (self.entries[idx].occupied) {
                const ideal = @as(usize, @intCast(hashKey(K, self.entries[idx].key) & m));
                const dist_current = (idx -% ideal) & m;
                const dist_gap = (gap -% ideal) & m;
                if (dist_current > dist_gap) {
                    self.entries[gap] = self.entries[idx];
                    self.entries[idx] = .{ .key = defaultVal(K), .occupied = false };
                    gap = idx;
                }
                idx = (idx + 1) & m;
                if (idx == deleted) break;
            }
        }

        pub fn add(self: *Self, value: K) Allocator.Error!bool {
            if (self.needsResize()) try self.resize();
            const m = self.mask();
            var idx = @as(usize, @intCast(hashKey(K, value) & m));
            while (true) {
                if (!self.entries[idx].occupied) {
                    self.entries[idx] = .{ .key = value, .occupied = true };
                    self.size += 1;
                    return true;
                }
                if (keyEql(K, self.entries[idx].key, value)) return false;
                idx = (idx + 1) & m;
            }
        }

        pub fn remove(self: *Self, value: K) bool {
            if (self.size == 0) return false;
            const m = self.mask();
            var idx = @as(usize, @intCast(hashKey(K, value) & m));
            while (true) {
                if (!self.entries[idx].occupied) return false;
                if (keyEql(K, self.entries[idx].key, value)) {
                    self.entries[idx] = .{ .key = defaultVal(K), .occupied = false };
                    self.size -= 1;
                    self.rehashFrom(idx);
                    return true;
                }
                idx = (idx + 1) & m;
            }
        }

        pub fn contains(self: *const Self, value: K) bool {
            if (self.size == 0) return false;
            const m = self.mask();
            var idx = @as(usize, @intCast(hashKey(K, value) & m));
            while (true) {
                if (!self.entries[idx].occupied) return false;
                if (keyEql(K, self.entries[idx].key, value)) return true;
                idx = (idx + 1) & m;
            }
        }

        pub fn len(self: *const Self) usize {
            return self.size;
        }
        pub fn isEmpty(self: *const Self) bool {
            return self.size == 0;
        }

        pub fn clear(self: *Self) void {
            for (self.entries) |*e| {
                e.* = .{ .key = defaultVal(K), .occupied = false };
            }
            self.size = 0;
        }

        pub fn forEach(self: *const Self, f: *const fn (K) void) void {
            for (0..self.capacity) |i| {
                if (self.entries[i].occupied) f(self.entries[i].key);
            }
        }

        pub fn toSlice(self: *const Self, allocator: Allocator) Allocator.Error![]K {
            const result = try allocator.alloc(K, self.size);
            var idx: usize = 0;
            for (0..self.capacity) |i| {
                if (self.entries[i].occupied) {
                    result[idx] = self.entries[i].key;
                    idx += 1;
                }
            }
            return result;
        }
    };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn nextPow2(n: usize) usize {
    if (n == 0) return 1;
    var v = n - 1;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
    if (@bitSizeOf(usize) > 32) {
        v |= v >> 32;
    }
    return v + 1;
}

fn defaultVal(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .int, .comptime_int => 0,
        .float, .comptime_float => 0.0,
        .bool => false,
        else => @as(T, 0),
    };
}

fn valEql(comptime V: type, a: V, b: V) bool {
    if (V == f32) return @as(u32, @bitCast(a)) == @as(u32, @bitCast(b));
    if (V == f64) return @as(u64, @bitCast(a)) == @as(u64, @bitCast(b));
    return a == b;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "map: insert, get, remove" {
    var m = try OpenHashMap(i32, i32).init(std.testing.allocator, std.testing.allocator, std.testing.allocator);
    defer m.deinit();
    try std.testing.expectEqual(@as(?i32, null), try m.put(1, 10));
    try std.testing.expectEqual(@as(?i32, null), try m.put(2, 20));
    try std.testing.expectEqual(@as(?i32, 10), try m.put(1, 99));
    try std.testing.expectEqual(@as(?i32, 99), m.get(1));
    try std.testing.expectEqual(@as(?i32, 20), m.get(2));
    try std.testing.expectEqual(@as(?i32, null), m.get(3));
    try std.testing.expectEqual(@as(?i32, 99), m.remove(1));
    try std.testing.expectEqual(@as(?i32, null), m.get(1));
    try std.testing.expectEqual(@as(usize, 1), m.len());
}

test "map: resize" {
    var m = try OpenHashMap(i32, i32).init(std.testing.allocator, std.testing.allocator, std.testing.allocator);
    defer m.deinit();
    for (0..200) |i| {
        _ = try m.put(@intCast(i), @intCast(i * 10));
    }
    try std.testing.expectEqual(@as(usize, 200), m.len());
    for (0..200) |i| {
        try std.testing.expectEqual(@as(?i32, @intCast(i * 10)), m.get(@intCast(i)));
    }
}

test "map: delete heavy" {
    var m = try OpenHashMap(i32, i32).init(std.testing.allocator, std.testing.allocator, std.testing.allocator);
    defer m.deinit();
    for (0..50000) |i| {
        _ = try m.put(@intCast(i), @intCast(i));
    }
    var idx: i32 = 0;
    while (idx < 50000) : (idx += 2) _ = m.remove(idx);
    idx = 50000;
    while (idx < 75000) : (idx += 1) _ = try m.put(idx, idx);
    idx = 0;
    while (idx < 75000) : (idx += 1) _ = m.remove(idx);
    try std.testing.expectEqual(@as(usize, 0), m.len());
}

test "map: float keys" {
    var m = try OpenHashMap(f32, i32).init(std.testing.allocator, std.testing.allocator, std.testing.allocator);
    defer m.deinit();
    _ = try m.put(1.5, 10);
    _ = try m.put(2.5, 20);
    try std.testing.expectEqual(@as(?i32, 10), m.get(1.5));
    try std.testing.expectEqual(@as(?i32, null), m.get(3.5));
}

test "map: bool keys" {
    var m = try OpenHashMap(bool, i32).init(std.testing.allocator, std.testing.allocator, std.testing.allocator);
    defer m.deinit();
    _ = try m.put(true, 1);
    _ = try m.put(false, 0);
    try std.testing.expectEqual(@as(?i32, 1), m.get(true));
    try std.testing.expectEqual(@as(usize, 2), m.len());
}

test "set: add, remove, contains" {
    var s = try OpenHashSet(i32).init(std.testing.allocator, std.testing.allocator);
    defer s.deinit();
    try std.testing.expect(try s.add(1));
    try std.testing.expect(try s.add(2));
    try std.testing.expect(!(try s.add(1)));
    try std.testing.expectEqual(@as(usize, 2), s.len());
    try std.testing.expect(s.contains(1));
    try std.testing.expect(s.remove(1));
    try std.testing.expect(!s.contains(1));
    try std.testing.expectEqual(@as(usize, 1), s.len());
}

test "set: resize" {
    var s = try OpenHashSet(i32).init(std.testing.allocator, std.testing.allocator);
    defer s.deinit();
    for (0..200) |i| {
        _ = try s.add(@intCast(i));
    }
    try std.testing.expectEqual(@as(usize, 200), s.len());
    for (0..200) |i| {
        try std.testing.expect(s.contains(@intCast(i)));
    }
}

test "map: getPtr" {
    var m = try OpenHashMap(i32, i32).init(std.testing.allocator, std.testing.allocator, std.testing.allocator);
    defer m.deinit();
    _ = try m.put(1, 10);
    if (m.getPtr(1)) |ptr| {
        ptr.* += 5;
    }
    try std.testing.expectEqual(@as(?i32, 15), m.get(1));
}

test "map: ensureCapacity grows and subsequent puts do not resize" {
    var m = try OpenHashMap(i32, i32).init(std.testing.allocator, std.testing.allocator, std.testing.allocator);
    defer m.deinit();
    try m.ensureCapacity(1000);
    const reserved_cap = m.capacity;
    try std.testing.expect(reserved_cap >= 1000);
    for (0..1000) |i| {
        _ = try m.put(@intCast(i), @intCast(i * 2));
    }
    // Capacity must be unchanged — reservation was sufficient.
    try std.testing.expectEqual(reserved_cap, m.capacity);
    try std.testing.expectEqual(@as(usize, 1000), m.len());
    for (0..1000) |i| {
        try std.testing.expectEqual(@as(?i32, @intCast(i * 2)), m.get(@intCast(i)));
    }
}

test "map: ensureCapacity is idempotent when capacity already sufficient" {
    var m = try OpenHashMap(i32, i32).init(std.testing.allocator, std.testing.allocator, std.testing.allocator);
    defer m.deinit();
    const initial_cap = m.capacity;
    try m.ensureCapacity(1);
    try std.testing.expectEqual(initial_cap, m.capacity);
}

test "map: ensureCapacity propagates allocator errors" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const result = OpenHashMap(i32, i32).initCapacity(failing.allocator(), 16);
    try std.testing.expectError(error.OutOfMemory, result);
}

test "map: ensureCapacity on populated map preserves entries" {
    var m = try OpenHashMap(i32, i32).init(std.testing.allocator, std.testing.allocator, std.testing.allocator);
    defer m.deinit();
    for (0..10) |i| {
        _ = try m.put(@intCast(i), @intCast(i));
    }
    try m.ensureCapacity(500);
    try std.testing.expect(m.capacity >= 500);
    try std.testing.expectEqual(@as(usize, 10), m.len());
    for (0..10) |i| {
        try std.testing.expectEqual(@as(?i32, @intCast(i)), m.get(@intCast(i)));
    }
}

test "set: ensureCapacity grows and subsequent adds do not resize" {
    var s = try OpenHashSet(i32).init(std.testing.allocator, std.testing.allocator);
    defer s.deinit();
    try s.ensureCapacity(500);
    const reserved_cap = s.capacity;
    try std.testing.expect(reserved_cap >= 500);
    for (0..500) |i| {
        _ = try s.add(@intCast(i));
    }
    try std.testing.expectEqual(reserved_cap, s.capacity);
    try std.testing.expectEqual(@as(usize, 500), s.len());
}

test "set: ensureCapacity propagates allocator errors" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const result = OpenHashSet(i32).initCapacity(failing.allocator(), 16);
    try std.testing.expectError(error.OutOfMemory, result);
}
