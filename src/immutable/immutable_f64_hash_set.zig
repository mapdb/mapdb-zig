
const std = @import("std");
const Allocator = std.mem.Allocator;
const F64HashSet = @import("../hashset/f64_hash_set.zig").F64HashSet;

/// Immutable set of unique `f64` values, backed by an owned allocated slice.
///
/// All operations are read-only. Call `toMutable()` for an independent mutable copy.
pub const ImmutableF64HashSet = struct {
    items: []const f64,
    allocator: Allocator,

    pub fn of(allocator: Allocator, values: []const f64) ImmutableF64HashSet {
        // Deduplicate
        var mutable = F64HashSet.init(allocator);
        for (values) |val| _ = mutable.add(val);
        // Snapshot to owned slice
        var buf: std.ArrayListUnmanaged(f64) = .empty;
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) buf.append(allocator, mutable.inner.entries[i].key) catch @panic("out of memory");
        }
        mutable.deinit();
        const owned = buf.toOwnedSlice(allocator) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn fromMutable(allocator: Allocator, mutable: *const F64HashSet) ImmutableF64HashSet {
        var buf: std.ArrayListUnmanaged(f64) = .empty;
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) buf.append(allocator, mutable.inner.entries[i].key) catch @panic("out of memory");
        }
        const owned = buf.toOwnedSlice(allocator) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableF64HashSet) void {
        self.allocator.free(self.items);
    }

    pub fn len(self: *const ImmutableF64HashSet) usize {
        return self.items.len;
    }

    pub fn isEmpty(self: *const ImmutableF64HashSet) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableF64HashSet, value: f64) bool {
        for (self.items) |item| {
            if (@as(u64, @bitCast(item)) == @as(u64, @bitCast(value))) return true;
        }
        return false;
    }

    pub fn toSlice(self: *const ImmutableF64HashSet) []const f64 {
        return self.items;
    }

    pub fn toMutable(self: *const ImmutableF64HashSet) F64HashSet {
        return F64HashSet.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableF64HashSet, other: *const ImmutableF64HashSet) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items) |item| {
            if (!other.contains(item)) return false;
        }
        return true;
    }
};

test "ImmutableF64HashSet: of and contains" {
    var il = ImmutableF64HashSet.of(std.testing.allocator, &[_]f64{ 1.0, 2.0, 1.0 });
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expect(il.contains(1.0));
}

test "ImmutableF64HashSet: toMutable independence" {
    var il = ImmutableF64HashSet.of(std.testing.allocator, &[_]f64{ 1.0, 2.0 });
    defer il.deinit();
    var ml = il.toMutable();
    defer ml.deinit();
    _ = ml.add(3.0);
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expectEqual(@as(usize, 3), ml.len());
}
