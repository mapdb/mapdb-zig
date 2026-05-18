// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const BoolF32HashMap = @import("../hashmap/bool_f32_hash_map.zig").BoolF32HashMap;

/// Immutable hash map from `bool` keys to `f32` values.
///
/// Backed by a snapshot of the internal hash map. All operations are read-only.
pub const ImmutableBoolF32HashMap = struct {
    inner: OpenHashMap(bool, f32),
    allocator: Allocator,

    pub fn fromMutable(allocator: Allocator, mutable: *const BoolF32HashMap) ImmutableBoolF32HashMap {
        var inner = OpenHashMap(bool, f32).init(allocator, allocator, allocator) catch @panic("out of memory");
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) {
                _ = inner.put(mutable.inner.entries[i].key, mutable.inner.entries[i].value) catch @panic("out of memory");
            }
        }
        return .{ .inner = inner, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableBoolF32HashMap) void {
        self.inner.deinit();
    }

    pub fn get(self: *const ImmutableBoolF32HashMap, key: bool) ?f32 {
        return self.inner.get(key);
    }

    pub fn getOrDefault(self: *const ImmutableBoolF32HashMap, key: bool, default_value: f32) f32 {
        return self.get(key) orelse default_value;
    }

    pub fn containsKey(self: *const ImmutableBoolF32HashMap, key: bool) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const ImmutableBoolF32HashMap, value: f32) bool {
        return self.inner.containsValue(value);
    }

    pub fn len(self: *const ImmutableBoolF32HashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const ImmutableBoolF32HashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn toMutable(self: *const ImmutableBoolF32HashMap) BoolF32HashMap {
        var mutable = BoolF32HashMap.init(self.allocator);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                _ = mutable.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return mutable;
    }

    pub fn eql(self: *const ImmutableBoolF32HashMap, other: *const ImmutableBoolF32HashMap) bool {
        if (self.len() != other.len()) return false;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const other_val = other.get(self.inner.entries[i].key) orelse return false;
                if (!(@as(u32, @bitCast(self.inner.entries[i].value)) == @as(u32, @bitCast(other_val)))) return false;
            }
        }
        return true;
    }
};

test "ImmutableBoolF32HashMap: fromMutable and get" {
    var mm = BoolF32HashMap.init(std.testing.allocator);
    defer mm.deinit();
    _ = mm.put(true, 1.0);
    _ = mm.put(false, 2.0);
    var im = ImmutableBoolF32HashMap.fromMutable(std.testing.allocator, &mm);
    defer im.deinit();
    try std.testing.expectEqual(@as(?f32, 1.0), im.get(true));
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "ImmutableBoolF32HashMap: toMutable independence" {
    var mm = BoolF32HashMap.init(std.testing.allocator);
    _ = mm.put(true, 1.0);
    var im = ImmutableBoolF32HashMap.fromMutable(std.testing.allocator, &mm);
    mm.deinit();
    defer im.deinit();
    var mm2 = im.toMutable();
    defer mm2.deinit();
    _ = mm2.put(false, 2.0);
    try std.testing.expectEqual(@as(usize, 1), im.len());
    try std.testing.expectEqual(@as(usize, 2), mm2.len());
}
