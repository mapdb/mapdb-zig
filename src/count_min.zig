// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Count-Min Sketch — a `d×w` integer counter matrix giving a one-sided
//! **over**-estimate of an element's frequency, riding the deterministic hash
//! pipeline (see `spec/features/count-min.md`).
//!
//! The counter matrix after a given add-sequence is the cross-language oracle:
//! because the `d` column indices are exactly `hash.positions(encodeI32(item),
//! w, d)` — bit-identical across all five ports — the entire matrix, every
//! `estimate`, and `total` are bit-identical too. **No floating point** appears
//! in the deterministic surface (the only float, `optimal`, is native-only and
//! never used by the shared scenarios).
//!
//! Pinned rulings:
//! - **Row-hash derivation:** the column touched in row `r` is the `r`-th of
//!   `positions(encodeI32(item), m = w, k = d)` in derivation order
//!   (`c_r = (h1 + r*h2) mod w`). Repeated column numbers across rows touch
//!   **distinct** counters (one counter array per row) — NOT de-duplicated.
//! - **`estimate` = MIN over the `d` rows** (never average/sum/median/row-0).
//!   The empty MIN (`d = 0`) is `maxInt(u64)`.
//! - **Overflow SATURATES at `maxInt(u64)`** (does NOT wrap) — via the `+|`
//!   saturating-add operator; required by the no-under-estimate guarantee.
//! - **`add(item, count)` increments by `count`** (plain CMS, no conservative
//!   update); `addOne` == `add(item, 1)`.
//! - **Element encoding:** `i32` → reinterpret `u32` → 4 LE bytes → the byte
//!   `positions` path (length fold applied), identical to Bloom.

const std = @import("std");
const Allocator = std.mem.Allocator;
const hash = @import("hash.zig");

