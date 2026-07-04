// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Bounded LRU map (max-size v1) — `spec/features/bounded-lru.md`.
//!
//! A fixed-capacity `BoundedLruMap(K, V)` that evicts its least-recently-used
//! entry when an insert would exceed the capacity. The recency order is kept by
//! an **intrusive doubly-linked LRU list over an arena + slot-index** (the
//! Phase-0 arena/slot-index intrusive-list primitive): each live entry owns a
//! slot in a contiguous arena (`std.ArrayListUnmanaged(Node)`); nodes carry
//! `{prev, next}` **indices** (never raw pointers) plus a back-reference key,
//! and freed slots are recycled through a free-list. The list head is the LRU
//! end (the eviction victim), the tail is the MRU end. A recency refresh is an
//! O(1) unlink + push-to-tail; eviction is an O(1) pop-from-head.
//!
//! Recency is **position-implicit** (head = least-recently-used): there is no
//! stored `last_use` stamp and therefore nothing to overflow (spec §"`useSeq`
//! width / overflow" — the reference position-implicit form). The observable
//! contract (LRU-order contents, eviction log, results) is what the spec pins;
//! the arena mechanism is non-observable.
//!
//! v1 has **no wall clock**: all time is the caller-supplied logical tick. TTL
//! is an after-write `expire_at = saturating(now + ttl)`; `expireEntries(now)`
//! removes every entry with `expire_at <= now` (inclusive), firing the callback
//! with cause `expired` in ascending-`expire_at` then ascending-`last_use`
//! (LRU) order. Plain `put(k, v)` is defined as `putAt(k, v, 0)`.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Why an entry left the map (the eviction-callback cause). Only `size` and
/// `expired` exist in v1 — `put`-update, `remove`, and `clear` are NOT
/// evictions and never invoke the callback.
pub const EvictionCause = enum {
    /// Evicted because an insert exceeded `max_size` (the LRU victim).
    size,
    /// Removed by `expireEntries(now)` because its logical expiry tick passed.
    expired,

    /// The lower-case serialized name used by the cross-language suite.
    pub fn asStr(self: EvictionCause) []const u8 {
        return switch (self) {
            .size => "size",
            .expired => "expired",
        };
    }
};

/// Sentinel index meaning "no node" (list end / free-list end).
const NIL: usize = std.math.maxInt(usize);

/// The "+∞ / never" expiry sentinel: an entry with this `expire_at` never
/// expires, even at `now == maxInt(u64)` (no TTL configured, or `now + ttl`
/// saturated). See spec §"TTL saturation / unsigned ticks".
const NEVER: u64 = std.math.maxInt(u64);

