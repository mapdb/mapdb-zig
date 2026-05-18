
const std = @import("std");
const Allocator = std.mem.Allocator;
const I16HashSet = @import("../hashset/i16_hash_set.zig").I16HashSet;

/// Immutable set of unique `i16` values, backed by an owned allocated slice.
///
/// All operations are read-only. Call `toMutable()` for an independent mutable copy.
pub const ImmutableI16HashSet = struct {
    items: []const i16,
    allocator: Allocator,

    pub fn of(allocator: Allocator, values: []const i16) ImmutableI16HashSet {
        // Deduplicate
        var mutable = I16HashSet.init(allocator);
        for (values) |val| _ = mutable.add(val);
        // Snapshot to owned slice
        var buf: std.ArrayListUnmanaged(i16) = .empty;
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) buf.append(allocator, mutable.inner.entries[i].key) catch @panic("out of memory");
        }
        mutable.deinit();
        const owned = buf.toOwnedSlice(allocator) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn fromMutable(allocator: Allocator, mutable: *const I16HashSet) ImmutableI16HashSet {
        var buf: std.ArrayListUnmanaged(i16) = .empty;
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) buf.append(allocator, mutable.inner.entries[i].key) catch @panic("out of memory");
        }
        const owned = buf.toOwnedSlice(allocator) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableI16HashSet) void {
        self.allocator.free(self.items);
    }

    pub fn len(self: *const ImmutableI16HashSet) usize {
        return self.items.len;
    }

    pub fn isEmpty(self: *const ImmutableI16HashSet) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableI16HashSet, value: i16) bool {
        for (self.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    pub fn toSlice(self: *const ImmutableI16HashSet) []const i16 {
        return self.items;
    }

    pub fn toMutable(self: *const ImmutableI16HashSet) I16HashSet {
        return I16HashSet.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableI16HashSet, other: *const ImmutableI16HashSet) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items) |item| {
            if (!other.contains(item)) return false;
        }
        return true;
    }
};

test "ImmutableI16HashSet: of and contains" {
    var il = ImmutableI16HashSet.of(std.testing.allocator, &[_]i16{ 1, 2, 1 });
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expect(il.contains(1));
}

test "ImmutableI16HashSet: toMutable independence" {
    var il = ImmutableI16HashSet.of(std.testing.allocator, &[_]i16{ 1, 2 });
    defer il.deinit();
    var ml = il.toMutable();
    defer ml.deinit();
    _ = ml.add(3);
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expectEqual(@as(usize, 3), ml.len());
}