/// A Count-Min Sketch over a flat row-major `[]u64` matrix of `d*w` counters.
///
/// Construct with `withParams` (the only constructor the cross-language
/// scenarios use) or the native-only `optimal`. Caller owns the allocator;
/// release with `deinit`.
pub const CountMin = struct {
    d: u32,
    w: u32,
    /// Flat row-major matrix: counter `matrix[r*w + col]` is row `r`, column
    /// `col`. Length is exactly `d*w`.
    matrix: []u64,
    /// Running sum of every `count` argument (the stream length `N`), saturating.
    total_count: u64,
    allocator: Allocator,

    /// Construct a `d×w` sketch with all counters zero. `d` is the depth (rows /
    /// hash functions = the `k` argument to `positions`); `w` is the width
    /// (columns per row = the `m` argument to `positions`).
    ///
    /// `w == 0` is invalid (a zero-column row holds nothing and every modulo
    /// would divide by zero) and traps — identical to Bloom's `m = 0` ruling.
    /// `d == 0` is legal and degenerate (an empty matrix; `estimate` returns
    /// `maxInt(u64)`).
    pub fn withParams(allocator: Allocator, d: u32, w: u32) Allocator.Error!CountMin {
        // Required-input trap: always-on (`std.debug.assert` is compiled out in
        // ReleaseFast/ReleaseSmall, turning a `w == 0` divide-by-zero into UB).
        if (w == 0) @panic("CountMin width w must be non-zero");
        const len: usize = @as(usize, d) * @as(usize, w);
        const matrix = try allocator.alloc(u64, len);
        @memset(matrix, 0);
        return .{
            .d = d,
            .w = w,
            .matrix = matrix,
            .total_count = 0,
            .allocator = allocator,
        };
    }

    /// Native-only convenience constructor sizing the sketch from a target
    /// additive error `epsilon` and failure probability `delta` using the
    /// standard Count-Min formulas `w = ceil(e/epsilon)`,
    /// `d = ceil(ln(1/delta))`, then delegating to `withParams`.
    ///
    /// **Float-quarantined: never used by the cross-language scenarios** (the
    /// `ln`/`e`/`ceil` derivation can drift across libm implementations). Each
    /// port native-tests it against the pinned integer table.
    ///
    /// Requires `0 < epsilon < 1` and `0 < delta < 1`; values `<= 0`, `>= 1`,
    /// `NaN`, or `±Infinity` are invalid and trap.
    pub fn optimal(allocator: Allocator, epsilon: f64, delta: f64) Allocator.Error!CountMin {
        // Required-input traps: always-on (`std.debug.assert` is compiled out
        // in ReleaseFast/ReleaseSmall, turning a non-positive epsilon/delta into
        // a non-finite `(d, w)` and UB at the float->int cast / withParams).
        if (!(epsilon > 0.0 and epsilon < 1.0)) @panic("CountMin.optimal requires 0 < epsilon < 1");
        if (!(delta > 0.0 and delta < 1.0)) @panic("CountMin.optimal requires 0 < delta < 1");
        const w_f = @ceil(std.math.e / epsilon);
        const d_f = @ceil(@log(1.0 / delta));
        if (!(std.math.isFinite(w_f) and std.math.isFinite(d_f) and w_f >= 1.0 and d_f >= 1.0))
            @panic("CountMin.optimal produced a non-finite (d, w)");
        return withParams(allocator, @intFromFloat(d_f), @intFromFloat(w_f));
    }

    /// Release the counter matrix.
    pub fn deinit(self: *CountMin) void {
        self.allocator.free(self.matrix);
        self.* = undefined;
    }

    /// The little-endian 4-byte encoding of an i32 element: reinterpret to u32
    /// (NOT sign-extend), then LE bytes — the byte `positions` path (length
    /// fold applied), identical to Bloom.
    fn encodeI32(item: i32) [4]u8 {
        var le: [4]u8 = undefined;
        std.mem.writeInt(u32, &le, @bitCast(item), .little);
        return le;
    }

    /// The two Kirsch–Mitzenmacher base hashes for `item`, computed exactly as
    /// `hash.positions(encodeI32(item), …)` does: `h1 = hash32Bytes(le, 0)`,
    /// `h2 = hash32Bytes(le, SALT2)`. Reused so `add`/`estimate` derive the `d`
    /// columns without allocating a positions buffer; the per-row column is then
    /// `(h1 +% r*%h2) % w`, identical to `positionsFromHashes`.
    fn baseHashes(item: i32) struct { h1: u32, h2: u32 } {
        const le = encodeI32(item);
        return .{ .h1 = hash.hash32Bytes(&le, 0), .h2 = hash.hash32Bytes(&le, hash.SALT2) };
    }

    /// The column touched in row `r`: `(h1 +% r*%h2) % w`, the `r`-th
    /// `positionsFromHashes` output. Identical to `positions()[r]`.
    fn columnAt(h1: u32, h2: u32, r: u32, w: u32) u32 {
        const combined: u32 = h1 +% (r *% h2);
        return combined % w;
    }

    /// Increment the `d` selected counters (one per row) by `count`, saturating
    /// at `maxInt(u64)`. `add(item, count)` yields the identical counters to
    /// `count` repeated `addOne` calls (increments are commutative). `count = 0`
    /// is legal: a no-op on the counters that still updates `total` (by 0).
    /// Plain CMS — increments **all** `d` counters (no conservative update).
    pub fn add(self: *CountMin, item: i32, count: u64) void {
        const bh = baseHashes(item);
        // The d columns are positions(encodeI32(item), w, d) in derivation order;
        // c_r is the column touched in row r. d == 0 -> no counter touched.
        var r: u32 = 0;
        while (r < self.d) : (r += 1) {
            const c = columnAt(bh.h1, bh.h2, r, self.w);
            const idx = @as(usize, r) * @as(usize, self.w) + @as(usize, c);
            self.matrix[idx] +|= count;
        }
        self.total_count +|= count;
    }

    /// Convenience for `add(item, 1)`; identical bits.
    pub fn addOne(self: *CountMin, item: i32) void {
        self.add(item, 1);
    }

    /// The frequency estimate for `item`: the **MIN** over the `d` rows of the
    /// selected counter. Never under-estimates (within the `u64` domain). For
    /// `d = 0` the MIN over zero rows is the empty-min identity `maxInt(u64)`.
    pub fn estimate(self: *const CountMin, item: i32) u64 {
        const bh = baseHashes(item);
        var min: u64 = std.math.maxInt(u64);
        var r: u32 = 0;
        while (r < self.d) : (r += 1) {
            const c = columnAt(bh.h1, bh.h2, r, self.w);
            const idx = @as(usize, r) * @as(usize, self.w) + @as(usize, c);
            if (self.matrix[idx] < min) min = self.matrix[idx];
        }
        return min;
    }

    /// The running sum of every `count` argument ever added (the stream length
    /// `N`), saturating at `maxInt(u64)`.
    pub fn total(self: *const CountMin) u64 {
        return self.total_count;
    }

    /// The depth `d` (number of rows / hash functions).
    pub fn depth(self: *const CountMin) u32 {
        return self.d;
    }

    /// The width `w` (number of columns per row).
    pub fn width(self: *const CountMin) u32 {
        return self.w;
    }

    /// The full counter matrix as `d*w` values, **row-major** (row 0 first,
    /// column 0 first within a row). Dense (all cells, including zeros). Returns
    /// a freshly allocated, caller-owned slice of length exactly `d*w`.
    pub fn toCounters(self: *const CountMin, allocator: Allocator) Allocator.Error![]u64 {
        const out = try allocator.alloc(u64, self.matrix.len);
        @memcpy(out, self.matrix);
        return out;
    }
};