/// A fixed-capacity LRU map from `K` to `V`.
///
/// The map holds at most `max_size` entries; a new-key insert that would
/// exceed it evicts the least-recently-used entry first (evict-before-insert),
/// so the inserted key is never its own victim.
pub fn BoundedLruMap(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        /// The eviction callback type: invoked with `(key, value-at-eviction,
        /// cause)`. A pure recorder in the suite; MUST NOT mutate the map.
        pub const OnEvictFn = *const fn (ctx: ?*anyopaque, key: K, value: V, cause: EvictionCause) void;

        /// Construction options. `max_size` is required; `ttl` (after-write
        /// logical-tick TTL) and `on_evict` (recording callback + context) are
        /// optional.
        pub const Options = struct {
            max_size: usize,
            ttl: ?u64 = null,
            on_evict: ?OnEvictFn = null,
            on_evict_ctx: ?*anyopaque = null,
        };

        /// One arena slot: an intrusive doubly-linked-list node. When live it
        /// links into the LRU list (`prev`/`next` are slot indices, `key` is
        /// the back-reference into the index). When free it sits on the
        /// free-list (`next` chains the free-list; the rest is dead).
        const Node = struct {
            prev: usize,
            next: usize,
            key: K,
            value: V,
            /// Logical expiry tick: expires when `now >= expire_at`. `NEVER`
            /// (`maxInt(u64)`) means "never".
            expire_at: u64,
        };

        allocator: Allocator,
        /// Key -> arena slot index. The slot holds the value + LRU links.
        index: std.AutoHashMapUnmanaged(K, usize),
        /// The arena of LRU-list nodes (slot-index addressed).
        arena: std.ArrayListUnmanaged(Node),
        /// Free-list head (a slot index), or `NIL` when no free slot.
        free_head: usize,
        /// LRU-list head = least-recently-used (the eviction victim), or `NIL`.
        head: usize,
        /// LRU-list tail = most-recently-used, or `NIL`.
        tail: usize,
        /// Capacity `n` (`0` ⇒ permanently empty; every insert drops).
        max_size: usize,
        /// After-write TTL in logical ticks, or `null` for a pure max-size map.
        ttl: ?u64,
        on_evict: ?OnEvictFn,
        on_evict_ctx: ?*anyopaque,

        /// Construct a bounded LRU map. The arena/index are lazily grown.
        pub fn init(allocator: Allocator, options: Options) Self {
            return .{
                .allocator = allocator,
                .index = .{},
                .arena = .{},
                .free_head = NIL,
                .head = NIL,
                .tail = NIL,
                .max_size = options.max_size,
                .ttl = options.ttl,
                .on_evict = options.on_evict,
                .on_evict_ctx = options.on_evict_ctx,
            };
        }

        /// Release all owned memory.
        pub fn deinit(self: *Self) void {
            self.index.deinit(self.allocator);
            self.arena.deinit(self.allocator);
            self.* = undefined;
        }

        /// Current entry count (`0 ..= max_size`).
        pub fn len(self: *const Self) usize {
            return self.index.count();
        }

        /// Whether the map is empty.
        pub fn isEmpty(self: *const Self) bool {
            return self.index.count() == 0;
        }

        /// The configured capacity `n`.
        pub fn capacity(self: *const Self) usize {
            return self.max_size;
        }

        // --- arena / intrusive-list primitives (non-observable) -------------

        /// Allocate a slot for a fresh entry (reusing a free slot if
        /// available). The node is NOT yet linked into the LRU list.
        fn allocNode(self: *Self, key: K, value: V, expire_at: u64) !usize {
            if (self.free_head != NIL) {
                const idx = self.free_head;
                self.free_head = self.arena.items[idx].next;
                self.arena.items[idx] = .{
                    .prev = NIL,
                    .next = NIL,
                    .key = key,
                    .value = value,
                    .expire_at = expire_at,
                };
                return idx;
            }
            const idx = self.arena.items.len;
            try self.arena.append(self.allocator, .{
                .prev = NIL,
                .next = NIL,
                .key = key,
                .value = value,
                .expire_at = expire_at,
            });
            return idx;
        }

        /// Return a slot to the free-list (node must already be unlinked from
        /// the LRU list and removed from the index).
        fn freeNode(self: *Self, idx: usize) void {
            self.arena.items[idx].next = self.free_head;
            self.arena.items[idx].prev = NIL;
            self.free_head = idx;
        }

        /// Unlink a node from the LRU list (O(1)); leaves the slot allocated.
        fn unlink(self: *Self, idx: usize) void {
            const prev = self.arena.items[idx].prev;
            const next = self.arena.items[idx].next;
            if (prev != NIL) {
                self.arena.items[prev].next = next;
            } else {
                self.head = next;
            }
            if (next != NIL) {
                self.arena.items[next].prev = prev;
            } else {
                self.tail = prev;
            }
            self.arena.items[idx].prev = NIL;
            self.arena.items[idx].next = NIL;
        }

        /// Push a (currently unlinked) node onto the MRU end (tail).
        fn pushTail(self: *Self, idx: usize) void {
            const old_tail = self.tail;
            self.arena.items[idx].prev = old_tail;
            self.arena.items[idx].next = NIL;
            if (old_tail != NIL) {
                self.arena.items[old_tail].next = idx;
            } else {
                self.head = idx;
            }
            self.tail = idx;
        }

        /// Move an existing live node to the MRU end (a recency refresh).
        fn touch(self: *Self, idx: usize) void {
            if (self.tail == idx) return; // already MRU
            self.unlink(idx);
            self.pushTail(idx);
        }

        /// Remove a victim node entirely (index-remove + unlink + free) and
        /// fire the eviction callback with the value-at-eviction and cause.
        fn evictNode(self: *Self, idx: usize, cause: EvictionCause) void {
            const key = self.arena.items[idx].key;
            const value = self.arena.items[idx].value;
            _ = self.index.remove(key);
            self.unlink(idx);
            self.freeNode(idx);
            if (self.on_evict) |cb| {
                cb(self.on_evict_ctx, key, value, cause);
            }
        }

        // --- map surface ----------------------------------------------------

        /// `put(k, v)` == `putAt(k, v, 0)` (no hidden clock). On a no-TTL map
        /// `now` is irrelevant; on a TTL map this writes with `now = 0`.
        pub fn put(self: *Self, key: K, value: V) !?V {
            return self.putAt(key, value, 0);
        }

        /// Insert-or-update with a logical write tick. Refreshes recency of
        /// `key`; a new-key insert at capacity evicts the LRU entry first
        /// (evict-before-insert). Returns the previous value, or `null`.
        pub fn putAt(self: *Self, key: K, value: V, now: u64) !?V {
            const expire_at: u64 = if (self.ttl) |ttl|
                std.math.add(u64, now, ttl) catch NEVER
            else
                NEVER;

            if (self.index.get(key)) |idx| {
                // Update: value replaced, expiry reset, recency refreshed; NO
                // evict (size unchanged).
                const old = self.arena.items[idx].value;
                self.arena.items[idx].value = value;
                self.arena.items[idx].expire_at = expire_at;
                self.touch(idx);
                return old;
            }

            // Genuine insertion of a new key.
            if (self.max_size == 0) {
                // Capacity 0: dropped, never resident, no victim, no callback.
                return null;
            }

            // Evict-before-insert: the invariant `size() <= max_size` holds on
            // every op, so a new-key insert needs AT MOST ONE size eviction
            // when max_size >= 1 (spec §"At most one eviction per put"). An
            // `if` (not a loop) makes the one-eviction contract explicit.
            std.debug.assert(self.len() <= self.max_size);
            if (self.len() >= self.max_size) {
                const victim = self.head; // LRU end; valid since size() >= 1.
                self.evictNode(victim, .size);
            }

            const idx = try self.allocNode(key, value, expire_at);
            // Insert into the index BEFORE pushing onto the list so that an
            // allocation failure leaves the structure consistent (node stays on
            // the free-list path via arena, never linked).
            self.index.put(self.allocator, key, idx) catch |err| {
                // Roll the freshly allocated slot back onto the free-list.
                self.freeNode(idx);
                return err;
            };
            self.pushTail(idx);
            return null;
        }

        /// Lookup. On a hit refreshes recency; on a miss does nothing.
        pub fn get(self: *Self, key: K) ?V {
            if (self.index.get(key)) |idx| {
                const v = self.arena.items[idx].value;
                self.touch(idx);
                return v;
            }
            return null;
        }

        /// A `get` that returns `default` on a miss. A hit refreshes recency
        /// exactly like `get`; a miss does NOT refresh recency and does NOT
        /// insert `default`.
        pub fn getOrDefault(self: *Self, key: K, default: V) V {
            return self.get(key) orelse default;
        }

        /// Membership test. Does NOT refresh recency and never evicts.
        pub fn containsKey(self: *const Self, key: K) bool {
            return self.index.contains(key);
        }

        /// Delete `key`. Does not evict and does NOT invoke the eviction
        /// callback (manual removal is not eviction). Returns the removed
        /// value, or `null`.
        pub fn remove(self: *Self, key: K) ?V {
            if (self.index.fetchRemove(key)) |kv| {
                const idx = kv.value;
                const v = self.arena.items[idx].value;
                self.unlink(idx);
                self.freeNode(idx);
                return v;
            }
            return null;
        }

        /// Remove all entries. Does NOT invoke the eviction callback for the
        /// cleared entries (bulk manual removal is not eviction).
        pub fn clear(self: *Self) void {
            self.index.clearRetainingCapacity();
            self.arena.clearRetainingCapacity();
            self.free_head = NIL;
            self.head = NIL;
            self.tail = NIL;
        }

        /// Logical-time expiry pass: remove every entry with `expire_at <= now`
        /// (inclusive), firing the callback with cause `expired` in ascending
        /// `expire_at`, then ascending `last_use` (LRU) order. Returns the
        /// count removed. The only time-driven eviction; surviving entries'
        /// recency is unchanged. A no-TTL map expires nothing for any `now`.
        pub fn expireEntries(self: *Self, now: u64) !usize {
            if (self.ttl == null) return 0;

            // Collect victims: every live node with `expire_at <= now`. Walking
            // the LRU list head->tail gives ascending `last_use`; a STABLE sort
            // by `expire_at` then preserves that order within each tie, so the
            // result is (expire_at asc, last_use asc). `NEVER` is the saturated
            // "+∞" sentinel and is excluded even at `now == maxInt(u64)`.
            const Victim = struct { expire_at: u64, idx: usize };
            var victims = std.ArrayListUnmanaged(Victim){};
            defer victims.deinit(self.allocator);

            var cur = self.head;
            while (cur != NIL) {
                const node = self.arena.items[cur];
                const next = node.next;
                if (node.expire_at != NEVER and node.expire_at <= now) {
                    try victims.append(self.allocator, .{ .expire_at = node.expire_at, .idx = cur });
                }
                cur = next;
            }

            // Stable sort by expire_at keeps the head->tail (ascending last_use)
            // order within each expire_at tie.
            std.mem.sort(Victim, victims.items, {}, struct {
                fn lessThan(_: void, a: Victim, b: Victim) bool {
                    return a.expire_at < b.expire_at;
                }
            }.lessThan);

            const count = victims.items.len;
            for (victims.items) |vic| {
                self.evictNode(vic.idx, .expired);
            }
            return count;
        }

        // --- iteration (LRU order, read-only snapshots) ---------------------

        /// All keys in LRU order (least-recently-used first), caller-owned.
        /// A read-only snapshot: does NOT refresh recency and never evicts.
        pub fn keys(self: *const Self, allocator: Allocator) ![]K {
            var out = try allocator.alloc(K, self.len());
            var i: usize = 0;
            var cur = self.head;
            while (cur != NIL) : (i += 1) {
                out[i] = self.arena.items[cur].key;
                cur = self.arena.items[cur].next;
            }
            return out;
        }

        /// All values in LRU order, parallel to `keys`. Caller-owned read-only
        /// snapshot.
        pub fn values(self: *const Self, allocator: Allocator) ![]V {
            var out = try allocator.alloc(V, self.len());
            var i: usize = 0;
            var cur = self.head;
            while (cur != NIL) : (i += 1) {
                out[i] = self.arena.items[cur].value;
                cur = self.arena.items[cur].next;
            }
            return out;
        }

        /// One `(key, value)` entry.
        pub const Entry = struct { key: K, value: V };

        /// All `(key, value)` entries in LRU order. Caller-owned read-only
        /// snapshot.
        pub fn entries(self: *const Self, allocator: Allocator) ![]Entry {
            var out = try allocator.alloc(Entry, self.len());
            var i: usize = 0;
            var cur = self.head;
            while (cur != NIL) : (i += 1) {
                out[i] = .{ .key = self.arena.items[cur].key, .value = self.arena.items[cur].value };
                cur = self.arena.items[cur].next;
            }
            return out;
        }
    };
}

