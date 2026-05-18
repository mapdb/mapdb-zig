
const std = @import("std");
const Allocator = std.mem.Allocator;
const BoolHashSet = @import("../hashset/bool_hash_set.zig").BoolHashSet;

/// Immutable set of unique `bool` values, backed by an owned allocated slice.
///
/// All operations are read-only. Call `toMutable()` for an independent mutable copy.
pub const ImmutableBoolHashSet = struct {
    items: []const bool,
    allocator: Allocator,

    pub fn of(allocator: Allocator, values: []const bool) ImmutableBoolHashSet {
        // Deduplicate
        var mutable = BoolHashSet.init(allocator);
        for (values) |val| _ = mutable.add(val);
        // Snapshot to owned slice
        var buf: std.ArrayListUnmanaged(bool) = .empty;
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) buf.append(allocator, mutable.inner.entries[i].key) catch @panic("out of memory");
        }
        mutable.deinit();
        const owned = buf.toOwnedSlice(allocator) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn fromMutable(allocator: Allocator, mutable: *const BoolHashSet) ImmutableBoolHashSet {
        var buf: std.ArrayListUnmanaged(bool) = .empty;
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) buf.append(allocator, mutable.inner.entries[i].key) catch @panic("out of memory");
        }
        const owned = buf.toOwnedSlice(allocator) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableBoolHashSet) void {
        self.allocator.free(self.items);
    }

    pub fn len(self: *const ImmutableBoolHashSet) usize {
        return self.items.len;
    }

    pub fn isEmpty(self: *const ImmutableBoolHashSet) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableBoolHashSet, value: bool) bool {
        for (self.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    pub fn toSlice(self: *const ImmutableBoolHashSet) []const bool {
        return self.items;
    }

    pub fn toMutable(self: *const ImmutableBoolHashSet) BoolHashSet {
        return BoolHashSet.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableBoolHashSet, other: *const ImmutableBoolHashSet) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items) |item| {
            if (!other.contains(item)) return false;
        }
        return true;
    }
};

test "ImmutableBoolHashSet: of and contains" {
    var il = ImmutableBoolHashSet.of(std.testing.allocator, &[_]bool{ true, false, true });
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expect(il.contains(true));
}

test "ImmutableBoolHashSet: toMutable independence" {
    var il = ImmutableBoolHashSet.of(std.testing.allocator, &[_]bool{true});
    defer il.deinit();
    var ml = il.toMutable();
    defer ml.deinit();
    _ = ml.add(false);
    try std.testing.expectEqual(@as(usize, 1), il.len());
    try std.testing.expectEqual(@as(usize, 2), ml.len());
}
