
const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorConfig = @import("../allocator_config.zig").AllocatorConfig;

/// Resizable array-backed list of `u21` values.
///
/// Specialized for `u21` — no boxing, contiguous memory layout.
/// Supports both simple single-allocator and advanced multi-allocator construction.
pub const CharArrayList = struct {
    items: std.ArrayListUnmanaged(u21) = .empty,
    config: AllocatorConfig,

    /// Create with a single allocator for all internal structures.
    pub fn init(allocator: Allocator) CharArrayList {
        return .{ .config = AllocatorConfig.init(allocator) };
    }

    /// Create with an AllocatorConfig for fine-grained allocator control.
    pub fn initWithConfig(config: AllocatorConfig) CharArrayList {
        return .{ .config = config };
    }

    /// Release all allocated memory.
    pub fn deinit(self: *CharArrayList) void {
        self.items.deinit(self.config.itemsAllocator());
    }

    /// Create a list from a slice of values.
    pub fn of(allocator: Allocator, values: []const u21) CharArrayList {
        var list = init(allocator);
        list.items.appendSlice(list.config.itemsAllocator(), values) catch @panic("out of memory");
        return list;
    }

    /// Appends a value to the end of the list.
    pub fn push(self: *CharArrayList, value: u21) void {
        self.items.append(self.config.itemsAllocator(), value) catch @panic("out of memory");
    }

    /// Appends all values from a slice.
    pub fn pushAll(self: *CharArrayList, values: []const u21) void {
        self.items.appendSlice(self.config.itemsAllocator(), values) catch @panic("out of memory");
    }

    /// Returns the element at the given index, or null if out of bounds.
    pub fn get(self: *const CharArrayList, index: usize) ?u21 {
        if (index >= self.items.items.len) return null;
        return self.items.items[index];
    }

    /// Sets the element at the given index. Returns the old value.
    pub fn set(self: *CharArrayList, index: usize, value: u21) u21 {
        const old = self.items.items[index];
        self.items.items[index] = value;
        return old;
    }

    /// Removes and returns the element at the given index.
    pub fn removeAtIndex(self: *CharArrayList, index: usize) u21 {
        return self.items.orderedRemove(index);
    }

    /// Removes the first occurrence of the value. Returns true if found.
    pub fn remove(self: *CharArrayList, value: u21) bool {
        if (self.indexOf(value)) |idx| {
            _ = self.items.orderedRemove(idx);
            return true;
        }
        return false;
    }

    /// Returns true if the list contains the given value.
    pub fn contains(self: *const CharArrayList, value: u21) bool {
        for (self.items.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    /// Returns the index of the first occurrence, or null if not found.
    pub fn indexOf(self: *const CharArrayList, value: u21) ?usize {
        for (self.items.items, 0..) |item, i| {
            if (item == value) return i;
        }
        return null;
    }

    /// Returns the number of elements.
    pub fn len(self: *const CharArrayList) usize {
        return self.items.items.len;
    }

    /// Alias for len() — matches Go/Java naming.
    pub fn size(self: *const CharArrayList) usize {
        return self.len();
    }

    /// Returns true if the list is empty.
    pub fn isEmpty(self: *const CharArrayList) bool {
        return self.items.items.len == 0;
    }

    /// Alias for push() — matches Go/Java Add naming.
    pub fn add(self: *CharArrayList, value: u21) void {
        self.push(value);
    }

    /// Alias for pushAll() — matches Go/Java AddAll naming.
    pub fn addAll(self: *CharArrayList, values: []const u21) void {
        self.pushAll(values);
    }

    /// Removes all elements.
    pub fn clear(self: *CharArrayList) void {
        self.items.clearRetainingCapacity();
    }

    // ---- Fallible capacity reservation ----

    /// Ensures that `additional` more items can be appended without a
    /// reallocation. Returns `error.OutOfMemory` if the allocator fails.
    /// Pair this with the infallible `push` / `with` methods to get an
    /// opt-in allocation-failure handling path. See
    /// `docs/zig/error-handling.md`.
    pub fn ensureUnusedCapacity(self: *CharArrayList, additional: usize) Allocator.Error!void {
        return self.items.ensureUnusedCapacity(self.config.itemsAllocator(), additional);
    }

    /// Ensures the list's total capacity is at least `new_capacity`.
    /// Idempotent. Returns `error.OutOfMemory` if the allocator fails.
    pub fn ensureTotalCapacity(self: *CharArrayList, new_capacity: usize) Allocator.Error!void {
        return self.items.ensureTotalCapacity(self.config.itemsAllocator(), new_capacity);
    }

    /// Returns a new list with only elements satisfying the predicate.
    pub fn select(self: *const CharArrayList, predicate: *const fn (u21) bool) CharArrayList {
        var result = init(self.config.base);
        for (self.items.items) |item| {
            if (predicate(item)) result.push(item);
        }
        return result;
    }

    /// Returns a new list with elements NOT satisfying the predicate.
    pub fn reject(self: *const CharArrayList, predicate: *const fn (u21) bool) CharArrayList {
        var result = init(self.config.base);
        for (self.items.items) |item| {
            if (!predicate(item)) result.push(item);
        }
        return result;
    }

    /// Returns the first element satisfying the predicate, or null.
    pub fn detect(self: *const CharArrayList, predicate: *const fn (u21) bool) ?u21 {
        for (self.items.items) |item| {
            if (predicate(item)) return item;
        }
        return null;
    }

    /// Returns true if any element satisfies the predicate.
    pub fn anySatisfy(self: *const CharArrayList, predicate: *const fn (u21) bool) bool {
        for (self.items.items) |item| {
            if (predicate(item)) return true;
        }
        return false;
    }

    /// Returns true if all elements satisfy the predicate.
    pub fn allSatisfy(self: *const CharArrayList, predicate: *const fn (u21) bool) bool {
        for (self.items.items) |item| {
            if (!predicate(item)) return false;
        }
        return true;
    }

    /// Returns true if no element satisfies the predicate.
    pub fn noneSatisfy(self: *const CharArrayList, predicate: *const fn (u21) bool) bool {
        for (self.items.items) |item| {
            if (predicate(item)) return false;
        }
        return true;
    }

    /// Returns the count of elements satisfying the predicate.
    pub fn count(self: *const CharArrayList, predicate: *const fn (u21) bool) usize {
        var c: usize = 0;
        for (self.items.items) |item| {
            if (predicate(item)) c += 1;
        }
        return c;
    }

    /// Returns the sum of all elements.
    pub fn sum(self: *const CharArrayList) i64 {
        var total: i64 = 0;
        for (self.items.items) |item| {
            total += @as(i64, @intCast(item));
        }
        return total;
    }

    /// Returns the minimum element, or null if empty.
    pub fn min(self: *const CharArrayList) ?u21 {
        if (self.items.items.len == 0) return null;
        var result = self.items.items[0];
        for (self.items.items[1..]) |item| {
            if (std.math.order(item, result) == .lt) result = item;
        }
        return result;
    }

    /// Returns the maximum element, or null if empty.
    pub fn max(self: *const CharArrayList) ?u21 {
        if (self.items.items.len == 0) return null;
        var result = self.items.items[0];
        for (self.items.items[1..]) |item| {
            if (std.math.order(item, result) == .gt) result = item;
        }
        return result;
    }

    /// Sorts the list in ascending order.
    pub fn sort(self: *CharArrayList) void {
        std.mem.sort(u21, self.items.items, {}, struct {
            pub fn f(_: void, a: u21, b: u21) bool {
                return std.math.order(a, b) == .lt;
            }
        }.f);
    }

    /// Returns a new list with elements in reverse order.
    pub fn reversed(self: *const CharArrayList) CharArrayList {
        var result = init(self.config.base);
        var i = self.items.items.len;
        while (i > 0) {
            i -= 1;
            result.push(self.items.items[i]);
        }
        return result;
    }

    /// Returns the elements as a slice.
    pub fn toSlice(self: *const CharArrayList) []const u21 {
        return self.items.items;
    }

    // ---- Iteration ----

    /// Calls f for each element.
    pub fn forEach(self: *const CharArrayList, f: *const fn (u21) void) void {
        for (self.items.items) |item| f(item);
    }

    /// Calls f(index, value) for each element.
    pub fn forEachWithIndex(self: *const CharArrayList, f: *const fn (usize, u21) void) void {
        for (self.items.items, 0..) |item, i| f(i, item);
    }

    // ---- Advanced Operations ----

    /// Fold/reduce over all elements.
    pub fn injectInto(self: *const CharArrayList, initial: u21, f: *const fn (u21, u21) u21) u21 {
        var acc = initial;
        for (self.items.items) |item| acc = f(acc, item);
        return acc;
    }

    /// Returns a new list with duplicate elements removed (preserving first occurrence order).
    pub fn distinct(self: *const CharArrayList) CharArrayList {
        var result = init(self.config.base);
        for (self.items.items) |item| {
            if (!result.contains(item)) result.push(item);
        }
        return result;
    }

    /// Binary search on a sorted list. Returns the index if found, null otherwise.
    pub fn binarySearch(self: *const CharArrayList, value: u21) ?usize {
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
    pub fn toImmutable(self: *const CharArrayList) @import("../immutable/immutable_char_array_list.zig").ImmutableCharArrayList {
        return @import("../immutable/immutable_char_array_list.zig").ImmutableCharArrayList.fromMutable(self.config.base, self);
    }

    // ---- Fluent API ----

    /// Appends a value (fluent).
    pub fn with(self: *CharArrayList, value: u21) *CharArrayList {
        self.push(value);
        return self;
    }

    /// Removes the first occurrence (fluent).
    pub fn without(self: *CharArrayList, value: u21) *CharArrayList {
        _ = self.remove(value);
        return self;
    }

    /// Appends all values (fluent).
    pub fn withAll(self: *CharArrayList, values: []const u21) *CharArrayList {
        self.pushAll(values);
        return self;
    }

    /// Removes all occurrences of each value (fluent).
    pub fn withoutAll(self: *CharArrayList, values: []const u21) *CharArrayList {
        for (values) |val| _ = self.remove(val);
        return self;
    }

    // ---- Equality ----

    /// Formats the list as "[v1, v2, v3]".
    pub fn format(self: *const CharArrayList, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll("[");
        for (self.items.items, 0..) |item, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{any}", .{item});
        }
        try writer.writeAll("]");
    }

    /// Returns true if two lists have equal elements in the same order.
    pub fn eql(self: *const CharArrayList, other: *const CharArrayList) bool {
        if (self.items.items.len != other.items.items.len) return false;
        for (self.items.items, other.items.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }
};

test "CharArrayList: push and get" {
    var l = CharArrayList.init(std.testing.allocator);
    defer l.deinit();
    l.push('a');
    l.push('b');
    l.push('c');
    try std.testing.expectEqual(@as(usize, 3), l.len());
    try std.testing.expectEqual(@as(?u21, 'a'), l.get(0));
    try std.testing.expectEqual(@as(?u21, 'c'), l.get(2));
    try std.testing.expectEqual(@as(?u21, null), l.get(99));
}

test "CharArrayList: of" {
    var l = CharArrayList.of(std.testing.allocator, &[_]u21{ 'a', 'b', 'c' });
    defer l.deinit();
    try std.testing.expectEqual(@as(usize, 3), l.len());
}

test "CharArrayList: set" {
    var l = CharArrayList.of(std.testing.allocator, &[_]u21{ 'a', 'b' });
    defer l.deinit();
    const old = l.set(0, 'c');
    try std.testing.expectEqual('a', old);
    try std.testing.expectEqual(@as(?u21, 'c'), l.get(0));
}

test "CharArrayList: removeAtIndex" {
    var l = CharArrayList.of(std.testing.allocator, &[_]u21{ 'a', 'b', 'c' });
    defer l.deinit();
    const removed = l.removeAtIndex(1);
    try std.testing.expectEqual('b', removed);
    try std.testing.expectEqual(@as(usize, 2), l.len());
}

test "CharArrayList: remove" {
    var l = CharArrayList.of(std.testing.allocator, &[_]u21{ 'a', 'b', 'c' });
    defer l.deinit();
    try std.testing.expect(l.remove('b'));
    try std.testing.expect(!l.contains('b'));
    try std.testing.expect(!l.remove('z'));
}

test "CharArrayList: contains" {
    var l = CharArrayList.of(std.testing.allocator, &[_]u21{ 'a', 'b' });
    defer l.deinit();
    try std.testing.expect(l.contains('a'));
    try std.testing.expect(!l.contains('z'));
}

test "CharArrayList: isEmpty and clear" {
    var l = CharArrayList.init(std.testing.allocator);
    defer l.deinit();
    try std.testing.expect(l.isEmpty());
    l.push('a');
    try std.testing.expect(!l.isEmpty());
    l.clear();
    try std.testing.expect(l.isEmpty());
}

test "CharArrayList: sum min max" {
    var l = CharArrayList.of(std.testing.allocator, &[_]u21{ 'c', 'a', 'b' });
    defer l.deinit();
    try std.testing.expectEqual(@as(?u21, 'a'), l.min());
    try std.testing.expectEqual(@as(?u21, 'c'), l.max());
}

test "CharArrayList: sort" {
    var l = CharArrayList.of(std.testing.allocator, &[_]u21{ 'c', 'a', 'b' });
    defer l.deinit();
    l.sort();
    try std.testing.expectEqual(@as(?u21, 'a'), l.get(0));
    try std.testing.expectEqual(@as(?u21, 'b'), l.get(1));
    try std.testing.expectEqual(@as(?u21, 'c'), l.get(2));
}

test "CharArrayList: reversed" {
    var l = CharArrayList.of(std.testing.allocator, &[_]u21{ 'a', 'b', 'c' });
    defer l.deinit();
    var r = l.reversed();
    defer r.deinit();
    try std.testing.expectEqual(@as(?u21, 'c'), r.get(0));
    try std.testing.expectEqual(@as(?u21, 'a'), r.get(2));
}

test "CharArrayList: eql" {
    var l1 = CharArrayList.of(std.testing.allocator, &[_]u21{ 'a', 'b' });
    defer l1.deinit();
    var l2 = CharArrayList.of(std.testing.allocator, &[_]u21{ 'a', 'b' });
    defer l2.deinit();
    var l3 = CharArrayList.of(std.testing.allocator, &[_]u21{'a'});
    defer l3.deinit();
    try std.testing.expect(l1.eql(&l2));
    try std.testing.expect(!l1.eql(&l3));
}

test "CharArrayList: resize" {
    var l = CharArrayList.init(std.testing.allocator);
    defer l.deinit();
    var i: u21 = 0;
    while (i < 100) : (i += 1) {
        l.push(@as(u21, @intCast(i % 26)) + 'a');
    }
    try std.testing.expectEqual(@as(usize, 100), l.len());
}

test "CharArrayList: distinct" {
    var l = CharArrayList.of(std.testing.allocator, &[_]u21{ 'a', 'b', 'a', 'c', 'b' });
    defer l.deinit();
    var d = l.distinct();
    defer d.deinit();
    try std.testing.expectEqual(@as(usize, 3), d.len());
}

test "CharArrayList: binarySearch" {
    var l = CharArrayList.of(std.testing.allocator, &[_]u21{ 'a', 'b', 'c' });
    defer l.deinit();
    l.sort();
    try std.testing.expect(l.binarySearch('b') != null);
    try std.testing.expectEqual(@as(?usize, null), l.binarySearch('z'));
}

test "CharArrayList: toImmutable" {
    var l = CharArrayList.of(std.testing.allocator, &[_]u21{ 'a', 'b' });
    defer l.deinit();
    var il = l.toImmutable();
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 2), il.len());
    l.push('c');
    try std.testing.expectEqual(@as(usize, 2), il.len());
}

test "CharArrayList: fluent with/without" {
    var l = CharArrayList.init(std.testing.allocator);
    defer l.deinit();
    _ = l.with('a').with('b').with('c');
    try std.testing.expectEqual(@as(usize, 3), l.len());
    _ = l.without('b');
    try std.testing.expectEqual(@as(usize, 2), l.len());
}

test "CharArrayList: ensureUnusedCapacity reserves and subsequent push does not reallocate" {
    var l = CharArrayList.init(std.testing.allocator);
    defer l.deinit();
    try l.ensureUnusedCapacity(10);
    const reserved = l.items.capacity;
    try std.testing.expect(reserved >= 10);
    l.push('a');
    l.push('b');
    l.push('c');
    // Reserved capacity must not have grown — the three puts fit inside it.
    try std.testing.expectEqual(reserved, l.items.capacity);
}

test "CharArrayList: ensureTotalCapacity sets minimum capacity" {
    var l = CharArrayList.init(std.testing.allocator);
    defer l.deinit();
    try l.ensureTotalCapacity(100);
    try std.testing.expect(l.items.capacity >= 100);
}

test "CharArrayList: ensureUnusedCapacity propagates allocator error" {
    // fail_index = 0: ArrayList.init doesn't allocate, so the very first
    // alloc (the grow triggered by ensureUnusedCapacity) fails immediately.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var l = CharArrayList.initWithConfig(AllocatorConfig.init(failing.allocator()));
    defer l.deinit();
    try std.testing.expectError(error.OutOfMemory, l.ensureUnusedCapacity(1024));
}
