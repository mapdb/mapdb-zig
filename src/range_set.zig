// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! `RangeSet(comptime T)` — a mutable, auto-coalescing set of cut-regions over
//! a totally-ordered `T` (v1 ships the `i32` specialisation, `I32RangeSet`).
//!
//! A `RangeSet` stores a collection of **disjoint, non-empty, pairwise
//! non-connected** `Range(T)`s (the *normal form*). It auto-coalesces on
//! [`add`](RangeSet.add): two ranges merge iff they are connected
//! (`Range.isConnected`) — which is **broader** than mere overlap, because an
//! *abutment* (a cut-touch, e.g. `[1, 3)` & `[3, 5)`) is also connected. Every
//! coalescing / split / complement / ordering decision reduces to the
//! side-aware cut comparisons of `range.zig`; there is no `(value, inclusive)`
//! boolean reasoning and **no `±1` endpoint arithmetic** (the
//! `INT_MIN`/`INT_MAX` overflow trap).
//!
//! ## Cut-region, not integer-value-set
//!
//! Because Phase 0 has no `DiscreteDomain`, a `RangeSet` models *cut-regions*,
//! not the set of `i32` values they happen to contain. `add(open(1, 2))` over
//! `i32` produces a **non-empty** set whose single stored range `(1, 2)` is
//! cut-non-empty even though [`contains`](RangeSet.contains) is false for every
//! `i32`. So `{}` and `{(1, 2)}` are **distinct** RangeSets. Every set-level
//! predicate (`isEmpty`, canonicality, `complement`, `intersects`, `span`) is
//! defined on the stored cut-regions; only the point queries (`contains` /
//! `rangeContaining`) ask about an actual `i32`.
//!
//! ## Backing & ownership
//!
//! The backing is a flat `std.ArrayListUnmanaged(Range(T))` kept in the normal
//! form (non-empty, pairwise non-connected, ascending by lower cut). `Range(T)`
//! is a value (`Copy`) type, so the only owned resource is the backing buffer;
//! [`deinit`](RangeSet.deinit) frees it. `complement` / `subRangeSet` return
//! **new independent** `RangeSet`s (materialized snapshots, see the spec
//! §Views) that own their own buffers.

const std = @import("std");
const Allocator = std.mem.Allocator;
const range_mod = @import("range.zig");

