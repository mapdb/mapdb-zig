// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Compact immutable sorted map / set (`sorted-table-map`).
//!
//! A purpose-built, **pointerless** immutable sorted collection: keys (and,
//! for a map, the matching values) are packed into contiguous parallel,
//! owned slices and queried by binary search. The on-heap analogue of MapDB
//! 3's `SortedTableMap` — we port the observable behaviour and the
//! packed-array + binary-search mechanism, not the off-heap `Volume`/byte
//! machinery. Mirrors the frozen Rust reference (`src/immutable_sorted.rs`).
//!
//! This is **distinct** from the frozen-copy `Immutable*` wrappers (which seal
//! a live structure's per-entry layout against mutation) and from `Interval`
//! (a *virtual* arithmetic progression with no stored elements).
//!
//! ## Layout — flat single sorted array (the reference default)
//!
//! One flat ascending array pair (`keys` + parallel `values` for a map, a
//! single `elems` array for a set). MapDB 3 paged the arrays with a per-page
//! key directory; **paging is a legal but unobservable implementation choice**
//! (lookup, iteration, range, `len`/`isEmpty` results are identical
//! regardless). A flat array is trivially paging-invariant, so it is the
//! reference.
//!
//! ## Construction is the only way in — built once from sorted input
//!
//! `fromSorted` takes a **strictly ascending** snapshot. Construction
//! **traps** (`@panic` — the family's always-on bad-input posture, like
//! `Range`'s out-of-order constructor and `Interval`'s minimum step) unless
//! every adjacent input pair satisfies `keys[i-1] < keys[i]` strictly:
//!
//! * out-of-order input (`keys[i] < keys[i-1]`) panics;
//! * a duplicate key (`keys[i] == keys[i-1]`) panics — **no last-wins / dedup**;
//! * (map) a `keys`/`values` length mismatch panics.
//!
//! Empty input is valid and builds an empty collection; single-element input
//! is valid. Construction **copies** the input into freshly allocated,
//! collection-owned slices, so the built collection is a snapshot independent
//! of the caller's source slices (mutating them afterwards never affects the
//! collection, and vice versa). Free the backing storage with `deinit`.
//!
//! ## Immutable — no mutators
//!
//! The types expose **no** `put`/`add`/`remove`/`clear`/`set`/`insert`. There
//! is nothing to trap on a mutator: the methods simply do not exist.
//!
//! ## Iterators: materialized snapshots
//!
//! The ascending key/value/element slices are borrowed views into the owned
//! storage (`keysSlice`/`valuesSlice`/`elementsSlice`). The descending and
//! range methods return freshly allocated, **caller-owned** slices (the caller
//! frees them), matching the repo's "owned-slice methods take an allocator"
//! convention (`style/zig.md` §"Allocator discipline").
//!
//! v1 ships the `i32` surface (the cross-language validation universe). The
//! types stay `comptime`-generic over a totally-ordered primitive so the float
//! / wider-integer matrix widens later exactly as `Interval` and `Range` did;
//! ordering goes through `compareValues` (binary search / total order), never
//! a bare `<` on a generic, so float keys will widen by routing through the
//! IEEE-754 total order with no algorithm change.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Order = std.math.Order;

const range_mod = @import("../range.zig");
const Range = range_mod.Range;
const float_order = @import("../float_order.zig");

/// Total order on the element type. Integers use the natural signed/unsigned
/// order; floats route through the IEEE-754 **total order**
/// (`algorithms.md` §"Float ordering for tree collections") so that `-0.0 <
/// +0.0` and NaN payloads are ordered — identical to the primitive
/// `TreeMap`/`TreeSet` float behaviour, so the same key type never yields two
/// different orders across the library (F6). `bool` is ordered explicitly
/// (false < true) so the generic shape can be force-compiled with a `bool`
/// parameter as the rest of the family does.
fn compareValues(comptime T: type, a: T, b: T) Order {
    if (T == bool) {
        if (a == b) return .eq;
        return if (!a and b) .lt else .gt;
    }
    if (T == f32) return float_order.totalCmpF32(a, b);
    if (T == f64) return float_order.totalCmpF64(a, b);
    return std.math.order(a, b);
}

