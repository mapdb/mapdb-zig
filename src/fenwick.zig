// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Fenwick tree / Binary Indexed Tree (prefix & range sums).
//!
//! A fixed-size index structure with O(log n) point-update and O(log n)
//! prefix/range sum over signed `i32` element values accumulated in a wrapping
//! `i64` accumulator. See `spec/features/fenwick.md` (mapdb-collection-spec)
//! for the pinned design; this is a port of the frozen reference
//! (mapdb-rust `src/fenwick.rs`).
//!
//! Pinned invariants realized here:
//! - **Indexing**: the public API is 0-based (`0 .. n-1`); the BIT is
//!   classically 1-based internally (`internal = public + 1`). The 1-based
//!   index is never observable. The backing array is length `n + 1` with slot 0
//!   unused.
//! - **Ranges**: `prefixSum(i)` is the INCLUSIVE prefix `[0..=i]`;
//!   `rangeSum(lo, hi)` is the INCLUSIVE closed range `[lo..=hi]`;
//!   `total() == prefixSum(n-1)` (and `0` for the empty tree).
//! - **Accumulator**: each slot and every sum is a wrapping two's-complement
//!   `i64` (Zig `+%` / `-%`; checked `+`/`-` trap in Debug/ReleaseSafe). The
//!   per-element value widens to `i64` and does NOT re-wrap at `i32`, so `get`
//!   returns `i64`.
//! - **Out-of-range**: mutators (`update`/`set`), `get`, and `prefixSum` trap
//!   on an out-of-domain index. `rangeSum` validates BOTH endpoints first
//!   (out-of-domain endpoint traps), THEN returns `0` for an empty `lo > hi`
//!   range. (Zig indexes with `usize`, so only `i >= n` is representable —
//!   `i < 0` is unrepresentable, not a runtime trap.)

const std = @import("std");
const Allocator = std.mem.Allocator;

