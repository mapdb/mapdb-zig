// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Bound / Range value model — a pure in-memory value type describing a
//! region `[lo, hi)`, `(-∞, hi]`, `(lo, +∞)`, … with each endpoint
//! independently unbounded / open / closed.
//!
//! This is **not** `Interval` (which materialises an arithmetic progression
//! and enumerates elements). A `Range` holds no elements; it only describes a
//! region (`contains(x)`) and supports the open/unbounded endpoints `Interval`
//! cannot.
//!
//! The design follows Google Guava's `Range<C>` / `BoundType` / `Cut`. The
//! algebra (`intersection`, `span`, `isConnected`, `encloses`) is total and
//! unambiguous because endpoints are modelled as **cuts between values**
//! rather than `(value, inclusive)` pairs. See
//! `spec/features/bound-range.md` for the normative algorithms; every
//! operation here reduces to a side-aware cut comparison, never to a
//! `(value, inclusive)` boolean.
//!
//! ## Side-aware cut ordering
//!
//! An unbounded cut is *contextual*: as a lower cut it is `-∞`, as an upper
//! cut it is `+∞`. There is therefore no single context-free order on one
//! `Unbounded` value. We avoid that trap by splitting the unbounded state into
//! two distinct sentinels — `Cut.below_all` (`-∞`) and `Cut.above_all`
//! (`+∞`). With those two sentinels the four-variant `Cut` has a *single total
//! order* (`below_all < below(v) < above(v) < above_all`, finite cuts breaking
//! ties by value then `below < above`), and the three spec comparators
//! (`compare_lower_cuts`, `compare_upper_cuts`, `compare_lower_to_upper`) all
//! collapse onto it. A lower cut never holds `above_all`; an upper cut never
//! holds `below_all`; that invariant is established by the factories.
//!
//! v1 ships the `i32` specialisation (matching the cross-language validation
//! universe); `Range(comptime T)` stays generic over a totally-ordered
//! primitive so the float / wider-integer matrix widens later exactly as
//! `Interval` did. For float `T` the IEEE-754 total order (not raw `<`) is the
//! ordering basis; that widening is deferred (v1 is i32 only).

const std = @import("std");

/// The kind of a finite endpoint: `open` (exclusive) or `closed` (inclusive).
///
/// `bound_type_str` renders these as the wire-format `"open"` / `"closed"`.
pub const BoundType = enum {
    open,
    closed,
};

