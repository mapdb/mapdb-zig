// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");
const Allocator = std.mem.Allocator;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const I16F64HashMap = @import("../hashmap/i16_f64_hash_map.zig").I16F64HashMap;

/// Immutable hash map from `i16` keys to `f64` values.
///
/// Backed by a snapshot of the internal hash map. All operations are read-only.
pub const ImmutableI16F64HashMap = struct {
    inner: OpenHashMap(i16, f64),
    allocator: Allocator,

    pub fn fromMutable(allocator: Allocator, mutable: *const I16F64HashMap) ImmutableI16F64HashMap {
        var inner = OpenHashMap(i16, f64).init(allocator, allocator, allocator) catch @panic("out of memory");
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) {
                _ = inner.put(mutable.inner.entries[i].key, mutable.inner.entries[i].value) catch @panic("out of memory");
            }
        }
        return .{ .inner = inner, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableI16F64HashMap) void {
        self.inner.deinit();
    }

    pub fn get(self: *const ImmutableI16F64HashMap, key: i16) ?f64 {
        return self.inner.get(key);
    }

    pub fn getOrDefault(self: *const ImmutableI16F64HashMap, key: i16, default_value: f64) f64 {
        return self.get(key) orelse default_value;
    }

    pub fn containsKey(self: *const ImmutableI16F64HashMap, key: i16) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const ImmutableI16F64HashMap, value: f64) bool {
        return self.inner.containsValue(value);
    }

    pub fn len(self: *const ImmutableI16F64HashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const ImmutableI16F64HashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn toMutable(self: *const ImmutableI16F64HashMap) I16F64HashMap {
        var mutable = I16F64HashMap.init(self.allocator);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                _ = mutable.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return mutable;
    }

    pub fn eql(self: *const ImmutableI16F64HashMap, other: *const ImmutableI16F64HashMap) bool {
        if (self.len() != other.len()) return false;
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                const other_val = other.get(self.inner.entries[i].key) orelse return false;
                if (!(@as(u64, @bitCast(self.inner.entries[i].value)) == @as(u64, @bitCast(other_val)))) return false;
            }
        }
        return true;
    }
};

test "ImmutableI16F64HashMap: fromMutable and get" {
    var mm = I16F64HashMap.init(std.testing.allocator);
    defer mm.deinit();
    _ = mm.put(1, 1.0);
    _ = mm.put(2, 2.0);
    var im = ImmutableI16F64HashMap.fromMutable(std.testing.allocator, &mm);
    defer im.deinit();
    try std.testing.expectEqual(@as(?f64, 1.0), im.get(1));
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "ImmutableI16F64HashMap: toMutable independence" {
    var mm = I16F64HashMap.init(std.testing.allocator);
    _ = mm.put(1, 1.0);
    var im = ImmutableI16F64HashMap.fromMutable(std.testing.allocator, &mm);
    mm.deinit();
    defer im.deinit();
    var mm2 = im.toMutable();
    defer mm2.deinit();
    _ = mm2.put(2, 2.0);
    try std.testing.expectEqual(@as(usize, 1), im.len());
    try std.testing.expectEqual(@as(usize, 2), mm2.len());
}