/// A Fenwick tree (Binary Indexed Tree) over `i32` element values with a
/// wrapping `i64` accumulator. Fixed size; no resize.
///
/// The backing array `tree` has length `n + 1`: slot `0` is the unused BIT
/// terminator and `tree[1 ..= n]` are the 1-based partial sums.
pub const FenwickTree = struct {
    /// 1-based partial sums; `tree[0]` unused. Length is `n + 1`.
    tree: []i64,
    /// Public size `n` (number of valid 0-based indices).
    n: usize,
    allocator: Allocator,

    /// Construct an all-zero tree of size `n`. `withSize(allocator, 0)` is a
    /// valid empty tree (`total() == 0`, `isEmpty() == true`). The caller owns
    /// the result and must `deinit` it.
    pub fn withSize(allocator: Allocator, n: usize) Allocator.Error!FenwickTree {
        const tree = try allocator.alloc(i64, n + 1);
        @memset(tree, 0);
        return .{ .tree = tree, .n = n, .allocator = allocator };
    }

    /// Build from an initial `i32` array; the tree has `size() == values.len`
    /// and `get(i) == values[i]`. Uses the O(n) in-place build (it produces the
    /// identical tree as `withSize(len)` then `update(i, values[i])`). The
    /// caller owns the result and must `deinit` it.
    pub fn fromValues(allocator: Allocator, values: []const i32) Allocator.Error!FenwickTree {
        const n = values.len;
        const tree = try allocator.alloc(i64, n + 1);
        tree[0] = 0;
        // Seed each 1-based slot with the (widened) element value.
        for (values, 0..) |v, i| {
            tree[i + 1] = @as(i64, v);
        }
        // O(n) in-place build: push each slot's running sum to its parent.
        // Over the 1-based array: parent = i + (i & -i).
        var i: usize = 1;
        while (i <= n) : (i += 1) {
            const parent = i + lowbit(i);
            if (parent <= n) {
                tree[parent] = tree[parent] +% tree[i];
            }
        }
        return .{ .tree = tree, .n = n, .allocator = allocator };
    }

    /// Free the backing array.
    pub fn deinit(self: *FenwickTree) void {
        self.allocator.free(self.tree);
        self.* = undefined;
    }

    /// Number of valid 0-based indices.
    pub fn len(self: *const FenwickTree) usize {
        return self.n;
    }

    /// True iff the tree is empty (`n == 0`).
    pub fn isEmpty(self: *const FenwickTree) bool {
        return self.n == 0;
    }

    /// Add `delta` (`i32`, widened to `i64`) to the value at 0-based index `i`.
    /// Traps if `i >= n` (out of the fixed `0 .. n-1` domain).
    pub fn update(self: *FenwickTree, i: usize, delta: i32) void {
        self.addInternal(i, @as(i64, delta));
    }

    /// Point-assign: make the value at `i` equal `value` (`i32`).
    ///
    /// Implemented as a Fenwick difference-add computed in wrapping `i64`
    /// (`delta = (value as i64) -% get(i)`), NOT routed through the `i32`
    /// `update` signature — so the internal delta stays exact even when the
    /// current slot value already exceeds `i32`.
    ///
    /// Traps if `i >= n`.
    pub fn set(self: *FenwickTree, i: usize, value: i32) void {
        const delta: i64 = @as(i64, value) -% self.get(i);
        self.addInternal(i, delta);
    }

    /// The single logical value currently at 0-based index `i`, as `i64`.
    /// Equivalent to `rangeSum(i, i)`.
    ///
    /// Traps if `i >= n`.
    pub fn get(self: *const FenwickTree, i: usize) i64 {
        if (i >= self.n) {
            std.debug.panic("FenwickTree.get index {d} out of range 0..{d}", .{ i, self.n });
        }
        // get(i) == prefixSum(i) - prefixSum(i-1); prefixSum(-1) := 0.
        if (i == 0) {
            return self.prefixSumInternal(0);
        }
        return self.prefixSumInternal(i) -% self.prefixSumInternal(i - 1);
    }

    /// Inclusive prefix sum `Σ values[0..=i]`, as wrapping `i64`.
    ///
    /// Traps if `i >= n`.
    pub fn prefixSum(self: *const FenwickTree, i: usize) i64 {
        if (i >= self.n) {
            std.debug.panic("FenwickTree.prefixSum index {d} out of range 0..{d}", .{ i, self.n });
        }
        return self.prefixSumInternal(i);
    }

    /// Inclusive range sum `Σ values[lo..=hi]`, as wrapping `i64`.
    ///
    /// Validates BOTH endpoints first: `lo` and `hi` must be valid public
    /// indices (`< n`). Only after both are valid, if `lo > hi` the range is
    /// empty and returns `0`.
    ///
    /// Traps if `lo >= n` or `hi >= n` (out-of-domain endpoint). On the empty
    /// tree every call traps (no valid endpoint exists).
    pub fn rangeSum(self: *const FenwickTree, lo: usize, hi: usize) i64 {
        if (lo >= self.n) {
            std.debug.panic("FenwickTree.rangeSum lo {d} out of range 0..{d}", .{ lo, self.n });
        }
        if (hi >= self.n) {
            std.debug.panic("FenwickTree.rangeSum hi {d} out of range 0..{d}", .{ hi, self.n });
        }
        // Both endpoints valid; an empty closed range (lo > hi) is a defined 0.
        if (lo > hi) {
            return 0;
        }
        // rangeSum = prefixSum(hi) - prefixSum(lo-1); prefixSum(-1) := 0.
        const upper = self.prefixSumInternal(hi);
        const lower: i64 = if (lo == 0) 0 else self.prefixSumInternal(lo - 1);
        return upper -% lower;
    }

    /// Grand total `Σ` of all values, `== prefixSum(n-1)` for `n >= 1`, and
    /// `0` for the empty tree.
    pub fn total(self: *const FenwickTree) i64 {
        if (self.n == 0) {
            return 0;
        }
        return self.prefixSumInternal(self.n - 1);
    }

    /// The canonical 1-based BIT projection: a freshly allocated length-`n`
    /// `i64` array where element `j-1` (0-based in the returned slice) is the
    /// partial sum the tree stores for the 1-based index `j` — i.e.
    /// `tree[1 ..= n]`. This is the layout-independent secondary determinism
    /// oracle. The caller owns the returned slice.
    pub fn canonicalTree(self: *const FenwickTree, allocator: Allocator) Allocator.Error![]i64 {
        const out = try allocator.alloc(i64, self.n);
        @memcpy(out, self.tree[1 .. self.n + 1]);
        return out;
    }

    // ---- internals (1-based BIT navigation) -------------------------------

    /// Add a wrapping-`i64` `delta` at 0-based index `i` via the low-bit walk.
    /// Traps if `i >= n` (shared by the `update`/`set` mutator path).
    fn addInternal(self: *FenwickTree, i: usize, delta: i64) void {
        if (i >= self.n) {
            std.debug.panic("FenwickTree mutator index {d} out of range 0..{d}", .{ i, self.n });
        }
        var j = i + 1; // public -> 1-based BIT
        while (j <= self.n) {
            self.tree[j] = self.tree[j] +% delta;
            j += lowbit(j);
        }
    }

    /// Inclusive prefix sum for 0-based index `i` (caller guarantees `i < n`).
    fn prefixSumInternal(self: *const FenwickTree, i: usize) i64 {
        var acc: i64 = 0;
        var j = i + 1; // public -> 1-based BIT
        while (j > 0) {
            acc = acc +% self.tree[j];
            j -= lowbit(j);
        }
        return acc;
    }
};