/// The v1 i32->i32 surface (spec §Scope). Top-level alias mirrors the other
/// `I32*` named handles in `root.zig`.
pub const I32I32BoundedLruMap = BoundedLruMap(i32, i32);

// ── native tests ────────────────────────────────────────────────────────────
//
// Mirror the Rust reference's `bounded_lru.rs` tests. A recording callback
// appends each (key, value, cause) triple to a shared log — the determinism
// oracle. All tests use the testing allocator (leak-checked).

const testing = std.testing;

/// A heap-recording eviction log used by the tests.
const TestLog = struct {
    const Triple = struct { key: i32, value: i32, cause: EvictionCause };
    entries: std.ArrayListUnmanaged(Triple) = .{},
    allocator: Allocator,

    fn record(ctx: ?*anyopaque, key: i32, value: i32, cause: EvictionCause) void {
        const self: *TestLog = @ptrCast(@alignCast(ctx.?));
        self.entries.append(self.allocator, .{ .key = key, .value = value, .cause = cause }) catch unreachable;
    }

    fn deinit(self: *TestLog) void {
        self.entries.deinit(self.allocator);
    }

    fn expect(self: *const TestLog, expected: []const Triple) !void {
        try testing.expectEqual(expected.len, self.entries.items.len);
        for (expected, self.entries.items) |e, g| {
            try testing.expectEqual(e.key, g.key);
            try testing.expectEqual(e.value, g.value);
            try testing.expectEqual(e.cause, g.cause);
        }
    }
};

