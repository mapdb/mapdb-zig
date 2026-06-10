// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;

/// Bag (multiset) of `f32` values with occurrence counting.
///
/// Backed by OpenHashMap(f32, usize).
pub const F32HashBag = struct {
    counts: OpenHashMap(f32, usize),
    size: usize,
    config: AllocatorConfig,

    pub fn init(allocator: Allocator) F32HashBag {
        return initWithConfig(AllocatorConfig.init(allocator));
    }

    pub fn initWithConfig(config: AllocatorConfig) F32HashBag {
        return .{
            .counts = OpenHashMap(f32, usize).init(config.keysAllocator(), config.indexAllocator(), config.keysAllocator()) catch @panic("out of memory"),
            .size = 0,
            .config = config,
        };
    }

    pub fn deinit(self: *F32HashBag) void {
        self.counts.deinit();
    }

    pub fn of(allocator: Allocator, values: []const f32) F32HashBag {
        var bag = init(allocator);
        for (values) |val| {
            bag.add(val);
        }
        return bag;
    }

    /// Add one occurrence of the value.
    pub fn add(self: *F32HashBag, value: f32) void {
        if (self.counts.getPtr(value)) |count_ptr| {
            count_ptr.* += 1;
        } else {
            _ = self.counts.put(value, 1) catch @panic("out of memory");
        }
        self.size += 1;
    }

    /// Remove one occurrence. Returns true if the value was present.
    pub fn remove(self: *F32HashBag, value: f32) bool {
        if (self.counts.getPtr(value)) |count_ptr| {
            count_ptr.* -= 1;
            if (count_ptr.* == 0) {
                _ = self.counts.remove(value);
            }
            self.size -= 1;
            return true;
        }
        return false;
    }

    /// Remove all occurrences of the value. Returns true if present.
    pub fn removeAll(self: *F32HashBag, value: f32) bool {
        if (self.counts.getPtr(value)) |count_ptr| {
            self.size -= count_ptr.*;
            _ = self.counts.remove(value);
            return true;
        }
        return false;
    }

    /// Returns the number of occurrences of the value.
    pub fn occurrencesOf(self: *const F32HashBag, value: f32) usize {
        return self.counts.get(value) orelse 0;
    }

    pub fn contains(self: *const F32HashBag, value: f32) bool {
        return self.occurrencesOf(value) > 0;
    }

    /// Total number of elements (counting duplicates).
    pub fn totalSize(self: *const F32HashBag) usize {
        return self.size;
    }

    /// Number of distinct values.
    pub fn sizeDistinct(self: *const F32HashBag) usize {
        return self.counts.len();
    }

    pub fn isEmpty(self: *const F32HashBag) bool {
        return self.size == 0;
    }

    pub fn clear(self: *F32HashBag) void {
        self.counts.clear();
        self.size = 0;
    }

    // ---- Fallible capacity reservation ----

    /// Ensures the internal count-map can hold `additional` more distinct
    /// values without triggering a rehash. Returns `error.OutOfMemory` on
    /// allocator failure. Note that the count is bounded by distinct
    /// values, not total occurrences.
    pub fn ensureUnusedCapacity(self: *F32HashBag, additional: usize) Allocator.Error!void {
        return self.counts.ensureCapacity(additional);
    }

    /// Ensures the internal count-map's total capacity can fit at least
    /// `new_capacity` distinct values.
    pub fn ensureTotalCapacity(self: *F32HashBag, new_capacity: usize) Allocator.Error!void {
        const cur = self.counts.len();
        if (new_capacity <= cur) return;
        return self.counts.ensureCapacity(new_capacity - cur);
    }

    pub fn len(self: *const F32HashBag) usize {
        return self.size;
    }

    /// Add multiple occurrences of a value.
    pub fn addOccurrences(self: *F32HashBag, value: f32, n: usize) void {
        var i: usize = 0;
        while (i < n) : (i += 1) self.add(value);
    }

    /// Remove up to n occurrences. Returns number actually removed.
    pub fn removeOccurrences(self: *F32HashBag, value: f32, n: usize) usize {
        var removed: usize = 0;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            if (self.remove(value)) {
                removed += 1;
            } else break;
        }
        return removed;
    }

    // ---- Iteration ----

    /// Calls f(value, count) for each distinct value.
    pub fn forEachWithOccurrences(self: *const F32HashBag, f: *const fn (f32, usize) void) void {
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                f(self.counts.entries[i].key, self.counts.entries[i].value);
            }
        }
    }

    /// Calls f(value) for each element (including duplicates).
    pub fn forEach(self: *const F32HashBag, f: *const fn (f32) void) void {
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                var j: usize = 0;
                while (j < self.counts.entries[i].value) : (j += 1) f(self.counts.entries[i].key);
            }
        }
    }

    // ---- Functional Operations ----

    /// Returns a new bag with only elements satisfying the predicate (preserving counts).
    pub fn select(self: *const F32HashBag, predicate: *const fn (f32) bool) F32HashBag {
        var result = init(self.config.base);
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                if (predicate(self.counts.entries[i].key)) result.addOccurrences(self.counts.entries[i].key, self.counts.entries[i].value);
            }
        }
        return result;
    }

    /// Returns a new bag with elements NOT satisfying the predicate.
    pub fn reject(self: *const F32HashBag, predicate: *const fn (f32) bool) F32HashBag {
        var result = init(self.config.base);
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                if (!predicate(self.counts.entries[i].key)) result.addOccurrences(self.counts.entries[i].key, self.counts.entries[i].value);
            }
        }
        return result;
    }

    /// Returns the first distinct value satisfying the predicate, or null.
    pub fn detect(self: *const F32HashBag, predicate: *const fn (f32) bool) ?f32 {
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                if (predicate(self.counts.entries[i].key)) return self.counts.entries[i].key;
            }
        }
        return null;
    }

    pub fn anySatisfy(self: *const F32HashBag, predicate: *const fn (f32) bool) bool {
        return self.detect(predicate) != null;
    }

    pub fn allSatisfy(self: *const F32HashBag, predicate: *const fn (f32) bool) bool {
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                if (!predicate(self.counts.entries[i].key)) return false;
            }
        }
        return true;
    }

    pub fn noneSatisfy(self: *const F32HashBag, predicate: *const fn (f32) bool) bool {
        return self.detect(predicate) == null;
    }

    // ---- Conversion ----

    /// Returns all elements (with duplicates) as an allocated slice.
    pub fn toSlice(self: *const F32HashBag, allocator: Allocator) []f32 {
        var buf: std.ArrayListUnmanaged(f32) = .empty;
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                var j: usize = 0;
                while (j < self.counts.entries[i].value) : (j += 1) buf.append(allocator, self.counts.entries[i].key) catch @panic("out of memory");
            }
        }
        return buf.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    /// Creates an immutable snapshot of this bag.
    pub fn toImmutable(self: *const F32HashBag) @import("../immutable/immutable.zig").ImmutableF32HashBag {
        return @import("../immutable/immutable.zig").ImmutableF32HashBag.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    pub fn with(self: *F32HashBag, value: f32) *F32HashBag {
        self.add(value);
        return self;
    }

    pub fn without(self: *F32HashBag, value: f32) *F32HashBag {
        _ = self.remove(value);
        return self;
    }

    pub fn withAll(self: *F32HashBag, values: []const f32) *F32HashBag {
        for (values) |val| self.add(val);
        return self;
    }

    pub fn withoutAll(self: *F32HashBag, values: []const f32) *F32HashBag {
        for (values) |val| _ = self.removeAll(val);
        return self;
    }

    // ---- Advanced ----

    /// Returns the top n values by occurrence count as (value, count) pairs.
    /// Caller owns the returned slice.
    pub fn topOccurrences(self: *const F32HashBag, allocator: Allocator, n: usize) []struct { value: f32, count: usize } {
        const Entry = struct { value: f32, count: usize };
        var buf: std.ArrayListUnmanaged(Entry) = .empty;
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                buf.append(allocator, .{ .value = self.counts.entries[i].key, .count = self.counts.entries[i].value }) catch @panic("out of memory");
            }
        }
        // Sort by count descending
        std.mem.sort(Entry, buf.items, {}, struct {
            pub fn f(_: void, a: Entry, b: Entry) bool {
                return a.count > b.count;
            }
        }.f);
        const limit = @min(n, buf.items.len);
        const result = allocator.alloc(Entry, limit) catch @panic("out of memory");
        @memcpy(result, buf.items[0..limit]);
        buf.deinit(allocator);
        return result;
    }

    // ---- Formatting ----

    /// Formats as "{v1x2, v2x1}".
    pub fn format(self: *const F32HashBag, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll("{");
        var first = true;
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                if (!first) try writer.writeAll(", ");
                try writer.print("{any}", .{self.counts.entries[i].key});
                try writer.writeAll("x");
                try writer.print("{any}", .{self.counts.entries[i].value});
                first = false;
            }
        }
        try writer.writeAll("}");
    }

    // ---- Equality ----

    pub fn eql(self: *const F32HashBag, other: *const F32HashBag) bool {
        if (self.size != other.size) return false;
        if (self.counts.len() != other.counts.len()) return false;
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                if (other.occurrencesOf(self.counts.entries[i].key) != self.counts.entries[i].value) return false;
            }
        }
        return true;
    }
};

