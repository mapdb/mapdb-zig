
const std = @import("std");
const Allocator = std.mem.Allocator;
const BitSet = @import("../bitset/bit_set.zig").BitSet;

/// Immutable bit-packed storage for booleans. Wraps an owned word slice.
/// All "mutating" operations return new immutable BitSets.
pub const ImmutableBitSet = struct {
    words: []const u64,
    bit_length: usize,
    allocator: Allocator,

    const BITS_PER_WORD: usize = 64;

    pub fn empty(allocator: Allocator) ImmutableBitSet {
        const owned = allocator.alloc(u64, 0) catch @panic("out of memory");
        return .{ .words = owned, .bit_length = 0, .allocator = allocator };
    }

    /// Copies the words of `mutable` into an owned slice.
    pub fn fromMutable(allocator: Allocator, mutable: *const BitSet) ImmutableBitSet {
        const owned = allocator.dupe(u64, mutable.words.items) catch @panic("out of memory");
        return .{ .words = owned, .bit_length = mutable.bit_length, .allocator = allocator };
    }

    pub fn deinit(self: *ImmutableBitSet) void {
        self.allocator.free(self.words);
    }

    inline fn wordIndex(bit: usize) usize {
        return bit / BITS_PER_WORD;
    }
    inline fn wordMask(bit: usize) u64 {
        return @as(u64, 1) << @intCast(bit % BITS_PER_WORD);
    }

    pub fn get(self: *const ImmutableBitSet, bit: usize) bool {
        const wi = wordIndex(bit);
        if (wi >= self.words.len) return false;
        return (self.words[wi] & wordMask(bit)) != 0;
    }

    pub fn len(self: *const ImmutableBitSet) usize {
        return self.bit_length;
    }

    pub fn cardinality(self: *const ImmutableBitSet) usize {
        if (self.bit_length == 0) return 0;
        const last_idx = wordIndex(self.bit_length - 1);
        var count: usize = 0;
        for (self.words, 0..) |w, i| {
            if (i < last_idx) {
                count += @popCount(w);
            } else if (i == last_idx) {
                const rem = self.bit_length - i * BITS_PER_WORD;
                const mask: u64 = if (rem == BITS_PER_WORD) ~@as(u64, 0) else (@as(u64, 1) << @intCast(rem)) - 1;
                count += @popCount(w & mask);
            }
        }
        return count;
    }

    pub fn isEmpty(self: *const ImmutableBitSet) bool {
        return self.cardinality() == 0;
    }

    pub fn toMutable(self: *const ImmutableBitSet) BitSet {
        var m = BitSet.init(self.allocator);
        m.words.appendSlice(self.allocator, self.words) catch @panic("out of memory");
        m.bit_length = self.bit_length;
        return m;
    }

    /// Returns a new immutable BitSet with `bit` set to 1.
    pub fn withBit(self: *const ImmutableBitSet, bit: usize) ImmutableBitSet {
        var m = self.toMutable();
        defer m.deinit();
        m.set(bit);
        return fromMutable(self.allocator, &m);
    }

    /// Returns a new immutable BitSet with `bit` cleared.
    pub fn withoutBit(self: *const ImmutableBitSet, bit: usize) ImmutableBitSet {
        var m = self.toMutable();
        defer m.deinit();
        m.clearBit(bit);
        return fromMutable(self.allocator, &m);
    }

    pub fn eql(self: *const ImmutableBitSet, other: *const ImmutableBitSet) bool {
        if (self.bit_length != other.bit_length) return false;
        const n = @min(self.words.len, other.words.len);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            if (self.words[i] != other.words[i]) return false;
        }
        // Any trailing words must be zero.
        var j: usize = n;
        while (j < self.words.len) : (j += 1) if (self.words[j] != 0) return false;
        j = n;
        while (j < other.words.len) : (j += 1) if (other.words[j] != 0) return false;
        return true;
    }
};

test "ImmutableBitSet: empty" {
    var b = ImmutableBitSet.empty(std.testing.allocator);
    defer b.deinit();
    try std.testing.expect(b.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), b.len());
    try std.testing.expect(!b.get(0));
}

test "ImmutableBitSet: fromMutable and get" {
    var m = BitSet.init(std.testing.allocator);
    defer m.deinit();
    m.set(3);
    m.set(65);
    var im = ImmutableBitSet.fromMutable(std.testing.allocator, &m);
    defer im.deinit();
    try std.testing.expect(im.get(3));
    try std.testing.expect(im.get(65));
    try std.testing.expect(!im.get(4));
    try std.testing.expectEqual(@as(usize, 2), im.cardinality());
}

test "ImmutableBitSet: persistent withBit/withoutBit" {
    var m = BitSet.init(std.testing.allocator);
    defer m.deinit();
    m.set(1);
    var b1 = ImmutableBitSet.fromMutable(std.testing.allocator, &m);
    defer b1.deinit();
    var b2 = b1.withBit(5);
    defer b2.deinit();
    var b3 = b2.withoutBit(1);
    defer b3.deinit();
    try std.testing.expect(b1.get(1));
    try std.testing.expect(!b1.get(5));
    try std.testing.expect(b2.get(1) and b2.get(5));
    try std.testing.expect(!b3.get(1) and b3.get(5));
}

test "ImmutableBitSet: toMutable independence" {
    var m = BitSet.init(std.testing.allocator);
    defer m.deinit();
    m.set(2);
    var im = ImmutableBitSet.fromMutable(std.testing.allocator, &m);
    defer im.deinit();
    var m2 = im.toMutable();
    defer m2.deinit();
    m2.set(10);
    try std.testing.expect(!im.get(10));
    try std.testing.expect(m2.get(10));
}