/// `Range(comptime T)` — an ordered region `(lower, upper)` over a
/// totally-ordered primitive `T`, with the invariant `lower <= upper`.
///
/// Equality is structural on the two cuts (`eql`): `closedOpen(v, v)` and
/// `openClosed(v, v)` are distinct (both empty) values, and empties at
/// different positions are unequal.
pub fn Range(comptime T: type) type {
    return struct {
        lower: Cut,
        upper: Cut,

        const Self = @This();

        /// A cut sits *between* values (Guava's `Cut`). The four-variant form
        /// carries two distinct unbounded sentinels (`below_all` = `-∞`,
        /// `above_all` = `+∞`) so the cut has a single, total, context-free
        /// order — there is no lone `unbounded` value with an ambiguous
        /// position.
        ///
        /// Total order: `below_all < below(v) < above(v) < above_all`. Finite
        /// cuts at different values order by value; at the same value
        /// `below(v) < above(v)`.
        ///
        /// Endpoint meaning:
        /// - `below(v)` — closed **lower** `[v`, or open **upper** `v)`.
        /// - `above(v)` — open **lower** `(v`, or closed **upper** `v]`.
        pub const Cut = union(enum) {
            /// `-∞`. Only ever a lower cut.
            below_all,
            /// The cut immediately below `v`.
            below: T,
            /// The cut immediately above `v`.
            above: T,
            /// `+∞`. Only ever an upper cut.
            above_all,

            /// Rank collapsing the finite variants so the sentinels order
            /// around them.
            fn rank(c: Cut) u8 {
                return switch (c) {
                    .below_all => 0,
                    .below, .above => 1,
                    .above_all => 2,
                };
            }

            /// Total order on cuts (the single source of truth for the
            /// algebra). The three side-aware spec comparators all reduce to
            /// this because the two unbounded states are distinct sentinels
            /// rather than one ambiguous `unbounded`. Returns a `std.math.Order`.
            ///
            /// Total order: `below_all < below(v) < above(v) < above_all`.
            /// Finite cuts at different values order by value; at the same
            /// value `below(v) < above(v)`.
            ///
            /// Public so the `RangeSet` / `RangeMap` cut algebra (coalescing,
            /// splitting, complement, ascending order) reduces to this single
            /// comparator — the `bound-range.md` "single source of truth" rule —
            /// instead of re-deriving boundary order from `(value, inclusive)`
            /// booleans or `±1` arithmetic.
            pub fn cmp(a: Cut, b: Cut) std.math.Order {
                const av: ?T = switch (a) {
                    .below, .above => |v| v,
                    else => null,
                };
                const bv: ?T = switch (b) {
                    .below, .above => |v| v,
                    else => null,
                };
                if (av != null and bv != null) {
                    const ord = compareValues(av.?, bv.?);
                    if (ord != .eq) return ord;
                    // Same value: below(v) < above(v).
                    const a_above = a == .above;
                    const b_above = b == .above;
                    if (!a_above and b_above) return .lt;
                    if (a_above and !b_above) return .gt;
                    return .eq;
                }
                return std.math.order(a.rank(), b.rank());
            }

            /// Whether this cut is finite (carries an endpoint value).
            fn isFinite(c: Cut) bool {
                return c == .below or c == .above;
            }

            /// The endpoint value, or null when unbounded.
            fn value(c: Cut) ?T {
                return switch (c) {
                    .below, .above => |v| v,
                    else => null,
                };
            }
        };

        /// Total order on the element type. v1 is i32 (natural signed order);
        /// the float matrix later routes floats through the IEEE-754 total
        /// order (`algorithms.md` §"Float ordering for tree collections").
        fn compareValues(a: T, b: T) std.math.Order {
            // `bool` has no `<`; order it explicitly (false < true) so the
            // generic tree collections can name `Range(bool)` when their
            // declarations are force-compiled (refAllDeclsRecursive). Float
            // widening (IEEE-754 total order) is deferred with the rest of the
            // float matrix; v1 exercises i32.
            if (T == bool) {
                if (a == b) return .eq;
                return if (!a and b) .lt else .gt;
            }
            return std.math.order(a, b);
        }

        fn maxCut(a: Cut, b: Cut) Cut {
            return if (Cut.cmp(a, b) == .lt) b else a;
        }

        fn minCut(a: Cut, b: Cut) Cut {
            return if (Cut.cmp(a, b) == .gt) b else a;
        }

        /// Construct from raw cuts after validating `lower <= upper`. Traps
        /// (`@panic`) if the cuts are out of order (a programming error, like
        /// `Interval.reversed` at the minimum step). The `@panic` is always-on
        /// (fires in every build profile), not a `std.debug.assert` no-op.
        fn fromCuts(lower: Cut, upper: Cut) Self {
            if (Cut.cmp(lower, upper) == .gt) {
                @panic("Range: lower cut must not exceed upper cut");
            }
            return .{ .lower = lower, .upper = upper };
        }

        // ---- factories (Guava-parity names) -------------------------------

        /// `(a, b)` — both endpoints open. Traps if `a >= b` (incl.
        /// `open(v, v)`, which is empty-but-invalid-as-open).
        pub fn open(a: T, b: T) Self {
            return fromCuts(.{ .above = a }, .{ .below = b });
        }

        /// `[a, b]` — both endpoints closed. Traps if `a > b`.
        pub fn closed(a: T, b: T) Self {
            return fromCuts(.{ .below = a }, .{ .above = b });
        }

        /// `(a, b]`. Traps if `a > b`.
        pub fn openClosed(a: T, b: T) Self {
            return fromCuts(.{ .above = a }, .{ .above = b });
        }

        /// `[a, b)`. Traps if `a > b`. `closedOpen(v, v)` is the valid empty
        /// range `(below(v), below(v))`.
        pub fn closedOpen(a: T, b: T) Self {
            return fromCuts(.{ .below = a }, .{ .below = b });
        }

        /// `(a, +∞)`.
        pub fn greaterThan(a: T) Self {
            return fromCuts(.{ .above = a }, .above_all);
        }

        /// `[a, +∞)`.
        pub fn atLeast(a: T) Self {
            return fromCuts(.{ .below = a }, .above_all);
        }

        /// `(-∞, b)`.
        pub fn lessThan(b: T) Self {
            return fromCuts(.below_all, .{ .below = b });
        }

        /// `(-∞, b]`.
        pub fn atMost(b: T) Self {
            return fromCuts(.below_all, .{ .above = b });
        }

        /// `(-∞, +∞)`.
        pub fn all() Self {
            return .{ .lower = .below_all, .upper = .above_all };
        }

        /// `[v, v]`.
        pub fn singleton(v: T) Self {
            return fromCuts(.{ .below = v }, .{ .above = v });
        }

        // ---- queries ------------------------------------------------------

        /// Whether `x` falls within the range (normative `contains`).
        pub fn contains(self: Self, x: T) bool {
            const lower_ok = switch (self.lower) {
                .below_all => true,
                .below => |v| compareValues(v, x) != .gt, // v <= x
                .above => |v| compareValues(v, x) == .lt, // v <  x
                .above_all => false,
            };
            const upper_ok = switch (self.upper) {
                .above_all => true,
                .below => |v| compareValues(x, v) == .lt, // x <  v
                .above => |v| compareValues(x, v) != .gt, // x <= v
                .below_all => false,
            };
            return lower_ok and upper_ok;
        }

        /// **Cut-empty**: `lower == upper`. NOT discrete cardinality —
        /// `open(1, 2)` over `i32` is *not* empty (no `DiscreteDomain` in
        /// Phase 0).
        pub fn isEmpty(self: Self) bool {
            return Cut.cmp(self.lower, self.upper) == .eq;
        }

        /// The `BoundType` of the lower endpoint; `null` when unbounded.
        pub fn lowerBoundType(self: Self) ?BoundType {
            return switch (self.lower) {
                .below => .closed,
                .above => .open,
                .below_all, .above_all => null,
            };
        }

        /// The `BoundType` of the upper endpoint; `null` when unbounded.
        pub fn upperBoundType(self: Self) ?BoundType {
            return switch (self.upper) {
                .below => .open,
                .above => .closed,
                .below_all, .above_all => null,
            };
        }

        /// The lower endpoint value; `null` when unbounded below.
        pub fn lowerEndpoint(self: Self) ?T {
            return self.lower.value();
        }

        /// The upper endpoint value; `null` when unbounded above.
        pub fn upperEndpoint(self: Self) ?T {
            return self.upper.value();
        }

        /// Whether the lower endpoint is finite.
        pub fn hasLowerBound(self: Self) bool {
            return self.lower.isFinite();
        }

        /// Whether the upper endpoint is finite.
        pub fn hasUpperBound(self: Self) bool {
            return self.upper.isFinite();
        }

        // ---- sorted-slice bracketing (cut-derived, overflow-safe) ---------

        /// Bracket the contiguous `[start, end)` index window of a **strictly
        /// ascending** slice whose elements fall inside this range. Membership
        /// over a sorted slice is contiguous (the range is convex), so two
        /// binary searches suffice: `start` is the lower bound of the in-range
        /// window, `end` one past its last element.
        ///
        /// The brackets are derived purely from the cut comparison
        /// (`below`/`above`/unbounded sentinels) — never from `v ± 1`
        /// predecessor/successor arithmetic — so open/closed bounds at
        /// `INT_MIN`/`INT_MAX` never overflow. `start == end` is an empty
        /// (possibly cut-empty or discrete-empty, e.g. `open(1, 2)` over `i32`)
        /// result, never an error. This is the bracketing the
        /// `sorted-table-map` packed-array range queries ride on
        /// (`spec/features/sorted-table-map.md` §"Range-query semantics").
        pub fn bracket(self: Self, sorted: []const T) [2]usize {
            // start: first index whose key is strictly ABOVE the lower cut.
            const start: usize = switch (self.lower) {
                .below_all => 0,
                // Closed lower `[v`: include v -> first key >= v.
                .below => |v| partitionPointLt(sorted, v),
                // Open lower `(v`: exclude v -> first key > v.
                .above => |v| partitionPointLe(sorted, v),
                // A lower cut is never above_all (factory invariant); empty.
                .above_all => sorted.len,
            };
            // end: first index whose key is NOT below the upper cut (one past
            // the last in-range key).
            const end: usize = switch (self.upper) {
                .above_all => sorted.len,
                // Open upper `v)`: exclude v -> first key >= v.
                .below => |v| partitionPointLt(sorted, v),
                // Closed upper `v]`: include v -> first key > v.
                .above => |v| partitionPointLe(sorted, v),
                // An upper cut is never below_all (factory invariant); empty.
                .below_all => 0,
            };
            // A fully-disjoint range can yield start > end; normalise to an
            // empty window so callers slice safely.
            if (start > end) return .{ end, end };
            return .{ start, end };
        }

        /// First index `i` with `!(sorted[i] < v)` — i.e. first key `>= v`.
        /// Overflow-safe midpoint (`lo + (hi - lo) / 2`) over `usize` indices;
        /// the comparison is the total-order `compareValues`, never a bare `<`.
        fn partitionPointLt(sorted: []const T, v: T) usize {
            var lo: usize = 0;
            var hi: usize = sorted.len;
            while (lo < hi) {
                const mid = lo + (hi - lo) / 2;
                if (compareValues(sorted[mid], v) == .lt) {
                    lo = mid + 1;
                } else {
                    hi = mid;
                }
            }
            return lo;
        }

        /// First index `i` with `!(sorted[i] <= v)` — i.e. first key `> v`.
        fn partitionPointLe(sorted: []const T, v: T) usize {
            var lo: usize = 0;
            var hi: usize = sorted.len;
            while (lo < hi) {
                const mid = lo + (hi - lo) / 2;
                if (compareValues(sorted[mid], v) != .gt) { // sorted[mid] <= v
                    lo = mid + 1;
                } else {
                    hi = mid;
                }
            }
            return lo;
        }

        // ---- algebra (all via cut comparison) -----------------------------

        /// Structural equality on the two cuts. `closedOpen(v, v)` and
        /// `openClosed(v, v)` are distinct (both empty) values.
        pub fn eql(self: Self, other: Self) bool {
            return Cut.cmp(self.lower, other.lower) == .eq and
                Cut.cmp(self.upper, other.upper) == .eq;
        }

        /// Cut-defined containment: `self.lower <= other.lower` and
        /// `self.upper >= other.upper`. NOT `∀ value ∈ other: contains(value)`
        /// — `[1, 5)` *encloses* the empty `[5, 5)` though `5 ∉ [1, 5)`.
        pub fn encloses(self: Self, other: Self) bool {
            return Cut.cmp(self.lower, other.lower) != .gt and
                Cut.cmp(self.upper, other.upper) != .lt;
        }

        /// Whether there is a (possibly empty) range enclosed by both.
        /// Cut-equal endpoints count as connected (empty overlap).
        pub fn isConnected(self: Self, other: Self) bool {
            return Cut.cmp(self.lower, other.upper) != .gt and
                Cut.cmp(other.lower, self.upper) != .gt;
        }

        /// The overlap. `null` **only** when disconnected; abutting operands
        /// return a *present* cut-empty range at the touch point.
        pub fn intersection(self: Self, other: Self) ?Self {
            if (!self.isConnected(other)) return null;
            const lower = maxCut(self.lower, other.lower);
            const upper = minCut(self.upper, other.upper);
            return .{ .lower = lower, .upper = upper };
        }

        /// The smallest range enclosing both. No cross-shape canonicalisation.
        pub fn span(self: Self, other: Self) Self {
            const lower = minCut(self.lower, other.lower);
            const upper = maxCut(self.upper, other.upper);
            return .{ .lower = lower, .upper = upper };
        }

        /// Render the range in interval notation, e.g. `[1, 5)`, `(-∞, 5)`.
        pub fn format(self: Self, writer: anytype) !void {
            switch (self.lower) {
                .below_all => try writer.writeAll("(-∞"),
                .below => |v| try writer.print("[{d}", .{v}),
                .above => |v| try writer.print("({d}", .{v}),
                .above_all => try writer.writeAll("(+∞"),
            }
            try writer.writeAll(", ");
            switch (self.upper) {
                .above_all => try writer.writeAll("+∞)"),
                .below => |v| try writer.print("{d})", .{v}),
                .above => |v| try writer.print("{d}]", .{v}),
                .below_all => try writer.writeAll("-∞)"),
            }
        }
    };
}