test "F32HashBag: add and occurrences" {
    var b = F32HashBag.init(std.testing.allocator);
    defer b.deinit();
    b.add(1.0);
    b.add(1.0);
    b.add(2.0);
    try std.testing.expectEqual(@as(usize, 2), b.occurrencesOf(1.0));
    try std.testing.expectEqual(@as(usize, 1), b.occurrencesOf(2.0));
    try std.testing.expectEqual(@as(usize, 3), b.totalSize());
    try std.testing.expectEqual(@as(usize, 2), b.sizeDistinct());
}

test "F32HashBag: remove" {
    var b = F32HashBag.of(std.testing.allocator, &[_]f32{ 1.0, 1.0, 1.0 });
    defer b.deinit();
    try std.testing.expect(b.remove(1.0));
    try std.testing.expectEqual(@as(usize, 2), b.occurrencesOf(1.0));
}

test "F32HashBag: removeAll" {
    var b = F32HashBag.of(std.testing.allocator, &[_]f32{ 1.0, 1.0, 2.0 });
    defer b.deinit();
    try std.testing.expect(b.removeAll(1.0));
    try std.testing.expect(!b.contains(1.0));
    try std.testing.expectEqual(@as(usize, 1), b.totalSize());
}

test "F32HashBag: clear" {
    var b = F32HashBag.of(std.testing.allocator, &[_]f32{1.0});
    defer b.deinit();
    b.clear();
    try std.testing.expect(b.isEmpty());
}

