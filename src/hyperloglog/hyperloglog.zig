// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! HyperLogLog distinct-count cardinality sketch (see
//! `spec/features/hyperloglog.md`). **Zig port of the frozen Rust reference.**
//!
//! ## Float-quarantine ruling (the heart of this feature)
//!
//! HyperLogLog has two observable surfaces:
//!
//! 1. The **integer register array** (`m = 2^p` `u8`s, each the max `rho` seen).
//!    This is **exact integer state**, a pure-integer function of
//!    `(p, add-sequence)` through the hash pipeline, and is the **cross-language
//!    oracle** — all five ports MUST produce the byte-identical array. The
//!    shared JSON scenarios assert ONLY this (via `register_hex`,
//!    `nonzero_registers`, `max_register`, `register_at_N`).
//!
//! 2. The **`f64` estimate** ([`estimate`]). It is a function of `ln` / `2^x` /
//!    division / summation and **cannot** be required to agree bit-for-bit
//!    across five libm implementations. It is tolerance-tested **natively** —
//!    it is **never** in the shared oracle. There is **no `estimate` assertion
//!    key**.
//!
//! `add`, `merge`, and the register array use **zero floating point** (only
//! `hash64`, shifts, `max`, byte packing); the float appears only inside
//! `estimate()`, a read-only projection that never writes a register.

const std = @import("std");
const Allocator = std.mem.Allocator;
const hash = @import("../hash.zig");

/// Minimum legal precision (`m = 16`).
pub const MIN_PRECISION: u8 = 4;
/// Maximum legal precision (`m = 262144`); the v1 ceiling matching `hll_split`.
pub const MAX_PRECISION: u8 = 18;

/// The 4-byte ASCII magic that version-tags the serialized form (`"HLL1"`).
const MAGIC = [4]u8{ 'H', 'L', 'L', '1' };

/// Errors from the HyperLogLog surface (construction / merge / deserialization).
pub const HllError = error{
    /// `p` outside `4 ..= 18` (never silently clamped).
    BadPrecision,
    /// `merge` of two sketches with different `p` (no resize/reproject).
    PrecisionMismatch,
    /// `from_bytes`: fewer than the 5-byte header.
    TooShort,
    /// `from_bytes`: magic was not `"HLL1"`.
    BadMagic,
    /// `from_bytes`: total length is not exactly `5 + 2^p`.
    LengthMismatch,
    /// `from_bytes`: a register byte exceeds the per-`p` ceiling `64 - p + 1`.
    RegisterOutOfRange,
};

/// The per-`p` maximum possible `rho` (and the `from_bytes` byte ceiling):
/// `64 - p + 1`.
fn rhoCeiling(p: u8) u8 {
    return 64 - p + 1;
}

