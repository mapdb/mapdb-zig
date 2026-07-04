// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! `Synchronized(C)` — coarse `RwLock` wrapper around any single-threaded
//! collection (concurrency tier L1, parity with the Rust/Go sibling ports).
//!
//! Memory story: trivial. Every mutation happens under the exclusive write
//! lock and every read under the shared read lock, so nothing is ever freed
//! while another thread can still observe it — no safe-memory-reclamation
//! machinery is needed. This works for *every* collection in the library
//! (maps, trees, multimaps, …) including ones that return borrowed
//! slices/iterators: those borrows are valid only while the guard is held.
//!
//! Usage:
//! ```zig
//! var sync = Synchronized(I32I32HashMap).init(try I32I32HashMap.init(alloc));
//! defer sync.deinit(); // caller guarantees quiescence (all user threads done)
//!
//! {
//!     var g = sync.lock();            // exclusive
//!     defer g.unlock();
//!     _ = try g.map().put(1, 10);
//! }
//! {
//!     var g = sync.lockShared();      // shared (multiple readers)
//!     defer g.unlock();
//!     const v = g.map().get(1);
//!     _ = v;
//! }
//! ```
//!
//! Everything borrowed from `g.map()` (pointers, slices, iterators) dies with
//! the guard — do not let it escape the `defer g.unlock()` scope. Zig cannot
//! enforce this, but the guard idiom makes it teachable. `deinit` is not
//! thread-safe: the caller must ensure all worker threads have stopped first.

const std = @import("std");

/// Wrap any collection type `C` in an `RwLock` for coarse-grained thread-safe
/// access. `C` must expose a `deinit(*C)` method (all managed collections do).
pub fn Synchronized(comptime C: type) type {
    return struct {
        const Self = @This();

        rwlock: std.Thread.RwLock = .{},
        inner: C,

        /// Take ownership of an already-constructed collection. Build `inner`
        /// with its own constructor (which may be fallible or take a comparator)
        /// and hand it over here.
        pub fn init(inner: C) Self {
            return .{ .inner = inner };
        }

        /// Free the wrapped collection. NOT thread-safe — the caller must ensure
        /// no other thread is still using the map (quiescence).
        pub fn deinit(self: *Self) void {
            self.inner.deinit();
        }

        /// Exclusive access guard. Release with `unlock` (typically via `defer`).
        pub const WriteGuard = struct {
            owner: *Self,

            /// Mutable access to the wrapped collection. Valid only until `unlock`.
            pub fn map(g: WriteGuard) *C {
                return &g.owner.inner;
            }

            pub fn unlock(g: WriteGuard) void {
                g.owner.rwlock.unlock();
            }
        };

        /// Shared (read) access guard. Multiple readers may hold one at once.
        pub const ReadGuard = struct {
            owner: *Self,

            /// Read-only access to the wrapped collection. Valid only until `unlock`.
            pub fn map(g: ReadGuard) *const C {
                return &g.owner.inner;
            }

            pub fn unlock(g: ReadGuard) void {
                g.owner.rwlock.unlockShared();
            }
        };

        /// Acquire the exclusive write lock and return a guard.
        pub fn lock(self: *Self) WriteGuard {
            self.rwlock.lock();
            return .{ .owner = self };
        }

        /// Acquire the shared read lock and return a guard.
        pub fn lockShared(self: *Self) ReadGuard {
            self.rwlock.lockShared();
            return .{ .owner = self };
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const HashMap = @import("../hashmap/hashmap.zig").HashMap;

test "Synchronized: single-threaded guard round-trip" {
    const M = HashMap(i64, i64);
    var sync = Synchronized(M).init(try M.init(std.testing.allocator));
    defer sync.deinit();

    {
        var g = sync.lock();
        defer g.unlock();
        _ = try g.map().put(1, 10);
        _ = try g.map().put(2, 20);
    }
    {
        var g = sync.lockShared();
        defer g.unlock();
        try std.testing.expectEqual(@as(?i64, 10), g.map().get(1));
        try std.testing.expectEqual(@as(usize, 2), g.map().len());
    }
}

test "Synchronized: concurrent writers on disjoint keys land every entry" {
    const M = HashMap(i64, i64);
    var sync = Synchronized(M).init(try M.init(std.testing.allocator));
    defer sync.deinit();

    const per_thread: i64 = 2000;
    const n_threads: usize = 8;

    const Worker = struct {
        fn run(s: *Synchronized(M), tid: i64, count: i64) void {
            var i: i64 = 0;
            while (i < count) : (i += 1) {
                const key = tid * count + i; // disjoint key ranges
                var g = s.lock();
                defer g.unlock();
                _ = g.map().put(key, key) catch return;
            }
        }
    };

    var threads: [n_threads]std.Thread = undefined;
    for (&threads, 0..) |*t, tid| {
        t.* = try std.Thread.spawn(.{}, Worker.run, .{ &sync, @as(i64, @intCast(tid)), per_thread });
    }
    for (&threads) |*t| t.join();

    var g = sync.lockShared();
    defer g.unlock();
    try std.testing.expectEqual(@as(usize, @intCast(per_thread * @as(i64, n_threads))), g.map().len());
    // Spot-check a value from each thread's range.
    for (0..n_threads) |tid| {
        const key = @as(i64, @intCast(tid)) * per_thread + 7;
        try std.testing.expectEqual(@as(?i64, key), g.map().get(key));
    }
}

test "Synchronized: many readers concurrent with occasional writer stays consistent" {
    const M = HashMap(i64, i64);
    var sync = Synchronized(M).init(try M.init(std.testing.allocator));
    defer sync.deinit();
    {
        var g = sync.lock();
        defer g.unlock();
        var i: i64 = 0;
        while (i < 100) : (i += 1) _ = try g.map().put(i, i * i);
    }

    const Reader = struct {
        fn run(s: *Synchronized(M), ok: *std.atomic.Value(bool)) void {
            var iter: usize = 0;
            while (iter < 5000) : (iter += 1) {
                var g = s.lockShared();
                defer g.unlock();
                const v = g.map().get(50) orelse {
                    ok.store(false, .seq_cst);
                    return;
                };
                if (v != 2500) ok.store(false, .seq_cst);
            }
        }
    };

    var ok = std.atomic.Value(bool).init(true);
    var threads: [6]std.Thread = undefined;
    for (&threads) |*t| t.* = try std.Thread.spawn(.{}, Reader.run, .{ &sync, &ok });
    for (&threads) |*t| t.join();
    try std.testing.expect(ok.load(.seq_cst));
}
