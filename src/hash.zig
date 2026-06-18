// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Deterministic, byte-exact, cross-language hash pipeline (see
//! `spec/features/hash-pipeline.md`).
//!
//! This is the Zig port of a small, frozen primitive whose entire contract is
//! *bit-exactness across all five language ports*: every `(input, seed)`
//! produces the identical `hash32` / `hash64` / `positions` bits in Rust, Go,
//! TypeScript, Zig and Java. It is a separate, additive module — it does NOT
//! touch the collections' bucket hash (`algorithms.md` §"Hash function"), which
//! keeps its native-hash carve-out. This module has **no carve-out**.
//!
//! - `hash32` — MurmurHash3 32-bit finalizer (`fmix32`) over the input word
//!   XOR'd with a 32-bit fold of the 64-bit seed.
//! - `hash64` — MurmurHash3 64-bit finalizer (`fmix64`, constants
//!   `0xff51afd7ed558ccd` / `0xc4ceb9fe1a85ec53`, shifts `33/33/33` — NOT the
//!   SplitMix64 generator's final mix) over the input word XOR'd with the seed.
//! - `positions` — Kirsch–Mitzenmacher double hashing (`h1 + i*h2 mod m`),
//!   all 32-bit wrapping, unsigned modulo.
//! - `hllSplit` — pre-stated `(register_index, leading_zero_run)` split for the
//!   later HyperLogLog feature.
//!
//! All multiplies are two's-complement **wrapping** at their declared width
//! (`*%`); all right shifts are **logical** (Zig `>>` on unsigned is logical).

const std = @import("std");

/// MurmurHash3 `fmix32` finalizer constants (the published values).
pub const FMIX32_C1: u32 = 0x85ebca6b;
pub const FMIX32_C2: u32 = 0xc2b2ae35;

/// MurmurHash3 `fmix64` finalizer constants (the published values). NOTE: these
/// are the MurmurHash3 `fmix64` constants with three `33`-bit shifts, NOT the
/// SplitMix64 *generator's* final mix (`0xbf58476d1ce4e5b9` /
/// `0x94d049bb133111eb`, shifts `30/27/31`) — a different function.
pub const FMIX64_C1: u64 = 0xff51afd7ed558ccd;
pub const FMIX64_C2: u64 = 0xc4ceb9fe1a85ec53;

/// The fixed 32-bit salt for the second base hash of the double-hashing
/// position scheme (the 32-bit golden-ratio prime). Distinct from the 64-bit
/// collection Fibonacci constant `0x9E3779B97F4A7C15`.
pub const SALT2: u64 = 0x9e3779b1;

/// 32-bit named hash: the MurmurHash3 `fmix32` finalizer applied to one 32-bit
/// lane derived from `input_word` and a 32-bit fold of the 64-bit `seed`.
///
/// The seed is folded with `seed ^ (seed >> 32)` so two seeds differing only in
/// their high 32 bits still produce different hashes. Seed `0` is an ordinary
/// seed (XOR'd in; no special case).
pub fn hash32(input_word: u32, seed: u64) u32 {
    // Fold the full 64-bit seed into one 32-bit lane (low XOR high).
    const seed32: u32 = @truncate(seed ^ (seed >> 32));
    var h: u32 = input_word ^ seed32;
    h ^= h >> 16;
    h = h *% FMIX32_C1;
    h ^= h >> 13;
    h = h *% FMIX32_C2;
    h ^= h >> 16;
    return h;
}

/// 64-bit named hash: the MurmurHash3 `fmix64` finalizer applied to
/// `input_word ^ seed`. The seed is mixed in first as a 64-bit integer (no
/// endianness, no special case for seed `0`).
pub fn hash64(input_word: u64, seed: u64) u64 {
    var h: u64 = input_word ^ seed;
    h ^= h >> 33;
    h = h *% FMIX64_C1;
    h ^= h >> 33;
    h = h *% FMIX64_C2;
    h ^= h >> 33;
    return h;
}

/// The high 32-bit lane of `hash64` (pins the TypeScript hi/lo lane split).
pub fn hash64Hi(input_word: u64, seed: u64) u32 {
    return @truncate(hash64(input_word, seed) >> 32);
}

/// The low 32-bit lane of `hash64`.
pub fn hash64Lo(input_word: u64, seed: u64) u32 {
    return @truncate(hash64(input_word, seed));
}

// ---- Per-type input-word encoders ----------------------------------------

