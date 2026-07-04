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

            // Merge `range` with every connected stored range, spanning all of
            // them. Connectivity (overlap OR abutment) is the predicate.
            var merged = range;
            var out: std.ArrayListUnmanaged(Range) = .{};
            errdefer out.deinit(self.allocator);
            try out.ensureTotalCapacity(self.allocator, self.ranges.items.len + 1);
            for (self.ranges.items) |r| {
                if (r.isConnected(merged)) {
                    merged = r.span(merged);
                } else {
                    out.appendAssumeCapacity(r);
                }
            }
            // Insert `merged` at its ascending-by-lower-cut position.
            var pos: usize = out.items.len;
            for (out.items, 0..) |r, i| {
                if (Cut.cmp(r.lower, merged.lower) == .gt) {
                    pos = i;
                    break;
                }
            }
            out.insertAssumeCapacity(pos, merged);

            self.ranges.deinit(self.allocator);
            self.ranges = out;
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
            var out: std.ArrayListUnmanaged(Range) = .{};
            errdefer out.deinit(self.allocator);
            try out.ensureTotalCapacity(self.allocator, self.ranges.items.len + 1);
            for (self.ranges.items) |r| {
                // No cut-non-empty overlap -> keep `r` unchanged. Abutment
                // alone (cut-empty intersection) does not split.
                if (r.intersection(range)) |i| {
                    if (!i.isEmpty()) {
                        // Left fragment: r below the removed range's lower cut.
                        if (Cut.cmp(r.lower, range.lower) == .lt) {
                            out.appendAssumeCapacity(.{ .lower = r.lower, .upper = range.lower });
                        }
                        // Right fragment: r above the removed range's upper cut.
                        if (Cut.cmp(range.upper, r.upper) == .lt) {
                            out.appendAssumeCapacity(.{ .lower = range.upper, .upper = r.upper });
                        }
                        continue;
                    }
                }
                out.appendAssumeCapacity(r);
            }
            self.ranges.deinit(self.allocator);
            self.ranges = out;
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
