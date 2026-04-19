// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

// Real-world examples demonstrating HashingStrategy, Comparator, TreeMap, TreeSet.
// These run as regular tests but double as usage documentation.

const std = @import("std");
const object = @import("object.zig");

// ── Example 1: Case-insensitive HTTP headers ──────────────────────────
//
// HTTP header names are case-insensitive per RFC 7230. A plain map would
// treat "Content-Type" and "content-type" as different keys. A
// case-insensitive HashingStrategy fixes that.

fn ciHash(s: []const u8) u64 {
    var h: u64 = 5381;
    for (s) |c| {
        const lower: u8 = if (c >= 'A' and c <= 'Z') c + 32 else c;
        h = ((h << 5) +% h) +% @as(u64, lower);
    }
    return h;
}

fn ciEql(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

test "Example_HTTPHeaders case-insensitive header map" {
    const allocator = std.testing.allocator;
    const strat = object.HashingStrategy([]const u8){
        .hashFn = &ciHash,
        .eqlFn = &ciEql,
    };
    var headers = object.HashMapWithStrategy([]const u8, []const u8).init(allocator, strat);
    defer headers.deinit();

    _ = headers.put("Content-Type", "application/json");
    _ = headers.put("Content-Length", "42");
    _ = headers.put("Authorization", "Bearer xyz");

    // Case-insensitive lookup
    try std.testing.expectEqualStrings("application/json", headers.get("content-type").?);
    try std.testing.expectEqualStrings("Bearer xyz", headers.get("AUTHORIZATION").?);

    // Overwriting with different case
    _ = headers.put("content-TYPE", "text/html");
    try std.testing.expectEqual(@as(usize, 3), headers.len());
    try std.testing.expectEqualStrings("text/html", headers.get("Content-Type").?);
}

// ── Example 2: Leaderboard with TreeMap ───────────────────────────────
//
// TreeMap keyed by score with reverseComparator — highest score first.

test "Example_Leaderboard reverse-ordered TreeMap" {
    const allocator = std.testing.allocator;
    var board = object.TreeMap(i32, []const u8).init(
        allocator,
        object.reverseComparator(i32),
    );
    defer board.deinit();

    _ = board.put(100, "Alice");
    _ = board.put(250, "Bob");
    _ = board.put(175, "Charlie");
    _ = board.put(50, "Dave");

    // Under reverse comparator, min() returns the highest score.
    const top = board.min().?;
    try std.testing.expectEqual(@as(i32, 250), top.key);
    try std.testing.expectEqualStrings("Bob", top.value);

    // Iterate in rank order (descending score).
    const values = board.valuesToSlice(allocator);
    defer allocator.free(values);

    try std.testing.expectEqual(@as(usize, 4), values.len);
    try std.testing.expectEqualStrings("Bob", values[0]);
    try std.testing.expectEqualStrings("Charlie", values[1]);
    try std.testing.expectEqualStrings("Alice", values[2]);
    try std.testing.expectEqualStrings("Dave", values[3]);
}

// ── Example 3: SortedByField — TreeSet of Person sorted by age ────────

const Person = struct {
    name: []const u8,
    age: i32,
};

fn cmpByAge(a: Person, b: Person) std.math.Order {
    return std.math.order(a.age, b.age);
}

test "Example_SortedByField TreeSet sorted by age" {
    const allocator = std.testing.allocator;
    var set = object.TreeSet(Person).init(allocator, &cmpByAge);
    defer set.deinit();

    _ = set.add(.{ .name = "Charlie", .age = 42 });
    _ = set.add(.{ .name = "Alice", .age = 25 });
    _ = set.add(.{ .name = "Bob", .age = 33 });
    _ = set.add(.{ .name = "Dave", .age = 19 });

    const sorted = set.toSlice(allocator);
    defer allocator.free(sorted);

    try std.testing.expectEqual(@as(usize, 4), sorted.len);
    try std.testing.expectEqualStrings("Dave", sorted[0].name);
    try std.testing.expectEqualStrings("Alice", sorted[1].name);
    try std.testing.expectEqualStrings("Bob", sorted[2].name);
    try std.testing.expectEqualStrings("Charlie", sorted[3].name);
}

// ── Example 4: RangeQuery — TreeMap of timestamps → events ────────────

test "Example_RangeQuery TreeMap chronological iteration" {
    const allocator = std.testing.allocator;
    var events = object.TreeMap(i64, []const u8).init(
        allocator,
        object.naturalComparator(i64),
    );
    defer events.deinit();

    // Insert 10 events out of order.
    _ = events.put(1700, "login");
    _ = events.put(1500, "boot");
    _ = events.put(1900, "logout");
    _ = events.put(1600, "load-config");
    _ = events.put(1800, "action");
    _ = events.put(1550, "handshake");
    _ = events.put(1750, "query");
    _ = events.put(1650, "auth");
    _ = events.put(1850, "write");
    _ = events.put(1950, "shutdown");

    try std.testing.expectEqual(@as(usize, 10), events.len());

    const keys = events.keysToSlice(allocator);
    defer allocator.free(keys);

    // Verify strictly ascending chronological order.
    var i: usize = 1;
    while (i < keys.len) : (i += 1) {
        try std.testing.expect(keys[i - 1] < keys[i]);
    }

    try std.testing.expectEqual(@as(i64, 1500), events.min().?.key);
    try std.testing.expectEqual(@as(i64, 1950), events.max().?.key);
}

// ── Example 5: DeduplicationByField — unique Person by name ───────────
//
// Two Persons are "the same" if their names match, regardless of age.

fn personByNameHash(p: Person) u64 {
    var h: u64 = 5381;
    for (p.name) |c| {
        h = ((h << 5) +% h) +% @as(u64, c);
    }
    return h;
}

fn personByNameEql(a: Person, b: Person) bool {
    return std.mem.eql(u8, a.name, b.name);
}

test "Example_DeduplicationByField HashSet unique by name" {
    const allocator = std.testing.allocator;
    const strat = object.HashingStrategy(Person){
        .hashFn = &personByNameHash,
        .eqlFn = &personByNameEql,
    };
    var unique = object.HashSetWithStrategy(Person).init(allocator, strat);
    defer unique.deinit();

    _ = unique.add(.{ .name = "Alice", .age = 25 });
    _ = unique.add(.{ .name = "Alice", .age = 99 }); // duplicate by name
    _ = unique.add(.{ .name = "Bob", .age = 33 });

    try std.testing.expectEqual(@as(usize, 2), unique.len());
    try std.testing.expect(unique.contains(.{ .name = "Alice", .age = 0 }));
    try std.testing.expect(unique.contains(.{ .name = "Bob", .age = 0 }));
}