/// Encode an `i32` element to the `hash32` input word: a two's-complement bit
/// **reinterpret** to `u32` (NOT a sign-extend).
pub fn encodeI32Word32(value: i32) u32 {
    return @bitCast(value);
}

/// Encode an `i32` element to the `hash64` input word: reinterpret to `u32`
/// then **zero-extend** to `u64` (so the high 32 bits are always `0`; the seed
/// supplies the high-word entropy). NOT a sign-extend.
pub fn encodeI32Word64(value: i32) u64 {
    const u: u32 = @bitCast(value);
    return @as(u64, u); // zero-extend
}

/// Fold a raw byte slice into the `hash32` input word: read 4 bytes at a time as
/// **little-endian** `u32` lanes, XOR-combine, zero-pad a sub-lane tail to the
/// low bytes, then XOR in `len(bytes) mod 2^32`.
pub fn encodeBytesWord32(bytes: []const u8) u32 {
    var word: u32 = 0;
    var i: usize = 0;
    while (i + 4 <= bytes.len) : (i += 4) {
        word ^= std.mem.readInt(u32, bytes[i..][0..4], .little);
    }
    if (i < bytes.len) {
        // Tail goes in the LOW bytes of its lane; remaining high bytes are 0.
        var buf = [_]u8{0} ** 4;
        const tail = bytes[i..];
        @memcpy(buf[0..tail.len], tail);
        word ^= std.mem.readInt(u32, &buf, .little);
    }
    // Length reduced mod 2^32 before the XOR.
    return word ^ @as(u32, @truncate(bytes.len));
}

/// Fold a raw byte slice into the `hash64` input word: read 8 bytes at a time as
/// **little-endian** `u64` lanes, XOR-combine, zero-pad a sub-lane tail to the
/// low bytes, then XOR in `len(bytes) mod 2^64`.
pub fn encodeBytesWord64(bytes: []const u8) u64 {
    var word: u64 = 0;
    var i: usize = 0;
    while (i + 8 <= bytes.len) : (i += 8) {
        word ^= std.mem.readInt(u64, bytes[i..][0..8], .little);
    }
    if (i < bytes.len) {
        var buf = [_]u8{0} ** 8;
        const tail = bytes[i..];
        @memcpy(buf[0..tail.len], tail);
        word ^= std.mem.readInt(u64, &buf, .little);
    }
    return word ^ @as(u64, bytes.len);
}

/// `hash32` of an `i32` element (reinterpret encoding).
pub fn hash32I32(value: i32, seed: u64) u32 {
    return hash32(encodeI32Word32(value), seed);
}

/// `hash32` of a raw byte slice (little-endian fold encoding).
pub fn hash32Bytes(bytes: []const u8, seed: u64) u32 {
    return hash32(encodeBytesWord32(bytes), seed);
}

/// `hash64` of an `i32` element (reinterpret + zero-extend encoding).
pub fn hash64I32(value: i32, seed: u64) u64 {
    return hash64(encodeI32Word64(value), seed);
}

/// `hash64` of a raw byte slice (little-endian fold encoding).
pub fn hash64Bytes(bytes: []const u8, seed: u64) u64 {
    return hash64(encodeBytesWord64(bytes), seed);
}

// ---- Derived positions (Kirsch–Mitzenmacher double hashing) --------------

/// Derive `k` array positions over a table of size `m` from two base hashes
/// `h1`/`h2`, combined linearly: `p_i = (h1 + i*h2) mod m`, all 32-bit
/// wrapping, unsigned modulo. Written into `out` in derivation order
/// `p_0 … p_{k-1}` (caller supplies a buffer of at least `k` elements).
///
/// This is the inner function the test-vector oracle is stated on; it is
/// independent of the `hash32` layer and the byte encoding.
pub fn positionsFromHashes(h1: u32, h2: u32, m: u32, out: []u32) void {
    var i: u32 = 0;
    while (i < out.len) : (i += 1) {
        const combined: u32 = h1 +% (i *% h2);
        out[i] = combined % m;
    }
}

/// Derive `k` array positions for `input` over a table of size `m` using
/// Kirsch–Mitzenmacher double hashing. `h1 = hash32(input, 0)`,
/// `h2 = hash32(input, SALT2)`; then `positionsFromHashes`. `out.len` is `k`.
pub fn positions(input: []const u8, m: u32, k: u32, out: []u32) void {
    std.debug.assert(out.len >= k);
    const h1 = hash32Bytes(input, 0);
    const h2 = hash32Bytes(input, SALT2);
    positionsFromHashes(h1, h2, m, out[0..k]);
}

// ---- HyperLogLog split (pre-stated for the HLL feature) ------------------

