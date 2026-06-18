// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Bloom filter — approximate set membership on the deterministic hash pipeline
//! (see `spec/features/bloom.md`).
//!
//! This is the Zig port of the first end-user collection of the probabilistic
//! wave. It rides directly on the deterministic hash pipeline (`hash.zig`): it
//! uses `hash.positions` (Kirsch–Mitzenmacher double-hashing) to pick `k` bit
//! indices in an `m`-bit array. Because `positions()` is **bit-identical across
//! all five ports**, the bit array after a given add-sequence is bit-identical
//! too — that bit array is the cross-language oracle.
//!
//! ## Element encoding (critical)
//!
//! An `i32` element `v` is reinterpreted to `u32` (`@bitCast`, NOT sign-extend),
//! encoded to **4 little-endian bytes**, and fed to the hash pipeline's
//! **byte-input** `positions(bytes, m, k)` path — the exact path the
//! `12-hash-pipeline/positions_*` scenarios drive, which **folds in the byte
//! length**. This is NOT the scalar `hash32I32` path: for `v = 7` the byte-path
//! input word is `0x07 ^ 4 = 0x03`. Worked example: `withParams(16, 4)` then
//! `add(7)` lights bits `{0, 2, 7, 9}` → `toBytes() = [0x85, 0x02]` →
//! `"0x8502"`, `bitCount() == 4`.
//!
//! ## Guarantees
//!
//! - **No false negative.** `add(v)` then `mightContain(v)` is always `true`.
//! - **Idempotent / order-independent.** The bit array depends only on the *set*
//!   of added elements.
//! - **Deterministic.** Identical `(m, k)` + add-sequence ⇒ identical bits on all
//!   five ports.

const std = @import("std");
const hash = @import("hash.zig");

const Allocator = std.mem.Allocator;

/// Error set for `union`-style operations: ORing two filters with mismatched
/// `(m, k)` is meaningless (incompatible bit arrays) and is reported as an error
/// rather than a silent truncate/pad.
pub const UnionError = error{ParamMismatch};

