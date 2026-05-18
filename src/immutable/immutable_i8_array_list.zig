
const std = @import("std");
const Allocator = std.mem.Allocator;
const I8ArrayList = @import("../arraylist/i8_array_list.zig").I8ArrayList;

/// Immutable list of `i8` values, backed by an owned allocated slice.
///
/// All operations are read-only. To modify, call `toMutable()` to get
/// an independent mutable copy. The caller must call `deinit()` when done.
///
/// Go equivalent:   ImmutableI8ArrayList
/// Rust equivalent:  ImmutableI8ArrayList (Arc-backed)
pub const ImmutableI8ArrayList = struct {
    items: []const i8,
    allocator: Allocator,

    /// Create from a slice by copying it. Caller retains ownership of the input.
    pub fn of(allocator: Allocator, values: []const i8) ImmutableI8ArrayList {
        const owned = allocator.dupe(i8, values) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    /// Create from a mutable list by taking a snapshot.
    pub fn fromMutable(allocator: Allocator, mutable: *const I8ArrayList) ImmutableI8ArrayList {
        return of(allocator, mutable.items.items);
    }

    /// Release the owned slice.
    pub fn deinit(self: *ImmutableI8ArrayList) void {
        self.allocator.free(self.items);
    }

    pub fn get(self: *const ImmutableI8ArrayList, index: usize) ?i8 {
        if (index >= self.items.len) return null;
        return self.items[index];
    }

    pub fn len(self: *const ImmutableI8ArrayList) usize {
        return self.items.len;
    }

    pub fn isEmpty(self: *const ImmutableI8ArrayList) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableI8ArrayList, value: i8) bool {
        for (self.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    pub fn indexOf(self: *const ImmutableI8ArrayList, value: i8) ?usize {
        for (self.items, 0..) |item, i| {
            if (item == value) return i;
        }
        return null;
    }

    pub fn toSlice(self: *const ImmutableI8ArrayList) []const i8 {
        return self.items;
    }

    /// Returns the sum of all elements.
    pub fn sum(self: *const ImmutableI8ArrayList) i64 {
        var total: i64 = 0;
        for (self.items) |item| {
            total += @as(i64, @intCast(item));
        }
        return total;
    }

    /// Returns the minimum element, or null if empty.
    pub fn min(self: *const ImmutableI8ArrayList) ?i8 {
        if (self.items.len == 0) return null;
        var result = self.items[0];
        for (self.items[1..]) |item| {
            if (std.math.order(item, result) == .lt) result = item;
        }
        return result;
    }

    /// Returns the maximum element, or null if empty.
    pub fn max(self: *const ImmutableI8ArrayList) ?i8 {
        if (self.items.len == 0) return null;
        var result = self.items[0];
        for (self.items[1..]) |item| {
            if (std.math.order(item, result) == .gt) result = item;
        }
        return result;
    }

    pub fn anySatisfy(self: *const ImmutableI8ArrayList, predicate: *const fn (i8) bool) bool {
        for (self.items) |item| {
            if (predicate(item)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const ImmutableI8ArrayList, predicate: *const fn (i8) bool) bool {
        for (self.items) |item| {
            if (!predicate(item)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const ImmutableI8ArrayList, predicate: *const fn (i8) bool) bool {
        for (self.items) |item| {
            if (predicate(item)) return false;
        }
        return true;
    }

    /// Create an independent mutable copy.
    pub fn toMutable(self: *const ImmutableI8ArrayList) I8ArrayList {
        return I8ArrayList.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableI8ArrayList, other: *const ImmutableI8ArrayList) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items, other.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }
};

test "ImmutableI8ArrayList: of and get" {
    var il = ImmutableI8ArrayList.of(std.testing.allocator, &[_]i8{ 1, 2, 3 });
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 3), il.len());
    try std.testing.expectEqual(@as(?i8, 1), il.get(0));
    try std.testing.expectEqual(@as(?i8, null), il.get(99));
}

test "ImmutableI8ArrayList: contains" {
    var il = ImmutableI8ArrayList.of(std.testing.allocator, &[_]i8{ 1, 2 });
    defer il.deinit();
    try std.testing.expect(il.contains(1));
    try std.testing.expect(!il.contains(99));
}

test "ImmutableI8ArrayList: fromMutable" {
    var ml = I8ArrayList.of(std.testing.allocator, &[_]i8{ 1, 2 });
    defer ml.deinit();
    var il = ImmutableI8ArrayList.fromMutable(std.testing.allocator, &ml);
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 2), il.len());
}

test "ImmutableI8ArrayList: toMutable independence" {
    var il = ImmutableI8ArrayList.of(std.testing.allocator, &[_]i8{ 1, 2 });
    defer il.deinit();
    var ml = il.toMutable();
    defer ml.deinit();
    ml.push(3);
    // Immutable list unchanged
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expectEqual(@as(usize, 3), ml.len());
}

test "ImmutableI8ArrayList: eql" {
    var a = ImmutableI8ArrayList.of(std.testing.allocator, &[_]i8{ 1, 2 });
    defer a.deinit();
    var b = ImmutableI8ArrayList.of(std.testing.allocator, &[_]i8{ 1, 2 });
    defer b.deinit();
    try std.testing.expect(a.eql(&b));
}