/// Low bit `j & -j` over a 1-based index (`j >= 1`). On `usize` the two's
/// complement negation is `j & (~j +% 1)` (wrapping negation).
inline fn lowbit(j: usize) usize {
    return j & (~j +% 1);
}

// ── tests ────────────────────────────────────────────────────────────────────

const testing = std.testing;

// A brute-force i64 reference: a flat array of per-index i64 values, with the
// same wrapping arithmetic the Fenwick tree must match.
const Brute = struct {
    vals: []i64,
    allocator: Allocator,

    fn withSize(allocator: Allocator, n: usize) !Brute {
        const vals = try allocator.alloc(i64, n);
        @memset(vals, 0);
        return .{ .vals = vals, .allocator = allocator };
    }
    fn deinit(self: *Brute) void {
        self.allocator.free(self.vals);
    }
    fn update(self: *Brute, i: usize, delta: i32) void {
        self.vals[i] = self.vals[i] +% @as(i64, delta);
    }
    fn set(self: *Brute, i: usize, value: i32) void {
        self.vals[i] = @as(i64, value);
    }
    fn get(self: *const Brute, i: usize) i64 {
        return self.vals[i];
    }
    fn prefixSum(self: *const Brute, i: usize) i64 {
        var acc: i64 = 0;
        var k: usize = 0;
        while (k <= i) : (k += 1) acc = acc +% self.vals[k];
        return acc;
    }
    fn rangeSum(self: *const Brute, lo: usize, hi: usize) i64 {
        if (lo > hi) return 0;
        var acc: i64 = 0;
        var k = lo;
        while (k <= hi) : (k += 1) acc = acc +% self.vals[k];
        return acc;
    }
    fn total(self: *const Brute) i64 {
        var acc: i64 = 0;
        for (self.vals) |v| acc = acc +% v;
        return acc;
    }
};

// A tiny deterministic LCG so the property tests need no external dep.
const Lcg = struct {
    state: u64,
    fn nextU64(self: *Lcg) u64 {
        self.state = self.state *% 6364136223846793005 +% 1442695040888963407;
        return self.state;
    }
    fn nextI32(self: *Lcg) i32 {
        return @bitCast(@as(u32, @truncate(self.nextU64())));
    }
    fn nextUsize(self: *Lcg, bound: usize) usize {
        return @intCast(self.nextU64() % @as(u64, bound));
    }
};

