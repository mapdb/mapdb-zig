
const std = @import("std");
const Allocator = std.mem.Allocator;
const I32ArrayList = @import("../arraylist/i32_array_list.zig").I32ArrayList;

/// Immutable list of `i32` values, backed by an owned allocated slice.
///
/// All operations are read-only. To modify, call `toMutable()` to get
/// an independent mutable copy. The caller must call `deinit()` when done.
///
/// Go equivalent:   ImmutableI32ArrayList
/// Rust equivalent:  ImmutableI32ArrayList (Arc-backed)
pub const ImmutableI32ArrayList = struct {
    items: []const i32,
    allocator: Allocator,

    /// Create from a slice by copying it. Caller retains ownership of the input.
    pub fn of(allocator: Allocator, values: []const i32) ImmutableI32ArrayList {
        const owned = allocator.dupe(i32, values) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    /// Create from a mutable list by taking a snapshot.
    pub fn fromMutable(allocator: Allocator, mutable: *const I32ArrayList) ImmutableI32ArrayList {
        return of(allocator, mutable.items.items);
    }

    /// Release the owned slice.
    pub fn deinit(self: *ImmutableI32ArrayList) void {
        self.allocator.free(self.items);
    }

    pub fn get(self: *const ImmutableI32ArrayList, index: usize) ?i32 {
        if (index >= self.items.len) return null;
        return self.items[index];
    }

    pub fn len(self: *const ImmutableI32ArrayList) usize {
        return self.items.len;
    }

    pub fn isEmpty(self: *const ImmutableI32ArrayList) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableI32ArrayList, value: i32) bool {
        for (self.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    pub fn indexOf(self: *const ImmutableI32ArrayList, value: i32) ?usize {
        for (self.items, 0..) |item, i| {
            if (item == value) return i;
        }
        return null;
    }

    pub fn toSlice(self: *const ImmutableI32ArrayList) []const i32 {
        return self.items;
    }

    /// Returns the sum of all elements.
    pub fn sum(self: *const ImmutableI32ArrayList) i64 {
        var total: i64 = 0;
        for (self.items) |item| {
            total += @as(i64, @intCast(item));
        }
        return total;
    }

    /// Returns the minimum element, or null if empty.
    pub fn min(self: *const ImmutableI32ArrayList) ?i32 {
        if (self.items.len == 0) return null;
        var result = self.items[0];
        for (self.items[1..]) |item| {
            if (std.math.order(item, result) == .lt) result = item;
        }
        return result;
    }

    /// Returns the maximum element, or null if empty.
    pub fn max(self: *const ImmutableI32ArrayList) ?i32 {
        if (self.items.len == 0) return null;
        var result = self.items[0];
        for (self.items[1..]) |item| {
            if (std.math.order(item, result) == .gt) result = item;
        }
        return result;
    }

    pub fn anySatisfy(self: *const ImmutableI32ArrayList, predicate: *const fn (i32) bool) bool {
        for (self.items) |item| {
            if (predicate(item)) return true;
        }
        return false;
    }

    pub fn allSatisfy(self: *const ImmutableI32ArrayList, predicate: *const fn (i32) bool) bool {
        for (self.items) |item| {
            if (!predicate(item)) return false;
        }
        return true;
    }

    pub fn noneSatisfy(self: *const ImmutableI32ArrayList, predicate: *const fn (i32) bool) bool {
        for (self.items) |item| {
            if (predicate(item)) return false;
        }
        return true;
    }

    /// Create an independent mutable copy.
    pub fn toMutable(self: *const ImmutableI32ArrayList) I32ArrayList {
        return I32ArrayList.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableI32ArrayList, other: *const ImmutableI32ArrayList) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items, other.items) |a, b| {
            if (!(a == b)) return false;
        }
        return true;
    }
};

test "ImmutableI32ArrayList: of and get" {
    var il = ImmutableI32ArrayList.of(std.testing.allocator, &[_]i32{ 1, 2, 3 });
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 3), il.len());
    try std.testing.expectEqual(@as(?i32, 1), il.get(0));
    try std.testing.expectEqual(@as(?i32, null), il.get(99));
}

test "ImmutableI32ArrayList: contains" {
    var il = ImmutableI32ArrayList.of(std.testing.allocator, &[_]i32{ 1, 2 });
    defer il.deinit();
    try std.testing.expect(il.contains(1));
    try std.testing.expect(!il.contains(99));
}

test "ImmutableI32ArrayList: fromMutable" {
    var ml = I32ArrayList.of(std.testing.allocator, &[_]i32{ 1, 2 });
    defer ml.deinit();
    var il = ImmutableI32ArrayList.fromMutable(std.testing.allocator, &ml);
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 2), il.len());
}

test "ImmutableI32ArrayList: toMutable independence" {
    var il = ImmutableI32ArrayList.of(std.testing.allocator, &[_]i32{ 1, 2 });
    defer il.deinit();
    var ml = il.toMutable();
    defer ml.deinit();
    ml.push(3);
    // Immutable list unchanged
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expectEqual(@as(usize, 3), ml.len());
}

test "ImmutableI32ArrayList: eql" {
    var a = ImmutableI32ArrayList.of(std.testing.allocator, &[_]i32{ 1, 2 });
    defer a.deinit();
    var b = ImmutableI32ArrayList.of(std.testing.allocator, &[_]i32{ 1, 2 });
    defer b.deinit();
    try std.testing.expect(a.eql(&b));
}
