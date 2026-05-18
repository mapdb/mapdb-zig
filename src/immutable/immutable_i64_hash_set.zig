// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const I64HashSet = @import("../hashset/i64_hash_set.zig").I64HashSet;

/// Immutable set of unique `i64` values, backed by an owned allocated slice.
///
/// All operations are read-only. Call `toMutable()` for an independent mutable copy.
pub const ImmutableI64HashSet = struct {
    items: []const i64,
    allocator: Allocator,

    pub fn of(allocator: Allocator, values: []const i64) ImmutableI64HashSet {
        // Deduplicate
        var mutable = I64HashSet.init(allocator);
        for (values) |val| _ = mutable.add(val);
        // Snapshot to owned slice
        var buf: std.ArrayListUnmanaged(i64) = .empty;
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) buf.append(allocator, mutable.inner.entries[i].key) catch @panic("out of memory");
        }
        mutable.deinit();
        const owned = buf.toOwnedSlice(allocator) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn fromMutable(allocator: Allocator, mutable: *const I64HashSet) ImmutableI64HashSet {
        var buf: std.ArrayListUnmanaged(i64) = .empty;
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) buf.append(allocator, mutable.inner.entries[i].key) catch @panic("out of memory");
        }
        const owned = buf.toOwnedSlice(allocator) catch @panic("out of memory");
        return .{ .items = owned, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableI64HashSet) void {
        self.allocator.free(self.items);
    }

    pub fn len(self: *const ImmutableI64HashSet) usize {
        return self.items.len;
    }

    pub fn isEmpty(self: *const ImmutableI64HashSet) bool {
        return self.items.len == 0;
    }

    pub fn contains(self: *const ImmutableI64HashSet, value: i64) bool {
        for (self.items) |item| {
            if (item == value) return true;
        }
        return false;
    }

    pub fn toSlice(self: *const ImmutableI64HashSet) []const i64 {
        return self.items;
    }

    pub fn toMutable(self: *const ImmutableI64HashSet) I64HashSet {
        return I64HashSet.of(self.allocator, self.items);
    }

    pub fn eql(self: *const ImmutableI64HashSet, other: *const ImmutableI64HashSet) bool {
        if (self.items.len != other.items.len) return false;
        for (self.items) |item| {
            if (!other.contains(item)) return false;
        }
        return true;
    }
};

test "ImmutableI64HashSet: of and contains" {
    var il = ImmutableI64HashSet.of(std.testing.allocator, &[_]i64{ 1, 2, 1 });
    defer il.deinit();
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expect(il.contains(1));
}

test "ImmutableI64HashSet: toMutable independence" {
    var il = ImmutableI64HashSet.of(std.testing.allocator, &[_]i64{ 1, 2 });
    defer il.deinit();
    var ml = il.toMutable();
    defer ml.deinit();
    _ = ml.add(3);
    try std.testing.expectEqual(@as(usize, 2), il.len());
    try std.testing.expectEqual(@as(usize, 3), ml.len());
}
