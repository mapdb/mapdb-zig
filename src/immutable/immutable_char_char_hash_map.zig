
const std = @import("std");
const Allocator = std.mem.Allocator;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const CharCharHashMap = @import("../hashmap/char_char_hash_map.zig").CharCharHashMap;

/// Immutable hash map from `u21` keys to `u21` values.
///
/// Backed by a snapshot of the internal hash map. All operations are read-only.
pub const ImmutableCharCharHashMap = struct {
    inner: OpenHashMap(u21, u21),
    allocator: Allocator,

    pub fn fromMutable(allocator: Allocator, mutable: *const CharCharHashMap) ImmutableCharCharHashMap {
        var inner = OpenHashMap(u21, u21).init(allocator, allocator, allocator) catch @panic("out of memory");
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) {
                _ = inner.put(mutable.inner.entries[i].key, mutable.inner.entries[i].value) catch @panic("out of memory");
            }
        }
        return .{ .inner = inner, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableCharCharHashMap) void {
        self.inner.deinit();
    }

    pub fn get(self: *const ImmutableCharCharHashMap, key: u21) ?u21 {
        return self.inner.get(key);
    }

    pub fn getOrDefault(self: *const ImmutableCharCharHashMap, key: u21, default_value: u21) u21 {
        return self.get(key) orelse default_value;
    }

    pub fn containsKey(self: *const ImmutableCharCharHashMap, key: u21) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const ImmutableCharCharHashMap, value: u21) bool {
        return self.inner.containsValue(value);
    }

    pub fn len(self: *const ImmutableCharCharHashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const ImmutableCharCharHashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn toMutable(self: *const ImmutableCharCharHashMap) CharCharHashMap {
        var mutable = CharCharHashMap.init(self.allocator);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                _ = mutable.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return mutable;
    }

    pub fn eql(self: *const ImmutableCharCharHashMap, other: *const ImmutableCharCharHashMap) bool {
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

test "ImmutableCharCharHashMap: fromMutable and get" {
    var mm = CharCharHashMap.init(std.testing.allocator);
    defer mm.deinit();
    _ = mm.put('a', 'a');
    _ = mm.put('b', 'b');
    var im = ImmutableCharCharHashMap.fromMutable(std.testing.allocator, &mm);
    defer im.deinit();
    try std.testing.expectEqual(@as(?u21, 'a'), im.get('a'));
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "ImmutableCharCharHashMap: toMutable independence" {
    var mm = CharCharHashMap.init(std.testing.allocator);
    _ = mm.put('a', 'a');
    var im = ImmutableCharCharHashMap.fromMutable(std.testing.allocator, &mm);
    mm.deinit();
    defer im.deinit();
    var mm2 = im.toMutable();
    defer mm2.deinit();
    _ = mm2.put('b', 'b');
    try std.testing.expectEqual(@as(usize, 1), im.len());
    try std.testing.expectEqual(@as(usize, 2), mm2.len());
}
