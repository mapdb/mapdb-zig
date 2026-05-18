
const std = @import("std");
const Allocator = std.mem.Allocator;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const I32HashBag = @import("../bag/i32_hash_bag.zig").I32HashBag;

/// Immutable bag (multiset) of `i32` values with occurrence counting.
///
/// Backed by a snapshot of the counts map. All operations are read-only.
pub const ImmutableI32HashBag = struct {
    counts: OpenHashMap(i32, usize),
    size: usize,
    allocator: Allocator,

    pub fn of(allocator: Allocator, values: []const i32) ImmutableI32HashBag {
        var mutable = I32HashBag.init(allocator);
        for (values) |val| mutable.add(val);
        const result = fromMutable(allocator, &mutable);
        mutable.deinit();
        return result;
    }

    pub fn fromMutable(allocator: Allocator, mutable: *const I32HashBag) ImmutableI32HashBag {
        var counts = OpenHashMap(i32, usize).init(allocator, allocator, allocator) catch @panic("out of memory");
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

    pub fn deinit(self: *ImmutableI32HashBag) void {
        self.counts.deinit();
    }

    pub fn occurrencesOf(self: *const ImmutableI32HashBag, value: i32) usize {
        return self.counts.get(value) orelse 0;
    }

    pub fn contains(self: *const ImmutableI32HashBag, value: i32) bool {
        return self.occurrencesOf(value) > 0;
    }

    pub fn totalSize(self: *const ImmutableI32HashBag) usize {
        return self.size;
    }

    pub fn sizeDistinct(self: *const ImmutableI32HashBag) usize {
        return self.counts.len();
    }

    pub fn isEmpty(self: *const ImmutableI32HashBag) bool {
        return self.size == 0;
    }

    pub fn len(self: *const ImmutableI32HashBag) usize {
        return self.size;
    }

    pub fn toSlice(self: *const ImmutableI32HashBag) []const i32 {
        _ = self;
        // Not directly applicable for bags; use toMutable().
        return &[_]i32{};
    }

    pub fn toMutable(self: *const ImmutableI32HashBag) I32HashBag {
        var mutable = I32HashBag.init(self.allocator);
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

test "ImmutableI32HashBag: of and occurrences" {
    var ib = ImmutableI32HashBag.of(std.testing.allocator, &[_]i32{ 1, 1, 2 });
    defer ib.deinit();
    try std.testing.expectEqual(@as(usize, 2), ib.occurrencesOf(1));
    try std.testing.expectEqual(@as(usize, 1), ib.occurrencesOf(2));
    try std.testing.expectEqual(@as(usize, 3), ib.totalSize());
    try std.testing.expectEqual(@as(usize, 2), ib.sizeDistinct());
}

test "ImmutableI32HashBag: toMutable independence" {
    var ib = ImmutableI32HashBag.of(std.testing.allocator, &[_]i32{ 1, 1 });
    defer ib.deinit();
    var mb = ib.toMutable();
    defer mb.deinit();
    mb.add(2);
    try std.testing.expectEqual(@as(usize, 2), ib.totalSize());
    try std.testing.expectEqual(@as(usize, 3), mb.totalSize());
}