/// A HyperLogLog distinct-count sketch.
///
/// Built by [`withPrecision`]; updated by [`add`] / [`merge`]; the register
/// array (the oracle) is read via [`registers`] / [`nonzeroRegisters`]; the
/// quarantined float answer is [`estimate`]; serialized via [`toBytes`] /
/// [`fromBytes`]. Owns its `registers` allocation — call [`deinit`].
pub const HyperLogLog = struct {
    p: u8,
    /// `m = 2^p` registers, each the max `rho` seen for that index (0 = empty).
    /// Heap-owned by `allocator`. Read externally via [`registers`].
    regs: []u8,
    allocator: Allocator,

    /// Construct an empty sketch with `m = 2^p` zeroed registers.
    ///
    /// `p` must be in `4 ..= 18`; otherwise `HllError.BadPrecision` (never a
    /// silent clamp — a clamp would let two ports build differently-sized
    /// arrays from the same nominal `p`).
    pub fn withPrecision(allocator: Allocator, p: u8) !HyperLogLog {
        if (p < MIN_PRECISION or p > MAX_PRECISION) {
            return HllError.BadPrecision;
        }
        const m = @as(usize, 1) << @intCast(p);
        const regs = try allocator.alloc(u8, m);
        @memset(regs, 0);
        return HyperLogLog{ .p = p, .regs = regs, .allocator = allocator };
    }

    /// Free the register allocation. After this the sketch is invalid.
    pub fn deinit(self: *HyperLogLog) void {
        self.allocator.free(self.regs);
        self.regs = &.{};
    }

    /// The precision `p` (`log2(m)`).
    pub fn precision(self: *const HyperLogLog) u8 {
        return self.p;
    }

    /// The register count `m = 2^p`.
    pub fn registerCount(self: *const HyperLogLog) usize {
        return self.regs.len;
    }

    /// Split a 64-bit hash into `(register_index, rho)` per the hash pipeline's
    /// pre-stated `hll_split` (top `p` bits → index; remaining bits + guard bit
    /// → `clz64 + 1`). Pure integer; the guard bit guarantees `w != 0` so
    /// `@clz` is never called on `0`.
    fn split(x: u64, p: u8) struct { idx: u32, rho: u8 } {
        const pp: u6 = @intCast(p);
        // Top `p` bits; logical (unsigned) shift by (64 - p), which is in
        // [46, 60] for p in [4, 18] and fits a u6.
        const idx: u32 = @truncate(x >> @intCast(@as(u7, 64) - @as(u7, @intCast(p))));
        // GUARD BIT: OR in `1 << (p - 1)`. If the remaining `64 - p` bits are
        // all zero, `w = 1 << (p-1)`, `@clz(w) = 64-p`, so `rho = 64-p+1` (its
        // max) and `@clz` is never invoked on `0`.
        const w: u64 = (x << pp) | (@as(u64, 1) << @intCast(p - 1));
        const rho: u8 = @intCast(@as(u32, @clz(w)) + 1);
        return .{ .idx = idx, .rho = rho };
    }

    /// Add an `i32` element. The item is encoded with the hash pipeline's `i32`
    /// rule — reinterpret to `u32`, **zero-extend** to `u64` (NOT sign-extend) —
    /// then `hash64(word, seed = 0)`, then `hll_split`, then
    /// `register[idx] = max(register[idx], rho)`. **Pure integer, zero floating
    /// point.**
    pub fn add(self: *HyperLogLog, item: i32) void {
        // i32 -> u32 reinterpret -> zero-extend to u64 (high 32 bits always 0).
        const word: u64 = @as(u64, @as(u32, @bitCast(item)));
        const x: u64 = hash.hash64(word, 0);
        const s = split(x, self.p);
        if (s.rho > self.regs[s.idx]) {
            self.regs[s.idx] = s.rho;
        }
    }

    /// The raw register array (the cross-language oracle bytes).
    pub fn registers(self: *const HyperLogLog) []const u8 {
        return self.regs;
    }

    /// The count of registers `> 0` (`= m - V`, where `V` is the zero count).
    pub fn nonzeroRegisters(self: *const HyperLogLog) u32 {
        var n: u32 = 0;
        for (self.regs) |r| {
            if (r > 0) n += 1;
        }
        return n;
    }

    /// The maximum register value (largest `rho` seen); `0` for a fresh sketch.
    pub fn maxRegister(self: *const HyperLogLog) u8 {
        var mx: u8 = 0;
        for (self.regs) |r| {
            if (r > mx) mx = r;
        }
        return mx;
    }

    /// Merge `other` into `self` by element-wise register **max** (the union's
    /// register `j` is the max over both input sets). Requires identical `p`
    /// (else `HllError.PrecisionMismatch`). Commutative, associative,
    /// idempotent. **Pure integer, zero floating point.**
    pub fn merge(self: *HyperLogLog, other: *const HyperLogLog) !void {
        if (self.p != other.p) {
            return HllError.PrecisionMismatch;
        }
        for (self.regs, other.regs) |*a, b| {
            if (b > a.*) a.* = b;
        }
    }

    /// The HLL bias constant `alpha_m`: pinned piecewise literals for small `m`,
    /// closed form for `m >= 128`.
    fn alphaM(p: u8) f64 {
        return switch (p) {
            4 => 0.673, // m = 16
            5 => 0.697, // m = 32
            6 => 0.709, // m = 64
            else => 0.7213 / (1.0 + 1.079 / @as(f64, @floatFromInt(@as(u64, 1) << @intCast(p)))), // m >= 128
        };
    }

    /// Estimate the distinct cardinality (the **quarantined `f64`**, native-only
    /// and tolerance-tested — never in the shared oracle).
    ///
    /// Original HyperLogLog estimator (Flajolet–Fusy–Gandouet–Meunier 2007) with
    /// the small-range linear-counting correction and the **`2^64`** large-range
    /// correction (this HLL consumes a 64-bit `hash64`, so the hash space is
    /// `2^64`, NOT the 2007 paper's `2^32`).
    pub fn estimate(self: *const HyperLogLog) f64 {
        const m: f64 = @floatFromInt(self.regs.len);
        const alpha = alphaM(self.p);

        // Z = sum 2^(-register[j]); register[j] == 0 contributes 2^0 = 1.
        var z: f64 = 0.0;
        for (self.regs) |r| {
            const denom: f64 = @floatFromInt(@as(u64, 1) << @intCast(r));
            z += 1.0 / denom;
        }
        const e = alpha * m * m / z;

        // Small-range (linear counting): E small AND there are empties (V > 0).
        var v: usize = 0;
        for (self.regs) |r| {
            if (r == 0) v += 1;
        }
        if (e <= 2.5 * m and v > 0) {
            return m * @log(m / @as(f64, @floatFromInt(v)));
        }

        // Large-range correction near the HASH-SPACE ceiling (2^64, NOT 2^32).
        const two64: f64 = 18446744073709551616.0; // 2^64, exactly representable.
        if (e > (1.0 / 30.0) * two64) {
            return -two64 * @log(1.0 - e / two64);
        }

        return e;
    }

    /// Serialize to the v1 wire form: 5-byte header (`"HLL1"` + `p`) followed by
    /// one `u8` per register in index order. Total length `5 + 2^p`. The
    /// returned slice is caller-owned (allocated by `allocator`).
    pub fn toBytes(self: *const HyperLogLog, allocator: Allocator) ![]u8 {
        const out = try allocator.alloc(u8, 5 + self.regs.len);
        @memcpy(out[0..4], &MAGIC);
        out[4] = self.p;
        @memcpy(out[5..], self.regs);
        return out;
    }

    /// Deserialize from the v1 wire form. Rejects (single MUST rule so no two
    /// ports disagree on validity): too short, bad magic, `p` out of range,
    /// length `!= 5 + 2^p`, or any register byte `> 64 - p + 1`. The returned
    /// sketch owns a fresh register allocation.
    pub fn fromBytes(allocator: Allocator, bytes: []const u8) !HyperLogLog {
        if (bytes.len < 5) {
            return HllError.TooShort;
        }
        if (!std.mem.eql(u8, bytes[0..4], &MAGIC)) {
            return HllError.BadMagic;
        }
        const p = bytes[4];
        if (p < MIN_PRECISION or p > MAX_PRECISION) {
            return HllError.BadPrecision;
        }
        const m = @as(usize, 1) << @intCast(p);
        const expected = 5 + m;
        if (bytes.len != expected) {
            return HllError.LengthMismatch;
        }
        const ceiling = rhoCeiling(p);
        const src = bytes[5..];
        for (src) |r| {
            if (r > ceiling) {
                return HllError.RegisterOutOfRange;
            }
        }
        const regs = try allocator.alloc(u8, m);
        @memcpy(regs, src);
        return HyperLogLog{ .p = p, .regs = regs, .allocator = allocator };
    }
};

