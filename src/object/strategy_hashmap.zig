// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Hash map with pluggable identity via `HashingStrategy`.
//!
//! Unlike the default `HashMap` which uses `std.AutoHashMapUnmanaged`'s
//! built-in hashing, this map lets the caller supply both the hash
//! function and the equality test. Useful for case-insensitive keys,
//! identity by extracted field, etc.
//!
//! Backed by `std.HashMapUnmanaged` with a custom `Context` that forwards
//! to the strategy's `hashFn` and `eqlFn`. Zig's native `*Context` API
//! variants (`fetchPutContext`, `getContext`, …) are used so the strategy
//! is applied on every lookup.

const std = @import("std");
const Allocator = std.mem.Allocator;
const strategy_mod = @import("strategy.zig");

/// Hash map keyed by `K`, with identity defined by a `HashingStrategy(K)`.
///
/// Example (case-insensitive HTTP headers):
///
///     fn ciHash(s: []const u8) u64 { ... lowercase then std.hash_map hash ... }
///     fn ciEql(a: []const u8, b: []const u8) bool {
///         return std.ascii.eqlIgnoreCase(a, b);
///     }
///     const strat = strategy_mod.HashingStrategy([]const u8){
///         .hashFn = &ciHash, .eqlFn = &ciEql,
///     };
///     var headers = HashMapWithStrategy([]const u8, []const u8).init(allocator, strat);
///     defer headers.deinit();
///     _ = headers.put("Content-Type", "application/json");
///     const v = headers.get("content-type"); // finds it
pub fn HashMapWithStrategy(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        const Context = struct {
            strat: strategy_mod.HashingStrategy(K),

            pub fn hash(ctx: @This(), key: K) u64 {
                return ctx.strat.hashFn(key);
            }

            pub fn eql(ctx: @This(), a: K, b: K) bool {
                return ctx.strat.eqlFn(a, b);
            }
        };

        const Map = std.HashMapUnmanaged(K, V, Context, std.hash_map.default_max_load_percentage);

        inner: Map,
        allocator: Allocator,
        ctx: Context,

        pub fn init(allocator: Allocator, strat: strategy_mod.HashingStrategy(K)) Self {
            return .{
                .inner = .{},
                .allocator = allocator,
                .ctx = .{ .strat = strat },
            };
        }

        pub fn deinit(self: *Self) void {
            self.inner.deinit(self.allocator);
        }

        /// Put a key-value pair. Returns the old value if the key was already present.
        pub fn put(self: *Self, key: K, value: V) Allocator.Error!?V {
            const result = try self.inner.fetchPutContext(self.allocator, key, value, self.ctx);
            if (result) |kv| return kv.value;
            return null;
        }

        pub fn get(self: *const Self, key: K) ?V {
            return self.inner.getContext(key, self.ctx);
        }

        /// Remove a key. Returns the old value if the key was present.
        pub fn remove(self: *Self, key: K) ?V {
            const result = self.inner.fetchRemoveContext(key, self.ctx);
            if (result) |kv| return kv.value;
            return null;
        }

        pub fn containsKey(self: *const Self, key: K) bool {
            return self.inner.containsContext(key, self.ctx);
        }

        pub fn len(self: *const Self) usize {
            return self.inner.count();
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.inner.count() == 0;
        }

        pub fn clear(self: *Self) void {
            self.inner.clearRetainingCapacity();
        }

        pub fn forEach(self: *const Self, ctx: *anyopaque, f: *const fn (ctx: *anyopaque, K, V) void) void {
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                f(ctx, entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        /// An entry yielded by `Iterator` — key and value by value.
        pub const IterEntry = struct { key: K, value: V };

        /// Pull-based iterator yielding `{ key, value }` entries in arbitrary
        /// (hash-table) order. Non-allocating: wraps the backing
        /// `HashMapUnmanaged` entry iterator. The iterator borrows the map; do
        /// not mutate while iterating.
        pub const Iterator = struct {
            inner: Map.Iterator,

            pub fn next(self: *Iterator) ?IterEntry {
                const entry = self.inner.next() orelse return null;
                return .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* };
            }
        };

        /// Returns a pull-based iterator over `{ key, value }` entries in
        /// arbitrary order. Non-allocating.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .inner = self.inner.iterator() };
        }

        pub fn keysToSlice(self: *const Self, allocator: Allocator) Allocator.Error![]K {
            const slice = try allocator.alloc(K, self.inner.count());
            var it = self.inner.iterator();
            var i: usize = 0;
            while (it.next()) |entry| {
                slice[i] = entry.key_ptr.*;
                i += 1;
            }
            return slice;
        }

        pub fn valuesToSlice(self: *const Self, allocator: Allocator) Allocator.Error![]V {
            const slice = try allocator.alloc(V, self.inner.count());
            var it = self.inner.iterator();
            var i: usize = 0;
            while (it.next()) |entry| {
                slice[i] = entry.value_ptr.*;
                i += 1;
            }
            return slice;
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn caseInsensitiveHash(s: []const u8) u64 {
    var h: u64 = 5381;
    for (s) |c| {
        const lower: u8 = if (c >= 'A' and c <= 'Z') c + 32 else c;
        h = ((h << 5) +% h) +% @as(u64, lower);
    }
    return h;
}

fn caseInsensitiveEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        const la: u8 = if (ca >= 'A' and ca <= 'Z') ca + 32 else ca;
        const lb: u8 = if (cb >= 'A' and cb <= 'Z') cb + 32 else cb;
        if (la != lb) return false;
    }
    return true;
}

