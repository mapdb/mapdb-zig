// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Hash set with pluggable identity via `HashingStrategy`.
//!
//! Set counterpart of `strategy_hashmap.HashMapWithStrategy`. See that
//! file for design notes. Two elements are considered duplicates iff
//! `strategy.eqlFn(a, b)` returns `true` — `strategy.hashFn` must
//! produce the same hash for equal values.

const std = @import("std");
const Allocator = std.mem.Allocator;
const strategy_mod = @import("strategy.zig");

/// Hash set of `T` values, with identity defined by a `HashingStrategy(T)`.
///
/// Example (deduplicate tags case-insensitively):
///
///     var tags = HashSetWithStrategy([]const u8).init(allocator, ciStrategy);
///     defer tags.deinit();
///     _ = tags.add("Rust");
///     _ = tags.add("rust");  // returns false — already present
///     _ = tags.add("RUST");  // returns false — already present
///     // tags.len() == 1
pub fn HashSetWithStrategy(comptime T: type) type {
    return struct {
        const Self = @This();

        const Context = struct {
            strat: strategy_mod.HashingStrategy(T),

            pub fn hash(ctx: @This(), key: T) u64 {
                return ctx.strat.hashFn(key);
            }

            pub fn eql(ctx: @This(), a: T, b: T) bool {
                return ctx.strat.eqlFn(a, b);
            }
        };

        const Map = std.HashMapUnmanaged(T, void, Context, std.hash_map.default_max_load_percentage);

        inner: Map,
        allocator: Allocator,
        ctx: Context,

        pub fn init(allocator: Allocator, strat: strategy_mod.HashingStrategy(T)) Self {
            return .{
                .inner = .{},
                .allocator = allocator,
                .ctx = .{ .strat = strat },
            };
        }

        pub fn deinit(self: *Self) void {
            self.inner.deinit(self.allocator);
        }

        /// Add an element. Returns true if it was newly inserted, false if already present.
        pub fn add(self: *Self, value: T) Allocator.Error!bool {
            const result = try self.inner.fetchPutContext(self.allocator, value, {}, self.ctx);
            return result == null;
        }

        /// Remove an element. Returns true if it was present.
        pub fn remove(self: *Self, value: T) bool {
            return self.inner.fetchRemoveContext(value, self.ctx) != null;
        }

        pub fn contains(self: *const Self, value: T) bool {
            return self.inner.containsContext(value, self.ctx);
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

        pub fn forEach(self: *const Self, context: anytype, comptime f: fn (@TypeOf(context), T) void) void {
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                f(context, entry.key_ptr.*);
            }
        }

        /// Pull-based iterator yielding each element by value in arbitrary
        /// (hash-table) order. Non-allocating: wraps the backing
        /// `HashMapUnmanaged` key iterator. The iterator borrows the set; do not
        /// mutate while iterating.
        pub const Iterator = struct {
            inner: Map.Iterator,

            pub fn next(self: *Iterator) ?T {
                const entry = self.inner.next() orelse return null;
                return entry.key_ptr.*;
            }
        };

        /// Returns a pull-based iterator over the elements in arbitrary order.
        /// Non-allocating.
        ///
        /// No `mutIterator()` is provided for sets (deliberate exclusion): a set
        /// element IS its own identity — here via the user hashing strategy — so
        /// mutating it in place would put it in the wrong bucket and corrupt the
        /// set. Remove the old element and add the new one instead.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .inner = self.inner.iterator() };
        }

        pub fn toSlice(self: *const Self, allocator: Allocator) Allocator.Error![]T {
            const slice = try allocator.alloc(T, self.inner.count());
            var it = self.inner.iterator();
            var i: usize = 0;
            while (it.next()) |entry| {
                slice[i] = entry.key_ptr.*;
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

test "HashSetWithStrategy basic add/contains" {
    const allocator = std.testing.allocator;
    const strat = strategy_mod.HashingStrategy([]const u8){
        .hashFn = &defaultStringHash,
        .eqlFn = &defaultStringEql,
    };
    var set = HashSetWithStrategy([]const u8).init(allocator, strat);
    defer set.deinit();

    try std.testing.expect(try set.add("hello"));
    try std.testing.expect(try set.add("world"));
    try std.testing.expect(!(try set.add("hello"))); // duplicate

    try std.testing.expectEqual(@as(usize, 2), set.len());
    try std.testing.expect(set.contains("hello"));
    try std.testing.expect(!set.contains("missing"));
}

test "HashSetWithStrategy case-insensitive" {
    const allocator = std.testing.allocator;
    const strat = strategy_mod.HashingStrategy([]const u8){
        .hashFn = &caseInsensitiveHash,
        .eqlFn = &caseInsensitiveEql,
    };
    var set = HashSetWithStrategy([]const u8).init(allocator, strat);
    defer set.deinit();

    try std.testing.expect(try set.add("Hello"));
    try std.testing.expect(!(try set.add("hello"))); // duplicate by case
    try std.testing.expect(!(try set.add("HELLO"))); // duplicate by case
    try std.testing.expectEqual(@as(usize, 1), set.len());
    try std.testing.expect(set.contains("hElLo"));
}

test "HashSetWithStrategy remove" {
    const allocator = std.testing.allocator;
    const strat = strategy_mod.HashingStrategy([]const u8){
        .hashFn = &defaultStringHash,
        .eqlFn = &defaultStringEql,
    };
    var set = HashSetWithStrategy([]const u8).init(allocator, strat);
    defer set.deinit();

    _ = try set.add("a");
    try std.testing.expect(set.remove("a"));
    try std.testing.expect(!set.remove("a"));
    try std.testing.expect(set.isEmpty());
}

test "HashSetWithStrategy clear" {
    const allocator = std.testing.allocator;
    const strat = strategy_mod.HashingStrategy([]const u8){
        .hashFn = &defaultStringHash,
        .eqlFn = &defaultStringEql,
    };
    var set = HashSetWithStrategy([]const u8).init(allocator, strat);
    defer set.deinit();

    _ = try set.add("x");
    set.clear();
    try std.testing.expect(set.isEmpty());
}

test "HashSetWithStrategy stress insert 1000 remove half" {
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
    var set = HashSetWithStrategy(i32).init(allocator, strat);
    defer set.deinit();

    var i: i32 = 0;
    while (i < 1000) : (i += 1) {
        _ = try set.add(i);
    }
    try std.testing.expectEqual(@as(usize, 1000), set.len());

    // Remove even values
    i = 0;
    while (i < 1000) : (i += 2) {
        _ = set.remove(i);
    }
    try std.testing.expectEqual(@as(usize, 500), set.len());

    // Verify remaining
    i = 1;
    while (i < 1000) : (i += 2) {
        try std.testing.expect(set.contains(i));
    }
}