// ==========================================================================
// Native tests (testing allocator; no leaks). Mirror the Rust reference port's
// tests. The register array is the cross-language oracle; the estimate is
// native-only / tolerance-bounded.
// ==========================================================================

const testing = std.testing;

/// Recompute the expected `(idx, rho)` for an i32 item independently of the
/// implementation, so the register-update tests are a real oracle check.
fn expectedSplit(item: i32, p: u8) struct { idx: u32, rho: u8 } {
    const word: u64 = @as(u64, @as(u32, @bitCast(item)));
    const x = hash.hash64(word, 0);
    const idx: u32 = @truncate(x >> @intCast(64 - @as(u7, @intCast(p))));
    const w: u64 = (x << @as(u6, @intCast(p))) | (@as(u64, 1) << @intCast(p - 1));
    return .{ .idx = idx, .rho = @intCast(@as(u32, @clz(w)) + 1) };
}

fn toHex(allocator: Allocator, bytes: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, bytes.len * 2);
    const digits = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[2 * i] = digits[b >> 4];
        out[2 * i + 1] = digits[b & 0xf];
    }
    return out;
}

// ---- Construction & p-range -----------------------------------------

test "withPrecision allocates m registers" {
    var p: u8 = MIN_PRECISION;
    while (p <= MAX_PRECISION) : (p += 1) {
        var h = try HyperLogLog.withPrecision(testing.allocator, p);
        defer h.deinit();
        try testing.expectEqual(@as(usize, 1) << @intCast(p), h.registerCount());
        for (h.regs) |r| try testing.expectEqual(@as(u8, 0), r);
        try testing.expectEqual(@as(u32, 0), h.nonzeroRegisters());
        try testing.expectEqual(@as(u8, 0), h.maxRegister());
    }
}

