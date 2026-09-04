// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! `RangeMap(comptime T, comptime V)` — a mutable piecewise mapping from
//! disjoint non-empty `Range(T)`s to values `V` (v1 ships the `i32 -> i32`
//! specialisation, `I32I32RangeMap`).
//!
//! Like `RangeSet`, a `RangeMap` is **always maximally merged** — but per
//! value: [`put`](RangeMap.put) is last-writer-wins (it clips/splits every
//! overlapping prior entry) and then **coalesces** the inserted entry with
//! connected neighbours holding an **equal** value. A **different** value is a
//! barrier and is never absorbed or crossed. The normal form therefore carries
//! a global invariant: *no two connected entries hold an equal value*.
//!
//! ## Divergence from Guava
//!
//! `TreeRangeMap.put` does not coalesce; coalescing lives in a separate
//! `putCoalescing`. We fold it into `put` and do **not** expose
//! `putCoalescing`. Guava's split is a compatibility retrofit (`RangeMap` is
//! `@since 14.0`, `putCoalescing` `@since 22.0`, by which point `put`'s
//! behaviour was observable through `asMapOfRanges()` and could not be
//! changed); we have no such constraint. See
//! `spec/features/range-set-map.md` §Coalescing.
//!
//! Every clip / split / merge / ordering decision reduces to the side-aware cut
//! comparisons of `range.zig`; there is **no `±1` endpoint arithmetic** (the
//! `INT_MIN`/`INT_MAX` overflow trap).
//!
//! ## Backing & ownership
//!
//! A flat `std.ArrayListUnmanaged(Entry)` kept in normal form: entry ranges
//! non-empty, pairwise disjoint, each value mapped by at most one point,
//! ascending by lower cut. `Range(T)` and `V` (v1 `i32`) are value (`Copy`)
//! types, so the only owned resource is the backing buffer;
//! [`deinit`](RangeMap.deinit) frees it. `subRangeMap` returns a **new
//! independent** snapshot owning its own buffer.

const std = @import("std");
const Allocator = std.mem.Allocator;
const range_mod = @import("range.zig");

