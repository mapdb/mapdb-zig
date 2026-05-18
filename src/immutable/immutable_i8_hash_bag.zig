// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const I8HashBag = @import("../bag/i8_hash_bag.zig").I8HashBag;

/// Immutable bag (multiset) of `i8` values with occurrence counting.
///
/// Backed by a snapshot of the counts map. All operations are read-only.
pub const ImmutableI8HashBag = struct {
    counts: OpenHashMap(i8, usize),
    size: usize,
    allocator: Allocator,

    pub fn of(allocator: Allocator, values: []const i8) ImmutableI8HashBag {
        var mutable = I8HashBag.init(allocator);
        for (values) |val| mutable.add(val);
        const result = fromMutable(allocator, &mutable);
        mutable.deinit();
        return result;
    }

    pub fn fromMutable(allocator: Allocator, mutable: *const I8HashBag) ImmutableI8HashBag {
        var counts = OpenHashMap(i8, usize).init(allocator, allocator, allocator) catch @panic("out of memory");
        for (0..mutable.counts.capacity) |i| {
            if (mutable.counts.entries[i].occupied) {
                _ = counts.put(mutable.counts.entries[i].key, mutable.counts.entries[i].value) catch @panic("out of memory");
            }
        }
        return .{
            .counts = counts,
            .size = mutable.size,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ImmutableI8HashBag) void {
        self.counts.deinit();
    }

    pub fn occurrencesOf(self: *const ImmutableI8HashBag, value: i8) usize {
        return self.counts.get(value) orelse 0;
    }

    pub fn contains(self: *const ImmutableI8HashBag, value: i8) bool {
        return self.occurrencesOf(value) > 0;
    }

    pub fn totalSize(self: *const ImmutableI8HashBag) usize {
        return self.size;
    }

    pub fn sizeDistinct(self: *const ImmutableI8HashBag) usize {
        return self.counts.len();
    }

    pub fn isEmpty(self: *const ImmutableI8HashBag) bool {
        return self.size == 0;
    }

    pub fn len(self: *const ImmutableI8HashBag) usize {
        return self.size;
    }

    pub fn toSlice(self: *const ImmutableI8HashBag) []const i8 {
        _ = self;
        // Not directly applicable for bags; use toMutable().
        return &[_]i8{};
    }

    pub fn toMutable(self: *const ImmutableI8HashBag) I8HashBag {
        var mutable = I8HashBag.init(self.allocator);
        for (0..self.counts.capacity) |i| {
            if (self.counts.entries[i].occupied) {
                var j: usize = 0;
                while (j < self.counts.entries[i].value) : (j += 1) {
                    mutable.add(self.counts.entries[i].key);
                }
            }
        }
        return mutable;
    }
};

test "ImmutableI8HashBag: of and occurrences" {
    var ib = ImmutableI8HashBag.of(std.testing.allocator, &[_]i8{ 1, 1, 2 });
    defer ib.deinit();
    try std.testing.expectEqual(@as(usize, 2), ib.occurrencesOf(1));
    try std.testing.expectEqual(@as(usize, 1), ib.occurrencesOf(2));
    try std.testing.expectEqual(@as(usize, 3), ib.totalSize());
    try std.testing.expectEqual(@as(usize, 2), ib.sizeDistinct());
}

test "ImmutableI8HashBag: toMutable independence" {
    var ib = ImmutableI8HashBag.of(std.testing.allocator, &[_]i8{ 1, 1 });
    defer ib.deinit();
    var mb = ib.toMutable();
    defer mb.deinit();
    mb.add(2);
    try std.testing.expectEqual(@as(usize, 2), ib.totalSize());
    try std.testing.expectEqual(@as(usize, 3), mb.totalSize());
}