/// `Range(i32)` — the v1 specialisation matching the cross-language validation
/// universe.
pub const I32Range = Range(i32);

// ── Native unit tests ───────────────────────────────────────────────────────

const testing = std.testing;

test "contains: closed" {
    const r = I32Range.closed(10, 20);
    try testing.expect(r.contains(10));
    try testing.expect(r.contains(15));
    try testing.expect(r.contains(20));
    try testing.expect(!r.contains(9));
    try testing.expect(!r.contains(21));
}

test "contains: open" {
    const r = I32Range.open(10, 20);
    try testing.expect(!r.contains(10));
    try testing.expect(!r.contains(20));
    try testing.expect(r.contains(11));
    try testing.expect(r.contains(19));
}

test "contains: half-open" {
    const co = I32Range.closedOpen(10, 20);
    try testing.expect(co.contains(10));
    try testing.expect(!co.contains(20));
    const oc = I32Range.openClosed(10, 20);
    try testing.expect(!oc.contains(10));
    try testing.expect(oc.contains(20));
}

test "contains: unbounded" {
    const a = I32Range.all();
    try testing.expect(a.contains(std.math.minInt(i32)));
    try testing.expect(a.contains(0));
    try testing.expect(a.contains(std.math.maxInt(i32)));

    const al = I32Range.atLeast(10);
    try testing.expect(al.contains(10));
    try testing.expect(!al.contains(9));
    try testing.expect(al.contains(std.math.maxInt(i32)));

    const gt = I32Range.greaterThan(10);
    try testing.expect(!gt.contains(10));
    try testing.expect(gt.contains(11));

    const lt = I32Range.lessThan(5);
    try testing.expect(lt.contains(4));
    try testing.expect(!lt.contains(5));

    const am = I32Range.atMost(5);
    try testing.expect(am.contains(5));
    try testing.expect(!am.contains(6));
}