/// A mutable piecewise mapping from disjoint ranges to values.
///
/// See the module docs for the put / coalescing semantics and the normal-form
/// invariant.
pub fn RangeMap(comptime T: type, comptime V: type) type {
    return struct {
        const Self = @This();

        /// The range value type (`range.zig`) used as keys.
        pub const Range = range_mod.Range(T);
        const Cut = Range.Cut;

        /// A `(range, value)` entry. `range` is the cut-region this value maps.
        pub const Entry = struct {
            range: Range,
            value: V,
        };

        /// Normal form: non-empty, pairwise disjoint, ascending by lower cut.
        entries: std.ArrayListUnmanaged(Entry) = .{},
        allocator: Allocator,

        /// An empty range map.
        pub fn init(allocator: Allocator) Self {
            return .{ .entries = .{}, .allocator = allocator };
        }

        /// Free the backing buffer.
        pub fn deinit(self: *Self) void {
            self.entries.deinit(self.allocator);
        }

        /// Assign `value` to **every** point of `range`, **last-writer-wins**
        /// over any prior overlap. Existing entries are clipped to the parts
        /// outside `range` (a straddling entry **splits into two**, both keeping
        /// the old value); the new `(range, value)` is then **coalesced** with
        /// any connected neighbour holding an **equal** value and inserted. A
        /// **different** value is a barrier. A **cut-empty** `range` is a
        /// **no-op**, decided before any clipping.
        pub fn put(self: *Self, range: Range, value: V) !void {
            if (range.isEmpty()) return;
            try self.clipOut(range);

            // Coalesce outward from the insertion position. Because the normal
            // form is maintained by every put, AT MOST ONE entry per side is
            // absorbable: if the neighbour is absorbed, the entry beyond it was
            // already either disconnected from it or differently-valued, and
            // stays so against the grown range. Each loop therefore runs at most
            // once. They are loops rather than ifs so a normal form violated by
            // a bug elsewhere degrades into a correct (if slower) result instead
            // of a malformed map.
            const pos = self.insertionPoint(range);
            var merged = range;

            var lo = pos;
            while (lo > 0) {
                const e = self.entries.items[lo - 1];
                if (e.value != value or !e.range.isConnected(merged)) break;
                merged = e.range.span(merged);
                lo -= 1;
            }

            var hi = pos;
            while (hi < self.entries.items.len) {
                const e = self.entries.items[hi];
                if (e.value != value or !e.range.isConnected(merged)) break;
                merged = e.range.span(merged);
                hi += 1;
            }

            // Replace entries[lo..hi] with the single merged entry. `clipOut`
            // reserved `len + 2` (one straddling entry can split into two
            // fragments, and this insert adds one more), so neither branch can
            // fail after the buffer has been disturbed.
            if (hi - lo == 0) {
                try self.entries.insert(self.allocator, lo, .{ .range = merged, .value = value });
            } else {
                self.entries.replaceRangeAssumeCapacity(lo, hi - lo, &[_]Entry{
                    .{ .range = merged, .value = value },
                });
            }
        }

        /// The value mapped at `value`, or `null` if uncovered.
        pub fn get(self: Self, value: T) ?V {
            for (self.entries.items) |e| {
                if (e.range.contains(value)) return e.value;
            }
            return null;
        }

        /// The `(range, value)` entry covering `value`, or `null`.
        pub fn getEntry(self: Self, value: T) ?Entry {
            for (self.entries.items) |e| {
                if (e.range.contains(value)) return e;
            }
            return null;
        }

        /// Unmap `range`, **splitting** any entry straddling either boundary
        /// (both fragments keep the old value). A cut-empty `range` is a
        /// **no-op**.
        pub fn remove(self: *Self, range: Range) Allocator.Error!void {
            if (range.isEmpty()) return;
            try self.clipOut(range);
        }

        /// The minimum range enclosing all entry ranges; `null` on an empty map.
        pub fn span(self: Self) ?Range {
            if (self.entries.items.len == 0) return null;
            const first = self.entries.items[0].range;
            const last = self.entries.items[self.entries.items.len - 1].range;
            return .{ .lower = first.lower, .upper = last.upper };
        }

        /// A **new** independent `RangeMap` restricted to `view` (each entry
        /// range clipped to `view`, values preserved). The caller owns the
        /// returned map (`deinit`).
        pub fn subRangeMap(self: Self, view: Range, allocator: Allocator) !Self {
            var out = Self.init(allocator);
            errdefer out.deinit();
            for (self.entries.items) |e| {
                if (e.range.intersection(view)) |i| {
                    if (!i.isEmpty()) {
                        try out.entries.append(allocator, .{ .range = i, .value = e.value });
                    }
                }
            }
            return out;
        }

        /// The canonical disjoint `(range, value)` entries, **ascending by lower
        /// cut**, copied into a caller-owned slice.
        pub fn asMapOfRanges(self: Self, allocator: Allocator) ![]Entry {
            return allocator.dupe(Entry, self.entries.items);
        }

        /// The entries as a borrowed slice (valid until the next mutation).
        /// Ascending by lower cut.
        pub fn items(self: Self) []const Entry {
            return self.entries.items;
        }

        /// Whether the map has no entries.
        pub fn isEmpty(self: Self) bool {
            return self.entries.items.len == 0;
        }

        /// Remove all entries (keeps the backing capacity).
        pub fn clear(self: *Self) void {
            self.entries.clearRetainingCapacity();
        }

        // ---- internals --------------------------------------------------------

        /// Clip every entry to the parts **outside** `range` (the `remove` /
        /// overlap-resolution split). A straddling entry becomes two fragments;
        /// an entry fully inside `range` is dropped. Pure cut arithmetic — the
        /// boundary cuts flip, never `±1`. Abutment alone (cut-empty
        /// intersection) leaves an entry untouched.
        fn clipOut(self: *Self, range: Range) !void {
            var out: std.ArrayListUnmanaged(Entry) = .{};
            errdefer out.deinit(self.allocator);
            // `+ 2`: at most one straddling entry splits into two fragments
            // (`+ 1`), and `put` inserts one more entry into this buffer after
            // `clipOut` returns.
            try out.ensureTotalCapacity(self.allocator, self.entries.items.len + 2);
            for (self.entries.items) |e| {
                const r = e.range;
                if (r.intersection(range)) |i| {
                    if (!i.isEmpty()) {
                        // Left fragment below the removed range's lower cut.
                        if (Cut.cmp(r.lower, range.lower) == .lt) {
                            out.appendAssumeCapacity(.{
                                .range = .{ .lower = r.lower, .upper = range.lower },
                                .value = e.value,
                            });
                        }
                        // Right fragment above the removed range's upper cut.
                        if (Cut.cmp(range.upper, r.upper) == .lt) {
                            out.appendAssumeCapacity(.{
                                .range = .{ .lower = range.upper, .upper = r.upper },
                                .value = e.value,
                            });
                        }
                        continue;
                    }
                }
                out.appendAssumeCapacity(e);
            }
            self.entries.deinit(self.allocator);
            self.entries = out;
        }

        /// The ascending-by-lower-cut index at which `range` belongs: the first
        /// index whose lower cut is above `range`'s. Callers must have already
        /// cleared the overlap (via `clipOut`), so `range` is disjoint from
        /// every remaining entry and every entry below the returned index lies
        /// strictly to its left.
        fn insertionPoint(self: Self, range: Range) usize {
            for (self.entries.items, 0..) |e, i| {
                if (Cut.cmp(e.range.lower, range.lower) == .gt) return i;
            }
            return self.entries.items.len;
        }
    };
}