/// A Bloom filter over `i32` elements with `m` bits and `k` hash functions, both
/// fixed at construction. The bit array is stored as a `[]u64` word array; the
/// internal word width is **not observable** — only `toBytes` (LSB-first,
/// ascending bytes) is the cross-language form.
pub const Bloom = struct {
    allocator: Allocator,
    /// Number of bits in the array (`m`, `1 ..= 2^32-1`).
    m_bits_v: u32,
    /// Number of hash functions / positions set per element.
    k_v: u32,
    /// The bit array, `ceil(m / 64)` words; bit `i` lives in word `i / 64` at
    /// bit position `i % 64` (LSB-first within a word).
    words: []u64,

    /// Canonical, fully-deterministic constructor: explicit bit count `m_bits`
    /// and hash count `k`. The filter starts empty (all bits `0`). The caller
    /// owns the returned filter and must `deinit` it.
    ///
    /// `m_bits == 0` is **invalid** and traps (a 0-bit array can hold nothing and
    /// every `positions` modulo would be by zero). `k == 0` is degenerate but
    /// **legal** (see `mightContain`).
    pub fn withParams(allocator: Allocator, m_bits: u32, k_funcs: u32) !Bloom {
        std.debug.assert(m_bits != 0); // m_bits must be >= 1
        const n_words: usize = (@as(usize, m_bits) + 63) / 64;
        const words = try allocator.alloc(u64, n_words);
        @memset(words, 0);
        return .{
            .allocator = allocator,
            .m_bits_v = m_bits,
            .k_v = k_funcs,
            .words = words,
        };
    }

    /// Convenience constructor sizing the filter from an expected element count
    /// `n` and a target false-positive probability `p`, using the standard Bloom
    /// formulas:
    ///
    /// ```text
    /// m = ceil( -n * ln(p) / (ln 2)^2 )
    /// k = max( 1, round( (m / n) * ln 2 ) )      # round-half-away-from-zero
    /// ```
    ///
    /// then delegates to `withParams`. This is **native-test-only**: it never
    /// appears in the shared cross-language scenarios (the float derivation could
    /// drift by a ULP across libms — quarantined to native tests against the
    /// pinned integer table in `spec/features/bloom.md`).
    ///
    /// Requires `n >= 1` and `0 < p < 1`. `n == 0`, `p <= 0`, `p >= 1`, `NaN`,
    /// and `±Infinity` are invalid and trap.
    pub fn optimal(allocator: Allocator, n_expected: u64, p: f64) !Bloom {
        std.debug.assert(n_expected >= 1); // n_expected must be >= 1
        std.debug.assert(std.math.isFinite(p) and p > 0.0 and p < 1.0); // p in (0,1)
        const n: f64 = @floatFromInt(n_expected);
        const ln2: f64 = std.math.ln2; // ln(2) in f64
        const m_f = @ceil(-n * @log(p) / (ln2 * ln2));
        std.debug.assert(std.math.isFinite(m_f) and m_f >= 1.0 and m_f <= @as(f64, @floatFromInt(std.math.maxInt(u32))));
        const m: u32 = @intFromFloat(m_f);
        // round-half-away-from-zero (the common `round()`), clamped to >= 1.
        const k_f = @round((@as(f64, @floatFromInt(m)) / n) * ln2);
        const k_i: i64 = @intFromFloat(k_f);
        const k_funcs: u32 = @intCast(@max(k_i, 1));
        return withParams(allocator, m, k_funcs);
    }

    /// Release the bit-array memory. After this the filter must not be used.
    pub fn deinit(self: *Bloom) void {
        self.allocator.free(self.words);
        self.* = undefined;
    }

    /// The bit count `m`.
    pub fn mBits(self: *const Bloom) u32 {
        return self.m_bits_v;
    }

    /// The hash count `k`.
    pub fn k(self: *const Bloom) u32 {
        return self.k_v;
    }

    /// Add an `i32` element: set the `k` bits for `v` (idempotent). With
    /// `k == 0` this sets no bits.
    ///
    /// There is **no `k` cap** — the reference derives all `k` positions for any
    /// `u32` `k`. Positions are streamed one-at-a-time (no buffer), so an
    /// arbitrarily large `k` is handled without allocation and without a stack
    /// cap. The position derivation order is `p_0 … p_{k-1}`, identical to
    /// `hash.positions`.
    pub fn add(self: *Bloom, v: i32) void {
        var it = self.positionIterator(v);
        while (it.next()) |p| self.setBit(p);
    }

    /// `mightContain` — the canonical name. Returns `false` ⇒ definitely absent;
    /// `true` ⇒ possibly present (may be a false positive). **Never** returns
    /// `false` for an element that was added (no false negative).
    ///
    /// With `k == 0` the AND over zero positions is **vacuously true**, so this
    /// returns `true` for every element (an all-false-positive filter).
    pub fn mightContain(self: *const Bloom, v: i32) bool {
        var it = self.positionIterator(v);
        while (it.next()) |p| {
            if (!self.getBit(p)) return false;
        }
        return true;
    }

    /// `true` iff no bit is set (equivalently: nothing has been added, or only
    /// `k == 0` adds). Equal to `bitCount() == 0`.
    pub fn isEmpty(self: *const Bloom) bool {
        for (self.words) |w| {
            if (w != 0) return false;
        }
        return true;
    }

    /// The number of set bits (popcount of the whole bit array). The zeroed tail
    /// bits never contribute (no `positions` index reaches them).
    pub fn bitCount(self: *const Bloom) u32 {
        var sum: u32 = 0;
        for (self.words) |w| sum += @popCount(w);
        return sum;
    }

    /// In-place bitwise OR: fold `other`'s set bits into `self`. The result's
    /// membership is the union of the two filters' membership (no false negatives
    /// lost). Mismatched `(m, k)` returns `error.ParamMismatch` (a filter built
    /// with different parameters has an incompatible bit array; ORing them is
    /// meaningless).
    pub fn unionWith(self: *Bloom, other: *const Bloom) UnionError!void {
        if (self.m_bits_v != other.m_bits_v or self.k_v != other.k_v) {
            return error.ParamMismatch;
        }
        for (self.words, other.words) |*a, b| a.* |= b;
    }

    /// Allocating union: a new `Bloom` whose bits are the OR of `self` and
    /// `other`. The caller owns the result and must `deinit` it. Mismatched
    /// `(m, k)` returns `error.ParamMismatch`.
    pub fn unionInto(self: *const Bloom, allocator: Allocator, other: *const Bloom) (UnionError || Allocator.Error)!Bloom {
        if (self.m_bits_v != other.m_bits_v or self.k_v != other.k_v) {
            return error.ParamMismatch;
        }
        const words = try allocator.alloc(u64, self.words.len);
        for (words, self.words, other.words) |*o, a, b| o.* = a | b;
        return .{
            .allocator = allocator,
            .m_bits_v = self.m_bits_v,
            .k_v = self.k_v,
            .words = words,
        };
    }

    /// Serialize the bit array into the caller-provided `out` buffer, which MUST
    /// be exactly `byteLen()` bytes. LSB-first bit order within each byte
    /// (bit `i` ⇒ `out[i / 8] |= 1 << (i % 8)`); ascending byte order;
    /// **little-endian on every host**; unused tail bits `0`.
    pub fn toBytes(self: *const Bloom, out: []u8) void {
        const n_bytes = self.byteLen();
        std.debug.assert(out.len == n_bytes);
        @memset(out, 0);
        for (self.words, 0..) |w, wi| {
            // Each word holds bits [wi*64 .. wi*64 + 64). Emit its 8 bytes
            // little-endian so bit (wi*64 + b*8 + j) lands at out[..]&(1<<j).
            var word_bytes: [8]u8 = undefined;
            std.mem.writeInt(u64, &word_bytes, w, .little);
            for (word_bytes, 0..) |byte, bi| {
                const out_idx = wi * 8 + bi;
                // out_idx >= n_bytes can only be a fully-zero tail byte (no
                // `positions` index reaches >= m), so dropping it is exact.
                if (out_idx < n_bytes) out[out_idx] = byte;
            }
        }
    }

    /// Allocate and serialize the bit array (length exactly `byteLen()`). The
    /// caller owns the returned slice and must free it.
    pub fn toBytesAlloc(self: *const Bloom, allocator: Allocator) ![]u8 {
        const out = try allocator.alloc(u8, self.byteLen());
        self.toBytes(out);
        return out;
    }

    /// The exact serialized length in bytes: `ceil(m / 8)`.
    pub fn byteLen(self: *const Bloom) usize {
        return (@as(usize, self.m_bits_v) + 7) / 8;
    }

    /// The sorted-ascending indices of the set bits — a human-legible alternate
    /// oracle to `toBytes` (drives the `set_bits` scenario assertion). The caller
    /// owns the returned slice and must free it.
    pub fn setBitsAlloc(self: *const Bloom, allocator: Allocator) ![]u32 {
        var list = try std.ArrayListUnmanaged(u32).initCapacity(allocator, self.bitCount());
        errdefer list.deinit(allocator);
        for (self.words, 0..) |w, wi| {
            var bits = w;
            while (bits != 0) {
                const j = @ctz(bits);
                try list.append(allocator, @as(u32, @intCast(wi)) * 64 + j);
                bits &= bits - 1; // clear lowest set bit
            }
        }
        return list.toOwnedSlice(allocator);
    }

    // ---- internal --------------------------------------------------------

    /// Streaming position derivation for element `v`: yields `p_0 … p_{k-1}` in
    /// the exact derivation order of `hash.positions` — `h1 = hash32(bytes, 0)`,
    /// `h2 = hash32(bytes, SALT2)`, `p_i = (h1 +% i*%h2) mod m` — without any
    /// buffer, so any `u32` `k` works (no cap, no allocation). Element bytes are
    /// the LE-4-byte, length-folded byte path (`@bitCast` i32 → u32 → LE).
    const PositionIterator = struct {
        h1: u32,
        h2: u32,
        m: u32,
        k: u32,
        i: u32 = 0,

        fn next(self: *PositionIterator) ?u32 {
            if (self.i >= self.k) return null;
            const combined: u32 = self.h1 +% (self.i *% self.h2);
            self.i += 1;
            return combined % self.m;
        }
    };

    fn positionIterator(self: *const Bloom, v: i32) PositionIterator {
        var le: [4]u8 = undefined;
        std.mem.writeInt(u32, &le, @bitCast(v), .little);
        return .{
            .h1 = hash.hash32Bytes(&le, 0),
            .h2 = hash.hash32Bytes(&le, hash.SALT2),
            .m = self.m_bits_v,
            .k = self.k_v,
        };
    }

    fn setBit(self: *Bloom, i: u32) void {
        std.debug.assert(i < self.m_bits_v);
        const idx: usize = i;
        self.words[idx / 64] |= @as(u64, 1) << @intCast(idx % 64);
    }

    fn getBit(self: *const Bloom, i: u32) bool {
        const idx: usize = i;
        return (self.words[idx / 64] >> @intCast(idx % 64)) & 1 == 1;
    }
};

