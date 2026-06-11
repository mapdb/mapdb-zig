// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Compact bit-packed storage for booleans. 64 bits per word.
/// O(1) set/clear/flip/get; cardinality and bitwise ops are O(n/64).
pub const BitSet = struct {
    words: std.ArrayListUnmanaged(u64) = .empty,
    bit_length: usize = 0,
    allocator: Allocator,

    const BITS_PER_WORD: usize = 64;

    pub fn init(allocator: Allocator) BitSet {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *BitSet) void {
        self.words.deinit(self.allocator);
    }

    pub fn withBitLength(allocator: Allocator, n_bits: usize) BitSet {
        var b = BitSet.init(allocator);
        const n_words = (n_bits + BITS_PER_WORD - 1) / BITS_PER_WORD;
        b.words.appendNTimes(b.allocator, 0, n_words) catch @panic("out of memory");
        b.bit_length = n_bits;
        return b;
    }

    inline fn wordIndex(bit: usize) usize {
        return bit / BITS_PER_WORD;
    }
    inline fn wordMask(bit: usize) u64 {
        return @as(u64, 1) << @intCast(bit % BITS_PER_WORD);
    }

    fn ensure(self: *BitSet, bit: usize) void {
        const needed = wordIndex(bit) + 1;
        while (self.words.items.len < needed) {
            self.words.append(self.allocator, 0) catch @panic("out of memory");
        }
        if (bit + 1 > self.bit_length) self.bit_length = bit + 1;
    }

    pub fn set(self: *BitSet, bit: usize) void {
        self.ensure(bit);
        self.words.items[wordIndex(bit)] |= wordMask(bit);
    }

    pub fn clearBit(self: *BitSet, bit: usize) void {
        if (wordIndex(bit) >= self.words.items.len) return;
        self.words.items[wordIndex(bit)] &= ~wordMask(bit);
    }

    pub fn flip(self: *BitSet, bit: usize) void {
        self.ensure(bit);
        self.words.items[wordIndex(bit)] ^= wordMask(bit);
    }

    pub fn get(self: *const BitSet, bit: usize) bool {
        const wi = wordIndex(bit);
        if (wi >= self.words.items.len) return false;
        return (self.words.items[wi] & wordMask(bit)) != 0;
    }

    pub fn cardinality(self: *const BitSet) usize {
        if (self.bit_length == 0) return 0;
        const last_idx = wordIndex(self.bit_length - 1);
        var count: usize = 0;
        for (self.words.items, 0..) |w, i| {
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

    pub fn len(self: *const BitSet) usize {
        return self.bit_length;
    }
    pub fn isEmpty(self: *const BitSet) bool {
        return self.cardinality() == 0;
    }

    pub fn clearAll(self: *BitSet) void {
        for (self.words.items) |*w| w.* = 0;
    }

    pub fn intersects(self: *const BitSet, other: *const BitSet) bool {
        const min = @min(self.words.items.len, other.words.items.len);
        var i: usize = 0;
        while (i < min) : (i += 1) {
            if ((self.words.items[i] & other.words.items[i]) != 0) return true;
        }
        return false;
    }

    pub fn andInPlace(self: *BitSet, other: *const BitSet) void {
        for (self.words.items, 0..) |*w, i| {
            const ow = if (i < other.words.items.len) other.words.items[i] else 0;
            w.* &= ow;
        }
    }

    pub fn orInPlace(self: *BitSet, other: *const BitSet) void {
        while (self.words.items.len < other.words.items.len) {
            self.words.append(self.allocator, 0) catch @panic("out of memory");
        }
        if (other.bit_length > self.bit_length) self.bit_length = other.bit_length;
        for (other.words.items, 0..) |ow, i| self.words.items[i] |= ow;
    }

    pub fn xorInPlace(self: *BitSet, other: *const BitSet) void {
        while (self.words.items.len < other.words.items.len) {
            self.words.append(self.allocator, 0) catch @panic("out of memory");
        }
        if (other.bit_length > self.bit_length) self.bit_length = other.bit_length;
        for (other.words.items, 0..) |ow, i| self.words.items[i] ^= ow;
    }

    pub fn andNotInPlace(self: *BitSet, other: *const BitSet) void {
        const min = @min(self.words.items.len, other.words.items.len);
        var i: usize = 0;
        while (i < min) : (i += 1) {
            self.words.items[i] &= ~other.words.items[i];
        }
    }

    pub fn nextSetBit(self: *const BitSet, from: usize) ?usize {
        var wi = wordIndex(from);
        if (wi >= self.words.items.len) return null;
        const offset = from % BITS_PER_WORD;
        var word: u64 = self.words.items[wi] & (~@as(u64, 0) << @intCast(offset));
        while (true) {
            if (word != 0) return wi * BITS_PER_WORD + @ctz(word);
            wi += 1;
            if (wi >= self.words.items.len) return null;
            word = self.words.items[wi];
        }
    }

    /// Pull-based iterator yielding the indices of all set bits in ascending
    /// order — the same sequence as `toOwnedSlice`, without allocating. Wraps
    /// `nextSetBit`. The iterator borrows the bit set; do not mutate while
    /// iterating.
    pub const Iterator = struct {
        bit_set: *const BitSet,
        next_from: usize = 0,

        pub fn next(self: *Iterator) ?usize {
            const bit = self.bit_set.nextSetBit(self.next_from) orelse return null;
            self.next_from = bit + 1;
            return bit;
        }
    };

    /// Returns a pull-based iterator over the indices of all set bits in
    /// ascending order (same sequence as `toOwnedSlice`). Non-allocating.
    pub fn iterator(self: *const BitSet) Iterator {
        return .{ .bit_set = self };
    }

    /// Returns indices of all set bits, ascending. Caller frees.
    pub fn toOwnedSlice(self: *const BitSet, allocator: Allocator) []usize {
        var out = std.ArrayListUnmanaged(usize){};
        out.ensureTotalCapacity(allocator, self.cardinality()) catch @panic("out of memory");
        var b = self.nextSetBit(0);
        while (b) |bit| {
            out.append(allocator, bit) catch @panic("out of memory");
            b = self.nextSetBit(bit + 1);
        }
        return out.toOwnedSlice(allocator) catch @panic("out of memory");
    }

    pub fn eql(self: *const BitSet, other: *const BitSet) bool {
        if (self.bit_length != other.bit_length) return false;
        const n = @max(self.words.items.len, other.words.items.len);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const a = if (i < self.words.items.len) self.words.items[i] else 0;
            const b = if (i < other.words.items.len) other.words.items[i] else 0;
            if (a != b) return false;
        }
        return true;
    }

    pub fn format(self: *const BitSet, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll("{");
        var first = true;
        var b = self.nextSetBit(0);
        while (b) |bit| {
            if (!first) try writer.writeAll(", ");
            try writer.print("{any}", .{bit});
            first = false;
            b = self.nextSetBit(bit + 1);
        }
        try writer.writeAll("}");
    }
};

test "BitSet: set get clearBit" {
    var b = BitSet.init(std.testing.allocator);
    defer b.deinit();
    b.set(0);
    b.set(5);
    b.set(100);
    try std.testing.expect(b.get(0));
    try std.testing.expect(b.get(5));
    try std.testing.expect(b.get(100));
    try std.testing.expect(!b.get(1));
    b.clearBit(5);
    try std.testing.expect(!b.get(5));
}

test "BitSet: flip" {
    var b = BitSet.init(std.testing.allocator);
    defer b.deinit();
    b.flip(3);
    try std.testing.expect(b.get(3));
    b.flip(3);
    try std.testing.expect(!b.get(3));
}

test "BitSet: cardinality" {
    var b = BitSet.init(std.testing.allocator);
    defer b.deinit();
    const bits = [_]usize{ 1, 5, 10, 63, 64, 127, 200 };
    for (bits) |i| b.set(i);
    try std.testing.expectEqual(@as(usize, 7), b.cardinality());
}

test "BitSet: and/or/xor/andNot" {
    var a = BitSet.init(std.testing.allocator);
    defer a.deinit();
    var c = BitSet.init(std.testing.allocator);
    defer c.deinit();
    a.set(1);
    a.set(5);
    a.set(10);
    c.set(5);
    c.set(10);
    c.set(20);
    try std.testing.expect(a.intersects(&c));

    var and_ = BitSet.init(std.testing.allocator);
    defer and_.deinit();
    and_.set(1);
    and_.set(5);
    and_.set(10);
    and_.andInPlace(&c);
    const s1 = and_.toOwnedSlice(std.testing.allocator);
    defer std.testing.allocator.free(s1);
    try std.testing.expectEqual(@as(usize, 2), s1.len);
}

test "BitSet: nextSetBit" {
    var b = BitSet.init(std.testing.allocator);
    defer b.deinit();
    b.set(0);
    b.set(5);
    b.set(100);
    try std.testing.expectEqual(@as(?usize, 0), b.nextSetBit(0));
    try std.testing.expectEqual(@as(?usize, 5), b.nextSetBit(1));
    try std.testing.expectEqual(@as(?usize, 100), b.nextSetBit(6));
    try std.testing.expectEqual(@as(?usize, null), b.nextSetBit(101));
}

test "BitSet: withBitLength" {
    var b = BitSet.withBitLength(std.testing.allocator, 200);
    defer b.deinit();
    try std.testing.expectEqual(@as(usize, 200), b.len());
    try std.testing.expectEqual(@as(usize, 0), b.cardinality());
}

test "BitSet: eql" {
    var a = BitSet.init(std.testing.allocator);
    defer a.deinit();
    var c = BitSet.init(std.testing.allocator);
    defer c.deinit();
    a.set(1);
    a.set(3);
    c.set(1);
    c.set(3);
    try std.testing.expect(a.eql(&c));
}