test "p out of range errors never clamps" {
    try testing.expectError(HllError.BadPrecision, HyperLogLog.withPrecision(testing.allocator, 3));
    try testing.expectError(HllError.BadPrecision, HyperLogLog.withPrecision(testing.allocator, 19));
    try testing.expectError(HllError.BadPrecision, HyperLogLog.withPrecision(testing.allocator, 0));
    try testing.expectError(HllError.BadPrecision, HyperLogLog.withPrecision(testing.allocator, 255));
}

// ---- rho / clz / guard-bit exactness --------------------------------

test "split guard bit all-zero remainder gives max rho" {
    // Craft x whose low (64 - p) bits are all zero: x = idx << (64 - p).
    // Then w = (x << p) | guard = guard = 1 << (p-1); clz64 = 64-p; rho =
    // 64-p+1 (the per-p maximum). This is the all-zero-remainder pin.
    for ([_]u8{ 4, 7, 14, 18 }) |p| {
        const pp: u6 = @intCast(p);
        const idx: u64 = 5 & ((@as(u64, 1) << pp) - 1);
        const x: u64 = idx << @intCast(64 - @as(u7, @intCast(p)));
        const s = HyperLogLog.split(x, p);
        try testing.expectEqual(@as(u32, @intCast(idx)), s.idx);
        try testing.expectEqual(@as(u8, 64 - p + 1), s.rho);
        try testing.expectEqual(rhoCeiling(p), s.rho);
    }
}

test "split min rho is one" {
    // Top remaining bit set -> clz64(w) = 0 -> rho = 1 (the minimum).
    const p: u8 = 4;
    const x: u64 = @as(u64, 1) << @intCast(64 - @as(u7, @intCast(p)) - 1);
    const s = HyperLogLog.split(x, p);
    try testing.expectEqual(@as(u8, 1), s.rho);
}

test "split idx is top p bits logical" {
    // High-bit-set x must use a LOGICAL shift for the index.
    const x: u64 = 0xffffffffffffffff;
    for ([_]u8{ 4, 10, 18 }) |p| {
        const s = HyperLogLog.split(x, p);
        try testing.expectEqual((@as(u32, 1) << @intCast(p)) - 1, s.idx);
    }
}

test "split rho within per-p bounds" {
    var p: u8 = MIN_PRECISION;
    while (p <= MAX_PRECISION) : (p += 1) {
        var item: i32 = 0;
        while (item < 2000) : (item += 1) {
            const x = hash.hash64(@as(u64, @as(u32, @bitCast(item))), 0);
            const s = HyperLogLog.split(x, p);
            try testing.expect(s.idx < (@as(u32, 1) << @intCast(p)));
            try testing.expect(s.rho >= 1 and s.rho <= rhoCeiling(p));
        }
    }
}

test "add(0) all-zero remainder pins max rho (hll_high_rho oracle)" {
    // hash64(0,0) == 0 -> remaining 60 bits all zero -> guard bit pins rho =
    // 64-4+1 = 61 at idx 0.
    var h = try HyperLogLog.withPrecision(testing.allocator, 4);
    defer h.deinit();
    h.add(0);
    try testing.expectEqual(@as(u8, 61), h.regs[0]);
    try testing.expectEqual(@as(u8, 61), h.maxRegister());
    try testing.expectEqual(@as(u32, 1), h.nonzeroRegisters());
}

