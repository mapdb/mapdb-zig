
const std = @import("std");
const Allocator = std.mem.Allocator;
const I64ArrayList = @import("../arraylist/i64_array_list.zig").I64ArrayList;

/// Immutable list of `i64` values, backed by an owned allocated slice.
///
/// All operations are read-only. To modify, call `toMutable()` to get
/// an independent mutable copy. The caller must call `deinit()` when done.
///
/// Go equivalent:   ImmutableI64ArrayList
/// Rust equivalent:  ImmutableI64ArrayList (Arc-backed)
pub const ImmutableI64ArrayList = struct {
    items: []const i64,
    allocator: Allocator,

    /// Create from a slice by copying it. Caller retains ownership of the input.
    pub fn of(allocator: Allocator, values: []const i64) ImmutableI64ArrayList {
        const owned = allocator.dupe(i64, values) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    /// Create from a mutable list by taking a snapshot.
    pub fn fromMutable(allocator: Allocator, mutable: *const I64ArrayList) ImmutableI64ArrayList {
        return of(allocator, mutable.items.items);
    }

    /// Release the owned slice.
    pub fn deinit(self: *ImmutableI64ArrayList) void {
        self.allocator.free(self.items);
    }

    pub fn get(self: *const ImmutableI64ArrayList, index: usize) ?i64 {
        if (index >= self.items.len) return null;
        return self.items[index];
    }

    pub fn len(self: *const ImmutableI64ArrayList) usize {
        return self.items.len;
    }

    pub fn isEmpty(self: *const ImmutableI64ArrayList) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableI64ArrayList, value: i64) bool {
        for (self.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    pub fn indexOf(self: *const ImmutableI64ArrayList, value: i64) ?usize {
        for (self.items, 0..) |item, i| {
            if (item == value) return i;
        }
        return null;
    }

    pub fn toSlice(self: *const ImmutableI64ArrayList) []const i64 {
        return self.items;
    }

    /// Returns the sum of all elements.
    pub fn sum(self: *const ImmutableI64ArrayList) i64 {
        var total: i64 = 0;
        for (self.items) |item| {
            total += item;
        }
        return total;
    }

    /// Returns the minimum element, or null if empty.
    pub fn min(self: *const ImmutableI64ArrayList) ?i64 {
        if (self.items.len == 0) return null;
        var result = self.items[0];
        for (self.items[1..]) |item| {
            if (std.math.order(item, result) == .lt) result = item;
        }
        return result;
    }

    /// Returns the maximum element, or null if empty.
    pub fn max(self: *const ImmutableI64ArrayList) ?i64 {
        if (self.items.len == 0) return null;
        var result = self.items[0];
        for (self.items[1..]) |item| {
            if (std.math.order(item, result) == .gt) result = item;
        }
        return result;
    }

    pub fn anySatisfy(self: *const ImmutableI64ArrayList, predicate: *const fn (i64) bool) bool {
        for (self.items) |item| {
            if (predicate(item)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const ImmutableI64ArrayList, predicate: *const fn (i64) bool) bool {
        for (self.items) |item| {
            if (!predicate(item)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const ImmutableI64ArrayList, predicate: *const fn (i64) bool) bool {
        for (self.items) |item| {
            if (predicate(item)) return false;
        }
        return true;
    }

    /// Create an independent mutable copy.
    pub fn toMutable(self: *const ImmutableI64ArrayList) I64ArrayList {
        return I64ArrayList.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableI64ArrayList, other: *const ImmutableI64ArrayList) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items, other.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }
};

test "ImmutableI64ArrayList: of and get" {
    var il = ImmutableI64ArrayList.of(std.testing.allocator, &[_]i64{ 1, 2, 3 });
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 3), il.len());
    try std.testing.expectEqual(@as(?i64, 1), il.get(0));
    try std.testing.expectEqual(@as(?i64, null), il.get(99));
}

test "ImmutableI64ArrayList: contains" {
    var il = ImmutableI64ArrayList.of(std.testing.allocator, &[_]i64{ 1, 2 });
    defer il.deinit();
    try std.testing.expect(il.contains(1));
    try std.testing.expect(!il.contains(99));
}

test "ImmutableI64ArrayList: fromMutable" {
    var ml = I64ArrayList.of(std.testing.allocator, &[_]i64{ 1, 2 });
    defer ml.deinit();
    var il = ImmutableI64ArrayList.fromMutable(std.testing.allocator, &ml);
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 2), il.len());
}

test "ImmutableI64ArrayList: toMutable independence" {
    var il = ImmutableI64ArrayList.of(std.testing.allocator, &[_]i64{ 1, 2 });
    defer il.deinit();
    var ml = il.toMutable();
    defer ml.deinit();
    ml.push(3);
    // Immutable list unchanged
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expectEqual(@as(usize, 3), ml.len());
}

test "ImmutableI64ArrayList: eql" {
    var a = ImmutableI64ArrayList.of(std.testing.allocator, &[_]i64{ 1, 2 });
    defer a.deinit();
    var b = ImmutableI64ArrayList.of(std.testing.allocator, &[_]i64{ 1, 2 });
    defer b.deinit();
    try std.testing.expect(a.eql(&b));
}