/// Binary-search result over a strictly-ascending slice: a hit at `index`, or
/// the lower-bound insertion `index` for an absent key. The midpoint is the
/// overflow-safe `lo + (hi - lo) / 2` over `usize` indices, so it is correct at
/// the signed value extremes and for large slices.
const SearchResult = struct {
    /// The hit index (when `found`) or the lower-bound insertion index.
    index: usize,
    /// Whether `key` is present at `index`.
    found: bool,
};

fn binarySearch(comptime T: type, sorted: []const T, key: T) SearchResult {
    var lo: usize = 0;
    var hi: usize = sorted.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        switch (compareValues(T, sorted[mid], key)) {
            .lt => lo = mid + 1,
            .gt => hi = mid,
            .eq => return .{ .index = mid, .found = true },
        }
    }
    return .{ .index = lo, .found = false };
}

/// Trap helper for the strictly-ascending construction check. Always-on
/// `@panic` (fires in every build profile), not a `std.debug.assert` no-op —
/// same posture as `Range.fromCuts` and `Interval`'s zero-step trap.
fn assertStrictlyAscending(comptime T: type, xs: []const T) void {
    if (xs.len < 2) return;
    var i: usize = 1;
    while (i < xs.len) : (i += 1) {
        // xs[i-1] < xs[i] strictly; equal or greater traps.
        if (compareValues(T, xs[i - 1], xs[i]) != .lt) {
            @panic("ImmutableSorted: input must be strictly ascending (no duplicate or out-of-order keys)");
        }
    }
}

// ===========================================================================
// ImmutableSortedMap(K, V)
// ===========================================================================