test "bound types and endpoints" {
    const r = I32Range.closedOpen(10, 20);
    try testing.expectEqual(BoundType.closed, r.lowerBoundType().?);
    try testing.expectEqual(BoundType.open, r.upperBoundType().?);
    try testing.expectEqual(@as(i32, 10), r.lowerEndpoint().?);
    try testing.expectEqual(@as(i32, 20), r.upperEndpoint().?);
    try testing.expect(r.hasLowerBound());
    try testing.expect(r.hasUpperBound());

    const a = I32Range.all();
    try testing.expect(a.lowerBoundType() == null);
    try testing.expect(a.upperBoundType() == null);
    try testing.expect(a.lowerEndpoint() == null);
    try testing.expect(a.upperEndpoint() == null);
    try testing.expect(!a.hasLowerBound());
    try testing.expect(!a.hasUpperBound());
}

test "isEmpty: open(1,2) NOT empty (no DiscreteDomain)" {
    const o = I32Range.open(1, 2);
    try testing.expect(!o.isEmpty());
    try testing.expect(!o.contains(1));
    try testing.expect(!o.contains(2));
}

test "isEmpty: closedOpen(v,v) != openClosed(v,v) but both empty" {
    const co = I32Range.closedOpen(5, 5);
    const oc = I32Range.openClosed(5, 5);
    try testing.expect(co.isEmpty());
    try testing.expect(oc.isEmpty());
    try testing.expect(!co.eql(oc));
    try testing.expect(!co.contains(5));
    try testing.expect(!oc.contains(5));
    // Bound types are preserved per the cuts.
    try testing.expectEqual(BoundType.closed, co.lowerBoundType().?);
    try testing.expectEqual(BoundType.open, co.upperBoundType().?);
    try testing.expectEqual(BoundType.open, oc.lowerBoundType().?);
    try testing.expectEqual(BoundType.closed, oc.upperBoundType().?);
    // Empties at different positions are unequal.
    try testing.expect(!co.eql(I32Range.closedOpen(6, 6)));
}