/// Pre-stated HyperLogLog split: from a single 64-bit hash, derive a
/// `(register_index, leading_zero_run)` pair. `p = log2(number of registers)`,
/// `4 <= p <= 18`. Only `hash64(input, 0)` is locked here; HLL itself is a
/// separate later feature.
///
/// - `idx` = the top `p` bits of the hash (the register index).
/// - `rho` = `clz64(w) + 1`, the 1-based leading-zero run of the remaining bits
///   shifted up with a guard bit set at position `p - 1`.
pub const HllSplit = struct { idx: u32, rho: u32 };

pub fn hllSplit(input: []const u8, p: u5) HllSplit {
    std.debug.assert(p >= 4 and p <= 18);
    const x: u64 = hash64Bytes(input, 0);
    const shift: u6 = @intCast(64 - @as(u7, p));
    const idx: u32 = @truncate(x >> shift);
    const w: u64 = (x << p) | (@as(u64, 1) << (p - 1));
    const rho: u32 = @as(u32, @clz(w)) + 1;
    return .{ .idx = idx, .rho = rho };
}

// ==========================================================================
// Native tests (the committed oracle, mirroring spec §"Test vectors" and the
// Rust reference port's tests). Testing allocator; no leaks.
// ==========================================================================

const testing = std.testing;

// ---- Self-consistency anchors (spec §"Self-consistency anchors") ---------

test "anchor hash32 zero" {
    // hash32(0, 0): seed32=0, h=0, every step 0 -> 0. Universal self-check.
    try testing.expectEqual(@as(u32, 0x00000000), hash32(0x00000000, 0));
}

test "anchor hash64 zero" {
    try testing.expectEqual(@as(u64, 0), hash64(0, 0));
    try testing.expectEqual(@as(u32, 0x00000000), hash64Hi(0, 0));
    try testing.expectEqual(@as(u32, 0x00000000), hash64Lo(0, 0));
}

test "hash64 all ones logical shift" {
    // h>>33 on all-ones is 0x000000007fffffff (top 33 bits zero): a logical,
    // not arithmetic, shift. The value below is the reference output.
    try testing.expectEqual(@as(u64, 0x64b5720b4b825f21), hash64(0xffffffffffffffff, 0));
}

test "seed fold identity" {
    // seed32 = seed ^ (seed>>32). 0x00000000ffffffff -> ffffffff^00000000 =
    // ffffffff. 0xffffffff00000000 -> 00000000 ^ ffffffff = ffffffff. Equal.
    try testing.expectEqual(
        hash32(0x12345678, 0x00000000ffffffff),
        hash32(0x12345678, 0xffffffff00000000),
    );
    // Two seeds that fold to DIFFERENT seed32 produce different hashes.
    try testing.expect(hash32(0x12345678, 0x0000000000000001) != hash32(0x12345678, 0x0000000000000002));
    // And the high word genuinely affects the fold.
    try testing.expect(hash32(0x12345678, 0x0000000100000000) != hash32(0x12345678, 0x0000000000000000));
}

// ---- Per-type encoder pins (spec §"Input → input-word derivation") -------

test "i32 reinterpret not sign extend" {
    try testing.expectEqual(@as(u32, 0xffffffff), encodeI32Word32(-1));
    try testing.expectEqual(hash32(0xffffffff, 0), hash32I32(-1, 0));
    try testing.expectEqual(@as(u32, 0x80000000), encodeI32Word32(std.math.minInt(i32)));
    try testing.expectEqual(@as(u32, 0x7fffffff), encodeI32Word32(std.math.maxInt(i32)));
}

test "i32 zero extend for hash64" {
    // i32(-1) -> u64 0x00000000ffffffff (ZERO-extend, not 0xffffffffffffffff).
    try testing.expectEqual(@as(u64, 0x00000000ffffffff), encodeI32Word64(-1));
    try testing.expectEqual(hash64(0x00000000ffffffff, 0), hash64I32(-1, 0));
    // The sign-extend trap made observable: zero-extended != all-ones.
    try testing.expect(hash64I32(-1, 0) != hash64(0xffffffffffffffff, 0));
    try testing.expectEqual(@as(u64, 0x0000000080000000), encodeI32Word64(std.math.minInt(i32)));
}

test "bytes le fold 32" {
    // [01 02 03 04] reads LE to lane 0x04030201 then XOR len(4).
    try testing.expectEqual(@as(u32, 0x04030201 ^ 4), encodeBytesWord32(&[_]u8{ 0x01, 0x02, 0x03, 0x04 }));
    try testing.expectEqual(hash32(0x04030201 ^ 4, 0), hash32Bytes(&[_]u8{ 0x01, 0x02, 0x03, 0x04 }, 0));
}