/// `RangeMap(i32, i32)` — the v1 specialisation matching the cross-language
/// validation universe.
pub const I32I32RangeMap = RangeMap(i32, i32);

// ── Native unit tests (testing allocator: no leaks) ─────────────────────────

const testing = std.testing;
const I32Range = range_mod.I32Range;

const MapEntry = I32I32RangeMap.Entry;

fn expectEntries(m: I32I32RangeMap, expected: []const MapEntry) !void {
    try testing.expectEqual(expected.len, m.items().len);
    for (expected, m.items()) |e, got| {
        try testing.expect(e.range.eql(got.range));
        try testing.expectEqual(e.value, got.value);
    }
}

fn ent(r: I32Range, v: i32) MapEntry {
    return .{ .range = r, .value = v };
}

test "put basic" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(1, 5), 100);
    try m.put(I32Range.closed(8, 9), 200);
    try expectEntries(m, &.{ ent(I32Range.closedOpen(1, 5), 100), ent(I32Range.closed(8, 9), 200) });
    try testing.expectEqual(@as(?i32, 100), m.get(3));
    try testing.expectEqual(@as(?i32, null), m.get(6));
    try testing.expectEqual(@as(?i32, 200), m.get(8));
}

test "put overwrite clips" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(1, 5), 100);
    try m.put(I32Range.closedOpen(3, 9), 200);
    try expectEntries(m, &.{ ent(I32Range.closedOpen(1, 3), 100), ent(I32Range.closedOpen(3, 9), 200) });
    try testing.expectEqual(@as(?i32, 100), m.get(2));
    try testing.expectEqual(@as(?i32, 200), m.get(4));
    try testing.expectEqual(@as(?i32, 200), m.get(8));
}

test "put split straddle" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(1, 9), 100);
    try m.put(I32Range.closedOpen(3, 5), 200);
    try expectEntries(m, &.{
        ent(I32Range.closedOpen(1, 3), 100),
        ent(I32Range.closedOpen(3, 5), 200),
        ent(I32Range.closedOpen(5, 9), 100),
    });
    try testing.expectEqual(@as(?i32, 100), m.get(2));
    try testing.expectEqual(@as(?i32, 200), m.get(4));
    try testing.expectEqual(@as(?i32, 100), m.get(6));
}

test "put COALESCES equal value abut" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(1, 5), 100);
    try m.put(I32Range.closedOpen(5, 9), 100);
    // ONE entry: equal value and abutting, so plain put merges them.
    // Guava's TreeRangeMap leaves two here; this is the divergence.
    try expectEntries(m, &.{ent(I32Range.closedOpen(1, 9), 100)});
    try testing.expectEqual(@as(?i32, 100), m.get(5));
}

