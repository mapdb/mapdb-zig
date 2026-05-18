// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;

/// Bag (multiset) of `u21` values with occurrence counting.
///
/// Backed by OpenHashMap(u21, usize).
pub const CharHashBag = struct {
    counts: OpenHashMap(u21, usize),
    size: usize,
    config: AllocatorConfig,

    pub fn init(allocator: Allocator) CharHashBag {
        return initWithConfig(AllocatorConfig.init(allocator));
    }

    pub fn initWithConfig(config: AllocatorConfig) CharHashBag {
        return .{
            .counts = OpenHashMap(u21, usize).init(config.keysAllocator(), config.indexAllocator(), config.keysAllocator()) catch @panic("out of memory"),
            .size = 0,
            .config = config,
        };
    }

    pub fn deinit(self: *CharHashBag) void {
        self.counts.deinit();
    }

    pub fn of(allocator: Allocator, values: []const u21) CharHashBag {
        var bag = init(allocator);
        for (values) |val| {
            bag.add(val);
        }
        return bag;
    }

    /// Add one occurrence of the value.
    pub fn add(self: *CharHashBag, value: u21) void {
        if (self.counts.getPtr(value)) |count_ptr| {
            count_ptr.* += 1;
        } else {
            _ = self.counts.put(value, 1) catch @panic("out of memory");
        }
        self.size += 1;
    }

    /// Remove one occurrence. Returns true if the value was present.
    pub fn remove(self: *CharHashBag, value: u21) bool {
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
    pub fn removeAll(self: *CharHashBag, value: u21) bool {
        if (self.counts.getPtr(value)) |count_ptr| {
            self.size -= count_ptr.*;
            _ = self.counts.remove(value);
            return true;
        }
        return false;
    }

    /// Returns the number of occurrences of the value.
    pub fn occurrencesOf(self: *const CharHashBag, value: u21) usize {
        return self.counts.get(value) orelse 0;
    }

    pub fn contains(self: *const CharHashBag, value: u21) bool {
        return self.occurrencesOf(value) > 0;
    }

    /// Total number of elements (counting duplicates).
    pub fn totalSize(self: *const CharHashBag) usize {
        return self.size;
    }

    /// Number of distinct values.
    pub fn sizeDistinct(self: *const CharHashBag) usize {
        return self.counts.len();
    }

    pub fn isEmpty(self: *const CharHashBag) bool {
        return self.size == 0;
    }

    pub fn clear(self: *CharHashBag) void {
        self.counts.clear();
        self.size = 0;
    }

    // ---- Fallible capacity reservation ----

    /// Ensures the internal count-map can hold `additional` more distinct
    /// values without triggering a rehash. Returns `error.OutOfMemory` on
    /// allocator failure. Note that the count is bounded by distinct
    /// values, not total occurrences.
    pub fn ensureUnusedCapacity(self: *CharHashBag, additional: usize) Allocator.Error!void {
        return self.counts.ensureCapacity(additional);
    }

    /// Ensures the internal count-map's total capacity can fit at least
    /// `new_capacity` distinct values.
    pub fn ensureTotalCapacity(self: *CharHashBag, new_capacity: usize) Allocator.Error!void {
        const cur = self.counts.len();
        if (new_capacity <= cur) return;
        return self.counts.ensureCapacity(new_capacity - cur);
    }

    pub fn len(self: *const CharHashBag) usize {
        return self.size;
    }

    /// Add multiple occurrences of a value.
    pub fn addOccurrences(self: *CharHashBag, value: u21, n: usize) void {
        var i: usize = 0;
        while (i < n) : (i += 1) self.add(value);
    }

    /// Remove up to n occurrences. Returns number actually removed.
    pub fn removeOccurrences(self: *CharHashBag, value: u21, n: usize) usize {
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
    pub fn forEachWithOccurrences(self: *const CharHashBag, f: *const fn (u21, usize) void) void {
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                f(self.counts.entries[i].key, self.counts.entries[i].value);
            }
        }
    }

    /// Calls f(value) for each element (including duplicates).
    pub fn forEach(self: *const CharHashBag, f: *const fn (u21) void) void {
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                var j: usize = 0;
                while (j < self.counts.entries[i].value) : (j += 1) f(self.counts.entries[i].key);
            }
        }
    }

    // ---- Functional Operations ----

    /// Returns a new bag with only elements satisfying the predicate (preserving counts).
    pub fn select(self: *const CharHashBag, predicate: *const fn (u21) bool) CharHashBag {
        var result = init(self.config.base);
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                if (predicate(self.counts.entries[i].key)) result.addOccurrences(self.counts.entries[i].key, self.counts.entries[i].value);
            }
        }
        return result;
    }

    /// Returns a new bag with elements NOT satisfying the predicate.
    pub fn reject(self: *const CharHashBag, predicate: *const fn (u21) bool) CharHashBag {
        var result = init(self.config.base);
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                if (!predicate(self.counts.entries[i].key)) result.addOccurrences(self.counts.entries[i].key, self.counts.entries[i].value);
            }
        }
        return result;
    }

    /// Returns the first distinct value satisfying the predicate, or null.
    pub fn detect(self: *const CharHashBag, predicate: *const fn (u21) bool) ?u21 {
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                if (predicate(self.counts.entries[i].key)) return self.counts.entries[i].key;
            }
        }
        return null;
    }

    pub fn anySatisfy(self: *const CharHashBag, predicate: *const fn (u21) bool) bool {
        return self.detect(predicate) != null;
    }

    pub fn allSatisfy(self: *const CharHashBag, predicate: *const fn (u21) bool) bool {
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                if (!predicate(self.counts.entries[i].key)) return false;
            }
        }
        return true;
    }

    pub fn noneSatisfy(self: *const CharHashBag, predicate: *const fn (u21) bool) bool {
        return self.detect(predicate) == null;
    }

    // ---- Conversion ----

    /// Returns all elements (with duplicates) as an allocated slice.
    pub fn toSlice(self: *const CharHashBag, allocator: Allocator) []u21 {
        var buf: std.ArrayListUnmanaged(u21) = .empty;
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                var j: usize = 0;
                while (j < self.counts.entries[i].value) : (j += 1) buf.append(allocator, self.counts.entries[i].key) catch @panic("out of memory");
            }
        }
        return buf.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    /// Creates an immutable snapshot of this bag.
    pub fn toImmutable(self: *const CharHashBag) @import("../immutable/immutable_char_hash_bag.zig").ImmutableCharHashBag {
        return @import("../immutable/immutable_char_hash_bag.zig").ImmutableCharHashBag.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    pub fn with(self: *CharHashBag, value: u21) *CharHashBag {
        self.add(value);
        return self;
    }

    pub fn without(self: *CharHashBag, value: u21) *CharHashBag {
        _ = self.remove(value);
        return self;
    }

    pub fn withAll(self: *CharHashBag, values: []const u21) *CharHashBag {
        for (values) |val| self.add(val);
        return self;
    }

    pub fn withoutAll(self: *CharHashBag, values: []const u21) *CharHashBag {
        for (values) |val| _ = self.removeAll(val);
        return self;
    }

    // ---- Advanced ----

    /// Returns the top n values by occurrence count as (value, count) pairs.
    /// Caller owns the returned slice.
    pub fn topOccurrences(self: *const CharHashBag, allocator: Allocator, n: usize) []struct { value: u21, count: usize } {
        const Entry = struct { value: u21, count: usize };
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
    pub fn format(self: *const CharHashBag, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const CharHashBag, other: *const CharHashBag) bool {
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

test "CharHashBag: add and occurrences" {
    var b = CharHashBag.init(std.testing.allocator);
    defer b.deinit();
    b.add('a');
    b.add('a');
    b.add('b');
    try std.testing.expectEqual(@as(usize, 2), b.occurrencesOf('a'));
    try std.testing.expectEqual(@as(usize, 1), b.occurrencesOf('b'));
    try std.testing.expectEqual(@as(usize, 3), b.totalSize());
    try std.testing.expectEqual(@as(usize, 2), b.sizeDistinct());
}

test "CharHashBag: remove" {
    var b = CharHashBag.of(std.testing.allocator, &[_]u21{ 'a', 'a', 'a' });
    defer b.deinit();
    try std.testing.expect(b.remove('a'));
    try std.testing.expectEqual(@as(usize, 2), b.occurrencesOf('a'));
}

test "CharHashBag: removeAll" {
    var b = CharHashBag.of(std.testing.allocator, &[_]u21{ 'a', 'a', 'b' });
    defer b.deinit();
    try std.testing.expect(b.removeAll('a'));
    try std.testing.expect(!b.contains('a'));
    try std.testing.expectEqual(@as(usize, 1), b.totalSize());
}

test "CharHashBag: clear" {
    var b = CharHashBag.of(std.testing.allocator, &[_]u21{'a'});
    defer b.deinit();
    b.clear();
    try std.testing.expect(b.isEmpty());
}

test "CharHashBag: addOccurrences" {
    var b = CharHashBag.init(std.testing.allocator);
    defer b.deinit();
    b.addOccurrences('a', 5);
    try std.testing.expectEqual(@as(usize, 5), b.occurrencesOf('a'));
    try std.testing.expectEqual(@as(usize, 5), b.totalSize());
}

test "CharHashBag: select and reject" {
    var b = CharHashBag.of(std.testing.allocator, &[_]u21{ 'a', 'b', 'c' });
    defer b.deinit();
    var sel = b.select(struct {
        fn f(val: u21) bool {
            return val > 'a';
        }
    }.f);
    defer sel.deinit();
    try std.testing.expectEqual(@as(usize, 2), sel.totalSize());
}

test "CharHashBag: toSlice" {
    var b = CharHashBag.of(std.testing.allocator, &[_]u21{ 'a', 'a', 'b' });
    defer b.deinit();
    const slice = b.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqual(@as(usize, 3), slice.len);
}

test "CharHashBag: toImmutable" {
    var b = CharHashBag.of(std.testing.allocator, &[_]u21{ 'a', 'a' });
    defer b.deinit();
    var ib = b.toImmutable();
    defer ib.deinit();
    try std.testing.expectEqual(@as(usize, 2), ib.totalSize());
    b.add('b');
    try std.testing.expectEqual(@as(usize, 2), ib.totalSize());
}

test "CharHashBag: fluent with/without" {
    var b = CharHashBag.init(std.testing.allocator);
    defer b.deinit();
    _ = b.with('a').with('a').with('b');
    try std.testing.expectEqual(@as(usize, 3), b.totalSize());
    _ = b.without('a');
    try std.testing.expectEqual(@as(usize, 2), b.totalSize());
}

test "CharHashBag: eql" {
    var b1 = CharHashBag.of(std.testing.allocator, &[_]u21{ 'a', 'a', 'b' });
    defer b1.deinit();
    var b2 = CharHashBag.of(std.testing.allocator, &[_]u21{ 'b', 'a', 'a' });
    defer b2.deinit();
    try std.testing.expect(b1.eql(&b2));
}

test "CharHashBag: ensureUnusedCapacity reserves the count map" {
    var b = CharHashBag.init(std.testing.allocator);
    defer b.deinit();
    try b.ensureUnusedCapacity(500);
    const reserved = b.counts.capacity;
    try std.testing.expect(reserved >= 500);
    b.add('a');
    b.add('b');
    try std.testing.expectEqual(reserved, b.counts.capacity);
}

test "CharHashBag: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 1: Bag.init allocates the backing hash table (1st alloc),
    // then ensureUnusedCapacity triggers a grow that fails (2nd alloc).
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var b = CharHashBag.init(failing.allocator());
    defer b.deinit();
    try std.testing.expectError(error.OutOfMemory, b.ensureUnusedCapacity(10_000));
}