// ── Tests ────────────────────────────────────────────────────────────────────

const testing = std.testing;

fn encode(item: i32) [4]u8 {
    var le: [4]u8 = undefined;
    std.mem.writeInt(u32, &le, @bitCast(item), .little);
    return le;
}

fn positionsAlloc(allocator: Allocator, item: i32, m: u32, k: u32) ![]u32 {
    const le = encode(item);
    const out = try allocator.alloc(u32, k);
    hash.positions(&le, m, k, out);
    return out;
}

test "row-hash matches positions (byte path)" {
    const a = testing.allocator;
    var c = try CountMin.withParams(a, 4, 16);
    defer c.deinit();
    // The d columns are EXACTLY positions(encodeI32(item), w, d) in order.
    const cols = try positionsAlloc(a, 7, 16, 4);
    defer a.free(cols);
    // Pinned worked example: add(7) over (d=4,w=16) touches [7,0,9,2].
    try testing.expectEqualSlices(u32, &[_]u32{ 7, 0, 9, 2 }, cols);
}

test "addOne touches the four columns; estimate=min; total" {
    const a = testing.allocator;
    var c = try CountMin.withParams(a, 4, 16);
    defer c.deinit();
    c.addOne(7);
    const m = try c.toCounters(a);
    defer a.free(m);
    try testing.expectEqual(@as(u64, 1), m[7]); // row 0, col 7
    try testing.expectEqual(@as(u64, 1), m[16]); // row 1, col 0
    try testing.expectEqual(@as(u64, 1), m[2 * 16 + 9]); // row 2, col 9
    try testing.expectEqual(@as(u64, 1), m[3 * 16 + 2]); // row 3, col 2
    var ones: usize = 0;
    for (m) |v| {
        if (v == 1) ones += 1;
    }
    try testing.expectEqual(@as(usize, 4), ones);
    try testing.expectEqual(@as(u64, 1), c.estimate(7));
    try testing.expectEqual(@as(u64, 1), c.total());
    try testing.expectEqual(@as(usize, 64), m.len);
}

