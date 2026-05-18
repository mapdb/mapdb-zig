
const std = @import("std");
const Allocator = std.mem.Allocator;
const OpenHashMap = @import("../hash_table.zig").OpenHashMap;
const CharBoolHashMap = @import("../hashmap/char_bool_hash_map.zig").CharBoolHashMap;

/// Immutable hash map from `u21` keys to `bool` values.
///
/// Backed by a snapshot of the internal hash map. All operations are read-only.
pub const ImmutableCharBoolHashMap = struct {
    inner: OpenHashMap(u21, bool),
    allocator: Allocator,

    pub fn fromMutable(allocator: Allocator, mutable: *const CharBoolHashMap) ImmutableCharBoolHashMap {
        var inner = OpenHashMap(u21, bool).init(allocator, allocator, allocator) catch @panic("out of memory");
        for (0..mutable.inner.capacity) |i| {
            if (mutable.inner.entries[i].occupied) {
                _ = inner.put(mutable.inner.entries[i].key, mutable.inner.entries[i].value) catch @panic("out of memory");
            }
        }
        return .{ .inner = inner, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableCharBoolHashMap) void {
        self.inner.deinit();
    }

    pub fn get(self: *const ImmutableCharBoolHashMap, key: u21) ?bool {
        return self.inner.get(key);
    }

    pub fn getOrDefault(self: *const ImmutableCharBoolHashMap, key: u21, default_value: bool) bool {
        return self.get(key) orelse default_value;
    }

    pub fn containsKey(self: *const ImmutableCharBoolHashMap, key: u21) bool {
        return self.inner.containsKey(key);
    }

    pub fn containsValue(self: *const ImmutableCharBoolHashMap, value: bool) bool {
        return self.inner.containsValue(value);
    }

    pub fn len(self: *const ImmutableCharBoolHashMap) usize {
        return self.inner.len();
    }

    pub fn isEmpty(self: *const ImmutableCharBoolHashMap) bool {
        return self.inner.isEmpty();
    }

    pub fn toMutable(self: *const ImmutableCharBoolHashMap) CharBoolHashMap {
        var mutable = CharBoolHashMap.init(self.allocator);
        for (0..self.inner.capacity) |i| {
            if (self.inner.entries[i].occupied) {
                _ = mutable.put(self.inner.entries[i].key, self.inner.entries[i].value);
            }
        }
        return mutable;
    }

    pub fn eql(self: *const ImmutableCharBoolHashMap, other: *const ImmutableCharBoolHashMap) bool {
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

test "ImmutableCharBoolHashMap: fromMutable and get" {
    var mm = CharBoolHashMap.init(std.testing.allocator);
    defer mm.deinit();
    _ = mm.put('a', true);
    _ = mm.put('b', false);
    var im = ImmutableCharBoolHashMap.fromMutable(std.testing.allocator, &mm);
    defer im.deinit();
    try std.testing.expectEqual(@as(?bool, true), im.get('a'));
    try std.testing.expectEqual(@as(usize, 2), im.len());
}

test "ImmutableCharBoolHashMap: toMutable independence" {
    var mm = CharBoolHashMap.init(std.testing.allocator);
    _ = mm.put('a', true);
    var im = ImmutableCharBoolHashMap.fromMutable(std.testing.allocator, &mm);
    mm.deinit();
    defer im.deinit();
    var mm2 = im.toMutable();
    defer mm2.deinit();
    _ = mm2.put('b', false);
    try std.testing.expectEqual(@as(usize, 1), im.len());
    try std.testing.expectEqual(@as(usize, 2), mm2.len());
}
