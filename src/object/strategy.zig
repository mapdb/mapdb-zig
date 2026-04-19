// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Hashing strategies and comparators for strategy-backed collections.
//!
//! A `HashingStrategy(T)` externalises identity for hash-based collections
//! (see `HashSetWithStrategy`, `HashMapWithStrategy`). Instead of relying
//! on built-in hashing, the collection uses the strategy. This enables
//! case-insensitive string keys, identity by extracted field, etc.
//!
//! A `Comparator(T)` defines a total order between two values, powering
//! sorted collections (`TreeMap`, `TreeSet`). Zig comparators are plain
//! function pointers, so all composition (`reversed`, `comparatorByField`,
//! `thenComparing`) happens at comptime — each unique combination of
//! type parameters and sub-comparators yields a freshly monomorphised
//! function with no runtime indirection.

const std = @import("std");

// ── HashingStrategy ─────────────────────────────────────────────────────

/// Externalises identity (hash + equality) for hash-based collections.
///
/// `hashFn` must produce the same u64 for values that are `eqlFn`-equal.
/// Unlike the built-in equality, the strategy's functions decide whether
/// two values collide in a hash table — so a case-insensitive strategy
/// reports "Hello" == "hello", and the set will treat them as duplicates.
///
/// Typically constructed from standalone functions:
///
///     fn lowerHash(s: []const u8) u64 { ... }
///     fn lowerEql(a: []const u8, b: []const u8) bool {
///         return std.ascii.eqlIgnoreCase(a, b);
///     }
///     const strategy = HashingStrategy([]const u8){
///         .hashFn = &lowerHash,
///         .eqlFn = &lowerEql,
///     };
pub fn HashingStrategy(comptime T: type) type {
    return struct {
        hashFn: *const fn (T) u64,
        eqlFn: *const fn (T, T) bool,
    };
}

// ── Comparator ──────────────────────────────────────────────────────────

/// A total order over values of type `T`. Returns `.lt` if `a < b`,
/// `.gt` if `a > b`, `.eq` if the two values are considered equal.
///
/// Sorted collections (`TreeMap`, `TreeSet`) use `.eq` as their equality
/// test — two keys are "the same" iff `cmp(a, b) == .eq`, regardless of
/// any built-in equality. This matches Java's `TreeSet`/`TreeMap` contract.
pub fn Comparator(comptime T: type) type {
    return *const fn (T, T) std.math.Order;
}

/// Comparator using `std.math.order` (ascending for integers/floats,
/// lexicographic for strings via a future `std.mem.order` wrapper).
///
/// Example:
///
///     var set = TreeSet(i32).init(allocator, naturalComparator(i32));
///     _ = set.add(3);
///     _ = set.add(1);
///     _ = set.add(2);
///     // Iteration order: 1, 2, 3.
pub fn naturalComparator(comptime T: type) Comparator(T) {
    return &struct {
        fn cmp(a: T, b: T) std.math.Order {
            return std.math.order(a, b);
        }
    }.cmp;
}

/// Comparator with reversed natural ordering (descending for integers).
///
/// Example (leaderboard — highest score first):
///
///     var board = TreeMap(i32, []const u8).init(allocator, reverseComparator(i32));
///     _ = try board.put(100, "Alice");
///     _ = try board.put(250, "Bob");
///     // board.min() is the highest-scoring player.
pub fn reverseComparator(comptime T: type) Comparator(T) {
    return &struct {
        fn cmp(a: T, b: T) std.math.Order {
            return std.math.order(b, a);
        }
    }.cmp;
}

/// Reverses an existing comparator. Works on any comparator, not just
/// natural ordering (unlike `reverseComparator`).
///
/// Because composition is at comptime, the `orig` argument must be
/// comptime-known. Store the result in a `const` (optionally prefixed
/// with `comptime`) to pass it to further builders like `thenComparing`.
///
/// Example:
///
///     const byAge = comparatorByField(Person, i32, &getAge, naturalComparator(i32));
///     const byAgeDesc = reversed(Person, byAge);
pub fn reversed(comptime T: type, comptime orig: Comparator(T)) Comparator(T) {
    return &struct {
        fn cmp(a: T, b: T) std.math.Order {
            return switch (orig(a, b)) {
                .lt => .gt,
                .gt => .lt,
                .eq => .eq,
            };
        }
    }.cmp;
}

/// Comparator that orders by an extracted field using a sub-comparator.
///
/// Used to sort structs by one of their fields, optionally with custom
/// ordering for the field type (e.g. case-insensitive string sort).
///
/// `extract` and `sub` must both be comptime-known — pass addresses of
/// standalone functions or results of other comptime builders.
///
/// Example:
///
///     const extractName = struct {
///         fn f(p: Person) []const u8 { return p.name; }
///     }.f;
///     const byName = comparatorByField(
///         Person, []const u8,
///         &extractName, naturalComparator([]const u8),
///     );
pub fn comparatorByField(
    comptime T: type,
    comptime F: type,
    comptime extract: *const fn (T) F,
    comptime sub: Comparator(F),
) Comparator(T) {
    return &struct {
        fn cmp(a: T, b: T) std.math.Order {
            return sub(extract(a), extract(b));
        }
    }.cmp;
}

/// Chains two comparators. `primary` decides the order; when `primary`
/// reports `.eq`, `secondary` breaks the tie. Equivalent to Java's
/// `Comparator.thenComparing`.
///
/// Example (multi-level sort — age ascending, then name ascending):
///
///     const byAge  = comparatorByField(Person, i32, &getAge,  naturalComparator(i32));
///     const byName = comparatorByField(Person, []const u8, &getName, &strOrder);
///     const cmp    = thenComparing(Person, byAge, byName);
pub fn thenComparing(
    comptime T: type,
    comptime primary: Comparator(T),
    comptime secondary: Comparator(T),
) Comparator(T) {
    return &struct {
        fn cmp(a: T, b: T) std.math.Order {
            return switch (primary(a, b)) {
                .lt => .lt,
                .gt => .gt,
                .eq => secondary(a, b),
            };
        }
    }.cmp;
}

