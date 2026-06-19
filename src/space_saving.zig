// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Space-Saving — a bounded heavy-hitters / top-k summary tracking at most `m`
//! monitored `(item, count, error)` triples with a deterministic eviction rule
//! (see `spec/features/count-min.md`).
//!
//! Unlike the Count-Min Sketch, Space-Saving is **order-DEPENDENT** (eviction
//! depends on which item is the current min when the set is full, which depends
//! on add order). For an identical capacity `m` and an identical add-sequence
//! **in the same order**, the monitored set in canonical order is bit-identical
//! across all five ports. **No floating point** appears in any asserted value.
//!
//! Pinned rulings:
//! - **Eviction tie-break:** the victim is the monitored item minimizing
//!   `(count, signed-i32 item)` — smallest count, then smallest **signed** i32
//!   item (`minInt(i32)` < … < `-1` < `0` < `1`). `error` is NOT part of it.
//! - **Error accounting:** a displaced new item gets
//!   `count = evicted_count +| count`, `error = evicted_count`; an
//!   already-monitored item's `error` NEVER changes; a freshly-admitted (room)
//!   item has `error = 0`.
//! - **Saturating add** at `maxInt(u64)` via `+|` (does NOT wrap).
//! - **Canonical order:** `count` DESCENDING, then signed `item` ASCENDING (a
//!   total order; `error` rides along but never decides order). `topK(k)` is the
//!   first `k` of this order; `topK(size())` == `monitoredSet()`.
//! - **`count = 0` add is a no-op** (no admit, no increment, no eviction).

const std = @import("std");
const Allocator = std.mem.Allocator;

/// A monitored `(item, count, error)` triple — the projection element.
pub const Entry = struct {
    item: i32,
    count: u64,
    err: u64,
};

/// A monitored entry's `(count, error)` pair (the item is the map key).
const CountError = struct {
    count: u64,
    err: u64,
};