test "put different value no merge" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(1, 5), 100);
    try m.put(I32Range.closedOpen(5, 9), 200);
    try expectEntries(m, &.{ ent(I32Range.closedOpen(1, 5), 100), ent(I32Range.closedOpen(5, 9), 200) });
}

test "put coalesces both sides bridges" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(1, 5), 100);
    try m.put(I32Range.closedOpen(9, 12), 100);
    try m.put(I32Range.closedOpen(5, 9), 100);
    try expectEntries(m, &.{ent(I32Range.closedOpen(1, 12), 100)});
}

test "put coalesces chain in ascending order" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(1, 2), 7);
    try m.put(I32Range.closedOpen(2, 3), 7);
    // A chain never forms: the map is already [1,3) here.
    try expectEntries(m, &.{ent(I32Range.closedOpen(1, 3), 7)});
    try m.put(I32Range.closedOpen(3, 4), 7);
    try expectEntries(m, &.{ent(I32Range.closedOpen(1, 4), 7)});
}

test "put coalescing is order independent" {
    // Mirror of the ascending case: the same three puts, inserted so the
    // existing entries lie to the RIGHT of the last one. Identical result.
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(2, 3), 7);
    try m.put(I32Range.closedOpen(3, 4), 7);
    try m.put(I32Range.closedOpen(1, 2), 7);
    try expectEntries(m, &.{ent(I32Range.closedOpen(1, 4), 7)});
}

test "put different value is a hard barrier" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(1, 2), 7);
    try m.put(I32Range.closedOpen(2, 3), 8);
    try m.put(I32Range.closedOpen(3, 4), 7);
    // The 8 entry is neither absorbed nor crossed, so the far [1,2) -> 7 is
    // unreachable even though both hold 7.
    try expectEntries(m, &.{
        ent(I32Range.closedOpen(1, 2), 7),
        ent(I32Range.closedOpen(2, 3), 8),
        ent(I32Range.closedOpen(3, 4), 7),
    });
}

test "put split fragments do not rejoin across the insert" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(1, 9), 100);
    try m.put(I32Range.closedOpen(3, 5), 200);
    // The two 100 fragments are separated by the 200 entry, so they are not
    // connected and must not be re-merged by the coalescing step.
    try expectEntries(m, &.{
        ent(I32Range.closedOpen(1, 3), 100),
        ent(I32Range.closedOpen(3, 5), 200),
        ent(I32Range.closedOpen(5, 9), 100),
    });
}

test "normal form has no connected equal valued pair" {
    // The global invariant that the old put/putCoalescing split could not
    // state: after every operation, no two connected entries hold an equal
    // value.
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(1, 2), 7);
    try m.put(I32Range.closedOpen(2, 3), 7);
    try m.put(I32Range.closedOpen(3, 4), 8);
    try m.put(I32Range.closedOpen(4, 5), 8);
    try m.put(I32Range.closedOpen(5, 6), 7);
    const v = m.items();
    var i: usize = 0;
    while (i + 1 < v.len) : (i += 1) {
        try testing.expect(!(v[i].range.isConnected(v[i + 1].range) and v[i].value == v[i + 1].value));
    }
    try expectEntries(m, &.{
        ent(I32Range.closedOpen(1, 3), 7),
        ent(I32Range.closedOpen(3, 5), 8),
        ent(I32Range.closedOpen(5, 6), 7),
    });
}

test "remove splits" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(1, 9), 100);
    try m.remove(I32Range.closedOpen(4, 7));
    try expectEntries(m, &.{ ent(I32Range.closedOpen(1, 4), 100), ent(I32Range.closedOpen(7, 9), 100) });
    try testing.expectEqual(@as(?i32, null), m.get(5));
}

test "getEntry lookup" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(1, 5), 100);
    const e = m.getEntry(3).?;
    try testing.expect(e.range.eql(I32Range.closedOpen(1, 5)));
    try testing.expectEqual(@as(i32, 100), e.value);
    try testing.expect(m.getEntry(6) == null);
}

test "span over entries" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(1, 5), 100);
    try m.put(I32Range.closed(8, 9), 200);
    try testing.expect(m.span().?.eql(I32Range.closed(1, 9)));
}

test "empty put is no-op" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(5, 5), 100);
    try testing.expect(m.isEmpty());
    try testing.expectEqual(@as(usize, 0), m.items().len);
}