test "bytes le fold 64" {
    // [01..08] reads LE to lane 0x0807060504030201 then XOR len(8).
    try testing.expectEqual(
        @as(u64, 0x0807060504030201 ^ 8),
        encodeBytesWord64(&[_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 }),
    );
    try testing.expectEqual(
        hash64(0x0807060504030201 ^ 8, 0),
        hash64Bytes(&[_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 }, 0),
    );
}

test "bytes tail and length distinguish" {
    // Sub-lane tail goes to LOW bytes; length XOR'd in so these all differ.
    const h3 = hash32Bytes(&[_]u8{ 0x01, 0x02, 0x03 }, 0);
    const h2 = hash32Bytes(&[_]u8{ 0x01, 0x02 }, 0);
    const h4 = hash32Bytes(&[_]u8{ 0x01, 0x02, 0x03, 0x00 }, 0);
    try testing.expect(h3 != h2);
    try testing.expect(h3 != h4);
    // [00] != [00,00] (length XOR distinguishes equal-byte tails).
    try testing.expect(hash32Bytes(&[_]u8{0x00}, 0) != hash32Bytes(&[_]u8{ 0x00, 0x00 }, 0));
    // Tail in LOW bytes: [01] folds to lane 0x00000001.
    try testing.expectEqual(@as(u32, 0x00000001 ^ 1), encodeBytesWord32(&[_]u8{0x01}));
    // Sub-lane tail lengths 1/2/3/5/7 zero-pad to the low bytes (no trap).
    var prev: ?u32 = null;
    inline for (.{ 1, 2, 3, 5, 7 }) |n| {
        var buf: [n]u8 = undefined;
        for (&buf, 0..) |*b, idx| b.* = @intCast(idx + 1);
        const h = hash32Bytes(&buf, 0);
        if (prev) |p| try testing.expect(h != p);
        prev = h;
    }
}

// ---- positionsFromHashes oracle rows (spec §position matrix) -------------

fn expectPositions(h1: u32, h2: u32, m: u32, expected: []const u32) !void {
    var out: [16]u32 = undefined;
    positionsFromHashes(h1, h2, m, out[0..expected.len]);
    try testing.expectEqualSlices(u32, expected, out[0..expected.len]);
}

test "positions vector rows" {
    try expectPositions(0x00000000, 0x00000001, 16, &[_]u32{ 0, 1, 2, 3 });
    try expectPositions(0x0000000a, 0x00000003, 16, &[_]u32{ 10, 13, 0, 3 });
    try expectPositions(0xffffffff, 0x00000001, 16, &[_]u32{ 15, 0, 1 });
    // i*h2 multiply wrap: i=2, 2*0x80000000 = 0x100000000 -> 0.
    try expectPositions(0x80000000, 0x80000000, 7, &[_]u32{ 2, 0, 2 });
    // addition wrap + unsigned mod with high bit set.
    try expectPositions(0xfffffffd, 0x00000002, 1000, &[_]u32{ 293, 295, 1, 3, 5 });
}

test "positions pow2 equals modulo" {
    // A power-of-two m must agree with plain % m (no mask shortcut here).
    var out: [7]u32 = undefined;
    positions("hello", 64, 7, &out);
    const h1 = hash32Bytes("hello", 0);
    const h2 = hash32Bytes("hello", SALT2);
    for (out, 0..) |p, i| {
        const combined: u32 = h1 +% (@as(u32, @intCast(i)) *% h2);
        try testing.expectEqual(combined & 63, p);
        try testing.expectEqual(combined % 64, p);
    }
}

test "positions public uses internal seeds" {
    var a: [5]u32 = undefined;
    var b: [5]u32 = undefined;
    positions("abc", 1000, 5, &a);
    const h1 = hash32Bytes("abc", 0);
    const h2 = hash32Bytes("abc", SALT2);
    positionsFromHashes(h1, h2, 1000, &b);
    try testing.expectEqualSlices(u32, &b, &a);
}

// ---- hllSplit sanity (pre-stated) ----------------------------------------

test "hll split basic" {
    const s = hllSplit("x", 12);
    const x = hash64Bytes("x", 0);
    try testing.expectEqual(@as(u32, @truncate(x >> (64 - 12))), s.idx);
    try testing.expect(s.rho >= 1);
    try testing.expect(s.idx < (@as(u32, 1) << 12));
}