// ---- register max-update & idempotence ------------------------------

test "add updates expected register to rho" {
    const p: u8 = 14;
    var h = try HyperLogLog.withPrecision(testing.allocator, p);
    defer h.deinit();
    const s = expectedSplit(42, p);
    h.add(42);
    try testing.expectEqual(s.rho, h.regs[s.idx]);
    try testing.expectEqual(@as(u32, 1), h.nonzeroRegisters());
    try testing.expectEqual(s.rho, h.maxRegister());
}

test "add is max not overwrite and idempotent" {
    const p: u8 = 4;
    var a = try HyperLogLog.withPrecision(testing.allocator, p);
    defer a.deinit();
    a.add(7);
    var b = try HyperLogLog.withPrecision(testing.allocator, p);
    defer b.deinit();
    b.add(7);
    b.add(7);
    b.add(7);
    try testing.expectEqualSlices(u8, a.regs, b.regs);
}

test "add order independent" {
    const p: u8 = 6;
    var ab = try HyperLogLog.withPrecision(testing.allocator, p);
    defer ab.deinit();
    ab.add(11);
    ab.add(99999);
    var ba = try HyperLogLog.withPrecision(testing.allocator, p);
    defer ba.deinit();
    ba.add(99999);
    ba.add(11);
    try testing.expectEqualSlices(u8, ab.regs, ba.regs);
}

test "neg one zero-extend differs from sign-extend" {
    // add(-1) encodes 0x00000000ffffffff (zero-extend). The would-be
    // sign-extend (0xffffffffffffffff) yields a different x -> different
    // (idx, rho). Pin that the implementation uses the zero-extend.
    const p: u8 = 4;
    var h = try HyperLogLog.withPrecision(testing.allocator, p);
    defer h.deinit();
    h.add(-1);
    const zs = HyperLogLog.split(hash.hash64(0x00000000ffffffff, 0), p);
    const ss = HyperLogLog.split(hash.hash64(0xffffffffffffffff, 0), p);
    try testing.expectEqual(zs.rho, h.regs[zs.idx]);
    try testing.expect(zs.idx != ss.idx or zs.rho != ss.rho);
}

// ---- merge: element-wise max, p-mismatch ----------------------------

test "merge is element-wise max" {
    const p: u8 = 4;
    var a = try HyperLogLog.withPrecision(testing.allocator, p);
    defer a.deinit();
    for ([_]i32{ 1, 2, 3 }) |v| a.add(v);
    var b = try HyperLogLog.withPrecision(testing.allocator, p);
    defer b.deinit();
    for ([_]i32{ 3, 4, 5 }) |v| b.add(v);

    const expected = try testing.allocator.alloc(u8, a.regs.len);
    defer testing.allocator.free(expected);
    for (expected, a.regs, b.regs) |*e, av, bv| e.* = @max(av, bv);

    try a.merge(&b);
    try testing.expectEqualSlices(u8, expected, a.regs);
}

test "merge commutative and idempotent" {
    const p: u8 = 5;
    const build = struct {
        fn f(items: []const i32) !HyperLogLog {
            var h = try HyperLogLog.withPrecision(testing.allocator, p);
            for (items) |v| h.add(v);
            return h;
        }
    }.f;

    var ab = try build(&[_]i32{ 10, 20, 30 });
    defer ab.deinit();
    var bset = try build(&[_]i32{ 30, 40, 50 });
    defer bset.deinit();
    try ab.merge(&bset);

    var ba = try build(&[_]i32{ 30, 40, 50 });
    defer ba.deinit();
    var aset = try build(&[_]i32{ 10, 20, 30 });
    defer aset.deinit();
    try ba.merge(&aset);
    try testing.expectEqualSlices(u8, ab.regs, ba.regs);

    // Idempotent: merge(a, a) == a.
    var a = try build(&[_]i32{ 10, 20, 30 });
    defer a.deinit();
    var aa = try build(&[_]i32{ 10, 20, 30 });
    defer aa.deinit();
    try aa.merge(&a);
    try testing.expectEqualSlices(u8, aa.regs, a.regs);
}