test "subRangeMap clips, independent snapshot" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(1, 5), 100);
    try m.put(I32Range.closed(8, 9), 200);
    var sub = try m.subRangeMap(I32Range.closedOpen(3, 6), testing.allocator);
    defer sub.deinit();
    try expectEntries(sub, &.{ent(I32Range.closedOpen(3, 5), 100)});
    // Mutate the parent: sub unchanged.
    try m.put(I32Range.closed(3, 3), 999);
    try expectEntries(sub, &.{ent(I32Range.closedOpen(3, 5), 100)});
    // Mutate the snapshot: parent unchanged.
    try sub.put(I32Range.closed(50, 60), 7);
    try testing.expectEqual(@as(?i32, null), m.get(55));
}

test "signed extremes: no ±1" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    const min = std.math.minInt(i32);
    const max = std.math.maxInt(i32);
    try m.put(I32Range.closedOpen(min, 0), 1);
    try m.put(I32Range.closed(0, max), 2);
    try testing.expectEqual(@as(?i32, 1), m.get(min));
    try testing.expectEqual(@as(?i32, 2), m.get(0));
    try testing.expectEqual(@as(?i32, 2), m.get(max));
}

test "normal form disjoint after sequence" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(1, 10), 1);
    try m.put(I32Range.closedOpen(3, 5), 2);
    try m.put(I32Range.closedOpen(7, 20), 3);
    try m.put(I32Range.closedOpen(20, 25), 3);
    const v = m.items();
    var i: usize = 1;
    while (i < v.len) : (i += 1) {
        try testing.expectEqual(std.math.Order.lt, I32Range.Cut.cmp(v[i - 1].range.lower, v[i].range.lower));
        const inter = v[i - 1].range.intersection(v[i].range);
        const disjoint = if (inter) |x| x.isEmpty() else true;
        try testing.expect(disjoint);
    }
    for (v) |e| try testing.expect(!e.range.isEmpty());
}

test "asMapOfRanges returns owned ascending slice" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closed(5, 6), 50);
    try m.put(I32Range.closed(1, 2), 10);
    const arr = try m.asMapOfRanges(testing.allocator);
    defer testing.allocator.free(arr);
    try testing.expectEqual(@as(usize, 2), arr.len);
    try testing.expect(arr[0].range.eql(I32Range.closed(1, 2)));
    try testing.expectEqual(@as(i32, 10), arr[0].value);
    try testing.expect(arr[1].range.eql(I32Range.closed(5, 6)));
}

// ── Salvaged coalescing battery (NEXT #5) ───────────────────────────────────
// Rewritten from the pre-2026-07-31 `putCoalescing` tests for the coalescing
// `put`. Each pins a shape the outward walk must get right: unbounded chains,
// clip fragments rejoining chains beyond them, straddled equal entries, and
// cut-empty puts at an abutment.

test "put unbounded chains on both sides collapse to all" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.lessThan(-5), 7); // (-inf, -5)
    try m.put(I32Range.closedOpen(-5, 0), 7); // merges as it lands -> (-inf, 0)
    try m.put(I32Range.closedOpen(5, 10), 7);
    try m.put(I32Range.atLeast(10), 7); // merges as it lands -> [5, +inf)
    // Each pair merged on arrival; the gap [0,5) keeps the two sides apart.
    try expectEntries(m, &.{ ent(I32Range.lessThan(0), 7), ent(I32Range.atLeast(5), 7) });
    // Fill the gap: both unbounded neighbours absorb into (-inf, +inf).
    try m.put(I32Range.closedOpen(0, 5), 7);
    try expectEntries(m, &.{ent(I32Range.all(), 7)});
    try testing.expectEqual(@as(?i32, 7), m.get(std.math.minInt(i32)));
    try testing.expectEqual(@as(?i32, 7), m.get(0));
    try testing.expectEqual(@as(?i32, 7), m.get(std.math.maxInt(i32)));
}