/// A compact immutable sorted map backed by packed parallel, owned slices
/// (`keys[i]` -> `values[i]`), queried by binary search. Built once from
/// strictly-ascending input via `fromSorted`; thereafter immutable. Free with
/// `deinit`.
pub fn ImmutableSortedMap(comptime K: type, comptime V: type) type {
    return struct {
        // `[]const` so the packed backing is immutable even through direct
        // field access: `map.keys_buf[0] = x` is a COMPILE ERROR. Zig structs
        // have no private fields, so without the `const` element type the
        // backing would be externally mutable (unlike the Rust/Go/TS/Java
        // ports' encapsulated storage) — a cross-language immutability
        // divergence. The buffers are still owned (freed by `deinit`).
        keys_buf: []const K,
        values_buf: []const V,
        allocator: Allocator,

        const Self = @This();

        /// A `(key, value)` entry returned by the entry-form queries.
        pub const Entry = struct { key: K, value: V };

        /// Build from **strictly ascending** parallel slices: `values[i]` is the
        /// value of `keys[i]`. The input is **copied** into freshly allocated,
        /// map-owned storage (snapshot — independent of the caller's slices).
        /// Free with `deinit`.
        ///
        /// Traps (`@panic`) if `keys.len != values.len`, if the keys are not
        /// strictly ascending (out-of-order), or if any key is duplicated.
        /// There is no last-wins/dedup and no silent sort — a caller who wants
        /// those sorts/dedups first. Empty and single-element input are valid.
        pub fn fromSorted(allocator: Allocator, keys: []const K, values: []const V) Allocator.Error!Self {
            if (keys.len != values.len) {
                @panic("ImmutableSortedMap.fromSorted: keys/values length mismatch");
            }
            assertStrictlyAscending(K, keys);
            const keys_copy = try allocator.dupe(K, keys);
            errdefer allocator.free(keys_copy);
            const values_copy = try allocator.dupe(V, values);
            return .{ .keys_buf = keys_copy, .values_buf = values_copy, .allocator = allocator };
        }

        /// Free the owned backing storage.
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.keys_buf);
            self.allocator.free(self.values_buf);
            self.keys_buf = &.{};
            self.values_buf = &.{};
        }

        /// Number of entries.
        pub fn len(self: *const Self) usize {
            return self.keys_buf.len;
        }

        /// Whether the map is empty.
        pub fn isEmpty(self: *const Self) bool {
            return self.keys_buf.len == 0;
        }

        fn search(self: *const Self, key: K) SearchResult {
            return binarySearch(K, self.keys_buf, key);
        }

        /// The value for `key`, or `null` if absent.
        pub fn get(self: *const Self, key: K) ?V {
            const r = self.search(key);
            return if (r.found) self.values_buf[r.index] else null;
        }

        /// Whether `key` is present.
        pub fn containsKey(self: *const Self, key: K) bool {
            return self.search(key).found;
        }

        /// Minimum key, or `null` if empty.
        pub fn firstKey(self: *const Self) ?K {
            return if (self.keys_buf.len == 0) null else self.keys_buf[0];
        }

        /// Maximum key, or `null` if empty.
        pub fn lastKey(self: *const Self) ?K {
            return if (self.keys_buf.len == 0) null else self.keys_buf[self.keys_buf.len - 1];
        }

        /// Minimum `(key, value)` entry, or `null`.
        pub fn firstEntry(self: *const Self) ?Entry {
            if (self.keys_buf.len == 0) return null;
            return .{ .key = self.keys_buf[0], .value = self.values_buf[0] };
        }

        /// Maximum `(key, value)` entry, or `null`.
        pub fn lastEntry(self: *const Self) ?Entry {
            if (self.keys_buf.len == 0) return null;
            const i = self.keys_buf.len - 1;
            return .{ .key = self.keys_buf[i], .value = self.values_buf[i] };
        }

        // ── Point navigation (NavigableMap surface, reused verbatim) ─────
        //
        // floor `<= k`, ceiling `>= k`, lower `< k` (strict), higher `> k`
        // (strict). All resolve to a single binary search over the packed key
        // array; the index arithmetic never computes a `k ± 1`, so it is
        // overflow-safe at the signed extremes.

        /// Index of the greatest key `<= k`, or `null`.
        fn floorIndex(self: *const Self, k: K) ?usize {
            const r = self.search(k);
            if (r.found) return r.index;
            return if (r.index == 0) null else r.index - 1;
        }

        /// Index of the least key `>= k`, or `null`.
        fn ceilingIndex(self: *const Self, k: K) ?usize {
            const r = self.search(k);
            return if (r.index < self.keys_buf.len) r.index else null;
        }

        /// Index of the greatest key `< k` (strict), or `null`.
        fn lowerIndex(self: *const Self, k: K) ?usize {
            const r = self.search(k); // hit and absent both bracket at r.index
            return if (r.index == 0) null else r.index - 1;
        }

        /// Index of the least key `> k` (strict), or `null`.
        fn higherIndex(self: *const Self, k: K) ?usize {
            const r = self.search(k);
            const i = if (r.found) r.index + 1 else r.index;
            return if (i < self.keys_buf.len) i else null;
        }

        /// Greatest key `<= k`, or `null`.
        pub fn floorKey(self: *const Self, k: K) ?K {
            return if (self.floorIndex(k)) |i| self.keys_buf[i] else null;
        }

        /// Greatest key `<= k` with its value, or `null`.
        pub fn floorEntry(self: *const Self, k: K) ?Entry {
            return if (self.floorIndex(k)) |i| .{ .key = self.keys_buf[i], .value = self.values_buf[i] } else null;
        }

        /// Least key `>= k`, or `null`.
        pub fn ceilingKey(self: *const Self, k: K) ?K {
            return if (self.ceilingIndex(k)) |i| self.keys_buf[i] else null;
        }

        /// Least key `>= k` with its value, or `null`.
        pub fn ceilingEntry(self: *const Self, k: K) ?Entry {
            return if (self.ceilingIndex(k)) |i| .{ .key = self.keys_buf[i], .value = self.values_buf[i] } else null;
        }

        /// Greatest key `< k` (strict), or `null`.
        pub fn lowerKey(self: *const Self, k: K) ?K {
            return if (self.lowerIndex(k)) |i| self.keys_buf[i] else null;
        }

        /// Greatest key `< k` (strict) with its value, or `null`.
        pub fn lowerEntry(self: *const Self, k: K) ?Entry {
            return if (self.lowerIndex(k)) |i| .{ .key = self.keys_buf[i], .value = self.values_buf[i] } else null;
        }

        /// Least key `> k` (strict), or `null`.
        pub fn higherKey(self: *const Self, k: K) ?K {
            return if (self.higherIndex(k)) |i| self.keys_buf[i] else null;
        }

        /// Least key `> k` (strict) with its value, or `null`.
        pub fn higherEntry(self: *const Self, k: K) ?Entry {
            return if (self.higherIndex(k)) |i| .{ .key = self.keys_buf[i], .value = self.values_buf[i] } else null;
        }

        // ── Order statistics (rank / select) ────────────────────────────
        //
        // On a flat ascending array `rank` IS the lower-bound binary-search
        // index and `select(i)` IS `keys[i]`, trivially consistent with the
        // iteration order — no subtree-size augmentation needed.

        /// Number of keys **strictly less than** `key` — the 0-based
        /// lower-bound index `key` occupies (if present) or would occupy (if
        /// absent). In `0..=len()`. Defined for present and absent keys.
        pub fn rank(self: *const Self, key: K) usize {
            return self.search(key).index;
        }

        /// The `i`-th smallest key (0-based), or `null` if `i >= len()`.
        /// Round-trips with `rank`: `selectKey(rank(k)) == k` for present `k`.
        pub fn selectKey(self: *const Self, i: usize) ?K {
            return if (i < self.keys_buf.len) self.keys_buf[i] else null;
        }

        /// The `i`-th smallest `(key, value)` entry (0-based), or `null`.
        pub fn selectEntry(self: *const Self, i: usize) ?Entry {
            return if (i < self.keys_buf.len) .{ .key = self.keys_buf[i], .value = self.values_buf[i] } else null;
        }

        // ── Iteration (ascending) — borrowed views ──────────────────────

        /// Keys in ascending order (borrowed view into owned storage).
        pub fn keysSlice(self: *const Self) []const K {
            return self.keys_buf;
        }

        /// Values in **ascending-key order** (paired with `keysSlice`), NOT
        /// sorted by value (borrowed view into owned storage).
        pub fn valuesSlice(self: *const Self) []const V {
            return self.values_buf;
        }

        /// All `(key, value)` entries in **ascending key order** — `keysSlice`
        /// zipped with `valuesSlice` (NOT value-sorted). Freshly allocated;
        /// caller frees. Mirrors the Rust `entries()` iterator.
        pub fn entries(self: *const Self, allocator: Allocator) Allocator.Error![]Entry {
            const out = try allocator.alloc(Entry, self.keys_buf.len);
            for (self.keys_buf, self.values_buf, 0..) |k, v, i| {
                out[i] = .{ .key = k, .value = v };
            }
            return out;
        }

        // ── Iteration (descending) — required, not optional; caller-owned ─

        /// All keys, descending (freshly allocated; caller frees).
        pub fn descendingKeys(self: *const Self, allocator: Allocator) Allocator.Error![]K {
            const out = try allocator.alloc(K, self.keys_buf.len);
            for (self.keys_buf, 0..) |k, i| out[self.keys_buf.len - 1 - i] = k;
            return out;
        }

        /// All `(key, value)` entries, descending (freshly allocated; caller
        /// frees).
        pub fn descendingEntries(self: *const Self, allocator: Allocator) Allocator.Error![]Entry {
            const n = self.keys_buf.len;
            const out = try allocator.alloc(Entry, n);
            for (0..n) |i| out[n - 1 - i] = .{ .key = self.keys_buf[i], .value = self.values_buf[i] };
            return out;
        }

        // ── Range queries (consume `Range(K)`; membership == range.contains) ──
        //
        // The in-range entries form a CONTIGUOUS slice of the packed array (the
        // range is convex), bracketed by two binary searches via
        // `Range.bracket`. The brackets come from the range's CUT semantics
        // (`below(v)`/`above(v)`/unbounded), never from `v ± 1` arithmetic, so
        // open/closed bounds at `INT_MIN`/`INT_MAX` do not overflow.
        // `open(1, 2)` over i32 yields an empty slice (membership is
        // `contains`, never inferred cut-emptiness).

        /// Keys whose key ∈ `range`, ascending (freshly allocated; caller
        /// frees).
        pub fn rangeKeys(self: *const Self, range: Range(K), allocator: Allocator) Allocator.Error![]K {
            const b = range.bracket(self.keys_buf);
            return allocator.dupe(K, self.keys_buf[b[0]..b[1]]);
        }

        /// `(key, value)` entries whose key ∈ `range`, ascending (freshly
        /// allocated; caller frees).
        pub fn rangeEntries(self: *const Self, range: Range(K), allocator: Allocator) Allocator.Error![]Entry {
            const b = range.bracket(self.keys_buf);
            const out = try allocator.alloc(Entry, b[1] - b[0]);
            for (b[0]..b[1], 0..) |src, dst| {
                out[dst] = .{ .key = self.keys_buf[src], .value = self.values_buf[src] };
            }
            return out;
        }

        /// Keys whose key ∈ `range`, descending (freshly allocated; caller
        /// frees).
        pub fn descendingRangeKeys(self: *const Self, range: Range(K), allocator: Allocator) Allocator.Error![]K {
            const b = range.bracket(self.keys_buf);
            const n = b[1] - b[0];
            const out = try allocator.alloc(K, n);
            for (0..n) |i| out[i] = self.keys_buf[b[1] - 1 - i];
            return out;
        }

        /// `(key, value)` entries whose key ∈ `range`, descending (freshly
        /// allocated; caller frees).
        pub fn descendingRangeEntries(self: *const Self, range: Range(K), allocator: Allocator) Allocator.Error![]Entry {
            const b = range.bracket(self.keys_buf);
            const n = b[1] - b[0];
            const out = try allocator.alloc(Entry, n);
            for (0..n) |i| {
                const src = b[1] - 1 - i;
                out[i] = .{ .key = self.keys_buf[src], .value = self.values_buf[src] };
            }
            return out;
        }
    };
}

