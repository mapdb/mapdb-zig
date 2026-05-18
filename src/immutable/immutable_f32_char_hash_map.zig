
const std = @import("std");
const Allocator = std.mem.Allocator;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const F32CharHashMap = @import("../hashmap/f32_char_hash_map.zig").F32CharHashMap;

/// Immutable hash map from `f32` keys to `u21` values.
///
/// Backed by a snapshot of the internal hash map. All operations are read-only.
pub const ImmutableF32CharHashMap = struct {
    inner: OpenHashMap(f32, u21),
    allocator: Allocator,

    pub fn fromMutable(allocator: Allocator, mutable: *const F32CharHashMap) ImmutableF32CharHashMap {
        var inner = OpenHashMap(f32, u21).init(allocator, allocator, allocator) catch @panic("out of memory");
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) {
                _ = inner.put(mutable.inner.entries[i].key, mutable.inner.entries[i].value) catch @panic("out of memory");
            }
        }
        return .{ .inner = inner, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableF32CharHashMap) void {
        self.inner.deinit();
    }

    pub fn get(self: *const ImmutableF32CharHashMap, key: f32) ?u21 {
        return self.inner.get(key);
    }

    pub fn getOrDefault(self: *const ImmutableF32CharHashMap, key: f32, default_value: u21) u21 {
        return self.get(key) orelse default_value;
    }

    pub fn containsKey(self: *const ImmutableF32CharHashMap, key: f32) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const ImmutableF32CharHashMap, value: u21) bool {
        return self.inner.containsValue(value);
    }

    pub fn len(self: *const ImmutableF32CharHashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const ImmutableF32CharHashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn toMutable(self: *const ImmutableF32CharHashMap) F32CharHashMap {
        var mutable = F32CharHashMap.init(self.allocator);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                _ = mutable.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return mutable;
    }

    pub fn eql(self: *const ImmutableF32CharHashMap, other: *const ImmutableF32CharHashMap) bool {
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

test "ImmutableF32CharHashMap: fromMutable and get" {
    var mm = F32CharHashMap.init(std.testing.allocator);
    defer mm.deinit();
    _ = mm.put(1.0, 'a');
    _ = mm.put(2.0, 'b');
    var im = ImmutableF32CharHashMap.fromMutable(std.testing.allocator, &mm);
    defer im.deinit();
    try std.testing.expectEqual(@as(?u21, 'a'), im.get(1.0));
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "ImmutableF32CharHashMap: toMutable independence" {
    var mm = F32CharHashMap.init(std.testing.allocator);
    _ = mm.put(1.0, 'a');
    var im = ImmutableF32CharHashMap.fromMutable(std.testing.allocator, &mm);
    mm.deinit();
    defer im.deinit();
    var mm2 = im.toMutable();
    defer mm2.deinit();
    _ = mm2.put(2.0, 'b');
    try std.testing.expectEqual(@as(usize, 1), im.len());
    try std.testing.expectEqual(@as(usize, 2), mm2.len());
}
