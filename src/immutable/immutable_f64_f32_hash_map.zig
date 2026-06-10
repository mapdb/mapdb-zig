// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const F64F32HashMap = @import("../hashmap/hashmap.zig").F64F32HashMap;

/// Immutable hash map from `f64` keys to `f32` values.
///
/// Backed by a snapshot of the internal hash map. All operations are read-only.
pub const ImmutableF64F32HashMap = struct {
    inner: OpenHashMap(f64, f32),
    allocator: Allocator,

    pub fn fromMutable(allocator: Allocator, mutable: *const F64F32HashMap) ImmutableF64F32HashMap {
        var inner = OpenHashMap(f64, f32).init(allocator, allocator, allocator) catch @panic("out of memory");
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) {
                _ = inner.put(mutable.inner.entries[i].key, mutable.inner.entries[i].value) catch @panic("out of memory");
            }
        }
        return .{ .inner = inner, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableF64F32HashMap) void {
        self.inner.deinit();
    }

    pub fn get(self: *const ImmutableF64F32HashMap, key: f64) ?f32 {
        return self.inner.get(key);
    }

    pub fn getOrDefault(self: *const ImmutableF64F32HashMap, key: f64, default_value: f32) f32 {
        return self.get(key) orelse default_value;
    }

    pub fn containsKey(self: *const ImmutableF64F32HashMap, key: f64) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const ImmutableF64F32HashMap, value: f32) bool {
        return self.inner.containsValue(value);
    }

    pub fn len(self: *const ImmutableF64F32HashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const ImmutableF64F32HashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn toMutable(self: *const ImmutableF64F32HashMap) F64F32HashMap {
        var mutable = F64F32HashMap.init(self.allocator);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                _ = mutable.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return mutable;
    }

    pub fn eql(self: *const ImmutableF64F32HashMap, other: *const ImmutableF64F32HashMap) bool {
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

test "ImmutableF64F32HashMap: fromMutable and get" {
    var mm = F64F32HashMap.init(std.testing.allocator);
    defer mm.deinit();
    _ = mm.put(1.0, 1.0);
    _ = mm.put(2.0, 2.0);
    var im = ImmutableF64F32HashMap.fromMutable(std.testing.allocator, &mm);
    defer im.deinit();
    try std.testing.expectEqual(@as(?f32, 1.0), im.get(1.0));
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "ImmutableF64F32HashMap: toMutable independence" {
    var mm = F64F32HashMap.init(std.testing.allocator);
    _ = mm.put(1.0, 1.0);
    var im = ImmutableF64F32HashMap.fromMutable(std.testing.allocator, &mm);
    mm.deinit();
    defer im.deinit();
    var mm2 = im.toMutable();
    defer mm2.deinit();
    _ = mm2.put(2.0, 2.0);
    try std.testing.expectEqual(@as(usize, 1), im.len());
    try std.testing.expectEqual(@as(usize, 2), mm2.len());
}
