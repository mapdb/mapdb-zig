
const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;

/// Resizable array-backed list of `i16` values.
///
/// Specialized for `i16` — no boxing, contiguous memory layout.
/// Supports both simple single-allocator and advanced multi-allocator construction.
pub const I16ArrayList = struct {
    items: std.ArrayListUnmanaged(i16) = .empty,
    config: AllocatorConfig,

    /// Create with a single allocator for all internal structures.
    pub fn init(allocator: Allocator) I16ArrayList {
        return .{ .config = AllocatorConfig.init(allocator) };
    }

    /// Create with an AllocatorConfig for fine-grained allocator control.
    pub fn initWithConfig(config: AllocatorConfig) I16ArrayList {
        return .{ .config = config };
    }

    /// Release all allocated memory.
    pub fn deinit(self: *I16ArrayList) void {
        self.items.deinit(self.config.itemsAllocator());
    }

    /// Create a list from a slice of values.
    pub fn of(allocator: Allocator, values: []const i16) I16ArrayList {
        var list = init(allocator);
        list.items.appendSlice(list.config.itemsAllocator(), values) catch @panic("out of memory");
        return list;
    }

    /// Appends a value to the end of the list.
    pub fn push(self: *I16ArrayList, value: i16) void {
        self.items.append(self.config.itemsAllocator(), value) catch @panic("out of memory");
    }

    /// Appends all values from a slice.
    pub fn pushAll(self: *I16ArrayList, values: []const i16) void {
        self.items.appendSlice(self.config.itemsAllocator(), values) catch @panic("out of memory");
    }

    /// Returns the element at the given index, or null if out of bounds.
    pub fn get(self: *const I16ArrayList, index: usize) ?i16 {
        if (index >= self.items.items.len) return null;
        return self.items.items[index];
    }

    /// Sets the element at the given index. Returns the old value.
    pub fn set(self: *I16ArrayList, index: usize, value: i16) i16 {
        const old = self.items.items[index];
        self.items.items[index] = value;
        return old;
    }

    /// Removes and returns the element at the given index.
    pub fn removeAtIndex(self: *I16ArrayList, index: usize) i16 {
        return self.items.orderedRemove(index);
    }

    /// Removes the first occurrence of the value. Returns true if found.
    pub fn remove(self: *I16ArrayList, value: i16) bool {
        if (self.indexOf(value)) |idx| {
            _ = self.items.orderedRemove(idx);
            return true;
        }
        return false;
    }

    /// Returns true if the list contains the given value.
    pub fn contains(self: *const I16ArrayList, value: i16) bool {
        for (self.items.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    /// Returns the index of the first occurrence, or null if not found.
    pub fn indexOf(self: *const I16ArrayList, value: i16) ?usize {
        for (self.items.items, 0..) |item, i| {
            if (item == value) return i;
        }
        return null;
    }

    /// Returns the number of elements.
    pub fn len(self: *const I16ArrayList) usize {
        return self.items.items.len;
    }

    /// Alias for len() — matches Go/Java naming.
    pub fn size(self: *const I16ArrayList) usize {
        return self.len();
    }

    /// Returns true if the list is empty.
    pub fn isEmpty(self: *const I16ArrayList) bool {
        return self.items.items.len == 0;
    }

    /// Alias for push() — matches Go/Java Add naming.
    pub fn add(self: *I16ArrayList, value: i16) void {
        self.push(value);
    }

    /// Alias for pushAll() — matches Go/Java AddAll naming.
    pub fn addAll(self: *I16ArrayList, values: []const i16) void {
        self.pushAll(values);
    }

    /// Removes all elements.
    pub fn clear(self: *I16ArrayList) void {
        self.items.clearRetainingCapacity();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more items can be appended without a
    /// reallocation. Returns `error.OutOfMemory` if the allocator fails.
    /// Pair this with the infallible `push` / `with` methods to get an
    /// opt-in allocation-failure handling path. See
    /// `docs/zig/error-handling.md`.
    pub fn ensureUnusedCapacity(self: *I16ArrayList, additional: usize) Allocator.Error!void {
        return self.items.ensureUnusedCapacity(self.config.itemsAllocator(), additional);
    }

    /// Ensures the list's total capacity is at least `new_capacity`.
    /// Idempotent. Returns `error.OutOfMemory` if the allocator fails.
    pub fn ensureTotalCapacity(self: *I16ArrayList, new_capacity: usize) Allocator.Error!void {
        return self.items.ensureTotalCapacity(self.config.itemsAllocator(), new_capacity);
    }

    /// Returns a new list with only elements satisfying the predicate.
    pub fn select(self: *const I16ArrayList, predicate: *const fn (i16) bool) I16ArrayList {
        var result = init(self.config.base);
        for (self.items.items) |item| {
            if (predicate(item)) result.push(item);
        }
        return result;
    }

    /// Returns a new list with elements NOT satisfying the predicate.
    pub fn reject(self: *const I16ArrayList, predicate: *const fn (i16) bool) I16ArrayList {
        var result = init(self.config.base);
        for (self.items.items) |item| {
            if (!predicate(item)) result.push(item);
        }
        return result;
    }

    /// Returns the first element satisfying the predicate, or null.
    pub fn detect(self: *const I16ArrayList, predicate: *const fn (i16) bool) ?i16 {
        for (self.items.items) |item| {
            if (predicate(item)) return item;
        }
        return null;
    }

    /// Returns true if any element satisfies the predicate.
    pub fn anySatisfy(self: *const I16ArrayList, predicate: *const fn (i16) bool) bool {
        for (self.items.items) |item| {
            if (predicate(item)) return true;
        }
        return false;
    }

    /// Returns true if all elements satisfy the predicate.
    pub fn allSatisfy(self: *const I16ArrayList, predicate: *const fn (i16) bool) bool {
        for (self.items.items) |item| {
            if (!predicate(item)) return false;
        }
        return true;
    }

    /// Returns true if no element satisfies the predicate.
    pub fn noneSatisfy(self: *const I16ArrayList, predicate: *const fn (i16) bool) bool {
        for (self.items.items) |item| {
            if (predicate(item)) return false;
        }
        return true;
    }

    /// Returns the count of elements satisfying the predicate.
    pub fn count(self: *const I16ArrayList, predicate: *const fn (i16) bool) usize {
        var c: usize = 0;
        for (self.items.items) |item| {
            if (predicate(item)) c += 1;
        }
        return c;
    }

    /// Returns the sum of all elements.
    pub fn sum(self: *const I16ArrayList) i64 {
        var total: i64 = 0;
        for (self.items.items) |item| {
            total += @as(i64, @intCast(item));
        }
        return total;
    }

    /// Returns the minimum element, or null if empty.
    pub fn min(self: *const I16ArrayList) ?i16 {
        if (self.items.items.len == 0) return null;
        var result = self.items.items[0];
        for (self.items.items[1..]) |item| {
            if (std.math.order(item, result) == .lt) result = item;
        }
        return result;
    }

    /// Returns the maximum element, or null if empty.
    pub fn max(self: *const I16ArrayList) ?i16 {
        if (self.items.items.len == 0) return null;
        var result = self.items.items[0];
        for (self.items.items[1..]) |item| {
            if (std.math.order(item, result) == .gt) result = item;
        }
        return result;
    }

    /// Sorts the list in ascending order.
    pub fn sort(self: *I16ArrayList) void {
        std.mem.sort(i16, self.items.items, {}, struct {
            pub fn f(_: void, a: i16, b: i16) bool {
                return std.math.order(a, b) == .lt;
            }
        }.f);
    }

    /// Returns a new list with elements in reverse order.
    pub fn reversed(self: *const I16ArrayList) I16ArrayList {
        var result = init(self.config.base);
        var i = self.items.items.len;
        while (i > 0) {
            i -= 1;
            result.push(self.items.items[i]);
        }
        return result;
    }

    /// Returns the elements as a slice.
    pub fn toSlice(self: *const I16ArrayList) []const i16 {
        return self.items.items;
    }

    // ---- Iteration ----

    /// Calls f for each element.
    pub fn forEach(self: *const I16ArrayList, f: *const fn (i16) void) void {
        for (self.items.items) |item| f(item);
    }

    /// Calls f(index, value) for each element.
    pub fn forEachWithIndex(self: *const I16ArrayList, f: *const fn (usize, i16) void) void {
        for (self.items.items, 0..) |item, i| f(i, item);
    }

    // ---- Advanced Operations ----

    /// Fold/reduce over all elements.
    pub fn injectInto(self: *const I16ArrayList, initial: i16, f: *const fn (i16, i16) i16) i16 {
        var acc = initial;
        for (self.items.items) |item| acc = f(acc, item);
        return acc;
    }

    /// Returns a new list with duplicate elements removed (preserving first occurrence order).
    pub fn distinct(self: *const I16ArrayList) I16ArrayList {
        var result = init(self.config.base);
        for (self.items.items) |item| {
            if (!result.contains(item)) result.push(item);
        }
        return result;
    }

    /// Binary search on a sorted list. Returns the index if found, null otherwise.
    pub fn binarySearch(self: *const I16ArrayList, value: i16) ?usize {
        var lo: usize = 0;
        var hi: usize = self.items.items.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const ord = std.math.order(self.items.items[mid], value);
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
    pub fn toImmutable(self: *const I16ArrayList) @import("../immutable/immutable_i16_array_list.zig").ImmutableI16ArrayList {
        return @import("../immutable/immutable_i16_array_list.zig").ImmutableI16ArrayList.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    /// Appends a value (fluent).
    pub fn with(self: *I16ArrayList, value: i16) *I16ArrayList {
        self.push(value);
        return self;
    }

    /// Removes the first occurrence (fluent).
    pub fn without(self: *I16ArrayList, value: i16) *I16ArrayList {
        _ = self.remove(value);
        return self;
    }

    /// Appends all values (fluent).
    pub fn withAll(self: *I16ArrayList, values: []const i16) *I16ArrayList {
        self.pushAll(values);
        return self;
    }

    /// Removes all occurrences of each value (fluent).
    pub fn withoutAll(self: *I16ArrayList, values: []const i16) *I16ArrayList {
        for (values) |val| _ = self.remove(val);
        return self;
    }

    // ---- Equality ----

    /// Formats the list as "[v1, v2, v3]".
    pub fn format(self: *const I16ArrayList, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll("[");
        for (self.items.items, 0..) |item, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{any}", .{item});
        }
        try writer.writeAll("]");
    }

    /// Returns true if two lists have equal elements in the same order.
    pub fn eql(self: *const I16ArrayList, other: *const I16ArrayList) bool {
        if (self.items.items.len != other.items.items.len) return false;
        for (self.items.items, other.items.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }
};

test "I16ArrayList: push and get" {
    var l = I16ArrayList.init(std.testing.allocator);
    defer l.deinit();
    l.push(1);
    l.push(2);
    l.push(3);
    try std.testing.expectEqual(@as(usize, 3), l.len());
    try std.testing.expectEqual(@as(?i16, 1), l.get(0));
    try std.testing.expectEqual(@as(?i16, 3), l.get(2));
    try std.testing.expectEqual(@as(?i16, null), l.get(99));
}

test "I16ArrayList: of" {
    var l = I16ArrayList.of(std.testing.allocator, &[_]i16{ 1, 2, 3 });
    defer l.deinit();
    try std.testing.expectEqual(@as(usize, 3), l.len());
}

test "I16ArrayList: set" {
    var l = I16ArrayList.of(std.testing.allocator, &[_]i16{ 1, 2 });
    defer l.deinit();
    const old = l.set(0, 3);
    try std.testing.expectEqual(1, old);
    try std.testing.expectEqual(@as(?i16, 3), l.get(0));
}

test "I16ArrayList: removeAtIndex" {
    var l = I16ArrayList.of(std.testing.allocator, &[_]i16{ 1, 2, 3 });
    defer l.deinit();
    const removed = l.removeAtIndex(1);
    try std.testing.expectEqual(2, removed);
    try std.testing.expectEqual(@as(usize, 2), l.len());
}

test "I16ArrayList: remove" {
    var l = I16ArrayList.of(std.testing.allocator, &[_]i16{ 1, 2, 3 });
    defer l.deinit();
    try std.testing.expect(l.remove(2));
    try std.testing.expect(!l.contains(2));
    try std.testing.expect(!l.remove(99));
}

test "I16ArrayList: contains" {
    var l = I16ArrayList.of(std.testing.allocator, &[_]i16{ 1, 2 });
    defer l.deinit();
    try std.testing.expect(l.contains(1));
    try std.testing.expect(!l.contains(99));
}

test "I16ArrayList: isEmpty and clear" {
    var l = I16ArrayList.init(std.testing.allocator);
    defer l.deinit();
    try std.testing.expect(l.isEmpty());
    l.push(1);
    try std.testing.expect(!l.isEmpty());
    l.clear();
    try std.testing.expect(l.isEmpty());
}

test "I16ArrayList: sum min max" {
    var l = I16ArrayList.of(std.testing.allocator, &[_]i16{ 3, 1, 2 });
    defer l.deinit();
    try std.testing.expectEqual(@as(?i16, 1), l.min());
    try std.testing.expectEqual(@as(?i16, 3), l.max());
}

test "I16ArrayList: sort" {
    var l = I16ArrayList.of(std.testing.allocator, &[_]i16{ 3, 1, 2 });
    defer l.deinit();
    l.sort();
    try std.testing.expectEqual(@as(?i16, 1), l.get(0));
    try std.testing.expectEqual(@as(?i16, 2), l.get(1));
    try std.testing.expectEqual(@as(?i16, 3), l.get(2));
}

test "I16ArrayList: reversed" {
    var l = I16ArrayList.of(std.testing.allocator, &[_]i16{ 1, 2, 3 });
    defer l.deinit();
    var r = l.reversed();
    defer r.deinit();
    try std.testing.expectEqual(@as(?i16, 3), r.get(0));
    try std.testing.expectEqual(@as(?i16, 1), r.get(2));
}

test "I16ArrayList: eql" {
    var l1 = I16ArrayList.of(std.testing.allocator, &[_]i16{ 1, 2 });
    defer l1.deinit();
    var l2 = I16ArrayList.of(std.testing.allocator, &[_]i16{ 1, 2 });
    defer l2.deinit();
    var l3 = I16ArrayList.of(std.testing.allocator, &[_]i16{1});
    defer l3.deinit();
    try std.testing.expect(l1.eql(&l2));
    try std.testing.expect(!l1.eql(&l3));
}

test "I16ArrayList: resize" {
    var l = I16ArrayList.init(std.testing.allocator);
    defer l.deinit();
    var i: i32 = 0;
    while (i < 100) : (i += 1) {
        l.push(@as(i16, @intCast(i)));
    }
    try std.testing.expectEqual(@as(usize, 100), l.len());
}

test "I16ArrayList: distinct" {
    var l = I16ArrayList.of(std.testing.allocator, &[_]i16{ 1, 2, 1, 3, 2 });
    defer l.deinit();
    var d = l.distinct();
    defer d.deinit();
    try std.testing.expectEqual(@as(usize, 3), d.len());
}

test "I16ArrayList: binarySearch" {
    var l = I16ArrayList.of(std.testing.allocator, &[_]i16{ 1, 2, 3 });
    defer l.deinit();
    l.sort();
    try std.testing.expect(l.binarySearch(2) != null);
    try std.testing.expectEqual(@as(?usize, null), l.binarySearch(99));
}

test "I16ArrayList: toImmutable" {
    var l = I16ArrayList.of(std.testing.allocator, &[_]i16{ 1, 2 });
    defer l.deinit();
    var il = l.toImmutable();
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 2), il.len());
    l.push(3);
    try std.testing.expectEqual(@as(usize, 2), il.len());
}

test "I16ArrayList: fluent with/without" {
    var l = I16ArrayList.init(std.testing.allocator);
    defer l.deinit();
    _ = l.with(1).with(2).with(3);
    try std.testing.expectEqual(@as(usize, 3), l.len());
    _ = l.without(2);
    try std.testing.expectEqual(@as(usize, 2), l.len());
}

test "I16ArrayList: ensureUnusedCapacity reserves and subsequent push does not reallocate" {
    var l = I16ArrayList.init(std.testing.allocator);
    defer l.deinit();
    try l.ensureUnusedCapacity(10);
    const reserved = l.items.capacity;
    try std.testing.expect(reserved >= 10);
    l.push(1);
    l.push(2);
    l.push(3);
    // Reserved capacity must not have grown — the three puts fit inside it.
    try std.testing.expectEqual(reserved, l.items.capacity);
}

test "I16ArrayList: ensureTotalCapacity sets minimum capacity" {
    var l = I16ArrayList.init(std.testing.allocator);
    defer l.deinit();
    try l.ensureTotalCapacity(100);
    try std.testing.expect(l.items.capacity >= 100);
}

test "I16ArrayList: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: ArrayList.init doesn't allocate, so the very first
    // alloc (the grow triggered by ensureUnusedCapacity) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var l = I16ArrayList.initWithConfig(AllocatorConfig.init(failing.allocator()));
    defer l.deinit();
    try std.testing.expectError(error.OutOfMemory, l.ensureUnusedCapacity(1024));
}