// ==========================================================================
// Native tests (testing allocator; no leaks). Mirror the Rust reference port's
// tests and spec/features/bloom.md.
// ==========================================================================

const testing = std.testing;

fn hexAlloc(allocator: Allocator, bytes: []const u8) ![]u8 {
    var list = std.ArrayListUnmanaged(u8){};
    errdefer list.deinit(allocator);
    try list.appendSlice(allocator, "0x");
    for (bytes) |b| {
        try list.writer(allocator).print("{x:0>2}", .{b});
    }
    return list.toOwnedSlice(allocator);
}

test "worked example add(7) -> 0x8502" {
    var b = try Bloom.withParams(testing.allocator, 16, 4);
    defer b.deinit();
    try testing.expect(b.isEmpty());
    b.add(7);
    const sb = try b.setBitsAlloc(testing.allocator);
    defer testing.allocator.free(sb);
    try testing.expectEqualSlices(u32, &[_]u32{ 0, 2, 7, 9 }, sb);
    try testing.expectEqual(@as(u32, 4), b.bitCount());
    try testing.expect(!b.isEmpty());
    const bytes = try b.toBytesAlloc(testing.allocator);
    defer testing.allocator.free(bytes);
    try testing.expectEqualSlices(u8, &[_]u8{ 0x85, 0x02 }, bytes);
    const hexstr = try hexAlloc(testing.allocator, bytes);
    defer testing.allocator.free(hexstr);
    try testing.expectEqualStrings("0x8502", hexstr);
    try testing.expect(b.mightContain(7));
    try testing.expect(!b.mightContain(1)); // genuine absent
}