/// A mutable, auto-coalescing set of disjoint cut-regions over `T`.
///
/// See the module docs for the cut-region semantics and the normal-form
/// invariant.
pub fn RangeSet(comptime T: type) type {
    return struct {
        const Self = @This();

        /// The range value type (`range.zig`) this set stores.
        pub const Range = range_mod.Range(T);
        const Cut = Range.Cut;

        /// Normal form: non-empty, pairwise non-connected, ascending by lower
        /// cut. Order is unobservable beyond `asRanges`.
        ranges: std.ArrayListUnmanaged(Range) = .{},
        allocator: Allocator,

        /// An empty range set.
        pub fn init(allocator: Allocator) Self {
            return .{ .ranges = .{}, .allocator = allocator };
        }

        /// Free the backing buffer.
        pub fn deinit(self: *Self) void {
            self.ranges.deinit(self.allocator);
        }

        /// Union `range` in, coalescing **all connected** stored ranges. A
        /// **cut-empty** `range` (e.g. `closedOpen(5, 5)`) is a **no-op**,
        /// decided by `Range.isEmpty` (cut-empty), never by discrete
        /// cardinality — `add(open(1, 2))` over `i32` **stores** the range. The
        /// merged range keeps the **outer** cuts of every connected member (the
        /// cut min/max, no `±1` math).
        pub fn add(self: *Self, range: Range) Allocator.Error!void {
            // Empty-range no-op (cut-empty), per the normative empty-range rule.
            if (range.isEmpty()) return;

            // The stored ranges connected to `range` (overlap OR abutment) form
            // a contiguous run `[lo, hi)`: the backing is sorted ascending by
            // lower cut and pairwise non-connected, so both run bounds fall out
            // of a binary search over the (ascending) cut columns. This replaces
            // the previous full-list rebuild — O(n) scan plus one *fresh*
            // backing allocation on every `add` — with an O(log n) locate and a
            // single in-place splice (D13).
            const stored = self.ranges.items;
            const lo = runStart(stored, range, .connected);
            const hi = runEnd(stored, range, .connected);

            // Span the run (if any) with `range`; the endpoints carry the
            // extremal cuts (`stored[lo]` the min lower, `stored[hi-1]` the max
            // upper), so two `span`s suffice. This reads `stored` before the
            // splice below invalidates the slice.
            var merged = range;
            if (lo < hi) {
                merged = merged.span(stored[lo]);
                merged = merged.span(stored[hi - 1]);
            }

            if (lo == hi) {
                // No connected range: insert `merged` at its sorted position.
                // ArrayList growth is amortized, so this is O(log n) *total*
                // allocations across a run of inserts, not one per call.
                try self.ranges.insert(self.allocator, lo, merged);
            } else {
                // Collapse the connected run into the single merged range. new
                // length (1) <= removed length, so this never reallocates.
                try self.ranges.replaceRange(self.allocator, lo, hi - lo, &.{merged});
            }
        }

        /// [`add`](RangeSet.add) each range; the final normal form is
        /// order-independent.
        pub fn addAll(self: *Self, ranges: []const Range) Allocator.Error!void {
            for (ranges) |r| try self.add(r);
        }

        /// Subtract `range`, **splitting** any stored range straddling either
        /// boundary. A cut-empty `range` is a **no-op**. The split is pure cut
        /// arithmetic — the boundary cuts flip (`remove([4, 7))` from `[1, 9]`
        /// leaves `[1, 4)` and `[7, 9]`), never `±1`.
        pub fn remove(self: *Self, range: Range) Allocator.Error!void {
            if (range.isEmpty()) return;

            // The stored ranges with a cut-**non-empty** intersection form a
            // contiguous run `[lo, hi)`. Abutment (a cut-empty touch) does not
            // split, so — unlike `add`'s connectivity bounds — these bounds use
            // STRICT cut comparisons (`.overlapping`). Located by binary search,
            // spliced in place, replacing the previous full-list rebuild (D13).
            const stored = self.ranges.items;
            const lo = runStart(stored, range, .overlapping);
            const hi = runEnd(stored, range, .overlapping);
            if (lo >= hi) return; // nothing overlaps -> no-op

            // Only the first range in the run can leave a left fragment (the
            // part below `range.lower`) and only the last a right fragment
            // (above `range.upper`); every interior range is fully covered and
            // drops out. So the whole run collapses to at most two fragments,
            // read from `stored` before the splice invalidates the slice.
            var frags: [2]Range = undefined;
            var n: usize = 0;
            if (Cut.cmp(stored[lo].lower, range.lower) == .lt) {
                frags[n] = .{ .lower = stored[lo].lower, .upper = range.lower };
                n += 1;
            }
            if (Cut.cmp(range.upper, stored[hi - 1].upper) == .lt) {
                frags[n] = .{ .lower = range.upper, .upper = stored[hi - 1].upper };
                n += 1;
            }
            // The run shrinks except when a single range splits into two
            // fragments (n==2, hi-lo==1), which needs one extra slot. Reserve it
            // FIRST — the sole fallible step — so an OOM leaves the set unchanged
            // (`frags` are value copies, unaffected if the reserve relocates the
            // backing); then splice infallibly. `n - (hi - lo) <= 1` always.
            try self.ranges.ensureUnusedCapacity(self.allocator, n -| (hi - lo));
            self.ranges.replaceRangeAssumeCapacity(lo, hi - lo, frags[0..n]);
        }

        /// How the run bounds treat a cut-touch (abutment): `.connected` counts
        /// it (used by `add`, whose merge predicate is connectivity), while
        /// `.overlapping` excludes it (used by `remove`, which splits only on a
        /// cut-non-empty intersection).
        const RunKind = enum { connected, overlapping };

        /// First index `i` whose stored range reaches `range`'s lower cut —
        /// `range.lower <= stored[i].upper` for `.connected`, strict `<` for
        /// `.overlapping`. `items.len` if none. A lower-bound binary search:
        /// stored upper cuts ascend, so the predicate flips false→true once.
        fn runStart(stored: []const Range, range: Range, comptime kind: RunKind) usize {
            var lo: usize = 0;
            var hi: usize = stored.len;
            while (lo < hi) {
                const mid = lo + (hi - lo) / 2;
                const reaches = switch (Cut.cmp(range.lower, stored[mid].upper)) {
                    .lt => true,
                    .eq => kind == .connected, // touch counts only for add
                    .gt => false,
                };
                if (reaches) hi = mid else lo = mid + 1;
            }
            return lo;
        }

        /// First index `i` starting beyond `range`'s upper cut —
        /// `stored[i].lower > range.upper` for `.connected`, `>=` for
        /// `.overlapping`. `items.len` if none. A lower-bound binary search:
        /// stored lower cuts ascend, so the "beyond" predicate flips false→true
        /// once. Together with `runStart` this brackets the affected run `[lo,
        /// hi)`, and `lo <= hi` always (a stored range has `lower <= upper`).
        fn runEnd(stored: []const Range, range: Range, comptime kind: RunKind) usize {
            var lo: usize = 0;
            var hi: usize = stored.len;
            while (lo < hi) {
                const mid = lo + (hi - lo) / 2;
                const beyond = switch (Cut.cmp(stored[mid].lower, range.upper)) {
                    .gt => true,
                    .eq => kind == .overlapping, // touch ends the run only for remove
                    .lt => false,
                };
                if (beyond) hi = mid else lo = mid + 1;
            }
            return lo;
        }

        /// Whether `value` falls in some stored range. This is the **only**
        /// integer-point predicate — `(1, 2)` correctly contains no `i32`.
        pub fn contains(self: Self, value: T) bool {
            for (self.ranges.items) |r| {
                if (r.contains(value)) return true;
            }
            return false;
        }

        /// The stored range containing `value`, or `null`.
        pub fn rangeContaining(self: Self, value: T) ?Range {
            for (self.ranges.items) |r| {
                if (r.contains(value)) return r;
            }
            return null;
        }

        /// Whether some **single** stored range encloses `range` (cut-defined
        /// `Range.encloses`). A set covering `{[1, 3), [5, 9)}` does **not**
        /// enclose `[2, 6)` — no single stored range does.
        pub fn encloses(self: Self, range: Range) bool {
            for (self.ranges.items) |r| {
                if (r.encloses(range)) return true;
            }
            return false;
        }

        /// Whether [`encloses`](RangeSet.encloses) holds for **every** argument.
        pub fn enclosesAll(self: Self, ranges: []const Range) bool {
            for (ranges) |r| {
                if (!self.encloses(r)) return false;
            }
            return true;
        }

        /// Whether `range` has a **cut-non-empty intersection** with some stored
        /// range — pure cut algebra. An **abutment** is *not* an intersection
        /// (`intersects([3, 5))` against `[5, 9)` is false); a cut-empty query
        /// never intersects; but a discrete-empty-yet-cut-non-empty overlap
        /// **does** count (`intersects(open(1, 2))` against stored `(1, 2)` is
        /// **true**, though no `i32` lies in it).
        pub fn intersects(self: Self, range: Range) bool {
            for (self.ranges.items) |r| {
                if (r.intersection(range)) |i| {
                    if (!i.isEmpty()) return true;
                }
            }
            return false;
        }

        /// The minimum enclosing range `[min lower cut, max upper cut]`; `null`
        /// on an empty set.
        pub fn span(self: Self) ?Range {
            if (self.ranges.items.len == 0) return null;
            const first = self.ranges.items[0];
            const last = self.ranges.items[self.ranges.items.len - 1];
            return .{ .lower = first.lower, .upper = last.upper };
        }

        /// A **new** independent `RangeSet` of the cut-region **gaps** between
        /// the stored ranges over the full `(-∞, +∞)` domain.
        /// `complement(empty)` = `{all()}`; `complement({all()})` = `{}`; no
        /// spurious `±∞` gap when an end is already unbounded; the boundary side
        /// flips (closed↔open at the same cut value). `complement ∘ complement
        /// == identity`. The caller owns the returned set (`deinit`).
        pub fn complement(self: Self, allocator: Allocator) !Self {
            var out = Self.init(allocator);
            errdefer out.deinit();
            // Walking cut: the lower cut of the next gap. Starts at `-∞`.
            var cursor: Cut = .below_all;
            for (self.ranges.items) |r| {
                // Gap from `cursor` up to this range's lower cut, when non-empty.
                if (Cut.cmp(cursor, r.lower) == .lt) {
                    try out.ranges.append(allocator, .{ .lower = cursor, .upper = r.lower });
                }
                // Next gap starts just past this range's upper cut.
                cursor = r.upper;
            }
            // Trailing gap from the last upper cut to `+∞`, when non-empty.
            if (Cut.cmp(cursor, .above_all) == .lt) {
                try out.ranges.append(allocator, .{ .lower = cursor, .upper = .above_all });
            }
            return out;
        }

        /// A **new** independent `RangeSet` = this set **intersected** with
        /// `view` (each stored range clipped to `view`). `subRangeSet([3, 6))`
        /// of `{[1, 5), [8, 9]}` = `{[3, 5)}`. The caller owns the returned set.
        pub fn subRangeSet(self: Self, view: Range, allocator: Allocator) !Self {
            var out = Self.init(allocator);
            errdefer out.deinit();
            for (self.ranges.items) |r| {
                if (r.intersection(view)) |i| {
                    if (!i.isEmpty()) {
                        // The stored ranges are ascending and disjoint, so their
                        // clipped images stay ascending, disjoint, non-connected.
                        try out.ranges.append(allocator, i);
                    }
                }
            }
            return out;
        }

        /// The canonical disjoint ranges, **ascending by lower cut**, copied
        /// into a caller-owned slice.
        pub fn asRanges(self: Self, allocator: Allocator) ![]Range {
            return allocator.dupe(Range, self.ranges.items);
        }

        /// The stored ranges as a borrowed slice (valid until the next mutation).
        /// Ascending by lower cut.
        pub fn items(self: Self) []const Range {
            return self.ranges.items;
        }

        /// Whether the set has **no stored ranges**. A cut-region predicate —
        /// `{(1, 2)}` is **not** empty even though it contains no `i32`.
        pub fn isEmpty(self: Self) bool {
            return self.ranges.items.len == 0;
        }

        /// Remove all ranges (keeps the backing capacity).
        pub fn clear(self: *Self) void {
            self.ranges.clearRetainingCapacity();
        }
    };
}

