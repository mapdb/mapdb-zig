// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;
const float_order = @import("../float_order.zig");

/// Resizable array-backed list of `f32` values.
///
/// Specialized for `f32` — no boxing, contiguous memory layout.
/// Supports both simple single-allocator and advanced multi-allocator construction.
pub const F32ArrayList = struct {
    items: std.ArrayListUnmanaged(f32) = .empty,
    config: AllocatorConfig,

    /// Create with a single allocator for all internal structures.
    pub fn init(allocator: Allocator) F32ArrayList {
        return .{ .config = AllocatorConfig.init(allocator) };
    }

    /// Create with an AllocatorConfig for fine-grained allocator control.
    pub fn initWithConfig(config: AllocatorConfig) F32ArrayList {
        return .{ .config = config };
    }

    /// Release all allocated memory.
    pub fn deinit(self: *F32ArrayList) void {
        self.items.deinit(self.config.itemsAllocator());
    }

    /// Create a list from a slice of values.
    pub fn of(allocator: Allocator, values: []const f32) F32ArrayList {
        var list = init(allocator);
        list.items.appendSlice(list.config.itemsAllocator(), values) catch @panic("out of memory");
        return list;
    }

    /// Appends a value to the end of the list.
    pub fn push(self: *F32ArrayList, value: f32) void {
        self.items.append(self.config.itemsAllocator(), value) catch @panic("out of memory");
    }

    /// Appends all values from a slice.
    pub fn pushAll(self: *F32ArrayList, values: []const f32) void {
        self.items.appendSlice(self.config.itemsAllocator(), values) catch @panic("out of memory");
    }

    /// Returns the element at the given index, or null if out of bounds.
    pub fn get(self: *const F32ArrayList, index: usize) ?f32 {
        if (index >= self.items.items.len) return null;
        return self.items.items[index];
    }

    /// Sets the element at the given index. Returns the old value.
    pub fn set(self: *F32ArrayList, index: usize, value: f32) f32 {
        const old = self.items.items[index];
        self.items.items[index] = value;
        return old;
    }

    /// Removes and returns the element at the given index.
    pub fn removeAtIndex(self: *F32ArrayList, index: usize) f32 {
        return self.items.orderedRemove(index);
    }

    /// Removes the first occurrence of the value. Returns true if found.
    pub fn remove(self: *F32ArrayList, value: f32) bool {
        if (self.indexOf(value)) |idx| {
            _ = self.items.orderedRemove(idx);
            return true;
        }
        return false;
    }

    /// Returns true if the list contains the given value.
    pub fn contains(self: *const F32ArrayList, value: f32) bool {
        for (self.items.items) |item| {
            if (@as(u32, @bitCast(item)) == @as(u32, @bitCast(value))) return true;
        }
        return false;
    }

    /// Returns the index of the first occurrence, or null if not found.
    pub fn indexOf(self: *const F32ArrayList, value: f32) ?usize {
        for (self.items.items, 0..) |item, i| {
            if (@as(u32, @bitCast(item)) == @as(u32, @bitCast(value))) return i;
        }
        return null;
    }

    /// Returns the number of elements.
    pub fn len(self: *const F32ArrayList) usize {
        return self.items.items.len;
    }

    /// Alias for len() — matches Go/Java naming.
    pub fn size(self: *const F32ArrayList) usize {
        return self.len();
    }

    /// Returns true if the list is empty.
    pub fn isEmpty(self: *const F32ArrayList) bool {
        return self.items.items.len == 0;
    }

    /// Alias for push() — matches Go/Java Add naming.
    pub fn add(self: *F32ArrayList, value: f32) void {
        self.push(value);
    }

    /// Alias for pushAll() — matches Go/Java AddAll naming.
    pub fn addAll(self: *F32ArrayList, values: []const f32) void {
        self.pushAll(values);
    }

    /// Removes all elements.
    pub fn clear(self: *F32ArrayList) void {
        self.items.clearRetainingCapacity();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more items can be appended without a
    /// reallocation. Returns `error.OutOfMemory` if the allocator fails.
    /// Pair this with the infallible `push` / `with` methods to get an
    /// opt-in allocation-failure handling path.
    pub fn ensureUnusedCapacity(self: *F32ArrayList, additional: usize) Allocator.Error!void {
        return self.items.ensureUnusedCapacity(self.config.itemsAllocator(), additional);
    }

    /// Ensures the list's total capacity is at least `new_capacity`.
    /// Idempotent. Returns `error.OutOfMemory` if the allocator fails.
    pub fn ensureTotalCapacity(self: *F32ArrayList, new_capacity: usize) Allocator.Error!void {
        return self.items.ensureTotalCapacity(self.config.itemsAllocator(), new_capacity);
    }

    /// Returns a new list with only elements satisfying the predicate.
    pub fn select(self: *const F32ArrayList, predicate: *const fn (f32) bool) F32ArrayList {
        var result = init(self.config.base);
        for (self.items.items) |item| {
            if (predicate(item)) result.push(item);
        }
        return result;
    }

    /// Returns a new list with elements NOT satisfying the predicate.
    pub fn reject(self: *const F32ArrayList, predicate: *const fn (f32) bool) F32ArrayList {
        var result = init(self.config.base);
        for (self.items.items) |item| {
            if (!predicate(item)) result.push(item);
        }
        return result;
    }

    /// Returns the first element satisfying the predicate, or null.
    pub fn detect(self: *const F32ArrayList, predicate: *const fn (f32) bool) ?f32 {
        for (self.items.items) |item| {
            if (predicate(item)) return item;
        }
        return null;
    }

    /// Returns true if any element satisfies the predicate.
    pub fn anySatisfy(self: *const F32ArrayList, predicate: *const fn (f32) bool) bool {
        for (self.items.items) |item| {
            if (predicate(item)) return true;
        }
        return false;
    }

    /// Returns true if all elements satisfy the predicate.
    pub fn allSatisfy(self: *const F32ArrayList, predicate: *const fn (f32) bool) bool {
        for (self.items.items) |item| {
            if (!predicate(item)) return false;
        }
        return true;
    }

    /// Returns true if no element satisfies the predicate.
    pub fn noneSatisfy(self: *const F32ArrayList, predicate: *const fn (f32) bool) bool {
        for (self.items.items) |item| {
            if (predicate(item)) return false;
        }
        return true;
    }

    /// Returns the count of elements satisfying the predicate.
    pub fn count(self: *const F32ArrayList, predicate: *const fn (f32) bool) usize {
        var c: usize = 0;
        for (self.items.items) |item| {
            if (predicate(item)) c += 1;
        }
        return c;
    }

    /// Returns the sum of all elements.
    pub fn sum(self: *const F32ArrayList) f32 {
        var total: f32 = 0;
        for (self.items.items) |item| {
            total += item;
        }
        return total;
    }

    /// Returns the minimum element, or null if empty.
    pub fn min(self: *const F32ArrayList) ?f32 {
        if (self.items.items.len == 0) return null;
        var result = self.items.items[0];
        for (self.items.items[1..]) |item| {
            if (float_order.totalCmpF32(item, result) == .lt) result = item;
        }
        return result;
    }

    /// Returns the maximum element, or null if empty.
    pub fn max(self: *const F32ArrayList) ?f32 {
        if (self.items.items.len == 0) return null;
        var result = self.items.items[0];
        for (self.items.items[1..]) |item| {
            if (float_order.totalCmpF32(item, result) == .gt) result = item;
        }
        return result;
    }

    /// Sorts the list in ascending order.
    pub fn sort(self: *F32ArrayList) void {
        std.mem.sort(f32, self.items.items, {}, struct {
            pub fn f(_: void, a: f32, b: f32) bool {
                return float_order.totalCmpF32(a, b) == .lt;
            }
        }.f);
    }

    /// Returns a new list with elements in reverse order.
    pub fn reversed(self: *const F32ArrayList) F32ArrayList {
        var result = init(self.config.base);
        var i = self.items.items.len;
        while (i > 0) {
            i -= 1;
            result.push(self.items.items[i]);
        }
        return result;
    }

    /// Returns the elements as a slice.
    pub fn toSlice(self: *const F32ArrayList) []const f32 {
        return self.items.items;
    }

    // ---- Iteration ----

    /// Calls f for each element.
    pub fn forEach(self: *const F32ArrayList, f: *const fn (f32) void) void {
        for (self.items.items) |item| f(item);
    }

    /// Calls f(index, value) for each element.
    pub fn forEachWithIndex(self: *const F32ArrayList, f: *const fn (usize, f32) void) void {
        for (self.items.items, 0..) |item, i| f(i, item);
    }

    // ---- Advanced Operations ----

    /// Fold/reduce over all elements.
    pub fn injectInto(self: *const F32ArrayList, initial: f32, f: *const fn (f32, f32) f32) f32 {
        var acc = initial;
        for (self.items.items) |item| acc = f(acc, item);
        return acc;
    }

    /// Returns a new list with duplicate elements removed (preserving first occurrence order).
    pub fn distinct(self: *const F32ArrayList) F32ArrayList {
        var result = init(self.config.base);
        for (self.items.items) |item| {
            if (!result.contains(item)) result.push(item);
        }
        return result;
    }

    /// Binary search on a sorted list. Returns the index if found, null otherwise.
    pub fn binarySearch(self: *const F32ArrayList, value: f32) ?usize {
        var lo: usize = 0;
        var hi: usize = self.items.items.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const ord = float_order.totalCmpF32(self.items.items[mid], value);
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
    pub fn toImmutable(self: *const F32ArrayList) @import("../immutable/immutable.zig").ImmutableF32ArrayList {
        return @import("../immutable/immutable.zig").ImmutableF32ArrayList.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    /// Appends a value (fluent).
    pub fn with(self: *F32ArrayList, value: f32) *F32ArrayList {
        self.push(value);
        return self;
    }

    /// Removes the first occurrence (fluent).
    pub fn without(self: *F32ArrayList, value: f32) *F32ArrayList {
        _ = self.remove(value);
        return self;
    }

    /// Appends all values (fluent).
    pub fn withAll(self: *F32ArrayList, values: []const f32) *F32ArrayList {
        self.pushAll(values);
        return self;
    }

    /// Removes all occurrences of each value (fluent).
    pub fn withoutAll(self: *F32ArrayList, values: []const f32) *F32ArrayList {
        for (values) |val| _ = self.remove(val);
        return self;
    }

    // ---- Equality ----

    /// Formats the list as "[v1, v2, v3]".
    pub fn format(self: *const F32ArrayList, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll("[");
        for (self.items.items, 0..) |item, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{any}", .{item});
        }
        try writer.writeAll("]");
    }

    /// Returns true if two lists have equal elements in the same order.
    pub fn eql(self: *const F32ArrayList, other: *const F32ArrayList) bool {
        if (self.items.items.len != other.items.items.len) return false;
        for (self.items.items, other.items.items) |a, b| {
            if (!(@as(u32, @bitCast(a)) == @as(u32, @bitCast(b)))) return false;
        }
        return true;
    }
};

test "F32ArrayList: push and get" {
    var l = F32ArrayList.init(std.testing.allocator);
    defer l.deinit();
    l.push(1.0);
    l.push(2.0);
    l.push(3.0);
    try std.testing.expectEqual(@as(usize, 3), l.len());
    try std.testing.expectEqual(@as(?f32, 1.0), l.get(0));
    try std.testing.expectEqual(@as(?f32, 3.0), l.get(2));
    try std.testing.expectEqual(@as(?f32, null), l.get(99));
}

test "F32ArrayList: of" {
    var l = F32ArrayList.of(std.testing.allocator, &[_]f32{ 1.0, 2.0, 3.0 });
    defer l.deinit();
    try std.testing.expectEqual(@as(usize, 3), l.len());
}

test "F32ArrayList: set" {
    var l = F32ArrayList.of(std.testing.allocator, &[_]f32{ 1.0, 2.0 });
    defer l.deinit();
    const old = l.set(0, 3.0);
    try std.testing.expectEqual(1.0, old);
    try std.testing.expectEqual(@as(?f32, 3.0), l.get(0));
}

test "F32ArrayList: removeAtIndex" {
    var l = F32ArrayList.of(std.testing.allocator, &[_]f32{ 1.0, 2.0, 3.0 });
    defer l.deinit();
    const removed = l.removeAtIndex(1);
    try std.testing.expectEqual(2.0, removed);
    try std.testing.expectEqual(@as(usize, 2), l.len());
}

test "F32ArrayList: remove" {
    var l = F32ArrayList.of(std.testing.allocator, &[_]f32{ 1.0, 2.0, 3.0 });
    defer l.deinit();
    try std.testing.expect(l.remove(2.0));
    try std.testing.expect(!l.contains(2.0));
    try std.testing.expect(!l.remove(99.0));
}

test "F32ArrayList: contains" {
    var l = F32ArrayList.of(std.testing.allocator, &[_]f32{ 1.0, 2.0 });
    defer l.deinit();
    try std.testing.expect(l.contains(1.0));
    try std.testing.expect(!l.contains(99.0));
}

test "F32ArrayList: isEmpty and clear" {
    var l = F32ArrayList.init(std.testing.allocator);
    defer l.deinit();
    try std.testing.expect(l.isEmpty());
    l.push(1.0);
    try std.testing.expect(!l.isEmpty());
    l.clear();
    try std.testing.expect(l.isEmpty());
}

test "F32ArrayList: sum min max" {
    var l = F32ArrayList.of(std.testing.allocator, &[_]f32{ 3.0, 1.0, 2.0 });
    defer l.deinit();
    try std.testing.expectEqual(@as(?f32, 1.0), l.min());
    try std.testing.expectEqual(@as(?f32, 3.0), l.max());
}

test "F32ArrayList: sort" {
    var l = F32ArrayList.of(std.testing.allocator, &[_]f32{ 3.0, 1.0, 2.0 });
    defer l.deinit();
    l.sort();
    try std.testing.expectEqual(@as(?f32, 1.0), l.get(0));
    try std.testing.expectEqual(@as(?f32, 2.0), l.get(1));
    try std.testing.expectEqual(@as(?f32, 3.0), l.get(2));
}

test "F32ArrayList: reversed" {
    var l = F32ArrayList.of(std.testing.allocator, &[_]f32{ 1.0, 2.0, 3.0 });
    defer l.deinit();
    var r = l.reversed();
    defer r.deinit();
    try std.testing.expectEqual(@as(?f32, 3.0), r.get(0));
    try std.testing.expectEqual(@as(?f32, 1.0), r.get(2));
}

test "F32ArrayList: eql" {
    var l1 = F32ArrayList.of(std.testing.allocator, &[_]f32{ 1.0, 2.0 });
    defer l1.deinit();
    var l2 = F32ArrayList.of(std.testing.allocator, &[_]f32{ 1.0, 2.0 });
    defer l2.deinit();
    var l3 = F32ArrayList.of(std.testing.allocator, &[_]f32{1.0});
    defer l3.deinit();
    try std.testing.expect(l1.eql(&l2));
    try std.testing.expect(!l1.eql(&l3));
}

test "F32ArrayList: resize" {
    var l = F32ArrayList.init(std.testing.allocator);
    defer l.deinit();
    var i: i32 = 0;
    while (i < 100) : (i += 1) {
        l.push(@as(f32, @floatFromInt(i)));
    }
    try std.testing.expectEqual(@as(usize, 100), l.len());
}

test "F32ArrayList: distinct" {
    var l = F32ArrayList.of(std.testing.allocator, &[_]f32{ 1.0, 2.0, 1.0, 3.0, 2.0 });
    defer l.deinit();
    var d = l.distinct();
    defer d.deinit();
    try std.testing.expectEqual(@as(usize, 3), d.len());
}

test "F32ArrayList: binarySearch" {
    var l = F32ArrayList.of(std.testing.allocator, &[_]f32{ 1.0, 2.0, 3.0 });
    defer l.deinit();
    l.sort();
    try std.testing.expect(l.binarySearch(2.0) != null);
    try std.testing.expectEqual(@as(?usize, null), l.binarySearch(99.0));
}

test "F32ArrayList: toImmutable" {
    var l = F32ArrayList.of(std.testing.allocator, &[_]f32{ 1.0, 2.0 });
    defer l.deinit();
    var il = l.toImmutable();
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 2), il.len());
    l.push(3.0);
    try std.testing.expectEqual(@as(usize, 2), il.len());
}