test "worked example from spec" {
    var f = try FenwickTree.withSize(testing.allocator, 8);
    defer f.deinit();
    f.update(0, 5);
    f.update(3, 2);
    f.update(7, 9);
    try testing.expectEqual(@as(i64, 5), f.prefixSum(0));
    try testing.expectEqual(@as(i64, 7), f.prefixSum(3));
    try testing.expectEqual(@as(i64, 7), f.prefixSum(6));
    try testing.expectEqual(@as(i64, 16), f.prefixSum(7));
    try testing.expectEqual(@as(i64, 16), f.total());
    try testing.expectEqual(@as(i64, 11), f.rangeSum(1, 7));
    try testing.expectEqual(@as(i64, 2), f.get(3));
    try testing.expectEqual(@as(usize, 8), f.len());
    try testing.expectEqual(@as(usize, 8), f.len());
    try testing.expect(!f.isEmpty());

    const ct = try f.canonicalTree(testing.allocator);
    defer testing.allocator.free(ct);
    try testing.expectEqualSlices(i64, &[_]i64{ 5, 5, 0, 7, 0, 0, 0, 16 }, ct);
}

test "inclusive conventions" {
    var f = try FenwickTree.fromValues(testing.allocator, &[_]i32{ 3, 1, 4, 1, 5, 9, 2, 6 });
    defer f.deinit();
    // prefixSum(0) is the first value (NOT 0 — inclusive).
    try testing.expectEqual(@as(i64, 3), f.prefixSum(0));
    // single-element inclusive range == that value (NOT 0).
    try testing.expectEqual(@as(i64, 4), f.rangeSum(2, 2));
    try testing.expectEqual(@as(i64, 4), f.get(2));
    try testing.expectEqual(@as(i64, 31), f.prefixSum(7));
    try testing.expectEqual(@as(i64, 31), f.total());
    // total == prefixSum(n-1) == rangeSum(0, n-1).
    try testing.expectEqual(f.total(), f.prefixSum(7));
    try testing.expectEqual(f.total(), f.rangeSum(0, 7));

    const ct = try f.canonicalTree(testing.allocator);
    defer testing.allocator.free(ct);
    try testing.expectEqualSlices(i64, &[_]i64{ 3, 4, 4, 9, 5, 14, 2, 31 }, ct);
}

test "from_values matches updates" {
    const cases = [_][]const i32{
        &[_]i32{},
        &[_]i32{42},
        &[_]i32{ 3, 1, 4, 1, 5, 9, 2, 6 },
        &[_]i32{ std.math.minInt(i32), std.math.maxInt(i32), -1, 0, 7 },
        &[_]i32{ -5, -5, -5, -5, -5, -5, -5 },
    };
    for (cases) |vals| {
        var built = try FenwickTree.fromValues(testing.allocator, vals);
        defer built.deinit();
        var updated = try FenwickTree.withSize(testing.allocator, vals.len);
        defer updated.deinit();
        for (vals, 0..) |v, i| updated.update(i, v);

        const cb = try built.canonicalTree(testing.allocator);
        defer testing.allocator.free(cb);
        const cu = try updated.canonicalTree(testing.allocator);
        defer testing.allocator.free(cu);
        try testing.expectEqualSlices(i64, cu, cb);

        for (0..vals.len) |i| {
            try testing.expectEqual(updated.prefixSum(i), built.prefixSum(i));
            try testing.expectEqual(updated.get(i), built.get(i));
        }
        try testing.expectEqual(updated.total(), built.total());
    }
}

test "set replaces not adds" {
    var f = try FenwickTree.withSize(testing.allocator, 4);
    defer f.deinit();
    f.update(1, 5);
    f.set(1, 3); // replace, NOT add: get(1) must be 3, not 8.
    f.update(2, 7);
    try testing.expectEqual(@as(i64, 3), f.get(1));
    try testing.expectEqual(@as(i64, 7), f.get(2));
    try testing.expectEqual(@as(i64, 3), f.prefixSum(1));
    try testing.expectEqual(@as(i64, 10), f.prefixSum(3));
    try testing.expectEqual(@as(i64, 10), f.total());
}