test "add by count equals repeated addOne" {
    const a = testing.allocator;
    var x = try CountMin.withParams(a, 3, 13);
    defer x.deinit();
    var y = try CountMin.withParams(a, 3, 13);
    defer y.deinit();
    x.add(42, 5);
    for (0..5) |_| y.addOne(42);
    const mx = try x.toCounters(a);
    defer a.free(mx);
    const my = try y.toCounters(a);
    defer a.free(my);
    try testing.expectEqualSlices(u64, mx, my);
    try testing.expectEqual(@as(u64, 5), x.estimate(42));
    try testing.expectEqual(@as(u64, 5), x.total());
}

test "add count accumulates" {
    const a = testing.allocator;
    var c = try CountMin.withParams(a, 4, 16);
    defer c.deinit();
    c.add(7, 5);
    c.add(7, 3);
    try testing.expectEqual(@as(u64, 8), c.estimate(7));
    try testing.expectEqual(@as(u64, 8), c.total());
}

test "count=0 is a counter no-op but updates total" {
    const a = testing.allocator;
    var c = try CountMin.withParams(a, 3, 7);
    defer c.deinit();
    c.add(1, 0);
    const m0 = try c.toCounters(a);
    defer a.free(m0);
    for (m0) |v| try testing.expectEqual(@as(u64, 0), v);
    try testing.expectEqual(@as(u64, 0), c.total());
    c.add(1, 4);
    c.add(1, 0);
    try testing.expectEqual(@as(u64, 4), c.estimate(1));
    try testing.expectEqual(@as(u64, 4), c.total());
}

test "collision across rows not de-duplicated" {
    const a = testing.allocator;
    const d: u32 = 3;
    var w: u32 = 2;
    while (w < 32) : (w += 1) {
        var item: i32 = 0;
        while (item < 256) : (item += 1) {
            const cols = try positionsAlloc(a, item, w, d);
            defer a.free(cols);
            // find two rows sharing a column number.
            var r0: ?u32 = null;
            var r1: ?u32 = null;
            var col: u32 = 0;
            outer: for (cols, 0..) |ca, ia| {
                for (cols[ia + 1 ..], ia + 1..) |cb, ib| {
                    if (ca == cb) {
                        r0 = @intCast(ia);
                        r1 = @intCast(ib);
                        col = ca;
                        break :outer;
                    }
                }
            }
            if (r0 != null) {
                var c = try CountMin.withParams(a, d, w);
                defer c.deinit();
                c.addOne(item);
                const m = try c.toCounters(a);
                defer a.free(m);
                try testing.expectEqual(@as(u64, 1), m[@as(usize, r0.?) * w + col]);
                try testing.expectEqual(@as(u64, 1), m[@as(usize, r1.?) * w + col]);
                try testing.expectEqual(@as(u64, 1), c.estimate(item));
                return;
            }
        }
    }
    return error.NoCollisionFound;
}

test "estimate is MIN not average or row0" {
    const a = testing.allocator;
    var c = try CountMin.withParams(a, 4, 8);
    defer c.deinit();
    const target: i32 = 5;
    c.add(target, 1);
    var other: i32 = 0;
    while (other < 200) : (other += 1) {
        if (other == target) continue;
        c.add(other, 7);
    }
    const cols = try positionsAlloc(a, target, 8, 4);
    defer a.free(cols);
    const m = try c.toCounters(a);
    defer a.free(m);
    var min: u64 = std.math.maxInt(u64);
    var max: u64 = 0;
    for (cols, 0..) |col, r| {
        const v = m[r * 8 + col];
        if (v < min) min = v;
        if (v > max) max = v;
    }
    try testing.expectEqual(min, c.estimate(target));
    try testing.expect(c.estimate(target) >= 1);
    try testing.expect(max >= min);
}

test "overflow saturates, not wraps" {
    const a = testing.allocator;
    var c = try CountMin.withParams(a, 2, 4);
    defer c.deinit();
    c.add(9, std.math.maxInt(u64));
    c.add(9, 5);
    try testing.expectEqual(std.math.maxInt(u64), c.estimate(9));
    try testing.expectEqual(std.math.maxInt(u64), c.total());
    const cols = try positionsAlloc(a, 9, 4, 2);
    defer a.free(cols);
    const m = try c.toCounters(a);
    defer a.free(m);
    for (cols, 0..) |col, r| {
        try testing.expectEqual(std.math.maxInt(u64), m[r * 4 + col]);
    }
}