test "put rejoins clipped fragment and chain beyond it" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(0, 10), 7);
    try m.put(I32Range.closedOpen(10, 12), 9);
    // [6,11) clips [0,10) to [0,6) (equal value: rejoins) and [10,12) to
    // [11,12) (different value: barrier, stays distinct).
    try m.put(I32Range.closedOpen(6, 11), 7);
    try expectEntries(m, &.{ ent(I32Range.closedOpen(0, 11), 7), ent(I32Range.closedOpen(11, 12), 9) });
    try testing.expectEqual(@as(?i32, 7), m.get(0));
    try testing.expectEqual(@as(?i32, 7), m.get(10));
    try testing.expectEqual(@as(?i32, 9), m.get(11));
}

test "put rejoins both clip fragments of a straddled equal entry" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(0, 20), 7);
    // Straddled: clipOut leaves [0,6)->7 and [14,20)->7; both rejoin.
    try m.put(I32Range.closedOpen(6, 14), 7);
    try expectEntries(m, &.{ent(I32Range.closedOpen(0, 20), 7)});

    // Same shape flanked by different values: the fragments rejoin the insert
    // but never the barriers, so the map is unchanged.
    var m2 = I32I32RangeMap.init(testing.allocator);
    defer m2.deinit();
    try m2.put(I32Range.closedOpen(0, 2), 1);
    try m2.put(I32Range.closedOpen(2, 18), 7);
    try m2.put(I32Range.closedOpen(18, 20), 1);
    try m2.put(I32Range.closedOpen(6, 14), 7);
    try expectEntries(m2, &.{
        ent(I32Range.closedOpen(0, 2), 1),
        ent(I32Range.closedOpen(2, 18), 7),
        ent(I32Range.closedOpen(18, 20), 1),
    });
}

test "put cut-empty range at an abutment is a no-op" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(1, 5), 100);
    try m.put(I32Range.closedOpen(5, 9), 200);
    // Cut-empty puts must return BEFORE clipOut: no clip, no coalesce, even
    // when the empty range sits exactly on the abutment cut (both forms).
    const unchanged = [_]MapEntry{ ent(I32Range.closedOpen(1, 5), 100), ent(I32Range.closedOpen(5, 9), 200) };
    try m.put(I32Range.closedOpen(5, 5), 100);
    try expectEntries(m, &unchanged);
    try m.put(I32Range.openClosed(5, 5), 200);
    try expectEntries(m, &unchanged);
    try m.put(I32Range.closedOpen(3, 3), 999);
    try expectEntries(m, &unchanged);
}

test "no-integer range is a stored barrier" {
    // open(1, 2) over i32 holds no integer but is cut-NON-empty, so it is
    // stored, splits the enclosing entry, and blocks the two equal-valued
    // fragments from rejoining. The point-based oracle test cannot see this
    // shape (no integer to probe), hence the exact-entry check here.
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.all(), 1);
    try m.put(I32Range.open(1, 2), 2);
    try expectEntries(m, &.{
        ent(I32Range.atMost(1), 1),
        ent(I32Range.open(1, 2), 2),
        ent(I32Range.atLeast(2), 1),
    });
    // Removing it leaves the two fragments abutting NOTHING: a gap of zero
    // integers but non-zero cuts, so they stay distinct (no rejoin).
    try m.remove(I32Range.open(1, 2));
    try expectEntries(m, &.{ ent(I32Range.atMost(1), 1), ent(I32Range.atLeast(2), 1) });
}

test "remove of an unbounded range clips to the exact sentinel cut" {
    // The surviving fragment starts at the flipped boundary cut: below(0)
    // for lessThan(0), above(0) for atMost(0). No ±1.
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.all(), 1);
    try m.remove(I32Range.lessThan(0));
    try expectEntries(m, &.{ent(I32Range.atLeast(0), 1)});

    var m2 = I32I32RangeMap.init(testing.allocator);
    defer m2.deinit();
    try m2.put(I32Range.all(), 1);
    try m2.remove(I32Range.atMost(0));
    try expectEntries(m2, &.{ent(I32Range.greaterThan(0), 1)});
}