const Map = BoundedLruMap(i32, i32);

fn expectKeys(m: *const Map, allocator: Allocator, expected: []const i32) !void {
    const ks = try m.keys(allocator);
    defer allocator.free(ks);
    try testing.expectEqualSlices(i32, expected, ks);
}

fn expectValues(m: *const Map, allocator: Allocator, expected: []const i32) !void {
    const vs = try m.values(allocator);
    defer allocator.free(vs);
    try testing.expectEqualSlices(i32, expected, vs);
}

test "evict basic: victim is LRU, order, log" {
    const a = testing.allocator;
    var log = TestLog{ .allocator = a };
    defer log.deinit();
    var m = Map.init(a, .{ .max_size = 2, .on_evict = TestLog.record, .on_evict_ctx = &log });
    defer m.deinit();
    _ = try m.put(1, 10);
    _ = try m.put(2, 20);
    _ = try m.put(3, 30); // evicts 1 (LRU)
    try expectKeys(&m, a, &.{ 2, 3 });
    try expectValues(&m, a, &.{ 20, 30 });
    try log.expect(&.{.{ .key = 1, .value = 10, .cause = .size }});
}

test "get refreshes recency" {
    const a = testing.allocator;
    var log = TestLog{ .allocator = a };
    defer log.deinit();
    var m = Map.init(a, .{ .max_size = 2, .on_evict = TestLog.record, .on_evict_ctx = &log });
    defer m.deinit();
    _ = try m.put(1, 10);
    _ = try m.put(2, 20);
    try testing.expectEqual(@as(?i32, 10), m.get(1)); // 1 now MRU, 2 is LRU
    _ = try m.put(3, 30); // evicts 2
    try expectKeys(&m, a, &.{ 1, 3 });
    try log.expect(&.{.{ .key = 2, .value = 20, .cause = .size }});
}