/// `RangeSet(i32)` — the v1 specialisation matching the cross-language
/// validation universe.
pub const I32RangeSet = RangeSet(i32);

// ── Native unit tests (testing allocator: no leaks) ─────────────────────────

const testing = std.testing;
const I32Range = range_mod.I32Range;
const BoundType = range_mod.BoundType;

fn rsFrom(allocator: Allocator, ranges: []const I32Range) !I32RangeSet {
    var s = I32RangeSet.init(allocator);
    try s.addAll(ranges);
    return s;
}

fn expectRanges(s: I32RangeSet, expected: []const I32Range) !void {
    try testing.expectEqual(expected.len, s.items().len);
    for (expected, s.items()) |e, got| {
        try testing.expect(e.eql(got));
    }
}

test "coalesce overlap" {
    var s = try rsFrom(testing.allocator, &.{ I32Range.closed(1, 5), I32Range.closed(3, 9) });
    defer s.deinit();
    try expectRanges(s, &.{I32Range.closed(1, 9)});
    try testing.expect(s.contains(4));
    try testing.expect(!s.contains(10));
    try testing.expect(s.span().?.eql(I32Range.closed(1, 9)));
}

test "coalesce abut cut-touch keeps outer cuts" {
    // [1,3) & [3,5) touch at Below(3) -> single [1,5).
    var s = try rsFrom(testing.allocator, &.{ I32Range.closedOpen(1, 3), I32Range.closedOpen(3, 5) });
    defer s.deinit();
    try expectRanges(s, &.{I32Range.closedOpen(1, 5)});
    try testing.expect(s.contains(3));
    try testing.expect(!s.contains(5));
    try testing.expectEqual(BoundType.open, s.items()[0].upperBoundType().?);
}

