// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;

/// Bag (multiset) of `i16` values with occurrence counting.
///
/// Backed by OpenHashMap(i16, usize).
pub const I16HashBag = struct {
    counts: OpenHashMap(i16, usize),
    size: usize,
    config: AllocatorConfig,

    pub fn init(allocator: Allocator) I16HashBag {
        return initWithConfig(AllocatorConfig.init(allocator));
    }

    pub fn initWithConfig(config: AllocatorConfig) I16HashBag {
        return .{
            .counts = OpenHashMap(i16, usize).init(config.keysAllocator(), config.indexAllocator(), config.keysAllocator()) catch @panic("out of memory"),
            .size = 0,
            .config = config,
        };
    }

    pub fn deinit(self: *I16HashBag) void {
        self.counts.deinit();
    }

    pub fn of(allocator: Allocator, values: []const i16) I16HashBag {
        var bag = init(allocator);
        for (values) |val| {
            bag.add(val);
        }
        return bag;
    }

    /// Add one occurrence of the value.
    pub fn add(self: *I16HashBag, value: i16) void {
        if (self.counts.getPtr(value)) |count_ptr| {
            count_ptr.* += 1;
        } else {
            _ = self.counts.put(value, 1) catch @panic("out of memory");
        }
        self.size += 1;
    }

    /// Remove one occurrence. Returns true if the value was present.
    pub fn remove(self: *I16HashBag, value: i16) bool {
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
    pub fn removeAll(self: *I16HashBag, value: i16) bool {
        if (self.counts.getPtr(value)) |count_ptr| {
            self.size -= count_ptr.*;
            _ = self.counts.remove(value);
            return true;
        }
        return false;
    }

    /// Returns the number of occurrences of the value.
    pub fn occurrencesOf(self: *const I16HashBag, value: i16) usize {
        return self.counts.get(value) orelse 0;
    }

    pub fn contains(self: *const I16HashBag, value: i16) bool {
        return self.occurrencesOf(value) > 0;
    }

    /// Total number of elements (counting duplicates).
    pub fn totalSize(self: *const I16HashBag) usize {
        return self.size;
    }

    /// Number of distinct values.
    pub fn sizeDistinct(self: *const I16HashBag) usize {
        return self.counts.len();
    }

    pub fn isEmpty(self: *const I16HashBag) bool {
        return self.size == 0;
    }

    pub fn clear(self: *I16HashBag) void {
        self.counts.clear();
        self.size = 0;
    }

    // ---- Fallible capacity reservation ----

    /// Ensures the internal count-map can hold `additional` more distinct
    /// values without triggering a rehash. Returns `error.OutOfMemory` on
    /// allocator failure. Note that the count is bounded by distinct
    /// values, not total occurrences.
    pub fn ensureUnusedCapacity(self: *I16HashBag, additional: usize) Allocator.Error!void {
        return self.counts.ensureCapacity(additional);
    }

    /// Ensures the internal count-map's total capacity can fit at least
    /// `new_capacity` distinct values.
    pub fn ensureTotalCapacity(self: *I16HashBag, new_capacity: usize) Allocator.Error!void {
        const cur = self.counts.len();
        if (new_capacity <= cur) return;
        return self.counts.ensureCapacity(new_capacity - cur);
    }

    pub fn len(self: *const I16HashBag) usize {
        return self.size;
    }

    /// Add multiple occurrences of a value.
    pub fn addOccurrences(self: *I16HashBag, value: i16, n: usize) void {
        var i: usize = 0;
        while (i < n) : (i += 1) self.add(value);
    }

    /// Remove up to n occurrences. Returns number actually removed.
    pub fn removeOccurrences(self: *I16HashBag, value: i16, n: usize) usize {
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
    pub fn forEachWithOccurrences(self: *const I16HashBag, f: *const fn (i16, usize) void) void {
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                f(self.counts.entries[i].key, self.counts.entries[i].value);
            }
        }
    }

    /// Calls f(value) for each element (including duplicates).
    pub fn forEach(self: *const I16HashBag, f: *const fn (i16) void) void {
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                var j: usize = 0;
                while (j < self.counts.entries[i].value) : (j += 1) f(self.counts.entries[i].key);
            }
        }
    }

    // ---- Functional Operations ----

    /// Returns a new bag with only elements satisfying the predicate (preserving counts).
    pub fn select(self: *const I16HashBag, predicate: *const fn (i16) bool) I16HashBag {
        var result = init(self.config.base);
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                if (predicate(self.counts.entries[i].key)) result.addOccurrences(self.counts.entries[i].key, self.counts.entries[i].value);
            }
        }
        return result;
    }

    /// Returns a new bag with elements NOT satisfying the predicate.
    pub fn reject(self: *const I16HashBag, predicate: *const fn (i16) bool) I16HashBag {
        var result = init(self.config.base);
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                if (!predicate(self.counts.entries[i].key)) result.addOccurrences(self.counts.entries[i].key, self.counts.entries[i].value);
            }
        }
        return result;
    }

    /// Returns the first distinct value satisfying the predicate, or null.
    pub fn detect(self: *const I16HashBag, predicate: *const fn (i16) bool) ?i16 {
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                if (predicate(self.counts.entries[i].key)) return self.counts.entries[i].key;
            }
        }
        return null;
    }

    pub fn anySatisfy(self: *const I16HashBag, predicate: *const fn (i16) bool) bool {
        return self.detect(predicate) != null;
    }

    pub fn allSatisfy(self: *const I16HashBag, predicate: *const fn (i16) bool) bool {
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                if (!predicate(self.counts.entries[i].key)) return false;
            }
        }
        return true;
    }

    pub fn noneSatisfy(self: *const I16HashBag, predicate: *const fn (i16) bool) bool {
        return self.detect(predicate) == null;
    }

    // ---- Conversion ----

    /// Returns all elements (with duplicates) as an allocated slice.
    pub fn toSlice(self: *const I16HashBag, allocator: Allocator) []i16 {
        var buf: std.ArrayListUnmanaged(i16) = .empty;
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                var j: usize = 0;
                while (j < self.counts.entries[i].value) : (j += 1) buf.append(allocator, self.counts.entries[i].key) catch @panic("out of memory");
            }
        }
        return buf.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    /// Creates an immutable snapshot of this bag.
    pub fn toImmutable(self: *const I16HashBag) @import("../immutable/immutable.zig").ImmutableI16HashBag {
        return @import("../immutable/immutable.zig").ImmutableI16HashBag.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    pub fn with(self: *I16HashBag, value: i16) *I16HashBag {
        self.add(value);
        return self;
    }

    pub fn without(self: *I16HashBag, value: i16) *I16HashBag {
        _ = self.remove(value);
        return self;
    }

    pub fn withAll(self: *I16HashBag, values: []const i16) *I16HashBag {
        for (values) |val| self.add(val);
        return self;
    }

    pub fn withoutAll(self: *I16HashBag, values: []const i16) *I16HashBag {
        for (values) |val| _ = self.removeAll(val);
        return self;
    }

    // ---- Advanced ----

    /// Returns the top n values by occurrence count as (value, count) pairs.
    /// Caller owns the returned slice.
    pub fn topOccurrences(self: *const I16HashBag, allocator: Allocator, n: usize) []struct { value: i16, count: usize } {
        const Entry = struct { value: i16, count: usize };
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
    pub fn format(self: *const I16HashBag, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

    pub fn eql(self: *const I16HashBag, other: *const I16HashBag) bool {
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

test "I16HashBag: add and occurrences" {
    var b = I16HashBag.init(std.testing.allocator);
    defer b.deinit();
    b.add(1);
    b.add(1);
    b.add(2);
    try std.testing.expectEqual(@as(usize, 2), b.occurrencesOf(1));
    try std.testing.expectEqual(@as(usize, 1), b.occurrencesOf(2));
    try std.testing.expectEqual(@as(usize, 3), b.totalSize());
    try std.testing.expectEqual(@as(usize, 2), b.sizeDistinct());
}

test "I16HashBag: remove" {
    var b = I16HashBag.of(std.testing.allocator, &[_]i16{ 1, 1, 1 });
    defer b.deinit();
    try std.testing.expect(b.remove(1));
    try std.testing.expectEqual(@as(usize, 2), b.occurrencesOf(1));
}

test "I16HashBag: removeAll" {
    var b = I16HashBag.of(std.testing.allocator, &[_]i16{ 1, 1, 2 });
    defer b.deinit();
    try std.testing.expect(b.removeAll(1));
    try std.testing.expect(!b.contains(1));
    try std.testing.expectEqual(@as(usize, 1), b.totalSize());
}

test "I16HashBag: clear" {
    var b = I16HashBag.of(std.testing.allocator, &[_]i16{1});
    defer b.deinit();
    b.clear();
    try std.testing.expect(b.isEmpty());
}

test "I16HashBag: addOccurrences" {
    var b = I16HashBag.init(std.testing.allocator);
    defer b.deinit();
    b.addOccurrences(1, 5);
    try std.testing.expectEqual(@as(usize, 5), b.occurrencesOf(1));
    try std.testing.expectEqual(@as(usize, 5), b.totalSize());
}

test "I16HashBag: select and reject" {
    var b = I16HashBag.of(std.testing.allocator, &[_]i16{ 1, 2, 3 });
    defer b.deinit();
    var sel = b.select(struct {
        fn f(val: i16) bool {
            return val > 1;
        }
    }.f);
    defer sel.deinit();
    try std.testing.expectEqual(@as(usize, 2), sel.totalSize());
}

test "I16HashBag: toSlice" {
    var b = I16HashBag.of(std.testing.allocator, &[_]i16{ 1, 1, 2 });
    defer b.deinit();
    const slice = b.toSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);
    try std.testing.expectEqual(@as(usize, 3), slice.len);
}

test "I16HashBag: toImmutable" {
    var b = I16HashBag.of(std.testing.allocator, &[_]i16{ 1, 1 });
    defer b.deinit();
    var ib = b.toImmutable();
    defer ib.deinit();
    try std.testing.expectEqual(@as(usize, 2), ib.totalSize());
    b.add(2);
    try std.testing.expectEqual(@as(usize, 2), ib.totalSize());
}

test "I16HashBag: fluent with/without" {
    var b = I16HashBag.init(std.testing.allocator);
    defer b.deinit();
    _ = b.with(1).with(1).with(2);
    try std.testing.expectEqual(@as(usize, 3), b.totalSize());
    _ = b.without(1);
    try std.testing.expectEqual(@as(usize, 2), b.totalSize());
}

test "I16HashBag: eql" {
    var b1 = I16HashBag.of(std.testing.allocator, &[_]i16{ 1, 1, 2 });
    defer b1.deinit();
    var b2 = I16HashBag.of(std.testing.allocator, &[_]i16{ 2, 1, 1 });
    defer b2.deinit();
    try std.testing.expect(b1.eql(&b2));
}

test "I16HashBag: ensureUnusedCapacity reserves the count map" {
    var b = I16HashBag.init(std.testing.allocator);
    defer b.deinit();
    try b.ensureUnusedCapacity(500);
    const reserved = b.counts.capacity;
    try std.testing.expect(reserved >= 500);
    b.add(1);
    b.add(2);
    try std.testing.expectEqual(reserved, b.counts.capacity);
}

test "I16HashBag: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 1: Bag.init allocates the backing hash table (1st alloc),
    // then ensureUnusedCapacity triggers a grow that fails (2nd alloc).
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var b = I16HashBag.init(failing.allocator());
    defer b.deinit();
    try std.testing.expectError(error.OutOfMemory, b.ensureUnusedCapacity(10_000));
}