test "getOrDefault hit refreshes, miss does not" {
    const a = testing.allocator;
    var m = Map.init(a, .{ .max_size = 2 });
    defer m.deinit();
    _ = try m.put(1, 10);
    _ = try m.put(2, 20);
    try testing.expectEqual(@as(i32, 10), m.getOrDefault(1, -1)); // hit: 1 MRU
    try testing.expectEqual(@as(i32, -1), m.getOrDefault(99, -1)); // miss: no insert/refresh
    try testing.expectEqual(@as(usize, 2), m.len());
    try testing.expect(!m.containsKey(99));
    _ = try m.put(3, 30); // evicts 2
    try expectKeys(&m, a, &.{ 1, 3 });
}

test "containsKey does not refresh" {
    const a = testing.allocator;
    var log = TestLog{ .allocator = a };
    defer log.deinit();
    var m = Map.init(a, .{ .max_size = 2, .on_evict = TestLog.record, .on_evict_ctx = &log });
    defer m.deinit();
    _ = try m.put(1, 10);
    _ = try m.put(2, 20);
    try testing.expect(m.containsKey(1)); // must NOT refresh 1
    _ = try m.put(3, 30); // evicts 1 (still LRU)
    try expectKeys(&m, a, &.{ 2, 3 });
    try log.expect(&.{.{ .key = 1, .value = 10, .cause = .size }});
}

test "update at capacity does not evict" {
    const a = testing.allocator;
    var log = TestLog{ .allocator = a };
    defer log.deinit();
    var m = Map.init(a, .{ .max_size = 2, .on_evict = TestLog.record, .on_evict_ctx = &log });
    defer m.deinit();
    _ = try m.put(1, 10);
    _ = try m.put(2, 20);
    try testing.expectEqual(@as(?i32, 10), try m.put(1, 11)); // update: no evict, 1 MRU
    try testing.expectEqual(@as(usize, 0), log.entries.items.len);
    try expectKeys(&m, a, &.{ 2, 1 });
    _ = try m.put(3, 30); // now evicts 2 (LRU)
    try expectKeys(&m, a, &.{ 1, 3 });
    try log.expect(&.{.{ .key = 2, .value = 20, .cause = .size }});
}

test "iteration/snapshot does not refresh or evict" {
    const a = testing.allocator;
    var log = TestLog{ .allocator = a };
    defer log.deinit();
    var m = Map.init(a, .{ .max_size = 2, .on_evict = TestLog.record, .on_evict_ctx = &log });
    defer m.deinit();
    _ = try m.put(1, 10);
    _ = try m.put(2, 20);
    try expectKeys(&m, a, &.{ 1, 2 }); // snapshot must not touch recency
    try testing.expectEqual(@as(usize, 0), log.entries.items.len);
    _ = try m.put(3, 30); // 1 still LRU -> evicted
    try expectKeys(&m, a, &.{ 2, 3 });
    try log.expect(&.{.{ .key = 1, .value = 10, .cause = .size }});
}

test "remove: no callback, no other recency change; slot reuse" {
    const a = testing.allocator;
    var log = TestLog{ .allocator = a };
    defer log.deinit();
    var m = Map.init(a, .{ .max_size = 3, .on_evict = TestLog.record, .on_evict_ctx = &log });
    defer m.deinit();
    _ = try m.put(1, 10);
    _ = try m.put(2, 20);
    _ = try m.put(3, 30);
    try testing.expectEqual(@as(?i32, 20), m.remove(2));
    try testing.expectEqual(@as(usize, 0), log.entries.items.len);
    try expectKeys(&m, a, &.{ 1, 3 });
    _ = try m.put(4, 40);
    _ = try m.put(5, 50); // capacity 3, full {1,3,4} -> 5 evicts 1
    try expectKeys(&m, a, &.{ 3, 4, 5 });
    try log.expect(&.{.{ .key = 1, .value = 10, .cause = .size }});
}