test "open gap no-merge ((1,3) & (3,5))" {
    var s = try rsFrom(testing.allocator, &.{ I32Range.open(1, 3), I32Range.open(3, 5) });
    defer s.deinit();
    try expectRanges(s, &.{ I32Range.open(1, 3), I32Range.open(3, 5) });
    try testing.expect(!s.contains(3));
}

test "adjacent closed no integer-adjacency merge ([1,3] & [4,5])" {
    var s = try rsFrom(testing.allocator, &.{ I32Range.closed(1, 3), I32Range.closed(4, 5) });
    defer s.deinit();
    try expectRanges(s, &.{ I32Range.closed(1, 3), I32Range.closed(4, 5) });
}

test "add empty is no-op" {
    var s = I32RangeSet.init(testing.allocator);
    defer s.deinit();
    try s.add(I32Range.closedOpen(5, 5));
    try testing.expect(s.isEmpty());
    try s.add(I32Range.openClosed(5, 5));
    try testing.expect(s.isEmpty());
}

test "add open(1,2) is stored (cut-non-empty, no integer)" {
    var s = try rsFrom(testing.allocator, &.{I32Range.open(1, 2)});
    defer s.deinit();
    try testing.expect(!s.isEmpty());
    try expectRanges(s, &.{I32Range.open(1, 2)});
    try testing.expect(!s.contains(1));
    try testing.expect(!s.contains(2));
}

