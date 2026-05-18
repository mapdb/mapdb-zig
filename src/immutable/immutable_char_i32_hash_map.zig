// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const CharI32HashMap = @import("../hashmap/char_i32_hash_map.zig").CharI32HashMap;

/// Immutable hash map from `u21` keys to `i32` values.
///
/// Backed by a snapshot of the internal hash map. All operations are read-only.
pub const ImmutableCharI32HashMap = struct {
    inner: OpenHashMap(u21, i32),
    allocator: Allocator,

    pub fn fromMutable(allocator: Allocator, mutable: *const CharI32HashMap) ImmutableCharI32HashMap {
        var inner = OpenHashMap(u21, i32).init(allocator, allocator, allocator) catch @panic("out of memory");
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) {
                _ = inner.put(mutable.inner.entries[i].key, mutable.inner.entries[i].value) catch @panic("out of memory");
            }
        }
        return .{ .inner = inner, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableCharI32HashMap) void {
        self.inner.deinit();
    }

    pub fn get(self: *const ImmutableCharI32HashMap, key: u21) ?i32 {
        return self.inner.get(key);
    }

    pub fn getOrDefault(self: *const ImmutableCharI32HashMap, key: u21, default_value: i32) i32 {
        return self.get(key) orelse default_value;
    }

    pub fn containsKey(self: *const ImmutableCharI32HashMap, key: u21) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const ImmutableCharI32HashMap, value: i32) bool {
        return self.inner.containsValue(value);
    }

    pub fn len(self: *const ImmutableCharI32HashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const ImmutableCharI32HashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn toMutable(self: *const ImmutableCharI32HashMap) CharI32HashMap {
        var mutable = CharI32HashMap.init(self.allocator);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                _ = mutable.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return mutable;
    }

    pub fn eql(self: *const ImmutableCharI32HashMap, other: *const ImmutableCharI32HashMap) bool {
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

test "ImmutableCharI32HashMap: fromMutable and get" {
    var mm = CharI32HashMap.init(std.testing.allocator);
    defer mm.deinit();
    _ = mm.put('a', 1);
    _ = mm.put('b', 2);
    var im = ImmutableCharI32HashMap.fromMutable(std.testing.allocator, &mm);
    defer im.deinit();
    try std.testing.expectEqual(@as(?i32, 1), im.get('a'));
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "ImmutableCharI32HashMap: toMutable independence" {
    var mm = CharI32HashMap.init(std.testing.allocator);
    _ = mm.put('a', 1);
    var im = ImmutableCharI32HashMap.fromMutable(std.testing.allocator, &mm);
    mm.deinit();
    defer im.deinit();
    var mm2 = im.toMutable();
    defer mm2.deinit();
    _ = mm2.put('b', 2);
    try std.testing.expectEqual(@as(usize, 1), im.len());
    try std.testing.expectEqual(@as(usize, 2), mm2.len());
}