test "clear fires no callback and stays sane" {
    const a = testing.allocator;
    var log = TestLog{ .allocator = a };
    defer log.deinit();
    var m = Map.init(a, .{ .max_size = 3, .on_evict = TestLog.record, .on_evict_ctx = &log });
    defer m.deinit();
    _ = try m.put(1, 10);
    _ = try m.put(2, 20);
    m.clear();
    try testing.expect(m.isEmpty());
    try testing.expectEqual(@as(usize, 0), m.len());
    try testing.expectEqual(@as(usize, 0), log.entries.items.len);
    _ = try m.put(7, 70); // reuse works after clear
    try expectKeys(&m, a, &.{7});
}

test "capacity zero drops everything" {
    const a = testing.allocator;
    var log = TestLog{ .allocator = a };
    defer log.deinit();
    var m = Map.init(a, .{ .max_size = 0, .on_evict = TestLog.record, .on_evict_ctx = &log });
    defer m.deinit();
    try testing.expectEqual(@as(?i32, null), try m.put(1, 10));
    try testing.expectEqual(@as(?i32, null), try m.put(2, 20));
    try testing.expectEqual(@as(?i32, null), try m.put(3, 30));
    try testing.expectEqual(@as(usize, 0), m.len());
    try testing.expect(m.isEmpty());
    try testing.expectEqual(@as(?i32, null), m.get(1));
    try testing.expectEqual(@as(usize, 0), log.entries.items.len); // never resident
}

test "capacity one: evict then insert; update no log" {
    const a = testing.allocator;
    var log = TestLog{ .allocator = a };
    defer log.deinit();
    var m = Map.init(a, .{ .max_size = 1, .on_evict = TestLog.record, .on_evict_ctx = &log });
    defer m.deinit();
    _ = try m.put(1, 10);
    _ = try m.put(2, 20); // evicts 1
    try expectKeys(&m, a, &.{2});
    try log.expect(&.{.{ .key = 1, .value = 10, .cause = .size }});
    try testing.expectEqual(@as(?i32, 20), try m.put(2, 22)); // update: no new log entry
    try testing.expectEqual(@as(usize, 1), log.entries.items.len);
    try expectKeys(&m, a, &.{2});
    try expectValues(&m, a, &.{22});
}

test "evict before insert: new key never self-victim" {
    const a = testing.allocator;
    var log = TestLog{ .allocator = a };
    defer log.deinit();
    var m = Map.init(a, .{ .max_size = 1, .on_evict = TestLog.record, .on_evict_ctx = &log });
    defer m.deinit();
    _ = try m.put(1, 10);
    _ = try m.put(2, 20); // 2 inserted, 1 evicted
    try testing.expect(m.containsKey(2));
    try testing.expect(!m.containsKey(1));
    try log.expect(&.{.{ .key = 1, .value = 10, .cause = .size }});
}

test "same now: recency uses useSeq not now" {
    const a = testing.allocator;
    var log = TestLog{ .allocator = a };
    defer log.deinit();
    var m = Map.init(a, .{ .max_size = 2, .ttl = 100, .on_evict = TestLog.record, .on_evict_ctx = &log });
    defer m.deinit();
    _ = try m.putAt(1, 10, 5);
    _ = try m.putAt(2, 20, 5); // both at now=5
    try testing.expectEqual(@as(?i32, 10), m.get(1)); // 1 refreshed -> 2 LRU
    _ = try m.putAt(3, 30, 5); // evicts 2, NOT 1
    try expectKeys(&m, a, &.{ 1, 3 });
    try log.expect(&.{.{ .key = 2, .value = 20, .cause = .size }});
}

test "expire basic inclusive" {
    const a = testing.allocator;
    var log = TestLog{ .allocator = a };
    defer log.deinit();
    var m = Map.init(a, .{ .max_size = 10, .ttl = 10, .on_evict = TestLog.record, .on_evict_ctx = &log });
    defer m.deinit();
    _ = try m.putAt(1, 10, 0); // expire_at 10
    _ = try m.putAt(2, 20, 0); // expire_at 10
    _ = try m.putAt(3, 30, 5); // expire_at 15
    try testing.expectEqual(@as(usize, 2), try m.expireEntries(10)); // 1,2 (<=10)
    try expectKeys(&m, a, &.{3});
    try log.expect(&.{
        .{ .key = 1, .value = 10, .cause = .expired },
        .{ .key = 2, .value = 20, .cause = .expired },
    });
}

