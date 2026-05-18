// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const I16CharHashMap = @import("../hashmap/i16_char_hash_map.zig").I16CharHashMap;

/// Immutable hash map from `i16` keys to `u21` values.
///
/// Backed by a snapshot of the internal hash map. All operations are read-only.
pub const ImmutableI16CharHashMap = struct {
    inner: OpenHashMap(i16, u21),
    allocator: Allocator,

    pub fn fromMutable(allocator: Allocator, mutable: *const I16CharHashMap) ImmutableI16CharHashMap {
        var inner = OpenHashMap(i16, u21).init(allocator, allocator, allocator) catch @panic("out of memory");
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) {
                _ = inner.put(mutable.inner.entries[i].key, mutable.inner.entries[i].value) catch @panic("out of memory");
            }
        }
        return .{ .inner = inner, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableI16CharHashMap) void {
        self.inner.deinit();
    }

    pub fn get(self: *const ImmutableI16CharHashMap, key: i16) ?u21 {
        return self.inner.get(key);
    }

    pub fn getOrDefault(self: *const ImmutableI16CharHashMap, key: i16, default_value: u21) u21 {
        return self.get(key) orelse default_value;
    }

    pub fn containsKey(self: *const ImmutableI16CharHashMap, key: i16) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const ImmutableI16CharHashMap, value: u21) bool {
        return self.inner.containsValue(value);
    }

    pub fn len(self: *const ImmutableI16CharHashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const ImmutableI16CharHashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn toMutable(self: *const ImmutableI16CharHashMap) I16CharHashMap {
        var mutable = I16CharHashMap.init(self.allocator);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                _ = mutable.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return mutable;
    }

    pub fn eql(self: *const ImmutableI16CharHashMap, other: *const ImmutableI16CharHashMap) bool {
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

test "ImmutableI16CharHashMap: fromMutable and get" {
    var mm = I16CharHashMap.init(std.testing.allocator);
    defer mm.deinit();
    _ = mm.put(1, 'a');
    _ = mm.put(2, 'b');
    var im = ImmutableI16CharHashMap.fromMutable(std.testing.allocator, &mm);
    defer im.deinit();
    try std.testing.expectEqual(@as(?u21, 'a'), im.get(1));
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "ImmutableI16CharHashMap: toMutable independence" {
    var mm = I16CharHashMap.init(std.testing.allocator);
    _ = mm.put(1, 'a');
    var im = ImmutableI16CharHashMap.fromMutable(std.testing.allocator, &mm);
    mm.deinit();
    defer im.deinit();
    var mm2 = im.toMutable();
    defer mm2.deinit();
    _ = mm2.put(2, 'b');
    try std.testing.expectEqual(@as(usize, 1), im.len());
    try std.testing.expectEqual(@as(usize, 2), mm2.len());
}