test "merge p-mismatch errors" {
    var a = try HyperLogLog.withPrecision(testing.allocator, 4);
    defer a.deinit();
    var b = try HyperLogLog.withPrecision(testing.allocator, 5);
    defer b.deinit();
    try testing.expectError(HllError.PrecisionMismatch, a.merge(&b));
}

// ---- serialization round-trip + rejections --------------------------

test "serialize roundtrip and header" {
    var h = try HyperLogLog.withPrecision(testing.allocator, 4);
    defer h.deinit();
    h.add(1);
    h.add(7);
    h.add(-1);
    const bytes = try h.toBytes(testing.allocator);
    defer testing.allocator.free(bytes);
    try testing.expectEqual(@as(usize, 5 + 16), bytes.len);
    try testing.expectEqualSlices(u8, &MAGIC, bytes[0..4]);
    try testing.expectEqual(@as(u8, 4), bytes[4]);
    var back = try HyperLogLog.fromBytes(testing.allocator, bytes);
    defer back.deinit();
    try testing.expectEqual(h.p, back.p);
    try testing.expectEqualSlices(u8, h.regs, back.regs);
}

test "empty p4 register_hex anchor" {
    var h = try HyperLogLog.withPrecision(testing.allocator, 4);
    defer h.deinit();
    const bytes = try h.toBytes(testing.allocator);
    defer testing.allocator.free(bytes);
    const hex = try toHex(testing.allocator, bytes);
    defer testing.allocator.free(hex);
    try testing.expectEqualStrings("484c4c310400000000000000000000000000000000", hex);
}

test "fromBytes rejects bad magic" {
    var h = try HyperLogLog.withPrecision(testing.allocator, 4);
    defer h.deinit();
    const bytes = try h.toBytes(testing.allocator);
    defer testing.allocator.free(bytes);
    bytes[0] = 0x00;
    try testing.expectError(HllError.BadMagic, HyperLogLog.fromBytes(testing.allocator, bytes));
}

test "fromBytes rejects too short" {
    try testing.expectError(HllError.TooShort, HyperLogLog.fromBytes(testing.allocator, &[_]u8{ 0x48, 0x4c, 0x4c }));
}

test "fromBytes rejects bad p" {
    var h = try HyperLogLog.withPrecision(testing.allocator, 4);
    defer h.deinit();
    const bytes = try h.toBytes(testing.allocator);
    defer testing.allocator.free(bytes);
    bytes[4] = 3;
    try testing.expectError(HllError.BadPrecision, HyperLogLog.fromBytes(testing.allocator, bytes));
    bytes[4] = 19;
    try testing.expectError(HllError.BadPrecision, HyperLogLog.fromBytes(testing.allocator, bytes));
}

test "fromBytes rejects length mismatch" {
    var h = try HyperLogLog.withPrecision(testing.allocator, 4);
    defer h.deinit();
    const base = try h.toBytes(testing.allocator);
    defer testing.allocator.free(base);
    // One byte too many.
    const longer = try testing.allocator.alloc(u8, base.len + 1);
    defer testing.allocator.free(longer);
    @memcpy(longer[0..base.len], base);
    longer[base.len] = 0;
    try testing.expectError(HllError.LengthMismatch, HyperLogLog.fromBytes(testing.allocator, longer));
    // Truncated.
    try testing.expectError(HllError.LengthMismatch, HyperLogLog.fromBytes(testing.allocator, base[0..20]));
}

test "fromBytes rejects register above ceiling p4 (61 ok, 62 rejected)" {
    // At p=4 the ceiling is 64-4+1 = 61.
    var h = try HyperLogLog.withPrecision(testing.allocator, 4);
    defer h.deinit();
    const bytes = try h.toBytes(testing.allocator);
    defer testing.allocator.free(bytes);
    bytes[5] = 62;
    try testing.expectError(HllError.RegisterOutOfRange, HyperLogLog.fromBytes(testing.allocator, bytes));
    bytes[5] = 61;
    var ok = try HyperLogLog.fromBytes(testing.allocator, bytes);
    ok.deinit();
}