test "expire tiebreak by last_use" {
    const a = testing.allocator;
    var log = TestLog{ .allocator = a };
    defer log.deinit();
    var m = Map.init(a, .{ .max_size = 10, .ttl = 10, .on_evict = TestLog.record, .on_evict_ctx = &log });
    defer m.deinit();
    _ = try m.putAt(1, 10, 0);
    _ = try m.putAt(2, 20, 0);
    _ = try m.putAt(3, 30, 0); // all expire_at 10
    _ = m.get(2);
    _ = m.get(3);
    _ = m.get(1); // last_use asc: 2 < 3 < 1
    try testing.expectEqual(@as(usize, 3), try m.expireEntries(10));
    try log.expect(&.{
        .{ .key = 2, .value = 20, .cause = .expired },
        .{ .key = 3, .value = 30, .cause = .expired },
        .{ .key = 1, .value = 10, .cause = .expired },
    });
}

test "expire orders by expire_at then last_use" {
    const a = testing.allocator;
    var log = TestLog{ .allocator = a };
    defer log.deinit();
    var m = Map.init(a, .{ .max_size = 10, .ttl = 0, .on_evict = TestLog.record, .on_evict_ctx = &log });
    defer m.deinit();
    _ = try m.putAt(1, 10, 5); // expire_at 5
    _ = try m.putAt(2, 20, 3); // expire_at 3
    _ = try m.putAt(3, 30, 5); // expire_at 5
    _ = try m.putAt(4, 40, 3); // expire_at 3
    try testing.expectEqual(@as(usize, 4), try m.expireEntries(5));
    try log.expect(&.{
        .{ .key = 2, .value = 20, .cause = .expired },
        .{ .key = 4, .value = 40, .cause = .expired },
        .{ .key = 1, .value = 10, .cause = .expired },
        .{ .key = 3, .value = 30, .cause = .expired },
    });
}

test "expire inclusive and saturation" {
    const a = testing.allocator;
    var log = TestLog{ .allocator = a };
    defer log.deinit();
    var m = Map.init(a, .{ .max_size = 10, .ttl = std.math.maxInt(u64), .on_evict = TestLog.record, .on_evict_ctx = &log });
    defer m.deinit();
    _ = try m.putAt(1, 10, 5); // now+ttl saturates -> NEVER
    try testing.expectEqual(@as(usize, 0), try m.expireEntries(std.math.maxInt(u64) - 1));
    try testing.expect(m.containsKey(1));
    try testing.expectEqual(@as(usize, 0), log.entries.items.len);
}

test "ttl zero boundary" {
    const a = testing.allocator;
    var m = Map.init(a, .{ .max_size = 10, .ttl = 0 });
    defer m.deinit();
    _ = try m.putAt(1, 10, 5); // expire_at = 5
    try testing.expectEqual(@as(usize, 0), try m.expireEntries(4)); // 5 > 4
    try testing.expect(m.containsKey(1));
    try testing.expectEqual(@as(usize, 1), try m.expireEntries(5)); // 5 <= 5 inclusive
    try testing.expect(!m.containsKey(1));
}

test "no ttl pure lru" {
    const a = testing.allocator;
    var m = Map.init(a, .{ .max_size = 2 });
    defer m.deinit();
    _ = try m.put(1, 10);
    _ = try m.put(2, 20);
    try testing.expectEqual(@as(usize, 0), try m.expireEntries(std.math.maxInt(u64)));
    try expectKeys(&m, a, &.{ 1, 2 });
}

test "u64 max expire_at is the never sentinel" {
    const a = testing.allocator;
    var log = TestLog{ .allocator = a };
    defer log.deinit();
    var m = Map.init(a, .{ .max_size = 10, .ttl = 1, .on_evict = TestLog.record, .on_evict_ctx = &log });
    defer m.deinit();
    _ = try m.putAt(1, 10, std.math.maxInt(u64) - 1); // now+ttl == maxInt(u64) -> sentinel
    try testing.expectEqual(@as(usize, 0), try m.expireEntries(std.math.maxInt(u64)));
    try testing.expect(m.containsKey(1));
    try testing.expectEqual(@as(usize, 0), log.entries.items.len);
}