test "negative deltas cross zero" {
    var f = try FenwickTree.withSize(testing.allocator, 5);
    defer f.deinit();
    f.update(0, 10);
    f.update(1, -4);
    f.update(2, -20);
    f.update(3, 7);
    try testing.expectEqual(@as(i64, 10), f.prefixSum(0));
    try testing.expectEqual(@as(i64, 6), f.prefixSum(1));
    try testing.expectEqual(@as(i64, -14), f.prefixSum(2));
    try testing.expectEqual(@as(i64, -7), f.prefixSum(4));
    try testing.expectEqual(@as(i64, -7), f.total());
    try testing.expectEqual(@as(i64, -17), f.rangeSum(1, 3));
}

test "signed extremes widen to i64" {
    var f = try FenwickTree.withSize(testing.allocator, 3);
    defer f.deinit();
    f.set(0, std.math.maxInt(i32)); // 2147483647
    f.set(1, std.math.minInt(i32)); // -2147483648
    f.update(2, std.math.maxInt(i32));
    f.update(2, 1); // value becomes 2147483648 as i64 (NOT i32-wrapped).
    try testing.expectEqual(@as(i64, 2147483647), f.get(0));
    try testing.expectEqual(@as(i64, -2147483648), f.get(1));
    try testing.expectEqual(@as(i64, 2147483648), f.get(2));
    try testing.expectEqual(@as(i64, -1), f.prefixSum(1));
    try testing.expectEqual(@as(i64, 2147483647), f.total());
}

test "large i64 sum exceeds 2^53" {
    var f = try FenwickTree.withSize(testing.allocator, 4);
    defer f.deinit();
    for (0..4) |i| f.set(i, std.math.maxInt(i32));
    try testing.expectEqual(@as(i64, 8589934588), f.total()); // 4 * (2^31 - 1)
    try testing.expectEqual(@as(i64, 8589934588), f.prefixSum(3));
    try testing.expectEqual(@as(i64, 4294967294), f.rangeSum(1, 2));
}

test "i64 wrap is two's-complement not saturating" {
    // Seed a slot near maxInt(i64) at runtime via the internal add path, then
    // add past it: the production wrapping `+%` must wrap two's-complement.
    var f = try FenwickTree.withSize(testing.allocator, 1);
    defer f.deinit();
    f.addInternal(0, std.math.maxInt(i64) - 1);
    try testing.expectEqual(std.math.maxInt(i64) - 1, f.get(0));
    f.addInternal(0, 5); // (MAX-1) + 5 wraps two's-complement to negative.
    const expected = (std.math.maxInt(i64) - 1) +% @as(i64, 5);
    try testing.expect(expected < 0); // expected wrap to negative
    try testing.expectEqual(expected, f.get(0));
    try testing.expectEqual(expected, f.total());
    try testing.expectEqual(expected, f.prefixSum(0));
}

test "range_sum equals prefix diff after wrap" {
    // Invertibility holds even after the running total has wrapped.
    var f = try FenwickTree.withSize(testing.allocator, 3);
    defer f.deinit();
    f.addInternal(0, std.math.maxInt(i64) - 10);
    f.addInternal(1, 100); // prefixSum(1) wraps.
    f.addInternal(2, -7);
    // Each per-index logical value is exact (a single value never overflows;
    // only sums wrap), so rangeSum over a single index is exact post-wrap.
    try testing.expectEqual(std.math.maxInt(i64) - 10, f.get(0));
    try testing.expectEqual(@as(i64, 100), f.get(1));
    try testing.expectEqual(@as(i64, -7), f.get(2));
    try testing.expectEqual(@as(i64, 100), f.rangeSum(1, 1));
    try testing.expectEqual(@as(i64, -7), f.rangeSum(2, 2));
    const tot = (std.math.maxInt(i64) - 10) +% @as(i64, 100) +% @as(i64, -7);
    try testing.expect(tot < 0); // running total has wrapped
    try testing.expectEqual(tot, f.rangeSum(0, 2));
    try testing.expectEqual(tot, f.total());
    // Invertibility across every sub-range even after the wrap.
    for (0..3) |lo| {
        for (lo..3) |hi| {
            const direct = f.rangeSum(lo, hi);
            const lower: i64 = if (lo == 0) 0 else f.prefixSum(lo - 1);
            const via = f.prefixSum(hi) -% lower;
            try testing.expectEqual(via, direct);
        }
    }
}