test "singleton is not empty" {
    const s = I32Range.singleton(5);
    try testing.expect(!s.isEmpty());
    try testing.expect(s.contains(5));
    try testing.expect(!s.contains(4));
    try testing.expect(!s.contains(6));
}

test "encloses: cut-defined, incl. [1,5) encloses [5,5)" {
    const big = I32Range.closed(10, 30);
    try testing.expect(big.encloses(I32Range.closed(15, 25)));
    try testing.expect(!big.encloses(I32Range.closed(5, 25)));
    // [10,30] encloses empty@20.
    try testing.expect(big.encloses(I32Range.closedOpen(20, 20)));
    // [1,5) encloses empty@5 (cut-defined; 5 NOT contained).
    const half = I32Range.closedOpen(1, 5);
    try testing.expect(half.encloses(I32Range.closedOpen(5, 5)));
    try testing.expect(!half.contains(5));
}

test "isConnected / intersection: connected overlap (present, non-empty)" {
    const a = I32Range.closed(10, 20);
    const b = I32Range.closed(15, 25);
    try testing.expect(a.isConnected(b));
    const i = a.intersection(b).?;
    try testing.expect(!i.isEmpty());
    try testing.expect(i.eql(I32Range.closed(15, 20)));
}

test "intersection: abut closed/open present cut-empty (Below20,Below20)" {
    const a = I32Range.closedOpen(10, 20);
    const b = I32Range.closedOpen(20, 30);
    try testing.expect(a.isConnected(b));
    const i = a.intersection(b).?;
    try testing.expect(i.isEmpty());
    try testing.expect(i.eql(I32Range.closedOpen(20, 20)));
    try testing.expectEqual(BoundType.closed, i.lowerBoundType().?);
    try testing.expectEqual(BoundType.open, i.upperBoundType().?);
}

