// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const I32HashSet = @import("../hashset/i32_hash_set.zig").I32HashSet;

/// Immutable set of unique `i32` values, backed by an owned allocated slice.
///
/// All operations are read-only. Call `toMutable()` for an independent mutable copy.
pub const ImmutableI32HashSet = struct {
    items: []const i32,
    allocator: Allocator,

    pub fn of(allocator: Allocator, values: []const i32) ImmutableI32HashSet {
        // Deduplicate
        var mutable = I32HashSet.init(allocator);
        for (values) |val| _ = mutable.add(val);
        // Snapshot to owned slice
        var buf: std.ArrayListUnmanaged(i32) = .empty;
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) buf.append(allocator, mutable.inner.entries[i].key) catch @panic("out of memory");
        }
        mutable.deinit();
        const owned = buf.toOwnedSlice(allocator) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn fromMutable(allocator: Allocator, mutable: *const I32HashSet) ImmutableI32HashSet {
        var buf: std.ArrayListUnmanaged(i32) = .empty;
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) buf.append(allocator, mutable.inner.entries[i].key) catch @panic("out of memory");
        }
        const owned = buf.toOwnedSlice(allocator) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableI32HashSet) void {
        self.allocator.free(self.items);
    }

    pub fn len(self: *const ImmutableI32HashSet) usize {
        return self.items.len;
    }

    pub fn isEmpty(self: *const ImmutableI32HashSet) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableI32HashSet, value: i32) bool {
        for (self.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    pub fn toSlice(self: *const ImmutableI32HashSet) []const i32 {
        return self.items;
    }

    pub fn toMutable(self: *const ImmutableI32HashSet) I32HashSet {
        return I32HashSet.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableI32HashSet, other: *const ImmutableI32HashSet) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items) |item| {
            if (!other.contains(item)) return false;
        }
        return true;
    }
};

test "ImmutableI32HashSet: of and contains" {
    var il = ImmutableI32HashSet.of(std.testing.allocator, &[_]i32{ 1, 2, 1 });
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expect(il.contains(1));
}

test "ImmutableI32HashSet: fromMutable snapshot is independent of source mutation" {
    var ml = I32HashSet.init(std.testing.allocator);
    defer ml.deinit();
    _ = ml.add(1);
    _ = ml.add(2);
    var il = ImmutableI32HashSet.fromMutable(std.testing.allocator, &ml);
    defer il.deinit();
    _ = ml.remove(1);
    _ = ml.add(3);
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expect(il.contains(1));
    try std.testing.expect(!il.contains(3));
}

test "ImmutableI32HashSet: toMutable independence" {
    var il = ImmutableI32HashSet.of(std.testing.allocator, &[_]i32{ 1, 2 });
    defer il.deinit();
    var ml = il.toMutable();
    defer ml.deinit();
    _ = ml.add(3);
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expectEqual(@as(usize, 3), ml.len());
}