test "no under-estimate (signed extremes)" {
    const a = testing.allocator;
    var c = try CountMin.withParams(a, 5, 64);
    defer c.deinit();
    c.add(-1, 3);
    c.add(std.math.minInt(i32), 10);
    try testing.expect(c.estimate(-1) >= 3);
    try testing.expect(c.estimate(std.math.minInt(i32)) >= 10);
}

test "order independence" {
    const a = testing.allocator;
    var x = try CountMin.withParams(a, 4, 16);
    defer x.deinit();
    var y = try CountMin.withParams(a, 4, 16);
    defer y.deinit();
    const seq = [_]struct { it: i32, ct: u64 }{
        .{ .it = 1, .ct = 3 },
        .{ .it = 2, .ct = 5 },
        .{ .it = 1, .ct = 2 },
        .{ .it = -7, .ct = 9 },
        .{ .it = std.math.maxInt(i32), .ct = 1 },
    };
    for (seq) |s| x.add(s.it, s.ct);
    var i: usize = seq.len;
    while (i > 0) {
        i -= 1;
        y.add(seq[i].it, seq[i].ct);
    }
    const mx = try x.toCounters(a);
    defer a.free(mx);
    const my = try y.toCounters(a);
    defer a.free(my);
    try testing.expectEqualSlices(u64, mx, my);
    try testing.expectEqual(x.total(), y.total());
}

test "d=0 is legal vacuous-MAX" {
    const a = testing.allocator;
    var c = try CountMin.withParams(a, 0, 16);
    defer c.deinit();
    c.add(5, 1);
    const m = try c.toCounters(a);
    defer a.free(m);
    try testing.expectEqual(@as(usize, 0), m.len);
    try testing.expectEqual(@as(u64, 1), c.total());
    try testing.expectEqual(std.math.maxInt(u64), c.estimate(5));
}

test "empty matrix is all-zero dense" {
    const a = testing.allocator;
    var c = try CountMin.withParams(a, 4, 16);
    defer c.deinit();
    const m = try c.toCounters(a);
    defer a.free(m);
    try testing.expectEqual(@as(usize, 64), m.len);
    for (m) |v| try testing.expectEqual(@as(u64, 0), v);
    try testing.expectEqual(@as(u64, 0), c.estimate(7));
    try testing.expectEqual(@as(u64, 0), c.total());
}

test "element encoding byte path" {
    try testing.expectEqual([4]u8{ 0xff, 0xff, 0xff, 0xff }, encode(-1));
    try testing.expectEqual([4]u8{ 0x00, 0x00, 0x00, 0x80 }, encode(std.math.minInt(i32)));
    try testing.expectEqual([4]u8{ 0x07, 0x00, 0x00, 0x00 }, encode(7));
}

test "optimal integer table (native-only)" {
    const a = testing.allocator;
    const Case = struct { eps: f64, delta: f64, w: u32, d: u32 };
    const cases = [_]Case{
        .{ .eps = 0.01, .delta = 0.01, .w = 272, .d = 5 },
        .{ .eps = 0.001, .delta = 0.001, .w = 2719, .d = 7 },
        .{ .eps = 0.1, .delta = 0.05, .w = 28, .d = 3 },
        .{ .eps = 0.01, .delta = 0.001, .w = 272, .d = 7 },
        .{ .eps = 0.5, .delta = 0.5, .w = 6, .d = 1 },
    };
    for (cases) |cs| {
        var c = try CountMin.optimal(a, cs.eps, cs.delta);
        defer c.deinit();
        try testing.expectEqual(cs.w, c.width());
        try testing.expectEqual(cs.d, c.depth());
    }
}