test "intersection: abut open/closed present cut-empty (Above20,Above20)" {
    const a = I32Range.closed(10, 20);
    const b = I32Range.open(20, 30);
    try testing.expect(a.isConnected(b));
    const i = a.intersection(b).?;
    try testing.expect(i.isEmpty());
    try testing.expect(i.eql(I32Range.openClosed(20, 20)));
    try testing.expectEqual(BoundType.open, i.lowerBoundType().?);
    try testing.expectEqual(BoundType.closed, i.upperBoundType().?);
}

test "intersection: disjoint is null (NOT present-empty)" {
    const a = I32Range.closedOpen(10, 15);
    const b = I32Range.closedOpen(20, 25);
    try testing.expect(!a.isConnected(b));
    try testing.expect(a.intersection(b) == null);
}

test "intersection: unbounded abut present cut-empty (Below5,Below5)" {
    const a = I32Range.lessThan(5);
    const b = I32Range.atLeast(5);
    try testing.expect(a.isConnected(b));
    const i = a.intersection(b).?;
    try testing.expect(i.isEmpty());
    try testing.expect(i.eql(I32Range.closedOpen(5, 5)));
    try testing.expectEqual(BoundType.closed, i.lowerBoundType().?);
    try testing.expectEqual(BoundType.open, i.upperBoundType().?);
}

test "intersection: unbounded disjoint is null (5 is the gap)" {
    const a = I32Range.lessThan(5);
    const b = I32Range.greaterThan(5);
    try testing.expect(!a.isConnected(b));
    try testing.expect(a.intersection(b) == null);
}

test "span: basic" {
    const a = I32Range.closed(10, 15);
    const b = I32Range.closed(20, 25);
    const s = a.span(b);
    try testing.expect(s.eql(I32Range.closed(10, 25)));
    try testing.expectEqual(@as(i32, 10), s.lowerEndpoint().?);
    try testing.expectEqual(@as(i32, 25), s.upperEndpoint().?);
    try testing.expectEqual(BoundType.closed, s.lowerBoundType().?);
    try testing.expectEqual(BoundType.closed, s.upperBoundType().?);
}