// ── Tests ───────────────────────────────────────────────────────────────

test "naturalComparator ordering" {
    const cmp = naturalComparator(i32);
    try std.testing.expectEqual(std.math.Order.lt, cmp(1, 2));
    try std.testing.expectEqual(std.math.Order.eq, cmp(5, 5));
    try std.testing.expectEqual(std.math.Order.gt, cmp(9, 3));
}

test "reverseComparator ordering" {
    const cmp = reverseComparator(i32);
    try std.testing.expectEqual(std.math.Order.gt, cmp(1, 2));
    try std.testing.expectEqual(std.math.Order.eq, cmp(5, 5));
    try std.testing.expectEqual(std.math.Order.lt, cmp(9, 3));
}

test "reversed comparator" {
    const cmp = reversed(i32, naturalComparator(i32));
    // Reversed natural: 5 should come before 1 (i.e. 5 < 1 in reversed order).
    try std.testing.expectEqual(std.math.Order.lt, cmp(5, 1));
    try std.testing.expectEqual(std.math.Order.gt, cmp(1, 5));
    try std.testing.expectEqual(std.math.Order.eq, cmp(7, 7));

    // Sort array with reversed comparator and verify descending order.
    var arr = [_]i32{ 1, 3, 5, 2, 4 };
    const lessThan = struct {
        fn f(_: void, a: i32, b: i32) bool {
            return reversed(i32, naturalComparator(i32))(a, b) == .lt;
        }
    }.f;
    std.mem.sort(i32, &arr, {}, lessThan);
    try std.testing.expectEqual(@as(i32, 5), arr[0]);
    try std.testing.expectEqual(@as(i32, 1), arr[4]);
}

test "comparatorByField" {
    const Person = struct { name: []const u8, age: i32 };
    const extractAge = struct {
        fn f(p: Person) i32 {
            return p.age;
        }
    }.f;
    const cmp = comparatorByField(Person, i32, &extractAge, naturalComparator(i32));

    const alice = Person{ .name = "Alice", .age = 30 };
    const bob = Person{ .name = "Bob", .age = 25 };
    const carol = Person{ .name = "Carol", .age = 30 };

    try std.testing.expectEqual(std.math.Order.gt, cmp(alice, bob));
    try std.testing.expectEqual(std.math.Order.lt, cmp(bob, alice));
    try std.testing.expectEqual(std.math.Order.eq, cmp(alice, carol));
}

test "thenComparing chains age asc then name asc" {
    const Person = struct { name: []const u8, age: i32 };
    const extractAge = struct {
        fn f(p: Person) i32 {
            return p.age;
        }
    }.f;
    const extractName = struct {
        fn f(p: Person) []const u8 {
            return p.name;
        }
    }.f;
    const nameCmp = struct {
        fn f(a: []const u8, b: []const u8) std.math.Order {
            return std.mem.order(u8, a, b);
        }
    }.f;

    const byAge = comptime comparatorByField(Person, i32, &extractAge, naturalComparator(i32));
    const byName = comptime comparatorByField(Person, []const u8, &extractName, &nameCmp);
    const cmp = comptime thenComparing(Person, byAge, byName);

    const alice = Person{ .name = "Alice", .age = 30 };
    const bob = Person{ .name = "Bob", .age = 25 };
    const carol = Person{ .name = "Carol", .age = 30 };
    const alice2 = Person{ .name = "Alice", .age = 30 };

    // Bob (25) < Alice (30) by primary age.
    try std.testing.expectEqual(std.math.Order.lt, cmp(bob, alice));
    // Alice and Carol tie on age, fall back to name: Alice < Carol.
    try std.testing.expectEqual(std.math.Order.lt, cmp(alice, carol));
    try std.testing.expectEqual(std.math.Order.gt, cmp(carol, alice));
    // Same name and age -> equal.
    try std.testing.expectEqual(std.math.Order.eq, cmp(alice, alice2));

    // Full multi-level sort.
    var people = [_]Person{
        .{ .name = "Carol", .age = 30 },
        .{ .name = "Bob", .age = 25 },
        .{ .name = "Alice", .age = 30 },
    };
    const lessThan = struct {
        fn f(_: void, a: Person, b: Person) bool {
            const byAgeLocal = comptime comparatorByField(Person, i32, &extractAge, naturalComparator(i32));
            const byNameLocal = comptime comparatorByField(Person, []const u8, &extractName, &nameCmp);
            return (comptime thenComparing(Person, byAgeLocal, byNameLocal))(a, b) == .lt;
        }
    }.f;
    std.mem.sort(Person, &people, {}, lessThan);
    try std.testing.expectEqualStrings("Bob", people[0].name);
    try std.testing.expectEqualStrings("Alice", people[1].name);
    try std.testing.expectEqualStrings("Carol", people[2].name);
}

test "HashingStrategy struct layout" {
    const S = HashingStrategy(i32);
    const s = S{
        .hashFn = &struct {
            fn h(v: i32) u64 {
                return @as(u64, @intCast(@as(u32, @bitCast(v))));
            }
        }.h,
        .eqlFn = &struct {
            fn e(a: i32, b: i32) bool {
                return a == b;
            }
        }.e,
    };
    try std.testing.expectEqual(@as(u64, 42), s.hashFn(42));
    try std.testing.expect(s.eqlFn(10, 10));
    try std.testing.expect(!s.eqlFn(10, 20));
}
