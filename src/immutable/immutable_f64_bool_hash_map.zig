// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const F64BoolHashMap = @import("../hashmap/hashmap.zig").F64BoolHashMap;

/// Immutable hash map from `f64` keys to `bool` values.
///
/// Backed by a snapshot of the internal hash map. All operations are read-only.
pub const ImmutableF64BoolHashMap = struct {
    inner: OpenHashMap(f64, bool),
    allocator: Allocator,

    pub fn fromMutable(allocator: Allocator, mutable: *const F64BoolHashMap) ImmutableF64BoolHashMap {
        var inner = OpenHashMap(f64, bool).init(allocator, allocator, allocator) catch @panic("out of memory");
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) {
                _ = inner.put(mutable.inner.entries[i].key, mutable.inner.entries[i].value) catch @panic("out of memory");
            }
        }
        return .{ .inner = inner, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableF64BoolHashMap) void {
        self.inner.deinit();
    }

    pub fn get(self: *const ImmutableF64BoolHashMap, key: f64) ?bool {
        return self.inner.get(key);
    }

    pub fn getOrDefault(self: *const ImmutableF64BoolHashMap, key: f64, default_value: bool) bool {
        return self.get(key) orelse default_value;
    }

    pub fn containsKey(self: *const ImmutableF64BoolHashMap, key: f64) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const ImmutableF64BoolHashMap, value: bool) bool {
        return self.inner.containsValue(value);
    }

    pub fn len(self: *const ImmutableF64BoolHashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const ImmutableF64BoolHashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn toMutable(self: *const ImmutableF64BoolHashMap) F64BoolHashMap {
        var mutable = F64BoolHashMap.init(self.allocator);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                _ = mutable.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return mutable;
    }

    pub fn eql(self: *const ImmutableF64BoolHashMap, other: *const ImmutableF64BoolHashMap) bool {
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

test "ImmutableF64BoolHashMap: fromMutable and get" {
    var mm = F64BoolHashMap.init(std.testing.allocator);
    defer mm.deinit();
    _ = mm.put(1.0, true);
    _ = mm.put(2.0, false);
    var im = ImmutableF64BoolHashMap.fromMutable(std.testing.allocator, &mm);
    defer im.deinit();
    try std.testing.expectEqual(@as(?bool, true), im.get(1.0));
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "ImmutableF64BoolHashMap: toMutable independence" {
    var mm = F64BoolHashMap.init(std.testing.allocator);
    _ = mm.put(1.0, true);
    var im = ImmutableF64BoolHashMap.fromMutable(std.testing.allocator, &mm);
    mm.deinit();
    defer im.deinit();
    var mm2 = im.toMutable();
    defer mm2.deinit();
    _ = mm2.put(2.0, false);
    try std.testing.expectEqual(@as(usize, 1), im.len());
    try std.testing.expectEqual(@as(usize, 2), mm2.len());
}
