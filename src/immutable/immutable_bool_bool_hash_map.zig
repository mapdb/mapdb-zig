// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const BoolBoolHashMap = @import("../hashmap/hashmap.zig").BoolBoolHashMap;

/// Immutable hash map from `bool` keys to `bool` values.
///
/// Backed by a snapshot of the internal hash map. All operations are read-only.
pub const ImmutableBoolBoolHashMap = struct {
    inner: OpenHashMap(bool, bool),
    allocator: Allocator,

    pub fn fromMutable(allocator: Allocator, mutable: *const BoolBoolHashMap) ImmutableBoolBoolHashMap {
        var inner = OpenHashMap(bool, bool).init(allocator, allocator, allocator) catch @panic("out of memory");
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) {
                _ = inner.put(mutable.inner.entries[i].key, mutable.inner.entries[i].value) catch @panic("out of memory");
            }
        }
        return .{ .inner = inner, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableBoolBoolHashMap) void {
        self.inner.deinit();
    }

    pub fn get(self: *const ImmutableBoolBoolHashMap, key: bool) ?bool {
        return self.inner.get(key);
    }

    pub fn getOrDefault(self: *const ImmutableBoolBoolHashMap, key: bool, default_value: bool) bool {
        return self.get(key) orelse default_value;
    }

    pub fn containsKey(self: *const ImmutableBoolBoolHashMap, key: bool) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const ImmutableBoolBoolHashMap, value: bool) bool {
        return self.inner.containsValue(value);
    }

    pub fn len(self: *const ImmutableBoolBoolHashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const ImmutableBoolBoolHashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn toMutable(self: *const ImmutableBoolBoolHashMap) BoolBoolHashMap {
        var mutable = BoolBoolHashMap.init(self.allocator);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                _ = mutable.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return mutable;
    }

    pub fn eql(self: *const ImmutableBoolBoolHashMap, other: *const ImmutableBoolBoolHashMap) bool {
        if (self.len() != other.len()) return false;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const other_val = other.get(self.inner.entries[i].key) orelse return false;
                if (!(self.inner.entries[i].value == other_val)) return false;
            }
        }
        return true;
    }
};

test "ImmutableBoolBoolHashMap: fromMutable and get" {
    var mm = BoolBoolHashMap.init(std.testing.allocator);
    defer mm.deinit();
    _ = mm.put(true, true);
    _ = mm.put(false, false);
    var im = ImmutableBoolBoolHashMap.fromMutable(std.testing.allocator, &mm);
    defer im.deinit();
    try std.testing.expectEqual(@as(?bool, true), im.get(true));
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "ImmutableBoolBoolHashMap: toMutable independence" {
    var mm = BoolBoolHashMap.init(std.testing.allocator);
    _ = mm.put(true, true);
    var im = ImmutableBoolBoolHashMap.fromMutable(std.testing.allocator, &mm);
    mm.deinit();
    defer im.deinit();
    var mm2 = im.toMutable();
    defer mm2.deinit();
    _ = mm2.put(false, false);
    try std.testing.expectEqual(@as(usize, 1), im.len());
    try std.testing.expectEqual(@as(usize, 2), mm2.len());
}
