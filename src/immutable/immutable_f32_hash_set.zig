// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const F32HashSet = @import("../hashset/f32_hash_set.zig").F32HashSet;

/// Immutable set of unique `f32` values, backed by an owned allocated slice.
///
/// All operations are read-only. Call `toMutable()` for an independent mutable copy.
pub const ImmutableF32HashSet = struct {
    items: []const f32,
    allocator: Allocator,

    pub fn of(allocator: Allocator, values: []const f32) ImmutableF32HashSet {
        // Deduplicate
        var mutable = F32HashSet.init(allocator);
        for (values) |val| _ = mutable.add(val);
        // Snapshot to owned slice
        var buf: std.ArrayListUnmanaged(f32) = .empty;
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) buf.append(allocator, mutable.inner.entries[i].key) catch @panic("out of memory");
        }
        mutable.deinit();
        const owned = buf.toOwnedSlice(allocator) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn fromMutable(allocator: Allocator, mutable: *const F32HashSet) ImmutableF32HashSet {
        var buf: std.ArrayListUnmanaged(f32) = .empty;
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) buf.append(allocator, mutable.inner.entries[i].key) catch @panic("out of memory");
        }
        const owned = buf.toOwnedSlice(allocator) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableF32HashSet) void {
        self.allocator.free(self.items);
    }

    pub fn len(self: *const ImmutableF32HashSet) usize {
        return self.items.len;
    }

    pub fn isEmpty(self: *const ImmutableF32HashSet) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableF32HashSet, value: f32) bool {
        for (self.items) |item| {
            if (@as(u32, @bitCast(item)) == @as(u32, @bitCast(value))) return true;
        }
        return false;
    }

    pub fn toSlice(self: *const ImmutableF32HashSet) []const f32 {
        return self.items;
    }

    pub fn toMutable(self: *const ImmutableF32HashSet) F32HashSet {
        return F32HashSet.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableF32HashSet, other: *const ImmutableF32HashSet) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items) |item| {
            if (!other.contains(item)) return false;
        }
        return true;
    }
};

test "ImmutableF32HashSet: of and contains" {
    var il = ImmutableF32HashSet.of(std.testing.allocator, &[_]f32{ 1.0, 2.0, 1.0 });
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expect(il.contains(1.0));
}

test "ImmutableF32HashSet: toMutable independence" {
    var il = ImmutableF32HashSet.of(std.testing.allocator, &[_]f32{ 1.0, 2.0 });
    defer il.deinit();
    var ml = il.toMutable();
    defer ml.deinit();
    _ = ml.add(3.0);
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expectEqual(@as(usize, 3), ml.len());
}