test "span: unbounded" {
    const a = I32Range.atLeast(10);
    const b = I32Range.closed(0, 5);
    const s = a.span(b);
    try testing.expect(s.eql(I32Range.atLeast(0)));
    try testing.expectEqual(@as(i32, 0), s.lowerEndpoint().?);
    try testing.expect(s.upperEndpoint() == null);
    try testing.expectEqual(BoundType.closed, s.lowerBoundType().?);
    try testing.expect(s.upperBoundType() == null);
}

// ── Trap tests (native only) ─────────────────────────────────────────────────
//
// Zig's in-process test runner cannot catch @panic, so we cannot assert the
// trap with `testing.expect` here — same convention as Interval's zero-step
// trap (regression_phase3_test.zig). The contract is instead pinned by
// inspection: `fromCuts` uses an always-on `@panic` (fires in every build
// profile), not a `std.debug.assert` no-op. These tests pin the *valid*
// neighbours so a regression that loosens the lower<=upper guard is still
// visible, and document the panic expectation.
test "trap: closed(5,1) and open(3,3) trap (verified out of process)" {
    // closedOpen(v,v) / openClosed(v,v) are the VALID empties (lower==upper).
    try testing.expect(I32Range.closedOpen(5, 5).isEmpty());
    try testing.expect(I32Range.openClosed(3, 3).isEmpty());
    // closed(v,v) is the singleton (valid, non-empty).
    try testing.expect(!I32Range.closed(3, 3).isEmpty());
    // (closed(5,1) and open(3,3) trap via always-on @panic in fromCuts in all
    //  build profiles — verified out of process; the test runner cannot
    //  intercept @panic.)
}

test "bracket: cut-derived, overflow-safe at signed extremes" {
    const min = std.math.minInt(i32);
    const max = std.math.maxInt(i32);
    const keys = [_]i32{ min, -1, 0, 1, max };

    // closed_open(30,70) over a 10-key strided slice.
    const strided = [_]i32{ 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 };
    {
        const b = I32Range.closedOpen(30, 70).bracket(&strided);
        try testing.expectEqual(@as(usize, 2), b[0]);
        try testing.expectEqual(@as(usize, 6), b[1]);
    }
    // greater_than(MIN): excludes MIN, no MIN-1 arithmetic.
    {
        const b = I32Range.greaterThan(min).bracket(&keys);
        try testing.expectEqual(@as(usize, 1), b[0]);
        try testing.expectEqual(@as(usize, 5), b[1]);
    }
    // less_than(MAX): excludes MAX, no MAX+1 arithmetic.
    {
        const b = I32Range.lessThan(max).bracket(&keys);
        try testing.expectEqual(@as(usize, 0), b[0]);
        try testing.expectEqual(@as(usize, 4), b[1]);
    }
    // closed(MIN,MAX): full span.
    {
        const b = I32Range.closed(min, max).bracket(&keys);
        try testing.expectEqual(@as(usize, 0), b[0]);
        try testing.expectEqual(@as(usize, 5), b[1]);
    }
    // singleton(MAX): one element.
    {
        const b = I32Range.singleton(max).bracket(&keys);
        try testing.expectEqual(@as(usize, 4), b[0]);
        try testing.expectEqual(@as(usize, 5), b[1]);
    }
    // open(1,2) over adjacent ints: empty window, not an error.
    {
        const adj = [_]i32{ 1, 2 };
        const b = I32Range.open(1, 2).bracket(&adj);
        try testing.expectEqual(b[0], b[1]);
    }
    // cut-empty closed_open(5,5): empty.
    {
        const b = I32Range.closedOpen(5, 5).bracket(&strided);
        try testing.expectEqual(b[0], b[1]);
    }
    // all(): full slice.
    {
        const b = I32Range.all().bracket(&strided);
        try testing.expectEqual(@as(usize, 0), b[0]);
        try testing.expectEqual(@as(usize, strided.len), b[1]);
    }
}

test "format: interval notation" {
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try I32Range.closed(1, 5).format(fbs.writer());
    try testing.expectEqualStrings("[1, 5]", fbs.getWritten());
}