fn defaultStringHash(s: []const u8) u64 {
    var h: u64 = 5381;
    for (s) |c| {
        h = ((h << 5) +% h) +% @as(u64, c);
    }
    return h;
}

fn defaultStringEql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

test "HashMapWithStrategy basic put/get" {
    const allocator = std.testing.allocator;
    const strat = strategy_mod.HashingStrategy([]const u8){
        .hashFn = &defaultStringHash,
        .eqlFn = &defaultStringEql,
    };
    var map = HashMapWithStrategy([]const u8, i32).init(allocator, strat);
    defer map.deinit();

    try std.testing.expectEqual(@as(?i32, null), map.put("a", 1));
    try std.testing.expectEqual(@as(?i32, null), map.put("b", 2));
    try std.testing.expectEqual(@as(usize, 2), map.len());
    try std.testing.expectEqual(@as(?i32, 1), map.get("a"));
    try std.testing.expectEqual(@as(?i32, 2), map.get("b"));
}

test "HashMapWithStrategy case-insensitive" {
    const allocator = std.testing.allocator;
    const strat = strategy_mod.HashingStrategy([]const u8){
        .hashFn = &caseInsensitiveHash,
        .eqlFn = &caseInsensitiveEql,
    };
    var map = HashMapWithStrategy([]const u8, i32).init(allocator, strat);
    defer map.deinit();

    _ = try map.put("Content-Type", 1);
    _ = try map.put("content-type", 2); // should overwrite
    try std.testing.expectEqual(@as(usize, 1), map.len());
    try std.testing.expectEqual(@as(?i32, 2), map.get("CONTENT-TYPE"));
}

test "HashMapWithStrategy remove" {
    const allocator = std.testing.allocator;
    const strat = strategy_mod.HashingStrategy([]const u8){
        .hashFn = &defaultStringHash,
        .eqlFn = &defaultStringEql,
    };
    var map = HashMapWithStrategy([]const u8, i32).init(allocator, strat);
    defer map.deinit();

    _ = try map.put("x", 10);
    const removed = map.remove("x");
    try std.testing.expectEqual(@as(?i32, 10), removed);
    try std.testing.expect(map.isEmpty());
}

test "HashMapWithStrategy stress insert 1000 remove half" {
    const allocator = std.testing.allocator;

    const intHash = struct {
        fn h(v: i32) u64 {
            return @as(u64, @intCast(@as(u32, @bitCast(v))));
        }
    }.h;
    const intEql = struct {
        fn e(a: i32, b: i32) bool {
            return a == b;
        }
    }.e;
    const strat = strategy_mod.HashingStrategy(i32){
        .hashFn = &intHash,
        .eqlFn = &intEql,
    };
    var map = HashMapWithStrategy(i32, i32).init(allocator, strat);
    defer map.deinit();

    var i: i32 = 0;
    while (i < 1000) : (i += 1) {
        _ = try map.put(i, i * 10);
    }
    try std.testing.expectEqual(@as(usize, 1000), map.len());

    // Remove even keys
    i = 0;
    while (i < 1000) : (i += 2) {
        _ = map.remove(i);
    }
    try std.testing.expectEqual(@as(usize, 500), map.len());

    // Verify remaining
    i = 1;
    while (i < 1000) : (i += 2) {
        try std.testing.expect(map.containsKey(i));
    }
}