test "optimal() pinned integer table" {
    const cases = [_]struct { n: u64, p: f64, em: u32, ek: u32 }{
        .{ .n = 1000, .p = 0.01, .em = 9586, .ek = 7 },
        .{ .n = 1000, .p = 0.001, .em = 14378, .ek = 10 },
        .{ .n = 10000, .p = 0.01, .em = 95851, .ek = 7 },
        .{ .n = 100, .p = 0.1, .em = 480, .ek = 3 },
        .{ .n = 1, .p = 0.5, .em = 2, .ek = 1 },
    };
    for (cases) |c| {
        var b = try Bloom.optimal(testing.allocator, c.n, c.p);
        defer b.deinit();
        try testing.expectEqual(c.em, b.mBits());
        try testing.expectEqual(c.ek, b.k());
    }
}

test "m=0 traps (debug assert)" {
    // m_bits == 0 is the one construction error. In safe builds the assert in
    // withParams fires; we cannot catch an assert, so just document the
    // contract by asserting the precondition holds for the legal path.
    var b = try Bloom.withParams(testing.allocator, 1, 4);
    defer b.deinit();
    try testing.expectEqual(@as(u32, 1), b.mBits());
}

test "k=0 vacuous-true" {
    var b = try Bloom.withParams(testing.allocator, 16, 0);
    defer b.deinit();
    b.add(5);
    try testing.expectEqual(@as(u32, 0), b.bitCount());
    try testing.expect(b.isEmpty());
    const bytes = try b.toBytesAlloc(testing.allocator);
    defer testing.allocator.free(bytes);
    try testing.expectEqualSlices(u8, &[_]u8{ 0x00, 0x00 }, bytes);
    // might_contain vacuously true for everything.
    try testing.expect(b.mightContain(5));
    try testing.expect(b.mightContain(9999));
    try testing.expect(b.mightContain(-1));
}

