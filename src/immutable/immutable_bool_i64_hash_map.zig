// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const BoolI64HashMap = @import("../hashmap/bool_i64_hash_map.zig").BoolI64HashMap;

/// Immutable hash map from `bool` keys to `i64` values.
///
/// Backed by a snapshot of the internal hash map. All operations are read-only.
pub const ImmutableBoolI64HashMap = struct {
    inner: OpenHashMap(bool, i64),
    allocator: Allocator,

    pub fn fromMutable(allocator: Allocator, mutable: *const BoolI64HashMap) ImmutableBoolI64HashMap {
        var inner = OpenHashMap(bool, i64).init(allocator, allocator, allocator) catch @panic("out of memory");
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) {
                _ = inner.put(mutable.inner.entries[i].key, mutable.inner.entries[i].value) catch @panic("out of memory");
            }
        }
        return .{ .inner = inner, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableBoolI64HashMap) void {
        self.inner.deinit();
    }

    pub fn get(self: *const ImmutableBoolI64HashMap, key: bool) ?i64 {
        return self.inner.get(key);
    }

    pub fn getOrDefault(self: *const ImmutableBoolI64HashMap, key: bool, default_value: i64) i64 {
        return self.get(key) orelse default_value;
    }

    pub fn containsKey(self: *const ImmutableBoolI64HashMap, key: bool) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const ImmutableBoolI64HashMap, value: i64) bool {
        return self.inner.containsValue(value);
    }

    pub fn len(self: *const ImmutableBoolI64HashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const ImmutableBoolI64HashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn toMutable(self: *const ImmutableBoolI64HashMap) BoolI64HashMap {
        var mutable = BoolI64HashMap.init(self.allocator);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                _ = mutable.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return mutable;
    }

    pub fn eql(self: *const ImmutableBoolI64HashMap, other: *const ImmutableBoolI64HashMap) bool {
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

test "ImmutableBoolI64HashMap: fromMutable and get" {
    var mm = BoolI64HashMap.init(std.testing.allocator);
    defer mm.deinit();
    _ = mm.put(true, 1);
    _ = mm.put(false, 2);
    var im = ImmutableBoolI64HashMap.fromMutable(std.testing.allocator, &mm);
    defer im.deinit();
    try std.testing.expectEqual(@as(?i64, 1), im.get(true));
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "ImmutableBoolI64HashMap: toMutable independence" {
    var mm = BoolI64HashMap.init(std.testing.allocator);
    _ = mm.put(true, 1);
    var im = ImmutableBoolI64HashMap.fromMutable(std.testing.allocator, &mm);
    mm.deinit();
    defer im.deinit();
    var mm2 = im.toMutable();
    defer mm2.deinit();
    _ = mm2.put(false, 2);
    try std.testing.expectEqual(@as(usize, 1), im.len());
    try std.testing.expectEqual(@as(usize, 2), mm2.len());
}
