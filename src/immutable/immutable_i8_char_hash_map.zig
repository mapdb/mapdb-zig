// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const I8CharHashMap = @import("../hashmap/hashmap.zig").I8CharHashMap;

/// Immutable hash map from `i8` keys to `u21` values.
///
/// Backed by a snapshot of the internal hash map. All operations are read-only.
pub const ImmutableI8CharHashMap = struct {
    inner: OpenHashMap(i8, u21),
    allocator: Allocator,

    pub fn fromMutable(allocator: Allocator, mutable: *const I8CharHashMap) ImmutableI8CharHashMap {
        var inner = OpenHashMap(i8, u21).init(allocator, allocator, allocator) catch @panic("out of memory");
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) {
                _ = inner.put(mutable.inner.entries[i].key, mutable.inner.entries[i].value) catch @panic("out of memory");
            }
        }
        return .{ .inner = inner, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableI8CharHashMap) void {
        self.inner.deinit();
    }

    pub fn get(self: *const ImmutableI8CharHashMap, key: i8) ?u21 {
        return self.inner.get(key);
    }

    pub fn getOrDefault(self: *const ImmutableI8CharHashMap, key: i8, default_value: u21) u21 {
        return self.get(key) orelse default_value;
    }

    pub fn containsKey(self: *const ImmutableI8CharHashMap, key: i8) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const ImmutableI8CharHashMap, value: u21) bool {
        return self.inner.containsValue(value);
    }

    pub fn len(self: *const ImmutableI8CharHashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const ImmutableI8CharHashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn toMutable(self: *const ImmutableI8CharHashMap) I8CharHashMap {
        var mutable = I8CharHashMap.init(self.allocator);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                _ = mutable.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return mutable;
    }

    pub fn eql(self: *const ImmutableI8CharHashMap, other: *const ImmutableI8CharHashMap) bool {
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

test "ImmutableI8CharHashMap: fromMutable and get" {
    var mm = I8CharHashMap.init(std.testing.allocator);
    defer mm.deinit();
    _ = mm.put(1, 'a');
    _ = mm.put(2, 'b');
    var im = ImmutableI8CharHashMap.fromMutable(std.testing.allocator, &mm);
    defer im.deinit();
    try std.testing.expectEqual(@as(?u21, 'a'), im.get(1));
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "ImmutableI8CharHashMap: toMutable independence" {
    var mm = I8CharHashMap.init(std.testing.allocator);
    _ = mm.put(1, 'a');
    var im = ImmutableI8CharHashMap.fromMutable(std.testing.allocator, &mm);
    mm.deinit();
    defer im.deinit();
    var mm2 = im.toMutable();
    defer mm2.deinit();
    _ = mm2.put(2, 'b');
    try std.testing.expectEqual(@as(usize, 1), im.len());
    try std.testing.expectEqual(@as(usize, 2), mm2.len());
}