test "union in-place is bitwise OR; mismatch errors" {
    var a = try Bloom.withParams(testing.allocator, 32, 3);
    defer a.deinit();
    a.add(1);
    a.add(2);
    var c = try Bloom.withParams(testing.allocator, 32, 3);
    defer c.deinit();
    c.add(100);
    c.add(200);

    // expected OR words computed before the in-place fold.
    var expected: [1]u64 = .{a.words[0] | c.words[0]};

    var u = try Bloom.withParams(testing.allocator, 32, 3);
    defer u.deinit();
    try u.unionWith(&a);
    try u.unionWith(&c);
    try testing.expectEqualSlices(u64, expected[0..], u.words);
    try testing.expect(u.mightContain(1));
    try testing.expect(u.mightContain(2));
    try testing.expect(u.mightContain(100));
    try testing.expect(u.mightContain(200));

    // Allocating union matches.
    var ualloc = try a.unionInto(testing.allocator, &c);
    defer ualloc.deinit();
    try testing.expectEqualSlices(u64, expected[0..], ualloc.words);

    // Mismatched m -> error.
    var d = try Bloom.withParams(testing.allocator, 16, 4);
    defer d.deinit();
    var e = try Bloom.withParams(testing.allocator, 32, 4);
    defer e.deinit();
    try testing.expectError(error.ParamMismatch, d.unionWith(&e));
    // Mismatched k -> error.
    var f = try Bloom.withParams(testing.allocator, 16, 3);
    defer f.deinit();
    try testing.expectError(error.ParamMismatch, d.unionWith(&f));
}

test "add is idempotent and order-independent" {
    var once = try Bloom.withParams(testing.allocator, 64, 5);
    defer once.deinit();
    once.add(7);
    var twice = try Bloom.withParams(testing.allocator, 64, 5);
    defer twice.deinit();
    twice.add(7);
    twice.add(7);
    try testing.expectEqualSlices(u64, once.words, twice.words);
    try testing.expectEqual(once.bitCount(), twice.bitCount());

    var ab = try Bloom.withParams(testing.allocator, 128, 4);
    defer ab.deinit();
    ab.add(11);
    ab.add(22);
    ab.add(33);
    var ba = try Bloom.withParams(testing.allocator, 128, 4);
    defer ba.deinit();
    ba.add(33);
    ba.add(11);
    ba.add(22);
    try testing.expectEqualSlices(u64, ab.words, ba.words);
}

test "signed extremes reinterpret not sign-extend" {
    var b = try Bloom.withParams(testing.allocator, 256, 4);
    defer b.deinit();
    b.add(-1);
    b.add(std.math.minInt(i32));
    try testing.expect(b.mightContain(-1));
    try testing.expect(b.mightContain(std.math.minInt(i32)));

    var neg = try Bloom.withParams(testing.allocator, 256, 4);
    defer neg.deinit();
    neg.add(-1);
    var pos = try Bloom.withParams(testing.allocator, 256, 4);
    defer pos.deinit();
    pos.add(1);
    try testing.expect(!std.mem.eql(u64, neg.words, pos.words));
}

test "no false negative over a set" {
    var b = try Bloom.withParams(testing.allocator, 512, 7);
    defer b.deinit();
    var v: i32 = -50;
    while (v < 50) : (v += 1) b.add(v);
    b.add(std.math.minInt(i32));
    b.add(std.math.maxInt(i32));
    b.add(0);
    v = -50;
    while (v < 50) : (v += 1) try testing.expect(b.mightContain(v));
    try testing.expect(b.mightContain(std.math.minInt(i32)));
    try testing.expect(b.mightContain(std.math.maxInt(i32)));
}