// ---- Authoritative numeric test vectors (the committed oracle) -----------
// These rows mirror spec/features/hash-pipeline.md §"Test vectors" and the
// Rust reference port's tests. Any change here is a conformance break.

const HASH32_WORDS = [_]u32{ 0x00000000, 0x00000001, 0xffffffff, 0x80000000, 0x7fffffff, 0x04030201 };
const HASH32_SEEDS = [_]u64{ 0x0000000000000000, 0x0000000000000001, 0x00000000ffffffff, 0xffffffff00000000 };

test "hash32 vectors (full 24-row table)" {
    const expected = [6][4]u32{
        .{ 0x00000000, 0x514e28b7, 0x81f16f39, 0x81f16f39 },
        .{ 0x514e28b7, 0x00000000, 0x7995c304, 0x7995c304 },
        .{ 0x81f16f39, 0x7995c304, 0x00000000, 0x00000000 },
        .{ 0x6d3c65a0, 0x8b7f7a6a, 0xf9cc0ea8, 0xf9cc0ea8 },
        .{ 0xf9cc0ea8, 0x551b50f6, 0x6d3c65a0, 0x6d3c65a0 },
        .{ 0xd839eaff, 0x54ec0422, 0xaf02bbbc, 0xaf02bbbc },
    };
    for (HASH32_WORDS, 0..) |w, wi| {
        for (HASH32_SEEDS, 0..) |s, si| {
            try testing.expectEqual(expected[wi][si], hash32(w, s));
        }
    }
    // The two high/low-only seeds fold to the SAME seed32 (0xffffffff).
    for (HASH32_WORDS) |w| {
        try testing.expectEqual(hash32(w, 0x00000000ffffffff), hash32(w, 0xffffffff00000000));
    }
}

const HASH64_WORDS = [_]u64{
    0x0000000000000000,
    0x0000000000000001,
    0x00000000ffffffff,
    0x0000000080000000,
    0xffffffffffffffff,
    0x0807060504030201,
};
const HASH64_SEEDS = [_]u64{ 0x0000000000000000, 0x0000000000000001, 0x00000000ffffffff, 0xffffffff00000000 };

test "hash64 vectors (full 24-row table)" {
    const expected = [6][4]u64{
        .{ 0x0000000000000000, 0xb456bcfc34c2cb2c, 0xcc71ecda2aa8bcc6, 0xc9213cd20c528300 },
        .{ 0xb456bcfc34c2cb2c, 0x0000000000000000, 0x0789620c2ee64a3e, 0x2640647a5ca0376b },
        .{ 0xcc71ecda2aa8bcc6, 0x0789620c2ee64a3e, 0x0000000000000000, 0x64b5720b4b825f21 },
        .{ 0xe3beca1f9a7e4886, 0x81b875318ee00b8e, 0x8a662c1a93a26b91, 0xc4ca27146b0a922f },
        .{ 0x64b5720b4b825f21, 0x3a8593886c55a02b, 0xc9213cd20c528300, 0xcc71ecda2aa8bcc6 },
        .{ 0x9b57670c60240a13, 0xda66ed8bc89ffb5f, 0xbe7f6184429515e7, 0x916bf52bf4cf0681 },
    };
    for (HASH64_WORDS, 0..) |w, wi| {
        for (HASH64_SEEDS, 0..) |s, si| {
            try testing.expectEqual(expected[wi][si], hash64(w, s));
            // Lane split pins.
            try testing.expectEqual(@as(u32, @truncate(expected[wi][si] >> 32)), hash64Hi(w, s));
            try testing.expectEqual(@as(u32, @truncate(expected[wi][si])), hash64Lo(w, s));
        }
    }
}

test "scenario byte-fold reference values" {
    // hash64_bytes_le: bytes 01..08 -> word 0x0807060504030209 -> 0xa1dfdbe3d274f81c.
    try testing.expectEqual(
        @as(u64, 0xa1dfdbe3d274f81c),
        hash64Bytes(&[_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 }, 0),
    );
    // hash_bytes_le32: bytes 01020304 -> word 0x04030205 -> 0x318f91ff.
    try testing.expectEqual(@as(u32, 0x318f91ff), hash32Bytes(&[_]u8{ 0x01, 0x02, 0x03, 0x04 }, 0));
    // hash_bytes_tail: bytes 010203 -> 0xbb675c79.
    try testing.expectEqual(@as(u32, 0xbb675c79), hash32Bytes(&[_]u8{ 0x01, 0x02, 0x03 }, 0));
}
