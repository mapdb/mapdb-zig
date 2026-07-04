// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! `RangeMap(comptime T, comptime V)` — a mutable piecewise mapping from
//! disjoint non-empty `Range(T)`s to values `V` (v1 ships the `i32 -> i32`
//! specialisation, `I32I32RangeMap`).
//!
//! **Unlike `RangeSet`, a `RangeMap` does NOT coalesce across different
//! values.** [`put`](RangeMap.put) is last-writer-wins: it clips/splits every
//! overlapping prior entry and inserts the new `(range, value)`, but leaves
//! adjacent equal-valued entries **distinct**.
//! [`putCoalescing`](RangeMap.putCoalescing) is the variant that merges
//! connected neighbours holding an **equal** value.
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
/// See the module docs for the put / put-coalescing semantics and the
/// normal-form invariant.
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
        /// the old value); the new `(range, value)` is then inserted. A
        /// **cut-empty** `range` is a **no-op**. `put` does **not** coalesce —
        /// an adjacent equal value stays a distinct entry.
        pub fn put(self: *Self, range: Range, value: V) Allocator.Error!void {
            if (range.isEmpty()) return;
            try self.clipOut(range);
            try self.insertEntry(range, value);
        }

        /// Like [`put`](RangeMap.put), then **merge** the inserted entry with
        /// any **connected** (overlapping *or* abutting) neighbour whose value
        /// **equals** `value`, producing one entry spanning the union.
        /// Neighbours with a different value are left untouched (clipped by the
        /// `put` step as usual).
        pub fn putCoalescing(self: *Self, range: Range, value: V) Allocator.Error!void {
            if (range.isEmpty()) return;
            try self.clipOut(range);
            // Span over every connected entry with an EQUAL value, dropping them.
            var merged = range;
            var out: std.ArrayListUnmanaged(Entry) = .{};
            errdefer out.deinit(self.allocator);
            try out.ensureTotalCapacity(self.allocator, self.entries.items.len + 1);
            for (self.entries.items) |e| {
                if (e.value == value and e.range.isConnected(merged)) {
                    merged = e.range.span(merged);
                } else {
                    out.appendAssumeCapacity(e);
                }
            }
            self.entries.deinit(self.allocator);
            self.entries = out;
            try self.insertEntry(merged, value);
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
            try out.ensureTotalCapacity(self.allocator, self.entries.items.len + 1);
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

        /// Insert `(range, value)` at its ascending-by-lower-cut position.
        /// Callers must have already cleared the overlap (via `clipOut`);
        /// `range` is disjoint from every remaining entry.
        fn insertEntry(self: *Self, range: Range, value: V) !void {
            var pos: usize = self.entries.items.len;
            for (self.entries.items, 0..) |e, i| {
                if (Cut.cmp(e.range.lower, range.lower) == .gt) {
                    pos = i;
                    break;
                }
            }
            try self.entries.insert(self.allocator, pos, .{ .range = range, .value = value });
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

test "put does NOT coalesce" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(1, 5), 100);
    try m.put(I32Range.closedOpen(5, 9), 100);
    try expectEntries(m, &.{ ent(I32Range.closedOpen(1, 5), 100), ent(I32Range.closedOpen(5, 9), 100) });
    try testing.expectEqual(@as(?i32, 100), m.get(5));
}

test "putCoalescing equal value abut merges" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(1, 5), 100);
    try m.putCoalescing(I32Range.closedOpen(5, 9), 100);
    try expectEntries(m, &.{ent(I32Range.closedOpen(1, 9), 100)});
}

test "putCoalescing different value no merge" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(1, 5), 100);
    try m.putCoalescing(I32Range.closedOpen(5, 9), 200);
    try expectEntries(m, &.{ ent(I32Range.closedOpen(1, 5), 100), ent(I32Range.closedOpen(5, 9), 200) });
}

test "putCoalescing both sides bridges" {
    var m = I32I32RangeMap.init(testing.allocator);
    defer m.deinit();
    try m.put(I32Range.closedOpen(1, 5), 100);
    try m.put(I32Range.closedOpen(9, 12), 100);
    try m.putCoalescing(I32Range.closedOpen(5, 9), 100);
    try expectEntries(m, &.{ent(I32Range.closedOpen(1, 12), 100)});
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
    try m.putCoalescing(I32Range.closedOpen(20, 25), 3);
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