test "single element" {
    var f = try FenwickTree.withSize(testing.allocator, 1);
    defer f.deinit();
    f.update(0, 42);
    try testing.expectEqual(@as(usize, 1), f.len());
    try testing.expectEqual(@as(i64, 42), f.get(0));
    try testing.expectEqual(@as(i64, 42), f.prefixSum(0));
    try testing.expectEqual(@as(i64, 42), f.rangeSum(0, 0));
    try testing.expectEqual(@as(i64, 42), f.total());
}

test "empty tree edges" {
    var f = try FenwickTree.withSize(testing.allocator, 0);
    defer f.deinit();
    try testing.expectEqual(@as(usize, 0), f.len());
    try testing.expect(f.isEmpty());
    try testing.expectEqual(@as(i64, 0), f.total());

    var g = try FenwickTree.fromValues(testing.allocator, &[_]i32{});
    defer g.deinit();
    try testing.expectEqual(@as(usize, 0), g.len());
    try testing.expect(g.isEmpty());
    try testing.expectEqual(@as(i64, 0), g.total());
    const ct = try g.canonicalTree(testing.allocator);
    defer testing.allocator.free(ct);
    try testing.expectEqual(@as(usize, 0), ct.len);
}

test "lo > hi returns zero" {
    var f = try FenwickTree.fromValues(testing.allocator, &[_]i32{ 3, 1, 4, 1, 5, 9, 2, 6 });
    defer f.deinit();
    try testing.expectEqual(@as(i64, 0), f.rangeSum(5, 2)); // both valid, lo > hi.
    try testing.expectEqual(@as(i64, 0), f.rangeSum(7, 0));
}

// ── out-of-range trap tests (child-process death) ────────────────────────────
//
// A panic aborts the process; `std.testing.expectExit`-style spawning is not
// available, so each trap is exercised in a forked child whose non-zero exit
// confirms the trap. The helper re-runs this test binary with an env marker
// that selects which trap to provoke.

fn provokeTrap(which: []const u8) void {
    const a = std.heap.page_allocator;
    if (std.mem.eql(u8, which, "update")) {
        var f = FenwickTree.withSize(a, 4) catch unreachable;
        f.update(4, 1); // i == n.
    } else if (std.mem.eql(u8, which, "set")) {
        var f = FenwickTree.withSize(a, 4) catch unreachable;
        f.set(4, 1);
    } else if (std.mem.eql(u8, which, "get")) {
        const f = FenwickTree.withSize(a, 4) catch unreachable;
        _ = f.get(4);
    } else if (std.mem.eql(u8, which, "prefix")) {
        const f = FenwickTree.withSize(a, 4) catch unreachable;
        _ = f.prefixSum(4);
    } else if (std.mem.eql(u8, which, "range_hi")) {
        const f = FenwickTree.withSize(a, 4) catch unreachable;
        _ = f.rangeSum(0, 4); // hi == n traps (NOT inferred as empty).
    } else if (std.mem.eql(u8, which, "range_lo")) {
        const f = FenwickTree.withSize(a, 4) catch unreachable;
        _ = f.rangeSum(4, 0);
    } else if (std.mem.eql(u8, which, "empty_get")) {
        const f = FenwickTree.withSize(a, 0) catch unreachable;
        _ = f.get(0);
    } else if (std.mem.eql(u8, which, "empty_prefix")) {
        const f = FenwickTree.withSize(a, 0) catch unreachable;
        _ = f.prefixSum(0);
    } else if (std.mem.eql(u8, which, "empty_range")) {
        const f = FenwickTree.withSize(a, 0) catch unreachable;
        _ = f.rangeSum(0, 0);
    }
}

