
const std = @import("std");
const Allocator = std.mem.Allocator;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const BoolCharHashMap = @import("../hashmap/bool_char_hash_map.zig").BoolCharHashMap;

/// Immutable hash map from `bool` keys to `u21` values.
///
/// Backed by a snapshot of the internal hash map. All operations are read-only.
pub const ImmutableBoolCharHashMap = struct {
    inner: OpenHashMap(bool, u21),
    allocator: Allocator,

    pub fn fromMutable(allocator: Allocator, mutable: *const BoolCharHashMap) ImmutableBoolCharHashMap {
        var inner = OpenHashMap(bool, u21).init(allocator, allocator, allocator) catch @panic("out of memory");
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) {
                _ = inner.put(mutable.inner.entries[i].key, mutable.inner.entries[i].value) catch @panic("out of memory");
            }
        }
        return .{ .inner = inner, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableBoolCharHashMap) void {
        self.inner.deinit();
    }

    pub fn get(self: *const ImmutableBoolCharHashMap, key: bool) ?u21 {
        return self.inner.get(key);
    }

    pub fn getOrDefault(self: *const ImmutableBoolCharHashMap, key: bool, default_value: u21) u21 {
        return self.get(key) orelse default_value;
    }

    pub fn containsKey(self: *const ImmutableBoolCharHashMap, key: bool) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const ImmutableBoolCharHashMap, value: u21) bool {
        return self.inner.containsValue(value);
    }

    pub fn len(self: *const ImmutableBoolCharHashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const ImmutableBoolCharHashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn toMutable(self: *const ImmutableBoolCharHashMap) BoolCharHashMap {
        var mutable = BoolCharHashMap.init(self.allocator);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                _ = mutable.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return mutable;
    }

    pub fn eql(self: *const ImmutableBoolCharHashMap, other: *const ImmutableBoolCharHashMap) bool {
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

test "ImmutableBoolCharHashMap: fromMutable and get" {
    var mm = BoolCharHashMap.init(std.testing.allocator);
    defer mm.deinit();
    _ = mm.put(true, 'a');
    _ = mm.put(false, 'b');
    var im = ImmutableBoolCharHashMap.fromMutable(std.testing.allocator, &mm);
    defer im.deinit();
    try std.testing.expectEqual(@as(?u21, 'a'), im.get(true));
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "ImmutableBoolCharHashMap: toMutable independence" {
    var mm = BoolCharHashMap.init(std.testing.allocator);
    _ = mm.put(true, 'a');
    var im = ImmutableBoolCharHashMap.fromMutable(std.testing.allocator, &mm);
    mm.deinit();
    defer im.deinit();
    var mm2 = im.toMutable();
    defer mm2.deinit();
    _ = mm2.put(false, 'b');
    try std.testing.expectEqual(@as(usize, 1), im.len());
    try std.testing.expectEqual(@as(usize, 2), mm2.len());
}