test "remove splits" {
    var s = try rsFrom(testing.allocator, &.{I32Range.closed(1, 9)});
    defer s.deinit();
    try s.remove(I32Range.closedOpen(4, 7));
    try expectRanges(s, &.{ I32Range.closedOpen(1, 4), I32Range.closed(7, 9) });
}

test "remove empty is no-op" {
    var s = try rsFrom(testing.allocator, &.{I32Range.closed(1, 9)});
    defer s.deinit();
    try s.remove(I32Range.closedOpen(5, 5));
    try expectRanges(s, &.{I32Range.closed(1, 9)});
}

test "remove abutment does not split" {
    var s = try rsFrom(testing.allocator, &.{I32Range.closedOpen(1, 5)});
    defer s.deinit();
    try s.remove(I32Range.closedOpen(5, 9));
    try expectRanges(s, &.{I32Range.closedOpen(1, 5)});
}

test "contains and rangeContaining" {
    var s = try rsFrom(testing.allocator, &.{ I32Range.closedOpen(1, 5), I32Range.closed(8, 9) });
    defer s.deinit();
    try testing.expect(s.contains(3));
    try testing.expect(!s.contains(6));
    try testing.expect(s.rangeContaining(3).?.eql(I32Range.closedOpen(1, 5)));
    try testing.expect(s.rangeContaining(6) == null);
}

test "encloses is single-range, enclosesAll per-argument" {
    var s = try rsFrom(testing.allocator, &.{ I32Range.closedOpen(1, 3), I32Range.closedOpen(5, 9) });
    defer s.deinit();
    try testing.expect(!s.encloses(I32Range.closedOpen(2, 6)));
    try testing.expect(s.encloses(I32Range.closedOpen(1, 2)));
    try testing.expect(s.enclosesAll(&.{ I32Range.closedOpen(1, 2), I32Range.closedOpen(5, 8) }));
    try testing.expect(!s.enclosesAll(&.{ I32Range.closedOpen(1, 2), I32Range.closedOpen(2, 6) }));
}

test "intersects cut-algebra (abut false, cut-empty false)" {
    var s = try rsFrom(testing.allocator, &.{ I32Range.closedOpen(1, 3), I32Range.closedOpen(5, 9) });
    defer s.deinit();
    try testing.expect(s.intersects(I32Range.closedOpen(2, 6)));
    try testing.expect(!s.intersects(I32Range.closedOpen(5, 5)));
    var s2 = try rsFrom(testing.allocator, &.{I32Range.closedOpen(5, 9)});
    defer s2.deinit();
    try testing.expect(!s2.intersects(I32Range.closedOpen(3, 5)));
}