test "fromBytes ceiling is per-p p18 (47 ok, 48 rejected)" {
    // At p=18 the ceiling is 64-18+1 = 47.
    var h = try HyperLogLog.withPrecision(testing.allocator, 18);
    defer h.deinit();
    const bytes = try h.toBytes(testing.allocator);
    defer testing.allocator.free(bytes);
    bytes[5] = 48;
    try testing.expectError(HllError.RegisterOutOfRange, HyperLogLog.fromBytes(testing.allocator, bytes));
    bytes[5] = 47;
    var ok = try HyperLogLog.fromBytes(testing.allocator, bytes);
    ok.deinit();
}

// ---- estimate(): native-only, tolerance-bounded ---------------------

test "fresh HLL estimates zero" {
    for ([_]u8{ 4, 7, 14 }) |p| {
        var h = try HyperLogLog.withPrecision(testing.allocator, p);
        defer h.deinit();
        try testing.expectEqual(@as(f64, 0.0), h.estimate());
    }
}

test "estimate within tolerance on known cardinality" {
    // Documented tolerance: relative error < 5% (covers HLL's ~1.04/sqrt(m)
    // standard error AND cross-libm float drift). p=14 -> m=16384.
    const p: u8 = 14;
    const n: i32 = 10_000;
    var h = try HyperLogLog.withPrecision(testing.allocator, p);
    defer h.deinit();
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        h.add(i *% @as(i32, @bitCast(@as(u32, 2_654_435_761))));
    }
    const est = h.estimate();
    const rel = @abs(est - @as(f64, @floatFromInt(n))) / @as(f64, @floatFromInt(n));
    try testing.expect(rel < 0.05);
}

test "estimate small cardinality linear counting" {
    const p: u8 = 14;
    const n: i32 = 300;
    var h = try HyperLogLog.withPrecision(testing.allocator, p);
    defer h.deinit();
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        h.add(i *% @as(i32, @bitCast(@as(u32, 2_654_435_761))));
    }
    const est = h.estimate();
    const rel = @abs(est - @as(f64, @floatFromInt(n))) / @as(f64, @floatFromInt(n));
    try testing.expect(rel < 0.05);
}

test "alphaM matches pinned constants" {
    try testing.expectEqual(@as(f64, 0.673), HyperLogLog.alphaM(4));
    try testing.expectEqual(@as(f64, 0.697), HyperLogLog.alphaM(5));
    try testing.expectEqual(@as(f64, 0.709), HyperLogLog.alphaM(6));
    try testing.expectEqual(0.7213 / (1.0 + 1.079 / 128.0), HyperLogLog.alphaM(7));
}

test "estimate large range correction is finite" {
    // All registers NEAR the per-p max via fromBytes so raw E exceeds
    // (1/30)*2^64 while staying below 2^64; assert estimate() is finite.
    const p: u8 = 4;
    const near_max = rhoCeiling(p) - 1;
    var h = try HyperLogLog.withPrecision(testing.allocator, p);
    defer h.deinit();
    const bytes = try h.toBytes(testing.allocator);
    defer testing.allocator.free(bytes);
    for (bytes[5..]) |*b| b.* = near_max;
    var loaded = try HyperLogLog.fromBytes(testing.allocator, bytes);
    defer loaded.deinit();
    try testing.expect(std.math.isFinite(loaded.estimate()));
}

// ---- authoritative register_hex values for the scenarios ------------

test "scenario oracle values" {
    // single add(1) at p=4
    var h = try HyperLogLog.withPrecision(testing.allocator, 4);
    defer h.deinit();
    h.add(1);
    const bytes = try h.toBytes(testing.allocator);
    defer testing.allocator.free(bytes);
    const hex = try toHex(testing.allocator, bytes);
    defer testing.allocator.free(hex);
    try testing.expectEqualStrings("484c4c310400000000000000000000000200000000", hex);
    try testing.expectEqual(@as(u32, 1), h.nonzeroRegisters());
    try testing.expectEqual(@as(u8, 2), h.maxRegister());
    try testing.expectEqual(@as(u8, 2), h.regs[11]);
}