test "F32ArrayList: fluent with/without" {
    var l = F32ArrayList.init(std.testing.allocator);
    defer l.deinit();
    _ = l.with(1.0).with(2.0).with(3.0);
    try std.testing.expectEqual(@as(usize, 3), l.len());
    _ = l.without(2.0);
    try std.testing.expectEqual(@as(usize, 2), l.len());
}

test "F32ArrayList: ensureUnusedCapacity reserves and subsequent push does not reallocate" {
    var l = F32ArrayList.init(std.testing.allocator);
    defer l.deinit();
    try l.ensureUnusedCapacity(10);
    const reserved = l.items.capacity;
    try std.testing.expect(reserved >= 10);
    l.push(1.0);
    l.push(2.0);
    l.push(3.0);
    // Reserved capacity must not have grown — the three puts fit inside it.
    try std.testing.expectEqual(reserved, l.items.capacity);
}

test "F32ArrayList: ensureTotalCapacity sets minimum capacity" {
    var l = F32ArrayList.init(std.testing.allocator);
    defer l.deinit();
    try l.ensureTotalCapacity(100);
    try std.testing.expect(l.items.capacity >= 100);
}

test "F32ArrayList: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: ArrayList.init doesn't allocate, so the very first
    // alloc (the grow triggered by ensureUnusedCapacity) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var l = F32ArrayList.initWithConfig(AllocatorConfig.init(failing.allocator()));
    defer l.deinit();
    try std.testing.expectError(error.OutOfMemory, l.ensureUnusedCapacity(1024));
}
