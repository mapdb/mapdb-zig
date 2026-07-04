// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! `ShardedHashMap(K, V)` — the library's concurrent map (tier L2).
//!
//! N power-of-two shards, each a single-threaded `HashMap(K, V)` behind its own
//! `RwLock`, cache-line padded to avoid false sharing. A key is routed to a
//! shard by the HIGH bits of its hash (the inner table consumes the LOW bits,
//! so the two indices are decorrelated from one hash).
//!
//! ## Memory story: no safe-memory-reclamation needed
//!
//! Every structural free (rehash of a shard's old table, removed-entry backing)
//! happens while holding that shard's WRITE lock; every read holds the shard's
//! READ lock. Nothing is ever freed while a reader can still see it, so — unlike
//! a lock-free CHM port — this needs no epochs/hazard-pointers. Reads scale
//! across shards and within a shard (shared lock); writes scale across shards.
//!
//! ## API rules (all of them are *memory* rules)
//!
//! - Nothing pointer-shaped escapes a lock. `get`/`remove`/`put` COPY `V` in or
//!   out under the lock. Borrowed access is offered only *inside* a callback
//!   that runs under the lock (`getWith`, `compute`).
//! - That copy is SHALLOW. For a primitive `V` a copy-out value is a stable,
//!   independent snapshot. For a resource-owning `V` (an owned `[]u8`, a handle)
//!   the value returned by `get`/`putIfAbsent`/`entriesSnapshot` still ALIASES
//!   the map's payload: a concurrent `remove`/`put` on that key moves the payload
//!   out to *that* caller, who may free it — leaving your copy dangling. Copy-out
//!   is not a stable owned snapshot for owning `V`; use immutable/refcounted
//!   payloads or external lifetime coordination. `compute` returns the displaced
//!   value as the authoritative move-out (see its doc).
//! - Callbacks passed into accessors run under the shard lock: they must be
//!   brief and MUST NOT reenter this map (the RwLock is non-recursive, so
//!   touching the same shard self-deadlocks). This is documented UB, not
//!   silently-fine-on-some-shard-counts. The non-obvious reentrancy is the
//!   ALLOCATOR: `put`/`compute(.put)` may grow a shard under its write lock, and
//!   `entriesSnapshot` allocates under each shard's read lock — a custom
//!   allocator whose alloc/free path reenters this map self-deadlocks.
//! - The check-then-act family (`putIfAbsent`, `compute`) is REQUIRED, not
//!   optional: with a copy-out API, user-side `if (m.get(k)==null) m.put(...)`
//!   is a race; these do it atomically under one lock.
//! - Iteration (`forEach`, `entriesSnapshot`) locks one shard at a time and is
//!   **weakly consistent**: it reflects some state at/after the call, never
//!   throws, and may miss concurrent updates in other shards.
//! - The allocator MUST be thread-safe (shards allocate/free concurrently):
//!   `std.heap.smp_allocator`, `c_allocator`, page allocator, or a thread-safe
//!   GPA. Arena / fixed-buffer allocators are NOT safe here.
//! - `deinit`/`clear` require external quiescence for a *consistent* result;
//!   `clear` otherwise proceeds shard-by-shard (weakly consistent).
//!
//! Payload ownership is identical to the single-threaded object map (shallow;
//! move-out on remove/replace-return). See doc 01 and doc 02.

const std = @import("std");
const Allocator = std.mem.Allocator;
const HashMap = @import("../hashmap/hash_map.zig").HashMap;
const hashKey = @import("../hash_table.zig").hashKey;

const CACHE_LINE = 64;

/// What a `compute` callback asks the map to do with a key.
pub fn ComputeOp(comptime V: type) type {
    return union(enum) {
        /// Insert or replace the key with this value.
        put: V,
        /// Remove the key if present.
        remove,
        /// Leave the entry unchanged.
        keep,
    };
}

