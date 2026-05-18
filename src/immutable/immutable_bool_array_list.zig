
const std = @import("std");
const Allocator = std.mem.Allocator;
const BoolArrayList = @import("../arraylist/bool_array_list.zig").BoolArrayList;

/// Immutable list of `bool` values, backed by an owned allocated slice.
///
/// All operations are read-only. To modify, call `toMutable()` to get
/// an independent mutable copy. The caller must call `deinit()` when done.
///
/// Go equivalent:   ImmutableBoolArrayList
/// Rust equivalent:  ImmutableBoolArrayList (Arc-backed)
pub const ImmutableBoolArrayList = struct {
    items: []const bool,
    allocator: Allocator,

    /// Create from a slice by copying it. Caller retains ownership of the input.
    pub fn of(allocator: Allocator, values: []const bool) ImmutableBoolArrayList {
        const owned = allocator.dupe(bool, values) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    /// Create from a mutable list by taking a snapshot.
    pub fn fromMutable(allocator: Allocator, mutable: *const BoolArrayList) ImmutableBoolArrayList {
        return of(allocator, mutable.items.items);
    }

    /// Release the owned slice.
    pub fn deinit(self: *ImmutableBoolArrayList) void {
        self.allocator.free(self.items);
    }

    pub fn get(self: *const ImmutableBoolArrayList, index: usize) ?bool {
        if (index >= self.items.len) return null;
        return self.items[index];
    }

    pub fn len(self: *const ImmutableBoolArrayList) usize {
        return self.items.len;
    }

    pub fn isEmpty(self: *const ImmutableBoolArrayList) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableBoolArrayList, value: bool) bool {
        for (self.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    pub fn indexOf(self: *const ImmutableBoolArrayList, value: bool) ?usize {
        for (self.items, 0..) |item, i| {
            if (item == value) return i;
        }
        return null;
    }

    pub fn toSlice(self: *const ImmutableBoolArrayList) []const bool {
        return self.items;
    }

    /// Returns the sum of all elements.
    pub fn sum(self: *const ImmutableBoolArrayList) i64 {
        var total: i64 = 0;
        for (self.items) |item| {
            total += @as(i64, if (item) 1 else 0);
        }
        return total;
    }

    /// Returns the minimum element, or null if empty.
    pub fn min(self: *const ImmutableBoolArrayList) ?bool {
        if (self.items.len == 0) return null;
        var result = self.items[0];
        for (self.items[1..]) |item| {
            if (!item and result) result = item;
        }
        return result;
    }

    /// Returns the maximum element, or null if empty.
    pub fn max(self: *const ImmutableBoolArrayList) ?bool {
        if (self.items.len == 0) return null;
        var result = self.items[0];
        for (self.items[1..]) |item| {
            if (item and !result) result = item;
        }
        return result;
    }

    pub fn anySatisfy(self: *const ImmutableBoolArrayList, predicate: *const fn (bool) bool) bool {
        for (self.items) |item| {
            if (predicate(item)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const ImmutableBoolArrayList, predicate: *const fn (bool) bool) bool {
        for (self.items) |item| {
            if (!predicate(item)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const ImmutableBoolArrayList, predicate: *const fn (bool) bool) bool {
        for (self.items) |item| {
            if (predicate(item)) return false;
        }
        return true;
    }

    /// Create an independent mutable copy.
    pub fn toMutable(self: *const ImmutableBoolArrayList) BoolArrayList {
        return BoolArrayList.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableBoolArrayList, other: *const ImmutableBoolArrayList) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items, other.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }
};

test "ImmutableBoolArrayList: of and get" {
    var il = ImmutableBoolArrayList.of(std.testing.allocator, &[_]bool{ true, false, true });
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 3), il.len());
    try std.testing.expectEqual(@as(?bool, true), il.get(0));
    try std.testing.expectEqual(@as(?bool, null), il.get(99));
}

test "ImmutableBoolArrayList: contains" {
    var il = ImmutableBoolArrayList.of(std.testing.allocator, &[_]bool{ true, false });
    defer il.deinit();
    try std.testing.expect(il.contains(true));
}

test "ImmutableBoolArrayList: fromMutable" {
    var ml = BoolArrayList.of(std.testing.allocator, &[_]bool{ true, false });
    defer ml.deinit();
    var il = ImmutableBoolArrayList.fromMutable(std.testing.allocator, &ml);
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 2), il.len());
}

test "ImmutableBoolArrayList: toMutable independence" {
    var il = ImmutableBoolArrayList.of(std.testing.allocator, &[_]bool{ true, false });
    defer il.deinit();
    var ml = il.toMutable();
    defer ml.deinit();
    ml.push(true);
    // Immutable list unchanged
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expectEqual(@as(usize, 3), ml.len());
}

test "ImmutableBoolArrayList: eql" {
    var a = ImmutableBoolArrayList.of(std.testing.allocator, &[_]bool{ true, false });
    defer a.deinit();
    var b = ImmutableBoolArrayList.of(std.testing.allocator, &[_]bool{ true, false });
    defer b.deinit();
    try std.testing.expect(a.eql(&b));
}
