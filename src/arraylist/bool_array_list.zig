// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;

/// Resizable array-backed list of `bool` values.
///
/// Specialized for `bool` — no boxing, contiguous memory layout.
/// Supports both simple single-allocator and advanced multi-allocator construction.
pub const BoolArrayList = struct {
    items: std.ArrayListUnmanaged(bool) = .empty,
    config: AllocatorConfig,

    /// Create with a single allocator for all internal structures.
    pub fn init(allocator: Allocator) BoolArrayList {
        return .{ .config = AllocatorConfig.init(allocator) };
    }

    /// Create with an AllocatorConfig for fine-grained allocator control.
    pub fn initWithConfig(config: AllocatorConfig) BoolArrayList {
        return .{ .config = config };
    }

    /// Release all allocated memory.
    pub fn deinit(self: *BoolArrayList) void {
        self.items.deinit(self.config.itemsAllocator());
    }

    /// Create a list from a slice of values.
    pub fn of(allocator: Allocator, values: []const bool) BoolArrayList {
        var list = init(allocator);
        list.items.appendSlice(list.config.itemsAllocator(), values) catch @panic("out of memory");
        return list;
    }

    /// Appends a value to the end of the list.
    pub fn push(self: *BoolArrayList, value: bool) void {
        self.items.append(self.config.itemsAllocator(), value) catch @panic("out of memory");
    }

    /// Appends all values from a slice.
    pub fn pushAll(self: *BoolArrayList, values: []const bool) void {
        self.items.appendSlice(self.config.itemsAllocator(), values) catch @panic("out of memory");
    }

    /// Returns the element at the given index, or null if out of bounds.
    pub fn get(self: *const BoolArrayList, index: usize) ?bool {
        if (index >= self.items.items.len) return null;
        return self.items.items[index];
    }

    /// Sets the element at the given index. Returns the old value.
    pub fn set(self: *BoolArrayList, index: usize, value: bool) bool {
        const old = self.items.items[index];
        self.items.items[index] = value;
        return old;
    }

    /// Removes and returns the element at the given index.
    pub fn removeAtIndex(self: *BoolArrayList, index: usize) bool {
        return self.items.orderedRemove(index);
    }

    /// Removes the first occurrence of the value. Returns true if found.
    pub fn remove(self: *BoolArrayList, value: bool) bool {
        if (self.indexOf(value)) |idx| {
            _ = self.items.orderedRemove(idx);
            return true;
        }
        return false;
    }

    /// Returns true if the list contains the given value.
    pub fn contains(self: *const BoolArrayList, value: bool) bool {
        for (self.items.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    /// Returns the index of the first occurrence, or null if not found.
    pub fn indexOf(self: *const BoolArrayList, value: bool) ?usize {
        for (self.items.items, 0..) |item, i| {
            if (item == value) return i;
        }
        return null;
    }

    /// Returns the number of elements.
    pub fn len(self: *const BoolArrayList) usize {
        return self.items.items.len;
    }

    /// Alias for len() — matches Go/Java naming.
    pub fn size(self: *const BoolArrayList) usize {
        return self.len();
    }

    /// Returns true if the list is empty.
    pub fn isEmpty(self: *const BoolArrayList) bool {
        return self.items.items.len == 0;
    }

    /// Alias for push() — matches Go/Java Add naming.
    pub fn add(self: *BoolArrayList, value: bool) void {
        self.push(value);
    }

    /// Alias for pushAll() — matches Go/Java AddAll naming.
    pub fn addAll(self: *BoolArrayList, values: []const bool) void {
        self.pushAll(values);
    }

    /// Removes all elements.
    pub fn clear(self: *BoolArrayList) void {
        self.items.clearRetainingCapacity();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more items can be appended without a
    /// reallocation. Returns `error.OutOfMemory` if the allocator fails.
    /// Pair this with the infallible `push` / `with` methods to get an
    /// opt-in allocation-failure handling path.
    pub fn ensureUnusedCapacity(self: *BoolArrayList, additional: usize) Allocator.Error!void {
        return self.items.ensureUnusedCapacity(self.config.itemsAllocator(), additional);
    }

    /// Ensures the list's total capacity is at least `new_capacity`.
    /// Idempotent. Returns `error.OutOfMemory` if the allocator fails.
    pub fn ensureTotalCapacity(self: *BoolArrayList, new_capacity: usize) Allocator.Error!void {
        return self.items.ensureTotalCapacity(self.config.itemsAllocator(), new_capacity);
    }

    /// Returns a new list with only elements satisfying the predicate.
    pub fn select(self: *const BoolArrayList, predicate: *const fn (bool) bool) BoolArrayList {
        var result = init(self.config.base);
        for (self.items.items) |item| {
            if (predicate(item)) result.push(item);
        }
        return result;
    }

    /// Returns a new list with elements NOT satisfying the predicate.
    pub fn reject(self: *const BoolArrayList, predicate: *const fn (bool) bool) BoolArrayList {
        var result = init(self.config.base);
        for (self.items.items) |item| {
            if (!predicate(item)) result.push(item);
        }
        return result;
    }

    /// Returns the first element satisfying the predicate, or null.
    pub fn detect(self: *const BoolArrayList, predicate: *const fn (bool) bool) ?bool {
        for (self.items.items) |item| {
            if (predicate(item)) return item;
        }
        return null;
    }

    /// Returns true if any element satisfies the predicate.
    pub fn anySatisfy(self: *const BoolArrayList, predicate: *const fn (bool) bool) bool {
        for (self.items.items) |item| {
            if (predicate(item)) return true;
        }
        return false;
    }

    /// Returns true if all elements satisfy the predicate.
    pub fn allSatisfy(self: *const BoolArrayList, predicate: *const fn (bool) bool) bool {
        for (self.items.items) |item| {
            if (!predicate(item)) return false;
        }
        return true;
    }

    /// Returns true if no element satisfies the predicate.
    pub fn noneSatisfy(self: *const BoolArrayList, predicate: *const fn (bool) bool) bool {
        for (self.items.items) |item| {
            if (predicate(item)) return false;
        }
        return true;
    }

    /// Returns the count of elements satisfying the predicate.
    pub fn count(self: *const BoolArrayList, predicate: *const fn (bool) bool) usize {
        var c: usize = 0;
        for (self.items.items) |item| {
            if (predicate(item)) c += 1;
        }
        return c;
    }

    /// Returns the sum of all elements.
    pub fn sum(self: *const BoolArrayList) i64 {
        var total: i64 = 0;
        for (self.items.items) |item| {
            total += @as(i64, if (item) 1 else 0);
        }
        return total;
    }

    /// Returns the minimum element, or null if empty.
    pub fn min(self: *const BoolArrayList) ?bool {
        if (self.items.items.len == 0) return null;
        var result = self.items.items[0];
        for (self.items.items[1..]) |item| {
            if ((if (!item) true else false) and result) result = item;
        }
        return result;
    }

    /// Returns the maximum element, or null if empty.
    pub fn max(self: *const BoolArrayList) ?bool {
        if (self.items.items.len == 0) return null;
        var result = self.items.items[0];
        for (self.items.items[1..]) |item| {
            if ((if (item) true else false) and !result) result = item;
        }
        return result;
    }

    /// Sorts the list in ascending order.
    pub fn sort(self: *BoolArrayList) void {
        std.mem.sort(bool, self.items.items, {}, struct {
            pub fn f(_: void, a: bool, b: bool) bool {
                // false < true
                return !a and b;
            }
        }.f);
    }

    /// Returns a new list with elements in reverse order.
    pub fn reversed(self: *const BoolArrayList) BoolArrayList {
        var result = init(self.config.base);
        var i = self.items.items.len;
        while (i > 0) {
            i -= 1;
            result.push(self.items.items[i]);
        }
        return result;
    }

    /// Returns the elements as a slice.
    pub fn toSlice(self: *const BoolArrayList) []const bool {
        return self.items.items;
    }

    // ---- Iteration ----

    /// Calls f for each element.
    pub fn forEach(self: *const BoolArrayList, f: *const fn (bool) void) void {
        for (self.items.items) |item| f(item);
    }

    /// Calls f(index, value) for each element.
    pub fn forEachWithIndex(self: *const BoolArrayList, f: *const fn (usize, bool) void) void {
        for (self.items.items, 0..) |item, i| f(i, item);
    }

    // ---- Advanced Operations ----

    /// Fold/reduce over all elements.
    pub fn injectInto(self: *const BoolArrayList, initial: bool, f: *const fn (bool, bool) bool) bool {
        var acc = initial;
        for (self.items.items) |item| acc = f(acc, item);
        return acc;
    }

    /// Returns a new list with duplicate elements removed (preserving first occurrence order).
    pub fn distinct(self: *const BoolArrayList) BoolArrayList {
        var result = init(self.config.base);
        for (self.items.items) |item| {
            if (!result.contains(item)) result.push(item);
        }
        return result;
    }

    /// Binary search on a sorted list. Returns the index if found, null otherwise.
    pub fn binarySearch(self: *const BoolArrayList, value: bool) ?usize {
        var lo: usize = 0;
        var hi: usize = self.items.items.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const ord = if (self.items.items[mid] == value) std.math.Order.eq else if (!self.items.items[mid] and value) std.math.Order.lt else std.math.Order.gt;
            if (ord == .lt) {
                lo = mid + 1;
            } else if (ord == .gt) {
                hi = mid;
            } else {
                return mid;
            }
        }
        return null;
    }

    // ---- Conversion ----

    /// Creates an immutable snapshot of this list.
    pub fn toImmutable(self: *const BoolArrayList) @import("../immutable/immutable_bool_array_list.zig").ImmutableBoolArrayList {
        return @import("../immutable/immutable_bool_array_list.zig").ImmutableBoolArrayList.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    /// Appends a value (fluent).
    pub fn with(self: *BoolArrayList, value: bool) *BoolArrayList {
        self.push(value);
        return self;
    }

    /// Removes the first occurrence (fluent).
    pub fn without(self: *BoolArrayList, value: bool) *BoolArrayList {
        _ = self.remove(value);
        return self;
    }

    /// Appends all values (fluent).
    pub fn withAll(self: *BoolArrayList, values: []const bool) *BoolArrayList {
        self.pushAll(values);
        return self;
    }

    /// Removes all occurrences of each value (fluent).
    pub fn withoutAll(self: *BoolArrayList, values: []const bool) *BoolArrayList {
        for (values) |val| _ = self.remove(val);
        return self;
    }

    // ---- Equality ----

    /// Formats the list as "[v1, v2, v3]".
    pub fn format(self: *const BoolArrayList, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll("[");
        for (self.items.items, 0..) |item, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{any}", .{item});
        }
        try writer.writeAll("]");
    }

    /// Returns true if two lists have equal elements in the same order.
    pub fn eql(self: *const BoolArrayList, other: *const BoolArrayList) bool {
        if (self.items.items.len != other.items.items.len) return false;
        for (self.items.items, other.items.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }
};

test "BoolArrayList: push and get" {
    var l = BoolArrayList.init(std.testing.allocator);
    defer l.deinit();
    l.push(true);
    l.push(false);
    l.push(true);
    try std.testing.expectEqual(@as(usize, 3), l.len());
    try std.testing.expectEqual(@as(?bool, true), l.get(0));
    try std.testing.expectEqual(@as(?bool, true), l.get(2));
    try std.testing.expectEqual(@as(?bool, null), l.get(99));
}

test "BoolArrayList: of" {
    var l = BoolArrayList.of(std.testing.allocator, &[_]bool{ true, false, true });
    defer l.deinit();
    try std.testing.expectEqual(@as(usize, 3), l.len());
}

test "BoolArrayList: set" {
    var l = BoolArrayList.of(std.testing.allocator, &[_]bool{ true, false });
    defer l.deinit();
    const old = l.set(0, true);
    try std.testing.expectEqual(true, old);
    try std.testing.expectEqual(@as(?bool, true), l.get(0));
}

test "BoolArrayList: removeAtIndex" {
    var l = BoolArrayList.of(std.testing.allocator, &[_]bool{ true, false, true });
    defer l.deinit();
    const removed = l.removeAtIndex(1);
    try std.testing.expectEqual(false, removed);
    try std.testing.expectEqual(@as(usize, 2), l.len());
}

test "BoolArrayList: remove" {
    var l = BoolArrayList.of(std.testing.allocator, &[_]bool{ true, false, true });
    defer l.deinit();
    try std.testing.expect(l.remove(false));
    try std.testing.expect(!l.contains(false));
    try std.testing.expect(!l.remove(false));
}

test "BoolArrayList: contains" {
    var l = BoolArrayList.of(std.testing.allocator, &[_]bool{ true, false });
    defer l.deinit();
    try std.testing.expect(l.contains(true));
}

test "BoolArrayList: isEmpty and clear" {
    var l = BoolArrayList.init(std.testing.allocator);
    defer l.deinit();
    try std.testing.expect(l.isEmpty());
    l.push(true);
    try std.testing.expect(!l.isEmpty());
    l.clear();
    try std.testing.expect(l.isEmpty());
}

test "BoolArrayList: min max" {
    var l = BoolArrayList.of(std.testing.allocator, &[_]bool{ true, false });
    defer l.deinit();
    try std.testing.expectEqual(@as(?bool, false), l.min());
    try std.testing.expectEqual(@as(?bool, true), l.max());
}

test "BoolArrayList: sort" {
    var l = BoolArrayList.of(std.testing.allocator, &[_]bool{ true, false, true });
    defer l.deinit();
    l.sort();
    try std.testing.expectEqual(@as(?bool, false), l.get(0));
}

test "BoolArrayList: reversed" {
    var l = BoolArrayList.of(std.testing.allocator, &[_]bool{ true, false, true });
    defer l.deinit();
    var r = l.reversed();
    defer r.deinit();
    try std.testing.expectEqual(@as(?bool, true), r.get(0));
    try std.testing.expectEqual(@as(?bool, true), r.get(2));
}

test "BoolArrayList: eql" {
    var l1 = BoolArrayList.of(std.testing.allocator, &[_]bool{ true, false });
    defer l1.deinit();
    var l2 = BoolArrayList.of(std.testing.allocator, &[_]bool{ true, false });
    defer l2.deinit();
    var l3 = BoolArrayList.of(std.testing.allocator, &[_]bool{true});
    defer l3.deinit();
    try std.testing.expect(l1.eql(&l2));
    try std.testing.expect(!l1.eql(&l3));
}

test "BoolArrayList: resize" {
    var l = BoolArrayList.init(std.testing.allocator);
    defer l.deinit();
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        l.push(i % 2 == 0);
    }
    try std.testing.expectEqual(@as(usize, 100), l.len());
}

test "BoolArrayList: distinct" {
    var l = BoolArrayList.of(std.testing.allocator, &[_]bool{ true, false, true });
    defer l.deinit();
    var d = l.distinct();
    defer d.deinit();
    try std.testing.expectEqual(@as(usize, 2), d.len());
}

test "BoolArrayList: toImmutable" {
    var l = BoolArrayList.of(std.testing.allocator, &[_]bool{ true, false });
    defer l.deinit();
    var il = l.toImmutable();
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 2), il.len());
    l.push(true);
    try std.testing.expectEqual(@as(usize, 2), il.len());
}