test "intersects_open: cut-non-empty, no integer witness -> true" {
    var s = try rsFrom(testing.allocator, &.{I32Range.open(1, 2)});
    defer s.deinit();
    try testing.expect(s.intersects(I32Range.open(1, 2)));
}

test "complement basic" {
    var s = try rsFrom(testing.allocator, &.{I32Range.closed(1, 5)});
    defer s.deinit();
    var c = try s.complement(testing.allocator);
    defer c.deinit();
    try expectRanges(c, &.{ I32Range.lessThan(1), I32Range.greaterThan(5) });
}

test "complement(all) is empty" {
    var s = try rsFrom(testing.allocator, &.{I32Range.all()});
    defer s.deinit();
    var c = try s.complement(testing.allocator);
    defer c.deinit();
    try testing.expect(c.isEmpty());
}

test "complement(empty) is all" {
    var s = I32RangeSet.init(testing.allocator);
    defer s.deinit();
    var c = try s.complement(testing.allocator);
    defer c.deinit();
    try expectRanges(c, &.{I32Range.all()});
}

test "complement unbounded: no spurious leading gap" {
    var s = try rsFrom(testing.allocator, &.{I32Range.lessThan(10)});
    defer s.deinit();
    var c = try s.complement(testing.allocator);
    defer c.deinit();
    try expectRanges(c, &.{I32Range.atLeast(10)});
}

test "complement involution" {
    const cases = [_][]const I32Range{
        &.{I32Range.closed(1, 5)},
        &.{ I32Range.open(1, 3), I32Range.open(3, 5) },
        &.{I32Range.lessThan(10)},
        &.{ I32Range.closed(std.math.minInt(i32), 0), I32Range.openClosed(0, std.math.maxInt(i32)) },
        &.{},
        &.{I32Range.all()},
    };
    inline for (cases) |ranges| {
        var s = try rsFrom(testing.allocator, ranges);
        defer s.deinit();
        var c1 = try s.complement(testing.allocator);
        defer c1.deinit();
        var cc = try c1.complement(testing.allocator);
        defer cc.deinit();
        try testing.expectEqual(s.items().len, cc.items().len);
        for (s.items(), cc.items()) |a, b| {
            try testing.expect(a.eql(b));
        }
    }
}

test "subRangeSet clips, independent snapshot" {
    var s = try rsFrom(testing.allocator, &.{ I32Range.closedOpen(1, 5), I32Range.closed(8, 9) });
    defer s.deinit();
    var sub = try s.subRangeSet(I32Range.closedOpen(3, 6), testing.allocator);
    defer sub.deinit();
    try expectRanges(sub, &.{I32Range.closedOpen(3, 5)});
    // Mutating the snapshot must not touch the parent.
    try sub.add(I32Range.closed(100, 200));
    try expectRanges(s, &.{ I32Range.closedOpen(1, 5), I32Range.closed(8, 9) });
}

test "signed extremes: coalesce, no ±1" {
    var s = I32RangeSet.init(testing.allocator);
    defer s.deinit();
    const min = std.math.minInt(i32);
    const max = std.math.maxInt(i32);
    try s.add(I32Range.closed(min, 0));
    try s.add(I32Range.openClosed(0, max));
    // [MIN,0] & (0,MAX] abut at Above(0) -> coalesce to [MIN, MAX].
    try expectRanges(s, &.{I32Range.closed(min, max)});
    try testing.expect(s.contains(min));
    try testing.expect(s.contains(max));
    try testing.expect(s.span().?.eql(I32Range.closed(min, max)));
    // [MIN,MAX] is NOT all(): complement is the two flanking gaps, no overflow.
    var c = try s.complement(testing.allocator);
    defer c.deinit();
    try expectRanges(c, &.{ I32Range.lessThan(min), I32Range.greaterThan(max) });

    // all() over the whole domain DOES complement to empty.
    var whole = try rsFrom(testing.allocator, &.{I32Range.all()});
    defer whole.deinit();
    var wc = try whole.complement(testing.allocator);
    defer wc.deinit();
    try testing.expect(wc.isEmpty());
}