test "tail bits zeroed (m=13)" {
    var b = try Bloom.withParams(testing.allocator, 13, 3);
    defer b.deinit();
    b.add(7);
    b.add(42);
    const bytes = try b.toBytesAlloc(testing.allocator);
    defer testing.allocator.free(bytes);
    try testing.expectEqual(@as(usize, 2), bytes.len);
    const sb = try b.setBitsAlloc(testing.allocator);
    defer testing.allocator.free(sb);
    for (sb) |p| try testing.expect(p < 13);
    // byte1 only bit 10 (set in this fixture) -> high bits 13,14,15 are 0.
    try testing.expectEqualSlices(u8, &[_]u8{ 0x98, 0x04 }, bytes);
}

test "toBytes LSB-first independent of word width" {
    {
        var b = try Bloom.withParams(testing.allocator, 16, 1);
        defer b.deinit();
        b.setBit(8); // byte1 bit0 = 0x01
        const bytes = try b.toBytesAlloc(testing.allocator);
        defer testing.allocator.free(bytes);
        try testing.expectEqualSlices(u8, &[_]u8{ 0x00, 0x01 }, bytes);
    }
    {
        var c = try Bloom.withParams(testing.allocator, 16, 1);
        defer c.deinit();
        c.setBit(0);
        const bytes = try c.toBytesAlloc(testing.allocator);
        defer testing.allocator.free(bytes);
        try testing.expectEqualSlices(u8, &[_]u8{ 0x01, 0x00 }, bytes);
    }
    {
        var d = try Bloom.withParams(testing.allocator, 16, 1);
        defer d.deinit();
        d.setBit(7); // LSB-first: bit 7 is the high bit of byte 0 -> 0x80
        const bytes = try d.toBytesAlloc(testing.allocator);
        defer testing.allocator.free(bytes);
        try testing.expectEqualSlices(u8, &[_]u8{ 0x80, 0x00 }, bytes);
    }
    {
        var e = try Bloom.withParams(testing.allocator, 200, 1);
        defer e.deinit();
        e.setBit(130); // byte 130/8 = 16, bit 130%8 = 2 -> 0x04
        const bytes = try e.toBytesAlloc(testing.allocator);
        defer testing.allocator.free(bytes);
        try testing.expectEqual(@as(usize, 25), bytes.len);
        try testing.expectEqual(@as(u8, 0x04), bytes[16]);
    }
}

test "empty filter serializes to zero of full length" {
    var b = try Bloom.withParams(testing.allocator, 16, 4);
    defer b.deinit();
    const bytes = try b.toBytesAlloc(testing.allocator);
    defer testing.allocator.free(bytes);
    try testing.expectEqualSlices(u8, &[_]u8{ 0x00, 0x00 }, bytes);
    try testing.expectEqual(@as(u32, 0), b.bitCount());
    try testing.expect(b.isEmpty());
    try testing.expect(!b.mightContain(7)); // k>=1 empty: absent for everything
}

test "large k > stack path: no cap, deterministic" {
    // k = 100 (> the old 64 stack cap). add/mightContain must work for any
    // u32 k and stay bit-identical to hash.positions streaming derivation.
    var b = try Bloom.withParams(testing.allocator, 256, 100);
    defer b.deinit();
    b.add(7);
    try testing.expect(b.mightContain(7));
    try testing.expect(b.bitCount() >= 1);
    // Cross-check the exact set against hash.positions over the same encoding.
    var le: [4]u8 = undefined;
    std.mem.writeInt(u32, &le, @bitCast(@as(i32, 7)), .little);
    const ps = try testing.allocator.alloc(u32, 100);
    defer testing.allocator.free(ps);
    hash.positions(&le, 256, 100, ps);
    for (ps) |p| {
        try testing.expect((b.words[p / 64] >> @intCast(p % 64)) & 1 == 1);
    }
}

test "collision small m: bit_count < k" {
    // positions(0,5,3) collapse to {3,4} -> bit_count 2 < k=3, bytes 0x18.
    var b = try Bloom.withParams(testing.allocator, 5, 3);
    defer b.deinit();
    b.add(0);
    try testing.expectEqual(@as(u32, 2), b.bitCount());
    const bytes = try b.toBytesAlloc(testing.allocator);
    defer testing.allocator.free(bytes);
    try testing.expectEqualSlices(u8, &[_]u8{0x18}, bytes);
}