test "BoolArrayList: fluent with/without" {
    var l = BoolArrayList.init(std.testing.allocator);
    defer l.deinit();
    _ = l.with(true).with(false).with(true);
    try std.testing.expectEqual(@as(usize, 3), l.len());
    _ = l.without(false);
    try std.testing.expectEqual(@as(usize, 2), l.len());
}

test "BoolArrayList: ensureUnusedCapacity reserves and subsequent push does not reallocate" {
    var l = BoolArrayList.init(std.testing.allocator);
    defer l.deinit();
    try l.ensureUnusedCapacity(10);
    const reserved = l.items.capacity;
    try std.testing.expect(reserved >= 10);
    l.push(true);
    l.push(false);
    l.push(true);
    // Reserved capacity must not have grown — the three puts fit inside it.
    try std.testing.expectEqual(reserved, l.items.capacity);
}

test "BoolArrayList: ensureTotalCapacity sets minimum capacity" {
    var l = BoolArrayList.init(std.testing.allocator);
    defer l.deinit();
    try l.ensureTotalCapacity(100);
    try std.testing.expect(l.items.capacity >= 100);
}

test "BoolArrayList: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: ArrayList.init doesn't allocate, so the very first
    // alloc (the grow triggered by ensureUnusedCapacity) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var l = BoolArrayList.initWithConfig(AllocatorConfig.init(failing.allocator()));
    defer l.deinit();
    try std.testing.expectError(error.OutOfMemory, l.ensureUnusedCapacity(1024));
}