test "clear empties" {
    var s = try rsFrom(testing.allocator, &.{I32Range.closed(1, 9)});
    defer s.deinit();
    s.clear();
    try testing.expect(s.isEmpty());
    try testing.expectEqual(@as(usize, 0), s.items().len);
}

test "normal form after sequence: ascending, pairwise non-connected, non-empty" {
    var s = I32RangeSet.init(testing.allocator);
    defer s.deinit();
    const ops = [_]I32Range{
        I32Range.closed(1, 5),
        I32Range.closedOpen(10, 12),
        I32Range.closedOpen(12, 15),
        I32Range.open(20, 25),
        I32Range.closed(4, 11),
    };
    for (ops) |r| try s.add(r);
    const v = s.items();
    var i: usize = 1;
    while (i < v.len) : (i += 1) {
        try testing.expectEqual(std.math.Order.lt, I32Range.Cut.cmp(v[i - 1].lower, v[i].lower));
        try testing.expect(!v[i - 1].isConnected(v[i]));
    }
    for (v) |r| try testing.expect(!r.isEmpty());
}

test "asRanges returns owned ascending slice" {
    var s = try rsFrom(testing.allocator, &.{ I32Range.closed(5, 6), I32Range.closed(1, 2) });
    defer s.deinit();
    const arr = try s.asRanges(testing.allocator);
    defer testing.allocator.free(arr);
    try testing.expectEqual(@as(usize, 2), arr.len);
    try testing.expect(arr[0].eql(I32Range.closed(1, 2)));
    try testing.expect(arr[1].eql(I32Range.closed(5, 6)));
}

// ── Splice-path stress (D13: binary-search run + in-place splice) ────────────
// The bulk of the suite above uses 1–2 stored ranges, so it never exercises the
// multi-range run bounds. These add many disjoint ranges first, then hit the
// merge/split logic across an interior run.

test "add spanning range merges a whole interior run" {
    var s = I32RangeSet.init(testing.allocator);
    defer s.deinit();
    // Ten disjoint islands [0,1], [10,11], … [90,91].
    var k: i32 = 0;
    while (k < 10) : (k += 1) try s.add(I32Range.closed(k * 10, k * 10 + 1));
    try testing.expectEqual(@as(usize, 10), s.items().len);
    // A range covering [15, 75] swallows islands 2..7 and abuts none of the
    // survivors, collapsing the middle run to one range.
    try s.add(I32Range.closed(15, 75));
    try expectRanges(s, &.{
        I32Range.closed(0, 1),
        I32Range.closed(10, 11),
        I32Range.closed(15, 75),
        I32Range.closed(80, 81),
        I32Range.closed(90, 91),
    });
}

test "add at front, gap, and end lands in sorted position" {
    var s = try rsFrom(testing.allocator, &.{ I32Range.closed(10, 12), I32Range.closed(20, 22) });
    defer s.deinit();
    try s.add(I32Range.closed(0, 1)); // front
    try s.add(I32Range.closed(15, 16)); // interior gap
    try s.add(I32Range.closed(30, 31)); // end
    try expectRanges(s, &.{
        I32Range.closed(0, 1),
        I32Range.closed(10, 12),
        I32Range.closed(15, 16),
        I32Range.closed(20, 22),
        I32Range.closed(30, 31),
    });
}

test "remove spanning range clips ends and drops the interior run" {
    var s = I32RangeSet.init(testing.allocator);
    defer s.deinit();
    var k: i32 = 0;
    while (k < 6) : (k += 1) try s.add(I32Range.closedOpen(k * 10, k * 10 + 5)); // [0,5) [10,15) … [50,55)
    try testing.expectEqual(@as(usize, 6), s.items().len);
    // Remove [12, 43): clips [10,15)->[10,12), drops [20,25) & [30,35), clips
    // [40,45)->[43,45); [0,5) and [50,55) untouched.
    try s.remove(I32Range.closedOpen(12, 43));
    try expectRanges(s, &.{
        I32Range.closedOpen(0, 5),
        I32Range.closedOpen(10, 12),
        I32Range.closedOpen(43, 45),
        I32Range.closedOpen(50, 55),
    });
}