/// A bounded Space-Saving heavy-hitters summary of capacity `m`. Caller owns
/// the allocator; release with `deinit`.
pub const SpaceSaving = struct {
    cap: u32,
    monitored: std.AutoArrayHashMapUnmanaged(i32, CountError),
    allocator: Allocator,

    /// Construct an empty summary monitoring at most `m` items.
    ///
    /// `m == 0` is invalid (a zero-capacity summary can monitor nothing; every
    /// `add` would have to evict from an empty set) and traps.
    pub fn withCapacity(allocator: Allocator, m: u32) SpaceSaving {
        // Required-input trap: always-on (`std.debug.assert` is compiled out in
        // ReleaseFast/ReleaseSmall, leaving a 0-capacity summary that would
        // evict from an empty set / underflow). Mirrors CMS `w == 0`.
        if (m == 0) @panic("SpaceSaving capacity m must be non-zero");
        return .{
            .cap = m,
            .monitored = .{},
            .allocator = allocator,
        };
    }

    /// Release the monitored map.
    pub fn deinit(self: *SpaceSaving) void {
        self.monitored.deinit(self.allocator);
        self.* = undefined;
    }

    /// Add `item` with weight `count`.
    ///
    /// - `count = 0` is a no-op (no admit, increment, or eviction).
    /// - If `item` is already monitored: its `count` grows (saturating); its
    ///   `error` is unchanged.
    /// - If there is room (`size < m`): admit with `error = 0`.
    /// - If full: evict the `(count, signed item)`-min victim; the new item
    ///   takes `count = evicted_count +| count` and `error = evicted_count`.
    pub fn add(self: *SpaceSaving, item: i32, weight: u64) Allocator.Error!void {
        if (weight == 0) return; // zero-weight add changes nothing.
        if (self.monitored.getPtr(item)) |e| {
            e.count +|= weight;
            // error unchanged for an already-monitored item.
            return;
        }
        if (self.monitored.count() < self.cap) {
            try self.monitored.put(self.allocator, item, .{ .count = weight, .err = 0 });
            return;
        }
        // Full + unmonitored item: evict the (count, signed item)-min victim.
        const victim = self.argminVictim();
        const evicted_count = self.monitored.get(victim).?.count;
        _ = self.monitored.swapRemove(victim);
        try self.monitored.put(self.allocator, item, .{
            .count = evicted_count +| weight,
            .err = evicted_count,
        });
    }

    /// Convenience for `add(item, 1)`.
    pub fn addOne(self: *SpaceSaving, item: i32) Allocator.Error!void {
        return self.add(item, 1);
    }

    /// The monitored item minimizing `(count, signed item)`: smallest count,
    /// then smallest signed i32 item on a count tie. Items are distinct, so the
    /// victim is unique. Caller guarantees the set is non-empty.
    fn argminVictim(self: *const SpaceSaving) i32 {
        const items = self.monitored.keys();
        const entries = self.monitored.values();
        std.debug.assert(items.len > 0);
        var best_item = items[0];
        var best = entries[0];
        for (items[1..], entries[1..]) |it, e| {
            if (e.count < best.count or (e.count == best.count and it < best_item)) {
                best_item = it;
                best = e;
            }
        }
        return best_item;
    }

    /// The monitored `count` for `item`, or `0` if not monitored.
    pub fn count(self: *const SpaceSaving, item: i32) u64 {
        return if (self.monitored.get(item)) |e| e.count else 0;
    }

    /// The monitored `error` for `item`, or `0` if not monitored.
    pub fn @"error"(self: *const SpaceSaving, item: i32) u64 {
        return if (self.monitored.get(item)) |e| e.err else 0;
    }

    /// Whether `item` is currently monitored.
    pub fn isMonitored(self: *const SpaceSaving, item: i32) bool {
        return self.monitored.contains(item);
    }

    /// The number of currently monitored items (`<= m`).
    pub fn size(self: *const SpaceSaving) u32 {
        return @intCast(self.monitored.count());
    }

    /// The capacity `m`.
    pub fn capacity(self: *const SpaceSaving) u32 {
        return self.cap;
    }

    /// Order two triples by canonical order: `count` DESCENDING, then signed
    /// `item` ASCENDING. Returns true when `a` sorts before `b`.
    fn lessThanCanonical(_: void, a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count; // count DESC
        return a.item < b.item; // signed item ASC
    }

    /// The entire monitored set as `(item, count, error)` triples in canonical
    /// order: `count` DESCENDING, then signed `item` ASCENDING. Returns a
    /// freshly allocated, caller-owned slice.
    pub fn monitoredSet(self: *const SpaceSaving, allocator: Allocator) Allocator.Error![]Entry {
        const n = self.monitored.count();
        const out = try allocator.alloc(Entry, n);
        const items = self.monitored.keys();
        const entries = self.monitored.values();
        for (items, entries, 0..) |it, e, i| {
            out[i] = .{ .item = it, .count = e.count, .err = e.err };
        }
        std.mem.sort(Entry, out, {}, lessThanCanonical);
        return out;
    }

    /// The `k` highest-`count` monitored items in canonical order (the first `k`
    /// of `monitoredSet`). `k > size()` returns all monitored items (no
    /// padding); `k = 0` returns the empty list. Returns a freshly allocated,
    /// caller-owned slice.
    pub fn topK(self: *const SpaceSaving, allocator: Allocator, k: u32) Allocator.Error![]Entry {
        const all = try self.monitoredSet(allocator);
        const n: usize = @min(@as(usize, k), all.len);
        if (n == all.len) return all;
        const out = try allocator.alloc(Entry, n);
        @memcpy(out, all[0..n]);
        allocator.free(all);
        return out;
    }
};

// ── Tests ────────────────────────────────────────────────────────────────────

const testing = std.testing;

fn expectTriples(expected: []const Entry, got: []const Entry) !void {
    try testing.expectEqual(expected.len, got.len);
    for (expected, got) |e, g| {
        try testing.expectEqual(e.item, g.item);
        try testing.expectEqual(e.count, g.count);
        try testing.expectEqual(e.err, g.err);
    }
}