pub fn ShardedHashMap(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const Map = HashMap(K, V);

        /// One shard: an independent single-threaded map behind its own lock,
        /// padded so adjacent shards never share a cache line.
        const Shard = struct {
            rwlock: std.Thread.RwLock = .{},
            map: Map,
            _pad: [pad_len]u8 = undefined,

            const core = @sizeOf(std.Thread.RwLock) + @sizeOf(Map);
            const pad_len = (CACHE_LINE - (core % CACHE_LINE)) % CACHE_LINE;

            comptime {
                // `pad_len` is computed from summed field sizes; with two fields
                // laid out in descending-alignment order there is no inter-field
                // gap, so the padded size is a cache-line multiple. Assert it so a
                // future field/layout change that breaks per-shard isolation fails
                // the build instead of silently reintroducing false sharing.
                std.debug.assert(@sizeOf(Shard) % CACHE_LINE == 0);
            }
        };

        pub const Entry = struct { key: K, value: V };

        shards: []align(CACHE_LINE) Shard,
        shard_bits: std.math.Log2Int(u64),
        allocator: Allocator,

        /// Create with a default shard count (next power of two ≥ 4× the CPU
        /// count, clamped to [4, 256]). `allocator` must be thread-safe.
        pub fn init(allocator: Allocator) Allocator.Error!Self {
            const cpus = std.Thread.getCpuCount() catch 4;
            const want = std.math.ceilPowerOfTwo(usize, @max(4, cpus * 4)) catch 256;
            return initShardCount(allocator, std.math.clamp(want, 4, 256));
        }

        /// Create with an explicit shard count (rounded up to a power of two).
        /// `allocator` must be thread-safe.
        pub fn initShardCount(allocator: Allocator, requested_shards: usize) Allocator.Error!Self {
            const n = std.math.ceilPowerOfTwo(usize, @max(1, requested_shards)) catch return error.OutOfMemory;
            const shards = try allocator.alignedAlloc(Shard, .fromByteUnits(CACHE_LINE), n);
            errdefer allocator.free(shards);
            // Map.init is infallible (lazy table alloc), so no partial-shard
            // rollback is needed once the shard array itself is allocated.
            for (shards) |*s| {
                s.* = .{ .map = Map.init(allocator) };
            }
            return .{
                .shards = shards,
                .shard_bits = @intCast(std.math.log2_int(usize, n)),
                .allocator = allocator,
            };
        }

        /// Free all shards and their tables. NOT thread-safe: the caller must
        /// ensure all worker threads have stopped (quiescence).
        pub fn deinit(self: *Self) void {
            for (self.shards) |*s| s.map.deinit();
            self.allocator.free(self.shards);
        }

        fn shardFor(self: *Self, key: K) *Shard {
            const h = hashKey(K, key);
            // High bits pick the shard; shard_bits == 0 (single shard) must not
            // shift by 64 (UB), so special-case it.
            const idx: usize = if (self.shard_bits == 0)
                0
            else
                @intCast(h >> @intCast(64 - @as(u32, self.shard_bits)));
            return &self.shards[idx];
        }

        // ---- Copy-in / copy-out core ----

        /// Returns a COPY of the value for `key`, or null. Held under a read lock.
        pub fn get(self: *Self, key: K) ?V {
            const s = self.shardFor(key);
            s.rwlock.lockShared();
            defer s.rwlock.unlockShared();
            return s.map.get(key);
        }

        pub fn contains(self: *Self, key: K) bool {
            const s = self.shardFor(key);
            s.rwlock.lockShared();
            defer s.rwlock.unlockShared();
            return s.map.containsKey(key);
        }

        /// Insert or replace. Returns the displaced old value (moved out to the
        /// caller), or null. Held under a write lock.
        pub fn put(self: *Self, key: K, value: V) Allocator.Error!?V {
            const s = self.shardFor(key);
            s.rwlock.lock();
            defer s.rwlock.unlock();
            return s.map.put(key, value);
        }

        /// Remove `key`. Returns the removed value (moved out), or null.
        pub fn remove(self: *Self, key: K) ?V {
            const s = self.shardFor(key);
            s.rwlock.lock();
            defer s.rwlock.unlock();
            return s.map.remove(key);
        }

        // ---- Atomic check-then-act (required, not optional) ----

        /// If `key` is absent, insert `value` and return null. If present, leave
        /// it and return a COPY of the existing value. Atomic under one lock.
        pub fn putIfAbsent(self: *Self, key: K, value: V) Allocator.Error!?V {
            const s = self.shardFor(key);
            s.rwlock.lock();
            defer s.rwlock.unlock();
            if (s.map.get(key)) |existing| return existing;
            _ = try s.map.put(key, value);
            return null;
        }

        /// Atomically read the current value (a COPY, or null if absent) and
        /// apply the `ComputeOp` the callback returns (put/remove/keep). The
        /// callback runs under the shard's write lock and must not reenter.
        ///
        /// Returns the value this operation DISPLACED, moved out to the caller
        /// (same move-out contract as `put`/`remove`): the old value on a `.put`
        /// that replaced an existing entry, the removed value on `.remove`, and
        /// null on `.keep`, on `.put` of a fresh key, or on `.remove` of an
        /// absent key. For an owning `V` this is the handle you must free/reuse —
        /// discarding it leaks. (The `?V` the callback receives is a *shallow
        /// copy* that aliases the same payload; the returned value is the
        /// authoritative move-out.)
        pub fn compute(
            self: *Self,
            key: K,
            context: anytype,
            comptime f: fn (@TypeOf(context), ?V) ComputeOp(V),
        ) Allocator.Error!?V {
            const s = self.shardFor(key);
            s.rwlock.lock();
            defer s.rwlock.unlock();
            return switch (f(context, s.map.get(key))) {
                .put => |v| try s.map.put(key, v),
                .remove => s.map.remove(key),
                .keep => null,
            };
        }

        /// Run `f` on a borrowed `*const V` under the read lock if `key` is
        /// present; returns whether it was. The pointer is valid ONLY inside the
        /// callback. The callback must not reenter this map.
        pub fn getWith(
            self: *Self,
            key: K,
            context: anytype,
            comptime f: fn (@TypeOf(context), *const V) void,
        ) bool {
            const s = self.shardFor(key);
            s.rwlock.lockShared();
            defer s.rwlock.unlockShared();
            if (s.map.inner.getPtr(key)) |ptr| {
                f(context, ptr);
                return true;
            }
            return false;
        }

        // ---- Aggregate / iteration (weakly consistent) ----

        /// Sum of per-shard sizes. Weakly consistent: each shard is read under
        /// its own lock, so the total may reflect concurrent updates unevenly.
        pub fn count(self: *Self) usize {
            var total: usize = 0;
            for (self.shards) |*s| {
                s.rwlock.lockShared();
                defer s.rwlock.unlockShared();
                total += s.map.len();
            }
            return total;
        }

        pub fn isEmpty(self: *Self) bool {
            return self.count() == 0;
        }

        /// Visit every `{K, *const V}` entry, one shard at a time under a read
        /// lock. Weakly consistent (see the module doc). The callback runs under
        /// a shard lock and must not reenter this map.
        pub fn forEach(
            self: *Self,
            context: anytype,
            comptime f: fn (@TypeOf(context), K, *const V) void,
        ) void {
            for (self.shards) |*s| {
                s.rwlock.lockShared();
                defer s.rwlock.unlockShared();
                var it = s.map.iterator();
                while (it.next()) |e| {
                    // The entry is a by-value copy from the iterator; hand the
                    // callback a pointer to that copy (read-only, lock-scoped).
                    var v = e.value;
                    f(context, e.key, &v);
                }
            }
        }

        /// Allocate and return a caller-owned snapshot of all entries. Each shard
        /// is copied under its own read lock, so the snapshot is weakly
        /// consistent across shards. Free the slice with `allocator`.
        pub fn entriesSnapshot(self: *Self, allocator: Allocator) Allocator.Error![]Entry {
            var list = std.ArrayListUnmanaged(Entry){};
            errdefer list.deinit(allocator);
            for (self.shards) |*s| {
                s.rwlock.lockShared();
                defer s.rwlock.unlockShared();
                try list.ensureUnusedCapacity(allocator, s.map.len());
                var it = s.map.iterator();
                while (it.next()) |e| {
                    list.appendAssumeCapacity(.{ .key = e.key, .value = e.value });
                }
            }
            return list.toOwnedSlice(allocator);
        }

        /// Remove all entries, shard by shard (weakly consistent unless the
        /// caller guarantees quiescence).
        pub fn clear(self: *Self) void {
            for (self.shards) |*s| {
                s.rwlock.lock();
                defer s.rwlock.unlock();
                s.map.clear();
            }
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

test "ShardedHashMap: single-threaded get/put/remove/putIfAbsent/count" {
    var m = try ShardedHashMap(i64, i64).initShardCount(testing.allocator, 8);
    defer m.deinit();

    try testing.expect(try m.put(1, 10) == null);
    try testing.expectEqual(@as(?i64, 10), (try m.put(1, 11))); // replace returns old
    try testing.expectEqual(@as(?i64, 11), m.get(1));
    try testing.expect(m.contains(1));
    try testing.expectEqual(@as(usize, 1), m.count());

    // putIfAbsent: present -> returns existing, no change
    try testing.expectEqual(@as(?i64, 11), (try m.putIfAbsent(1, 99)));
    try testing.expectEqual(@as(?i64, 11), m.get(1));
    // putIfAbsent: absent -> inserts, returns null
    try testing.expect(try m.putIfAbsent(2, 20) == null);
    try testing.expectEqual(@as(?i64, 20), m.get(2));

    try testing.expectEqual(@as(?i64, 11), m.remove(1));
    try testing.expect(m.remove(1) == null);
    try testing.expectEqual(@as(usize, 1), m.count());
}

test "ShardedHashMap: compute put/remove/keep" {
    var m = try ShardedHashMap(i64, i64).initShardCount(testing.allocator, 4);
    defer m.deinit();

    // absent -> put via compute; fresh key displaces nothing -> null
    try testing.expectEqual(@as(?i64, null), try m.compute(5, @as(i64, 100), struct {
        fn f(seed: i64, cur: ?i64) ComputeOp(i64) {
            try_expect_absent(cur);
            return .{ .put = seed };
        }
        fn try_expect_absent(cur: ?i64) void {
            std.debug.assert(cur == null);
        }
    }.f));
    try testing.expectEqual(@as(?i64, 100), m.get(5));

    // present -> increment via compute; returns the displaced old value
    try testing.expectEqual(@as(?i64, 100), try m.compute(5, {}, struct {
        fn f(_: void, cur: ?i64) ComputeOp(i64) {
            return .{ .put = (cur orelse 0) + 1 };
        }
    }.f));
    try testing.expectEqual(@as(?i64, 101), m.get(5));

    // present -> remove via compute; returns the removed value (move-out)
    try testing.expectEqual(@as(?i64, 101), try m.compute(5, {}, struct {
        fn f(_: void, _: ?i64) ComputeOp(i64) {
            return .remove;
        }
    }.f));
    try testing.expect(m.get(5) == null);

    // remove of an absent key -> null
    try testing.expectEqual(@as(?i64, null), try m.compute(5, {}, struct {
        fn f(_: void, _: ?i64) ComputeOp(i64) {
            return .remove;
        }
    }.f));

    // keep -> no-op, displaces nothing -> null
    _ = try m.put(6, 60);
    try testing.expectEqual(@as(?i64, null), try m.compute(6, {}, struct {
        fn f(_: void, _: ?i64) ComputeOp(i64) {
            return .keep;
        }
    }.f));
    try testing.expectEqual(@as(?i64, 60), m.get(6));
}

test "ShardedHashMap: getWith borrows under the lock" {
    var m = try ShardedHashMap(i64, i64).initShardCount(testing.allocator, 4);
    defer m.deinit();
    _ = try m.put(7, 49);

    var seen: i64 = 0;
    const found = m.getWith(7, &seen, struct {
        fn f(out: *i64, v: *const i64) void {
            out.* = v.*;
        }
    }.f);
    try testing.expect(found);
    try testing.expectEqual(@as(i64, 49), seen);
    try testing.expect(!m.getWith(8, &seen, struct {
        fn f(_: *i64, _: *const i64) void {}
    }.f));
}

test "ShardedHashMap: entriesSnapshot returns every entry" {
    var m = try ShardedHashMap(i64, i64).initShardCount(testing.allocator, 8);
    defer m.deinit();
    var i: i64 = 0;
    while (i < 200) : (i += 1) _ = try m.put(i, i * 2);

    const snap = try m.entriesSnapshot(testing.allocator);
    defer testing.allocator.free(snap);
    try testing.expectEqual(@as(usize, 200), snap.len);
    // Verify the snapshot content (order across shards is arbitrary).
    var seen = [_]bool{false} ** 200;
    for (snap) |e| {
        try testing.expectEqual(e.key * 2, e.value);
        seen[@intCast(e.key)] = true;
    }
    for (seen) |b| try testing.expect(b);
}

test "ShardedHashMap: concurrent disjoint-range writers land every entry" {
    var m = try ShardedHashMap(i64, i64).init(testing.allocator);
    defer m.deinit();

    const per_thread: i64 = 3000;
    const n_threads: usize = 8;
    const Worker = struct {
        fn run(map: *ShardedHashMap(i64, i64), tid: i64, cnt: i64) void {
            var i: i64 = 0;
            while (i < cnt) : (i += 1) {
                const key = tid * cnt + i;
                _ = map.put(key, key) catch return;
            }
        }
    };
    var threads: [n_threads]std.Thread = undefined;
    for (&threads, 0..) |*t, tid| {
        t.* = try std.Thread.spawn(.{}, Worker.run, .{ &m, @as(i64, @intCast(tid)), per_thread });
    }
    for (&threads) |*t| t.join();

    try testing.expectEqual(@as(usize, @intCast(per_thread * @as(i64, n_threads))), m.count());
    var tid: i64 = 0;
    while (tid < n_threads) : (tid += 1) {
        const key = tid * per_thread + 123;
        try testing.expectEqual(@as(?i64, key), m.get(key));
    }
}

test "ShardedHashMap: concurrent putIfAbsent on the SAME key inserts exactly once" {
    var m = try ShardedHashMap(i64, i64).init(testing.allocator);
    defer m.deinit();

    const n_threads: usize = 8;
    const Worker = struct {
        fn run(map: *ShardedHashMap(i64, i64), tid: i64, wins: *std.atomic.Value(usize)) void {
            var i: i64 = 0;
            while (i < 5000) : (i += 1) {
                // Everyone races to claim key 42; only the first insert wins.
                if (map.putIfAbsent(42, tid) catch return) |_| {
                    // returned existing -> someone else already owns it
                } else {
                    _ = wins.fetchAdd(1, .seq_cst); // we inserted it
                }
            }
        }
    };
    var wins = std.atomic.Value(usize).init(0);
    var threads: [n_threads]std.Thread = undefined;
    for (&threads, 0..) |*t, tid| {
        t.* = try std.Thread.spawn(.{}, Worker.run, .{ &m, @as(i64, @intCast(tid)), &wins });
    }
    for (&threads) |*t| t.join();

    // Exactly one putIfAbsent across all threads observed the key as absent.
    try testing.expectEqual(@as(usize, 1), wins.load(.seq_cst));
    try testing.expectEqual(@as(usize, 1), m.count());
}