// ===========================================================================
// ImmutableSortedSet(T)
// ===========================================================================

/// A compact immutable sorted set backed by a single packed ascending, owned
/// slice, queried by binary search. The element analogue of
/// `ImmutableSortedMap`. Free with `deinit`.
pub fn ImmutableSortedSet(comptime T: type) type {
    return struct {
        // `[]const` so the packed backing is immutable even through direct
        // field access (`set.elems_buf[0] = x` is a COMPILE ERROR) — Zig
        // structs have no private fields, so an `[]T` would be externally
        // mutable unlike the other ports' encapsulated storage. Still owned
        // (freed by `deinit`).
        elems_buf: []const T,
        allocator: Allocator,

        const Self = @This();

        /// Build from a **strictly ascending** element slice (copied into
        /// freshly allocated, set-owned storage — snapshot). Free with
        /// `deinit`.
        ///
        /// Traps (`@panic`) if the elements are not strictly ascending or
        /// contain a duplicate. Empty and single-element input are valid.
        pub fn fromSorted(allocator: Allocator, elements: []const T) Allocator.Error!Self {
            assertStrictlyAscending(T, elements);
            const copy = try allocator.dupe(T, elements);
            return .{ .elems_buf = copy, .allocator = allocator };
        }

        /// Free the owned backing storage.
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.elems_buf);
            self.elems_buf = &.{};
        }

        /// Number of elements.
        pub fn len(self: *const Self) usize {
            return self.elems_buf.len;
        }

        /// Whether the set is empty.
        pub fn isEmpty(self: *const Self) bool {
            return self.elems_buf.len == 0;
        }

        fn search(self: *const Self, elem: T) SearchResult {
            return binarySearch(T, self.elems_buf, elem);
        }

        /// Whether `elem` is present.
        pub fn contains(self: *const Self, elem: T) bool {
            return self.search(elem).found;
        }

        /// Minimum element, or `null`.
        pub fn first(self: *const Self) ?T {
            return if (self.elems_buf.len == 0) null else self.elems_buf[0];
        }

        /// Maximum element, or `null`.
        pub fn last(self: *const Self) ?T {
            return if (self.elems_buf.len == 0) null else self.elems_buf[self.elems_buf.len - 1];
        }

        /// Greatest element `<= k`, or `null`.
        pub fn floor(self: *const Self, k: T) ?T {
            const r = self.search(k);
            if (r.found) return self.elems_buf[r.index];
            return if (r.index == 0) null else self.elems_buf[r.index - 1];
        }

        /// Least element `>= k`, or `null`.
        pub fn ceiling(self: *const Self, k: T) ?T {
            const r = self.search(k);
            return if (r.index < self.elems_buf.len) self.elems_buf[r.index] else null;
        }

        /// Greatest element `< k` (strict), or `null`.
        pub fn lower(self: *const Self, k: T) ?T {
            const r = self.search(k);
            return if (r.index == 0) null else self.elems_buf[r.index - 1];
        }

        /// Least element `> k` (strict), or `null`.
        pub fn higher(self: *const Self, k: T) ?T {
            const r = self.search(k);
            const i = if (r.found) r.index + 1 else r.index;
            return if (i < self.elems_buf.len) self.elems_buf[i] else null;
        }

        /// Number of elements **strictly less than** `elem` (lower-bound index).
        pub fn rank(self: *const Self, elem: T) usize {
            return self.search(elem).index;
        }

        /// The `i`-th smallest element (0-based), or `null` if `i >= len()`.
        pub fn select(self: *const Self, i: usize) ?T {
            return if (i < self.elems_buf.len) self.elems_buf[i] else null;
        }

        /// Elements in ascending order (borrowed view into owned storage).
        pub fn elementsSlice(self: *const Self) []const T {
            return self.elems_buf;
        }

        /// All elements, descending (freshly allocated; caller frees).
        pub fn descendingElements(self: *const Self, allocator: Allocator) Allocator.Error![]T {
            const out = try allocator.alloc(T, self.elems_buf.len);
            for (self.elems_buf, 0..) |e, i| out[self.elems_buf.len - 1 - i] = e;
            return out;
        }

        /// Elements ∈ `range`, ascending. Bracketed by two binary searches from
        /// the range's cut semantics (overflow-safe at the signed extremes).
        /// Freshly allocated; caller frees.
        pub fn rangeElements(self: *const Self, range: Range(T), allocator: Allocator) Allocator.Error![]T {
            const b = range.bracket(self.elems_buf);
            return allocator.dupe(T, self.elems_buf[b[0]..b[1]]);
        }

        /// Elements ∈ `range`, descending (freshly allocated; caller frees).
        pub fn descendingRangeElements(self: *const Self, range: Range(T), allocator: Allocator) Allocator.Error![]T {
            const b = range.bracket(self.elems_buf);
            const n = b[1] - b[0];
            const out = try allocator.alloc(T, n);
            for (0..n) |i| out[i] = self.elems_buf[b[1] - 1 - i];
            return out;
        }
    };
}

/// `ImmutableSortedMap(i32, i32)` — the v1 specialisation matching the
/// cross-language validation universe.
pub const ImmutableI32I32SortedMap = ImmutableSortedMap(i32, i32);

/// `ImmutableSortedSet(i32)` — the v1 specialisation.
pub const ImmutableI32SortedSet = ImmutableSortedSet(i32);

test {
    _ = @import("immutable_sorted_test.zig");
}