test "admit under capacity, no eviction" {
    const a = testing.allocator;
    var s = SpaceSaving.withCapacity(a, 3);
    defer s.deinit();
    try s.addOne(7);
    try s.addOne(7);
    try s.addOne(-1);
    try testing.expectEqual(@as(u32, 2), s.size());
    try testing.expectEqual(@as(u64, 2), s.count(7));
    try testing.expectEqual(@as(u64, 0), s.@"error"(7));
    try testing.expectEqual(@as(u64, 1), s.count(-1));
    const ms = try s.monitoredSet(a);
    defer a.free(ms);
    try expectTriples(&[_]Entry{ .{ .item = 7, .count = 2, .err = 0 }, .{ .item = -1, .count = 1, .err = 0 } }, ms);
    const tk = try s.topK(a, 1);
    defer a.free(tk);
    try expectTriples(&[_]Entry{.{ .item = 7, .count = 2, .err = 0 }}, tk);
}

test "evict min, tie-break smaller signed item; error accounting" {
    const a = testing.allocator;
    var s = SpaceSaving.withCapacity(a, 2);
    defer s.deinit();
    try s.addOne(1);
    try s.addOne(2);
    try s.addOne(3);
    const ms = try s.monitoredSet(a);
    defer a.free(ms);
    try expectTriples(&[_]Entry{ .{ .item = 3, .count = 2, .err = 1 }, .{ .item = 2, .count = 1, .err = 0 } }, ms);
    try testing.expectEqual(@as(u64, 0), s.count(1)); // evicted
    try testing.expect(!s.isMonitored(1));
    try testing.expectEqual(@as(u64, 2), s.count(3));
    try testing.expectEqual(@as(u64, 1), s.@"error"(3));
}

test "eviction tie-break: negative beats positive (signed)" {
    const a = testing.allocator;
    var s = SpaceSaving.withCapacity(a, 2);
    defer s.deinit();
    try s.addOne(-5);
    try s.addOne(2);
    try s.addOne(9);
    try testing.expect(!s.isMonitored(-5)); // smaller signed evicted
    try testing.expect(s.isMonitored(2));
    try testing.expect(s.isMonitored(9));
    try testing.expectEqual(@as(u64, 2), s.count(9));
    try testing.expectEqual(@as(u64, 1), s.@"error"(9));
}

test "already-monitored error never changes on re-add" {
    const a = testing.allocator;
    var s = SpaceSaving.withCapacity(a, 2);
    defer s.deinit();
    try s.addOne(1);
    try s.addOne(2);
    try s.addOne(3); // evicts 1; 3 -> count 2 error 1
    try testing.expectEqual(@as(u64, 1), s.@"error"(3));
    try s.add(3, 100); // re-add of monitored item: error unchanged.
    try testing.expectEqual(@as(u64, 102), s.count(3));
    try testing.expectEqual(@as(u64, 1), s.@"error"(3));
}

test "admitted with room has zero error" {
    const a = testing.allocator;
    var s = SpaceSaving.withCapacity(a, 5);
    defer s.deinit();
    try s.add(7, 9);
    try testing.expectEqual(@as(u64, 0), s.@"error"(7));
    try testing.expectEqual(@as(u64, 9), s.count(7));
}

test "count=0 is a no-op (full set, must not evict or increment)" {
    const a = testing.allocator;
    var s = SpaceSaving.withCapacity(a, 1);
    defer s.deinit();
    try s.addOne(1);
    try s.add(2, 0); // must NOT evict 1.
    try testing.expect(s.isMonitored(1));
    try testing.expect(!s.isMonitored(2));
    try testing.expectEqual(@as(u32, 1), s.size());
}

test "empty summary" {
    const a = testing.allocator;
    var s = SpaceSaving.withCapacity(a, 3);
    defer s.deinit();
    try testing.expectEqual(@as(u32, 0), s.size());
    try testing.expectEqual(@as(u32, 3), s.capacity());
    const ms = try s.monitoredSet(a);
    defer a.free(ms);
    try testing.expectEqual(@as(usize, 0), ms.len);
    try testing.expectEqual(@as(u64, 0), s.count(7));
    try testing.expectEqual(@as(u64, 0), s.@"error"(7));
    const tk = try s.topK(a, 3);
    defer a.free(tk);
    try testing.expectEqual(@as(usize, 0), tk.len);
}