/// Draw a random range whose endpoints lie in `[-8, 8]`, covering all four
/// bound types and every unbounded form so the `below_all` / `above_all`
/// sentinels are exercised. `open(v, v)` traps (invalid-as-open), so that draw
/// degrades to the legal cut-empty `closedOpen(v, v)`; cut-empty draws are let
/// through and must be no-ops.
fn oracleRandomRange(rnd: std.Random) I32Range {
    const a = rnd.intRangeAtMost(i32, -8, 8);
    const b = rnd.intRangeAtMost(i32, -8, 8);
    const lo = @min(a, b);
    const hi = @max(a, b);
    return switch (rnd.intRangeLessThan(u8, 0, 9)) {
        0 => I32Range.closed(lo, hi),
        1 => if (lo == hi) I32Range.closedOpen(lo, hi) else I32Range.open(lo, hi),
        2 => I32Range.closedOpen(lo, hi),
        3 => I32Range.openClosed(lo, hi),
        4 => I32Range.lessThan(a),
        5 => I32Range.atMost(a),
        6 => I32Range.greaterThan(a),
        7 => I32Range.atLeast(a),
        else => I32Range.all(),
    };
}

/// Run one seeded `put`/`remove` sequence against a dense `?i32`-per-point
/// oracle over `[-12, 12]`, checking after EVERY op that lookups, entries and
/// the normal form agree with it.
fn runPutRemoveOracle(seed: u64, ops: usize) !void {
    const LO: i32 = -12;
    const HI: i32 = 12;
    const N: usize = @intCast(HI - LO + 1);
    var oracle = [_]?i32{null} ** N;
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();

    var prng = std.Random.DefaultPrng.init(seed);
    const rnd = prng.random();
    var iter: usize = 0;
    while (iter < ops) : (iter += 1) {
        const r = oracleRandomRange(rnd);
        // ~70% put / 30% remove; values from {1,2,3} so equal-value
        // coalescing happens constantly.
        if (rnd.intRangeLessThan(u8, 0, 10) < 7) {
            const value = rnd.intRangeAtMost(i32, 1, 3);
            try m.put(r, value);
            var p = LO;
            while (p <= HI) : (p += 1) {
                if (r.contains(p)) oracle[@intCast(p - LO)] = value;
            }
        } else {
            try m.remove(r);
            var p = LO;
            while (p <= HI) : (p += 1) {
                if (r.contains(p)) oracle[@intCast(p - LO)] = null;
            }
        }

        // (a) get and (b) getEntry agree with the oracle at every point.
        var p = LO;
        while (p <= HI) : (p += 1) {
            const want = oracle[@intCast(p - LO)];
            try testing.expectEqual(want, m.get(p));
            if (m.getEntry(p)) |e| {
                try testing.expect(want != null);
                try testing.expect(e.range.contains(p));
                try testing.expectEqual(want.?, e.value);
            } else {
                try testing.expect(want == null);
            }
        }

        // (c) Normal form: ascending by lower cut, cut-non-empty, pairwise
        // disjoint, and no connected consecutive pair with an equal value.
        const v = m.items();
        for (v) |e| try testing.expect(!e.range.isEmpty());
        var i: usize = 1;
        while (i < v.len) : (i += 1) {
            const prev = v[i - 1];
            const cur = v[i];
            try testing.expectEqual(std.math.Order.lt, I32Range.Cut.cmp(prev.range.lower, cur.range.lower));
            if (prev.range.intersection(cur.range)) |x| try testing.expect(x.isEmpty());
            try testing.expect(!(prev.range.isConnected(cur.range) and prev.value == cur.value));
        }

        // (d) Rebuilding the dense array from the entries reproduces the
        // oracle exactly.
        var rebuilt = [_]?i32{null} ** N;
        for (v) |e| {
            var q = LO;
            while (q <= HI) : (q += 1) {
                if (e.range.contains(q)) {
                    try testing.expect(rebuilt[@intCast(q - LO)] == null); // disjointness, again
                    rebuilt[@intCast(q - LO)] = e.value;
                }
            }
        }
        try testing.expectEqualSlices(?i32, &oracle, &rebuilt);
    }
}

test "oracle: random put/remove vs dense per-point model" {
    // Seeded and deterministic; three seeds x 400 ops each.
    try runPutRemoveOracle(0x5A1_0001, 400);
    try runPutRemoveOracle(0x5A1_0002, 400);
    try runPutRemoveOracle(0x5A1_0003, 400);
}
