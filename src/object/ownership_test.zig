// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Executable documentation of the object-collection ownership contract
//! (fable-review-01 §6): shallow storage, move-out on remove/replace, drain
//! before deinit for owning values, and `getPtr` in-place mutation. Every test
//! uses `std.testing.allocator`, so a double-free crashes and a leak fails —
//! the leak-checker IS the assertion that the contract is followed exactly.

const std = @import("std");
const object = @import("object.zig");
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;

test "object.HashMap(u32,[]u8): shallow move-out contract with owning values" {
    const A = std.testing.allocator;
    var m = object.HashMap(u32, []u8).init(A);
    defer {
        // clear/deinit free structure only — drain owning payloads first.
        var it = m.iterator();
        while (it.next()) |e| A.free(e.value);
        m.deinit();
    }

    try expect(try m.put(1, try A.dupe(u8, "one")) == null);
    try expect(try m.put(2, try A.dupe(u8, "two")) == null);

    // get is a read: the returned slice header aliases map-owned bytes.
    try expectEqualStrings("one", m.get(1).?);

    // put-replace transfers the old value out — caller frees it.
    const old = (try m.put(1, try A.dupe(u8, "uno"))).?;
    A.free(old);
    try expectEqualStrings("uno", m.get(1).?);

    // remove transfers out — caller frees.
    A.free(m.remove(2).?);
    try expect(m.remove(2) == null);
    // key 1 remains and is drained by the defer above.
}

test "object.TreeMap(u32,[]u8): shallow move-out contract with owning values" {
    const A = std.testing.allocator;
    var m = object.TreeMap(u32, []u8).init(A, object.naturalComparator(u32));
    defer {
        var it = m.iterator();
        while (it.next()) |e| A.free(e.value);
        m.deinit();
    }
    try expect(try m.put(10, try A.dupe(u8, "ten")) == null);
    const old = (try m.put(10, try A.dupe(u8, "diez"))).?;
    A.free(old);
    try expectEqualStrings("diez", m.get(10).?);
    A.free(m.remove(10).?);
}

test "object.LinkedHashMap(u32,[]u8): shallow move-out contract with owning values" {
    const A = std.testing.allocator;
    var m = object.LinkedHashMap(u32, []u8).init(A);
    defer {
        var it = m.iterator();
        while (it.next()) |e| A.free(e.value);
        m.deinit();
    }
    try expect(try m.put(5, try A.dupe(u8, "five")) == null);
    A.free(m.remove(5).?);
    try expect(try m.put(6, try A.dupe(u8, "six")) == null); // drained by defer
}

test "getPtr aliases the stored value for in-place mutation" {
    const A = std.testing.allocator;
    {
        var m = object.HashMap(u32, i64).init(A);
        defer m.deinit();
        _ = try m.put(1, 100);
        const p = m.getPtr(1).?;
        p.* += 5;
        try std.testing.expectEqual(@as(?i64, 105), m.get(1));
        try std.testing.expectEqual(@as(?i64, 105), m.getConstPtr(1).?.*);
        try expect(m.getPtr(2) == null);
    }
    {
        var m = object.TreeMap(u32, i64).init(A, object.naturalComparator(u32));
        defer m.deinit();
        _ = try m.put(1, 7);
        m.getPtr(1).?.* = 42;
        try std.testing.expectEqual(@as(?i64, 42), m.get(1));
    }
    {
        var m = object.LinkedHashMap(u32, i64).init(A);
        defer m.deinit();
        _ = try m.put(1, 1);
        m.getPtr(1).?.* = 2;
        try std.testing.expectEqual(@as(?i64, 2), m.get(1));
    }
}
