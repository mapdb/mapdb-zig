// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const I64BoolHashMap = @import("../hashmap/hashmap.zig").I64BoolHashMap;

/// Immutable hash map from `i64` keys to `bool` values.
///
/// Backed by a snapshot of the internal hash map. All operations are read-only.
pub const ImmutableI64BoolHashMap = struct {
    inner: OpenHashMap(i64, bool),
    allocator: Allocator,

    pub fn fromMutable(allocator: Allocator, mutable: *const I64BoolHashMap) ImmutableI64BoolHashMap {
        var inner = OpenHashMap(i64, bool).init(allocator, allocator, allocator) catch @panic("out of memory");
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) {
                _ = inner.put(mutable.inner.entries[i].key, mutable.inner.entries[i].value) catch @panic("out of memory");
            }
        }
        return .{ .inner = inner, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableI64BoolHashMap) void {
        self.inner.deinit();
    }

    pub fn get(self: *const ImmutableI64BoolHashMap, key: i64) ?bool {
        return self.inner.get(key);
    }

    pub fn getOrDefault(self: *const ImmutableI64BoolHashMap, key: i64, default_value: bool) bool {
        return self.get(key) orelse default_value;
    }

    pub fn containsKey(self: *const ImmutableI64BoolHashMap, key: i64) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const ImmutableI64BoolHashMap, value: bool) bool {
        return self.inner.containsValue(value);
    }

    pub fn len(self: *const ImmutableI64BoolHashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const ImmutableI64BoolHashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn toMutable(self: *const ImmutableI64BoolHashMap) I64BoolHashMap {
        var mutable = I64BoolHashMap.init(self.allocator);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                _ = mutable.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return mutable;
    }

    pub fn eql(self: *const ImmutableI64BoolHashMap, other: *const ImmutableI64BoolHashMap) bool {
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

test "ImmutableI64BoolHashMap: fromMutable and get" {
    var mm = I64BoolHashMap.init(std.testing.allocator);
    defer mm.deinit();
    _ = mm.put(1, true);
    _ = mm.put(2, false);
    var im = ImmutableI64BoolHashMap.fromMutable(std.testing.allocator, &mm);
    defer im.deinit();
    try std.testing.expectEqual(@as(?bool, true), im.get(1));
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "ImmutableI64BoolHashMap: toMutable independence" {
    var mm = I64BoolHashMap.init(std.testing.allocator);
    _ = mm.put(1, true);
    var im = ImmutableI64BoolHashMap.fromMutable(std.testing.allocator, &mm);
    mm.deinit();
    defer im.deinit();
    var mm2 = im.toMutable();
    defer mm2.deinit();
    _ = mm2.put(2, false);
    try std.testing.expectEqual(@as(usize, 1), im.len());
    try std.testing.expectEqual(@as(usize, 2), mm2.len());
}