test "expire then size interaction" {
    const a = testing.allocator;
    var log = TestLog{ .allocator = a };
    defer log.deinit();
    var m = Map.init(a, .{ .max_size = 2, .ttl = 10, .on_evict = TestLog.record, .on_evict_ctx = &log });
    defer m.deinit();
    _ = try m.putAt(1, 10, 0);
    _ = try m.putAt(2, 20, 0);
    try testing.expectEqual(@as(usize, 2), try m.expireEntries(10)); // both expire
    try testing.expect(m.isEmpty());
    _ = try m.putAt(3, 30, 20); // below capacity -> no SIZE eviction
    try expectKeys(&m, a, &.{3});
    try log.expect(&.{
        .{ .key = 1, .value = 10, .cause = .expired },
        .{ .key = 2, .value = 20, .cause = .expired },
    });
}

test "update before expire resets expiry and value" {
    const a = testing.allocator;
    var log = TestLog{ .allocator = a };
    defer log.deinit();
    var m = Map.init(a, .{ .max_size = 10, .ttl = 10, .on_evict = TestLog.record, .on_evict_ctx = &log });
    defer m.deinit();
    _ = try m.putAt(1, 10, 0); // expire_at 10
    try testing.expectEqual(@as(?i32, 10), try m.putAt(1, 11, 5)); // update: value 11, expire_at 15
    try testing.expectEqual(@as(usize, 0), try m.expireEntries(10)); // survives
    try testing.expect(m.containsKey(1));
    try testing.expectEqual(@as(usize, 1), try m.expireEntries(15)); // expires with updated value
    try log.expect(&.{.{ .key = 1, .value = 11, .cause = .expired }});
}

test "miss does not refresh or insert" {
    const a = testing.allocator;
    var m = Map.init(a, .{ .max_size = 2 });
    defer m.deinit();
    _ = try m.put(1, 10);
    _ = try m.put(2, 20); // {1(LRU), 2}
    try testing.expectEqual(@as(?i32, null), m.get(99));
    try testing.expectEqual(@as(i32, -1), m.getOrDefault(99, -1));
    try testing.expectEqual(@as(usize, 2), m.len());
    _ = try m.put(4, 40); // 1 still LRU -> evicted
    try expectKeys(&m, a, &.{ 2, 4 });
}

test "remove then reinsert gets fresh recency" {
    const a = testing.allocator;
    var log = TestLog{ .allocator = a };
    defer log.deinit();
    var m = Map.init(a, .{ .max_size = 3, .on_evict = TestLog.record, .on_evict_ctx = &log });
    defer m.deinit();
    _ = try m.put(1, 10);
    _ = try m.put(2, 20);
    _ = try m.put(3, 30); // {1,2,3}
    _ = m.remove(1);
    _ = try m.put(1, 11); // fresh insert: 1 MRU -> {2,3,1}
    _ = try m.put(4, 40); // evicts 2 (LRU)
    try expectKeys(&m, a, &.{ 3, 1, 4 });
    try log.expect(&.{.{ .key = 2, .value = 20, .cause = .size }});
}

test "slot reuse after eviction: no dangling, arena bounded" {
    const a = testing.allocator;
    var m = Map.init(a, .{ .max_size = 3 });
    defer m.deinit();
    var k: i32 = 0;
    while (k < 1000) : (k += 1) {
        _ = try m.put(k, k * 10);
        try testing.expect(m.len() <= 3);
    }
    try expectKeys(&m, a, &.{ 997, 998, 999 });
    try expectValues(&m, a, &.{ 9970, 9980, 9990 });
    // Freed slots are reused: the arena never grows past capacity + a few.
    try testing.expect(m.arena.items.len <= 4);
}

test "tie-free determinism over a pseudo-random sequence" {
    const a = testing.allocator;
    const Replay = struct {
        fn run(allocator: Allocator) !struct { keys: []i32, values: []i32 } {
            var m = Map.init(allocator, .{ .max_size = 5 });
            defer m.deinit();
            var state: u64 = 0x1234_5678;
            var i: usize = 0;
            while (i < 2000) : (i += 1) {
                state = state *% 6364136223846793005 +% 1;
                const key: i32 = @intCast((state >> 33) % 20);
                switch ((state >> 30) & 3) {
                    0 => _ = try m.put(key, key * 100),
                    1 => _ = m.get(key),
                    2 => _ = m.containsKey(key),
                    else => _ = m.remove(key),
                }
            }
            return .{ .keys = try m.keys(allocator), .values = try m.values(allocator) };
        }
    };
    const r1 = try Replay.run(a);
    defer a.free(r1.keys);
    defer a.free(r1.values);
    const r2 = try Replay.run(a);
    defer a.free(r2.keys);
    defer a.free(r2.values);
    try testing.expectEqualSlices(i32, r1.keys, r2.keys);
    try testing.expectEqualSlices(i32, r1.values, r2.values);
}