test "out-of-range operations trap" {
    // If invoked as a trap child, provoke the requested trap and never return
    // (the panic exits non-zero; if it somehow returns, exit 0 = test failure).
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "FENWICK_TRAP")) |which| {
        defer std.heap.page_allocator.free(which);
        provokeTrap(which);
        // Reaching here means the call did NOT trap.
        std.process.exit(0);
    } else |_| {}

    const cases = [_][]const u8{
        "update",      "set",      "get",       "prefix",
        "range_hi",    "range_lo", "empty_get", "empty_prefix",
        "empty_range",
    };
    const self_exe = std.fs.selfExePathAlloc(testing.allocator) catch return; // skip if unavailable
    defer testing.allocator.free(self_exe);

    for (cases) |which| {
        var child = std.process.Child.init(&[_][]const u8{ self_exe, "test" }, testing.allocator);
        // Run only this test in the child and select the trap via env.
        var env = std.process.EnvMap.init(testing.allocator);
        defer env.deinit();
        try env.put("FENWICK_TRAP", which);
        child.env_map = &env;
        child.stderr_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        const term = try child.spawnAndWait();
        switch (term) {
            .Exited => |code| try testing.expect(code != 0),
            .Signal, .Stopped, .Unknown => {}, // a signal death is also a trap
        }
    }
}

test "fenwick identity vs brute force randomized" {
    var rng = Lcg{ .state = 0x1234_5678_9abc_def0 };
    var trial: usize = 0;
    while (trial < 200) : (trial += 1) {
        const n = 1 + rng.nextUsize(20);
        var f = try FenwickTree.withSize(testing.allocator, n);
        defer f.deinit();
        var b = try Brute.withSize(testing.allocator, n);
        defer b.deinit();
        const ops = 5 + rng.nextUsize(40);
        var o: usize = 0;
        while (o < ops) : (o += 1) {
            const i = rng.nextUsize(n);
            const pick = rng.nextU64() % 5;
            const v: i32 = switch (pick) {
                0 => std.math.minInt(i32),
                1 => std.math.maxInt(i32),
                else => rng.nextI32(),
            };
            if (rng.nextU64() % 2 == 0) {
                f.update(i, v);
                b.update(i, v);
            } else {
                f.set(i, v);
                b.set(i, v);
            }
        }
        for (0..n) |i| {
            try testing.expectEqual(b.get(i), f.get(i));
            try testing.expectEqual(b.prefixSum(i), f.prefixSum(i));
        }
        for (0..n) |lo| {
            for (0..n) |hi| {
                try testing.expectEqual(b.rangeSum(lo, hi), f.rangeSum(lo, hi));
            }
        }
        try testing.expectEqual(b.total(), f.total());
    }
}

test "build determinism randomized" {
    var rng = Lcg{ .state = 0xdead_beef_cafe_babe };
    var t: usize = 0;
    while (t < 200) : (t += 1) {
        const n = rng.nextUsize(20);
        const vals = try testing.allocator.alloc(i32, n);
        defer testing.allocator.free(vals);
        for (vals) |*v| {
            v.* = switch (rng.nextU64() % 4) {
                0 => std.math.minInt(i32),
                1 => std.math.maxInt(i32),
                else => rng.nextI32(),
            };
        }
        var built = try FenwickTree.fromValues(testing.allocator, vals);
        defer built.deinit();
        var updated = try FenwickTree.withSize(testing.allocator, n);
        defer updated.deinit();
        for (vals, 0..) |v, i| updated.update(i, v);

        const cb = try built.canonicalTree(testing.allocator);
        defer testing.allocator.free(cb);
        const cu = try updated.canonicalTree(testing.allocator);
        defer testing.allocator.free(cu);
        try testing.expectEqualSlices(i64, cu, cb);
    }
}