test "remove split is failure-atomic under OOM" {
    // The only growth in the splice paths: remove splitting one range into two
    // fragments. If the reserve OOMs, the set must be left UNCHANGED (project
    // OOM-atomicity contract), not half-mutated to just the left fragment.
    var s = try rsFrom(testing.allocator, &.{I32Range.closed(1, 9)});
    defer s.deinit();
    // Trim spare capacity to len so the split's +1 slot MUST allocate (else the
    // reserve is a no-op and the failure path is never exercised).
    s.ranges.shrinkAndFree(s.allocator, s.ranges.items.len);
    // Fail the next allocation (the ensureUnusedCapacity for the split slot).
    var failing = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    s.allocator = failing.allocator();
    try testing.expectError(error.OutOfMemory, s.remove(I32Range.closedOpen(4, 7)));
    s.allocator = testing.allocator; // restore for deinit
    // Unchanged: still the single [1, 9].
    try expectRanges(s, &.{I32Range.closed(1, 9)});
}

test "splice across unbounded sentinels (add bridge, remove producing unbounded frags)" {
    // add: bridge two unbounded-ended islands into one all().
    var s = try rsFrom(testing.allocator, &.{ I32Range.lessThan(0), I32Range.atLeast(10) });
    defer s.deinit();
    try s.add(I32Range.closedOpen(0, 10)); // fills the gap, abuts both ends
    try expectRanges(s, &.{I32Range.all()});

    // remove from all() straddling a finite window -> two unbounded fragments.
    try s.remove(I32Range.closedOpen(3, 6));
    try expectRanges(s, &.{ I32Range.lessThan(3), I32Range.atLeast(6) });

    // remove an unbounded tail across a multi-range set: drops/clips the run
    // whose lower cuts are >= the cut, leaving the bounded head untouched.
    var s2 = try rsFrom(testing.allocator, &.{
        I32Range.closed(0, 2),
        I32Range.closed(10, 12),
        I32Range.closed(20, 22),
    });
    defer s2.deinit();
    try s2.remove(I32Range.atLeast(11)); // clips [10,12]->[10,11), drops [20,22]
    try expectRanges(s2, &.{ I32Range.closed(0, 2), I32Range.closedOpen(10, 11) });
}

test "differential vs boolean model over a bounded domain (random add/remove)" {
    // Strongest guard on the splice bounds: apply thousands of random
    // closedOpen add/remove ops and cross-check contains() against a dense
    // bool array, since closedOpen(lo,hi) over i32 covers exactly integers
    // [lo,hi). Also re-verify the normal-form invariant after every op.
    const N: i32 = 48;
    var model = [_]bool{false} ** @as(usize, N);
    var s = I32RangeSet.init(testing.allocator);
    defer s.deinit();

    var prng = std.Random.DefaultPrng.init(0xD13_D13);
    const rnd = prng.random();
    var iter: usize = 0;
    while (iter < 3000) : (iter += 1) {
        const lo = rnd.intRangeAtMost(i32, 0, N);
        const len = rnd.intRangeAtMost(i32, 0, 8);
        const hi = @min(lo + len, N);
        const r = I32Range.closedOpen(lo, hi);
        if (rnd.boolean()) {
            try s.add(r);
            var v = lo;
            while (v < hi) : (v += 1) model[@intCast(v)] = true;
        } else {
            try s.remove(r);
            var v = lo;
            while (v < hi) : (v += 1) model[@intCast(v)] = false;
        }
        // contains() must match the dense model at every point.
        var v: i32 = 0;
        while (v < N) : (v += 1) {
            try testing.expectEqual(model[@intCast(v)], s.contains(v));
        }
        // Normal form: strictly ascending lowers, pairwise non-connected, non-empty.
        const items = s.items();
        var i: usize = 1;
        while (i < items.len) : (i += 1) {
            try testing.expectEqual(std.math.Order.lt, I32Range.Cut.cmp(items[i - 1].lower, items[i].lower));
            try testing.expect(!items[i - 1].isConnected(items[i]));
        }
        for (items) |rr| try testing.expect(!rr.isEmpty());
    }
}
