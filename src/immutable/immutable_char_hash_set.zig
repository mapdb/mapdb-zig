
const std = @import("std");
const Allocator = std.mem.Allocator;
const CharHashSet = @import("../hashset/char_hash_set.zig").CharHashSet;

/// Immutable set of unique `u21` values, backed by an owned allocated slice.
///
/// All operations are read-only. Call `toMutable()` for an independent mutable copy.
pub const ImmutableCharHashSet = struct {
    items: []const u21,
    allocator: Allocator,

    pub fn of(allocator: Allocator, values: []const u21) ImmutableCharHashSet {
        // Deduplicate
        var mutable = CharHashSet.init(allocator);
        for (values) |val| _ = mutable.add(val);
        // Snapshot to owned slice
        var buf: std.ArrayListUnmanaged(u21) = .empty;
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) buf.append(allocator, mutable.inner.entries[i].key) catch @panic("out of memory");
        }
        mutable.deinit();
        const owned = buf.toOwnedSlice(allocator) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn fromMutable(allocator: Allocator, mutable: *const CharHashSet) ImmutableCharHashSet {
        var buf: std.ArrayListUnmanaged(u21) = .empty;
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) buf.append(allocator, mutable.inner.entries[i].key) catch @panic("out of memory");
        }
        const owned = buf.toOwnedSlice(allocator) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableCharHashSet) void {
        self.allocator.free(self.items);
    }

    pub fn len(self: *const ImmutableCharHashSet) usize {
        return self.items.len;
    }

    pub fn isEmpty(self: *const ImmutableCharHashSet) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableCharHashSet, value: u21) bool {
        for (self.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    pub fn toSlice(self: *const ImmutableCharHashSet) []const u21 {
        return self.items;
    }

    pub fn toMutable(self: *const ImmutableCharHashSet) CharHashSet {
        return CharHashSet.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableCharHashSet, other: *const ImmutableCharHashSet) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items) |item| {
            if (!other.contains(item)) return false;
        }
        return true;
    }
};

test "ImmutableCharHashSet: of and contains" {
    var il = ImmutableCharHashSet.of(std.testing.allocator, &[_]u21{ 'a', 'b', 'a' });
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expect(il.contains('a'));
}

test "ImmutableCharHashSet: toMutable independence" {
    var il = ImmutableCharHashSet.of(std.testing.allocator, &[_]u21{ 'a', 'b' });
    defer il.deinit();
    var ml = il.toMutable();
    defer ml.deinit();
    _ = ml.add('c');
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expectEqual(@as(usize, 3), ml.len());
}