test "F32HashBag: addOccurrences" {
    var b = F32HashBag.init(std.testing.allocator);
    defer b.deinit();
    b.addOccurrences(1.0, 5);
    try std.testing.expectEqual(@as(usize, 5), b.occurrencesOf(1.0));
    try std.testing.expectEqual(@as(usize, 5), b.totalSize());
}

test "F32HashBag: select and reject" {
    var b = F32HashBag.of(std.testing.allocator, &[_]f32{ 1.0, 2.0, 3.0 });
    defer b.deinit();
    var sel = b.select(struct {
        fn f(val: f32) bool {
            return val > 1.0;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expectEqual(@as(usize, 2), sel.totalSize());
}

test "F32HashBag: toSlice" {
    var b = F32HashBag.of(std.testing.allocator, &[_]f32{ 1.0, 1.0, 2.0 });
    defer b.deinit();
    const slice = b.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqual(@as(usize, 3), slice.len);
}

test "F32HashBag: toImmutable" {
    var b = F32HashBag.of(std.testing.allocator, &[_]f32{ 1.0, 1.0 });
    defer b.deinit();
    var ib = b.toImmutable();
    defer ib.deinit();
    try std.testing.expectEqual(@as(usize, 2), ib.totalSize());
    b.add(2.0);
    try std.testing.expectEqual(@as(usize, 2), ib.totalSize());
}

test "F32HashBag: fluent with/without" {
    var b = F32HashBag.init(std.testing.allocator);
    defer b.deinit();
    _ = b.with(1.0).with(1.0).with(2.0);
    try std.testing.expectEqual(@as(usize, 3), b.totalSize());
    _ = b.without(1.0);
    try std.testing.expectEqual(@as(usize, 2), b.totalSize());
}

test "F32HashBag: eql" {
    var b1 = F32HashBag.of(std.testing.allocator, &[_]f32{ 1.0, 1.0, 2.0 });
    defer b1.deinit();
    var b2 = F32HashBag.of(std.testing.allocator, &[_]f32{ 2.0, 1.0, 1.0 });
    defer b2.deinit();
    try std.testing.expect(b1.eql(&b2));
}

test "F32HashBag: ensureUnusedCapacity reserves the count map" {
    var b = F32HashBag.init(std.testing.allocator);
    defer b.deinit();
    try b.ensureUnusedCapacity(500);
    const reserved = b.counts.capacity;
    try std.testing.expect(reserved >= 500);
    b.add(1.0);
    b.add(2.0);
    try std.testing.expectEqual(reserved, b.counts.capacity);
}

test "F32HashBag: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 1: Bag.init allocates the backing hash table (1st alloc),
    // then ensureUnusedCapacity triggers a grow that fails (2nd alloc).
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var b = F32HashBag.init(failing.allocator());
    defer b.deinit();
    try std.testing.expectError(error.OutOfMemory, b.ensureUnusedCapacity(10_000));
}