test "top_k canonical order and bounds (k>size no padding, k=0 empty)" {
    const a = testing.allocator;
    var s = SpaceSaving.withCapacity(a, 10);
    defer s.deinit();
    try s.add(1, 5);
    try s.add(2, 3);
    try s.add(3, 3); // tie at count 3 -> 2 before 3 (signed asc)
    try s.add(4, 1);
    const full = try s.monitoredSet(a);
    defer a.free(full);
    try expectTriples(&[_]Entry{
        .{ .item = 1, .count = 5, .err = 0 },
        .{ .item = 2, .count = 3, .err = 0 },
        .{ .item = 3, .count = 3, .err = 0 },
        .{ .item = 4, .count = 1, .err = 0 },
    }, full);
    const tk1 = try s.topK(a, 1);
    defer a.free(tk1);
    try expectTriples(&[_]Entry{.{ .item = 1, .count = 5, .err = 0 }}, tk1);
    const tk2 = try s.topK(a, 2);
    defer a.free(tk2);
    try expectTriples(&[_]Entry{ .{ .item = 1, .count = 5, .err = 0 }, .{ .item = 2, .count = 3, .err = 0 } }, tk2);
    const tk99 = try s.topK(a, 99); // k > size -> all, no padding
    defer a.free(tk99);
    try testing.expectEqual(@as(usize, 4), tk99.len);
    const tk0 = try s.topK(a, 0);
    defer a.free(tk0);
    try testing.expectEqual(@as(usize, 0), tk0.len);
}

test "count of unmonitored (evicted) item is 0" {
    const a = testing.allocator;
    var s = SpaceSaving.withCapacity(a, 1);
    defer s.deinit();
    try s.addOne(1);
    try s.addOne(2); // evicts 1
    try testing.expectEqual(@as(u64, 0), s.count(1));
    try testing.expect(!s.isMonitored(1));
}

test "overflow saturates" {
    const a = testing.allocator;
    var s = SpaceSaving.withCapacity(a, 1);
    defer s.deinit();
    try s.add(7, std.math.maxInt(u64));
    try s.add(7, std.math.maxInt(u64));
    try testing.expectEqual(std.math.maxInt(u64), s.count(7));
}

test "order dependence (deterministic per order)" {
    const a = testing.allocator;
    var x = SpaceSaving.withCapacity(a, 2);
    defer x.deinit();
    for ([_]i32{ 1, 1, 2, 3 }) |it| try x.addOne(it);
    const ms = try x.monitoredSet(a);
    defer a.free(ms);
    // 1->2; 2 admitted->1; 3 evicts 2 (count1) -> count2 error1. {1:2, 3:2e1}.
    try expectTriples(&[_]Entry{ .{ .item = 1, .count = 2, .err = 0 }, .{ .item = 3, .count = 2, .err = 1 } }, ms);
}

test "error floor unchanged across evictions" {
    const a = testing.allocator;
    var s = SpaceSaving.withCapacity(a, 2);
    defer s.deinit();
    try s.addOne(1);
    try s.addOne(2);
    try s.addOne(3); // evict 1: 3 -> count2 error1
    try testing.expectEqual(@as(u64, 1), s.@"error"(3));
    try s.addOne(3); // monitored re-add: count3 error1 (unchanged)
    try testing.expectEqual(@as(u64, 3), s.count(3));
    try testing.expectEqual(@as(u64, 1), s.@"error"(3));
    try s.addOne(4); // full {2:1,3:3}; evict 2 (count1): 4 -> count2 error1
    try testing.expectEqual(@as(u64, 1), s.@"error"(4));
    try testing.expectEqual(@as(u64, 2), s.count(4));
    try testing.expectEqual(@as(u64, 1), s.@"error"(3)); // 3 still unchanged
}
