// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Float keys in the object-tier hash collections obey bit-pattern identity
//! (spec algorithms.md, "NaN must hash and compare by bit pattern"): NaN is
//! findable, put(NaN) replaces, remove(NaN) works, ±0 are two keys, ±Inf are
//! two keys, and distinct NaN payloads are distinct keys.

const std = @import("std");
const testing = std.testing;
const HashMap = @import("hashmap.zig").HashMap;
const HashSet = @import("hashset.zig").HashSet;
const HashBag = @import("hashbag.zig").HashBag;
const HashBiMap = @import("hashbimap.zig").HashBiMap;
const LinkedHashMap = @import("linkedhashmap.zig").LinkedHashMap;
const LinkedHashSet = @import("linkedhashset.zig").LinkedHashSet;

fn nanA(comptime F: type) F {
    return if (F == f32) @bitCast(@as(u32, 0x7FC00000)) else @bitCast(@as(u64, 0x7FF8000000000000));
}

fn nanB(comptime F: type) F {
    return if (F == f32) @bitCast(@as(u32, 0x7FC00001)) else @bitCast(@as(u64, 0x7FF8000000000001));
}

// ── HashMap ─────────────────────────────────────────────────────────────

fn mapNaNKeyFindable(comptime F: type) !void {
    var m = HashMap(F, i32).init(testing.allocator);
    defer m.deinit();
    try testing.expectEqual(@as(?i32, null), try m.put(std.math.nan(F), 7));
    try testing.expectEqual(@as(usize, 1), m.len());
    try testing.expect(m.containsKey(std.math.nan(F)));
    try testing.expectEqual(@as(?i32, 7), m.get(std.math.nan(F)));
}

fn mapNaNKeyReplaces(comptime F: type) !void {
    var m = HashMap(F, i32).init(testing.allocator);
    defer m.deinit();
    _ = try m.put(std.math.nan(F), 1);
    try testing.expectEqual(@as(?i32, 1), try m.put(std.math.nan(F), 2));
    try testing.expectEqual(@as(usize, 1), m.len());
    try testing.expectEqual(@as(?i32, 2), m.get(std.math.nan(F)));
}

fn mapNaNKeyRemove(comptime F: type) !void {
    var m = HashMap(F, i32).init(testing.allocator);
    defer m.deinit();
    _ = try m.put(std.math.nan(F), 1);
    _ = try m.put(1.0, 2);
    try testing.expectEqual(@as(?i32, 1), m.remove(std.math.nan(F)));
    try testing.expectEqual(@as(usize, 1), m.len());
    try testing.expect(!m.containsKey(std.math.nan(F)));
    try testing.expectEqual(@as(?i32, null), m.remove(std.math.nan(F)));
    try testing.expectEqual(@as(usize, 1), m.len());
}

fn mapNegativeZeroDistinct(comptime F: type) !void {
    var m = HashMap(F, i32).init(testing.allocator);
    defer m.deinit();
    _ = try m.put(0.0, 1);
    try testing.expectEqual(@as(usize, 1), m.len());
    try testing.expect(!m.containsKey(-0.0));
    _ = try m.put(-0.0, 2);
    try testing.expectEqual(@as(usize, 2), m.len());
    try testing.expectEqual(@as(?i32, 1), m.get(0.0));
    try testing.expectEqual(@as(?i32, 2), m.get(-0.0));
    try testing.expectEqual(@as(?i32, 2), m.remove(-0.0));
    try testing.expectEqual(@as(usize, 1), m.len());
    try testing.expectEqual(@as(?i32, 1), m.get(0.0));
}

fn mapInfinityKeys(comptime F: type) !void {
    var m = HashMap(F, i32).init(testing.allocator);
    defer m.deinit();
    _ = try m.put(std.math.inf(F), 1);
    _ = try m.put(-std.math.inf(F), 2);
    try testing.expectEqual(@as(usize, 2), m.len());
    try testing.expectEqual(@as(?i32, 1), m.get(std.math.inf(F)));
    try testing.expectEqual(@as(?i32, 2), m.get(-std.math.inf(F)));
    try testing.expectEqual(@as(?i32, 1), try m.put(std.math.inf(F), 3));
    try testing.expectEqual(@as(usize, 2), m.len());
    try testing.expectEqual(@as(?i32, 2), m.remove(-std.math.inf(F)));
    try testing.expectEqual(@as(usize, 1), m.len());
}

fn mapNaNPayloadsDistinct(comptime F: type) !void {
    var m = HashMap(F, i32).init(testing.allocator);
    defer m.deinit();
    _ = try m.put(nanA(F), 1);
    try testing.expectEqual(@as(usize, 1), m.len());
    try testing.expect(!m.containsKey(nanB(F)));
    _ = try m.put(nanB(F), 2);
    try testing.expectEqual(@as(usize, 2), m.len());
    try testing.expectEqual(@as(?i32, 1), m.get(nanA(F)));
    try testing.expectEqual(@as(?i32, 2), m.get(nanB(F)));
    try testing.expectEqual(@as(?i32, 1), m.remove(nanA(F)));
    try testing.expectEqual(@as(usize, 1), m.len());
    try testing.expectEqual(@as(?i32, 2), m.get(nanB(F)));
}

test "object HashMap f32: NaNKey_Findable" {
    try mapNaNKeyFindable(f32);
}
test "object HashMap f64: NaNKey_Findable" {
    try mapNaNKeyFindable(f64);
}
test "object HashMap f32: NaNKey_Replaces" {
    try mapNaNKeyReplaces(f32);
}
test "object HashMap f64: NaNKey_Replaces" {
    try mapNaNKeyReplaces(f64);
}
test "object HashMap f32: NaNKey_Remove" {
    try mapNaNKeyRemove(f32);
}
test "object HashMap f64: NaNKey_Remove" {
    try mapNaNKeyRemove(f64);
}
test "object HashMap f32: NegativeZeroDistinct" {
    try mapNegativeZeroDistinct(f32);
}
test "object HashMap f64: NegativeZeroDistinct" {
    try mapNegativeZeroDistinct(f64);
}
test "object HashMap f32: InfinityKeys" {
    try mapInfinityKeys(f32);
}
test "object HashMap f64: InfinityKeys" {
    try mapInfinityKeys(f64);
}
test "object HashMap f32: NaNPayloadsDistinct" {
    try mapNaNPayloadsDistinct(f32);
}
test "object HashMap f64: NaNPayloadsDistinct" {
    try mapNaNPayloadsDistinct(f64);
}

// ── HashSet ─────────────────────────────────────────────────────────────

fn setNaNKeyFindable(comptime F: type) !void {
    var s = HashSet(F).init(testing.allocator);
    defer s.deinit();
    try testing.expect(try s.add(std.math.nan(F)));
    try testing.expectEqual(@as(usize, 1), s.len());
    try testing.expect(s.contains(std.math.nan(F)));
}

fn setNaNKeyReplaces(comptime F: type) !void {
    var s = HashSet(F).init(testing.allocator);
    defer s.deinit();
    try testing.expect(try s.add(std.math.nan(F)));
    try testing.expect(!try s.add(std.math.nan(F)));
    try testing.expectEqual(@as(usize, 1), s.len());
}

fn setNaNKeyRemove(comptime F: type) !void {
    var s = HashSet(F).init(testing.allocator);
    defer s.deinit();
    _ = try s.add(std.math.nan(F));
    _ = try s.add(1.0);
    try testing.expect(s.remove(std.math.nan(F)));
    try testing.expectEqual(@as(usize, 1), s.len());
    try testing.expect(!s.contains(std.math.nan(F)));
    try testing.expect(!s.remove(std.math.nan(F)));
    try testing.expectEqual(@as(usize, 1), s.len());
}

fn setNegativeZeroDistinct(comptime F: type) !void {
    var s = HashSet(F).init(testing.allocator);
    defer s.deinit();
    try testing.expect(try s.add(0.0));
    try testing.expect(!s.contains(-0.0));
    try testing.expect(try s.add(-0.0));
    try testing.expectEqual(@as(usize, 2), s.len());
    try testing.expect(s.remove(-0.0));
    try testing.expectEqual(@as(usize, 1), s.len());
    try testing.expect(s.contains(0.0));
}

fn setInfinityKeys(comptime F: type) !void {
    var s = HashSet(F).init(testing.allocator);
    defer s.deinit();
    try testing.expect(try s.add(std.math.inf(F)));
    try testing.expect(try s.add(-std.math.inf(F)));
    try testing.expect(!try s.add(std.math.inf(F)));
    try testing.expectEqual(@as(usize, 2), s.len());
    try testing.expect(s.remove(std.math.inf(F)));
    try testing.expectEqual(@as(usize, 1), s.len());
    try testing.expect(s.contains(-std.math.inf(F)));
}

fn setNaNPayloadsDistinct(comptime F: type) !void {
    var s = HashSet(F).init(testing.allocator);
    defer s.deinit();
    try testing.expect(try s.add(nanA(F)));
    try testing.expect(!s.contains(nanB(F)));
    try testing.expect(try s.add(nanB(F)));
    try testing.expectEqual(@as(usize, 2), s.len());
    try testing.expect(s.remove(nanA(F)));
    try testing.expectEqual(@as(usize, 1), s.len());
    try testing.expect(s.contains(nanB(F)));
}

test "object HashSet f32: NaNKey_Findable" {
    try setNaNKeyFindable(f32);
}
test "object HashSet f64: NaNKey_Findable" {
    try setNaNKeyFindable(f64);
}
test "object HashSet f32: NaNKey_Replaces" {
    try setNaNKeyReplaces(f32);
}
test "object HashSet f64: NaNKey_Replaces" {
    try setNaNKeyReplaces(f64);
}
test "object HashSet f32: NaNKey_Remove" {
    try setNaNKeyRemove(f32);
}
test "object HashSet f64: NaNKey_Remove" {
    try setNaNKeyRemove(f64);
}
test "object HashSet f32: NegativeZeroDistinct" {
    try setNegativeZeroDistinct(f32);
}
test "object HashSet f64: NegativeZeroDistinct" {
    try setNegativeZeroDistinct(f64);
}
test "object HashSet f32: InfinityKeys" {
    try setInfinityKeys(f32);
}
test "object HashSet f64: InfinityKeys" {
    try setInfinityKeys(f64);
}
test "object HashSet f32: NaNPayloadsDistinct" {
    try setNaNPayloadsDistinct(f32);
}
test "object HashSet f64: NaNPayloadsDistinct" {
    try setNaNPayloadsDistinct(f64);
}

// ── Other object hash collections sharing the key context ───────────────

test "object HashBag f32: NaN and signed-zero identity" {
    var b = HashBag(f32).init(testing.allocator);
    defer b.deinit();
    try b.add(std.math.nan(f32));
    try b.add(std.math.nan(f32));
    try b.add(nanB(f32));
    try b.add(0.0);
    try b.add(-0.0);
    try testing.expectEqual(@as(usize, 2), b.occurrencesOf(std.math.nan(f32)));
    try testing.expectEqual(@as(usize, 4), b.sizeDistinct());
    try testing.expectEqual(@as(usize, 5), b.len());
    try testing.expect(b.removeOne(std.math.nan(f32)));
    try testing.expectEqual(@as(usize, 1), b.occurrencesOf(std.math.nan(f32)));
}

test "object HashBiMap f64: float keys and float values by bit pattern" {
    var m = HashBiMap(f64, f64).init(testing.allocator);
    defer m.deinit();
    _ = try m.put(std.math.nan(f64), -0.0);
    _ = try m.put(-0.0, std.math.nan(f64));
    try testing.expectEqual(@as(usize, 2), m.len());
    try testing.expect(m.containsKey(std.math.nan(f64)));
    try testing.expect(m.containsValue(std.math.nan(f64)));
    try testing.expect(!m.containsValue(0.0));
    try testing.expectEqual(@as(u64, @bitCast(@as(f64, -0.0))), @as(u64, @bitCast(m.get(std.math.nan(f64)).?)));
    try testing.expect(m.remove(std.math.nan(f64)) != null);
    try testing.expectEqual(@as(usize, 1), m.len());
    try testing.expect(!m.containsValue(-0.0));
}

test "object LinkedHashMap f32: NaN, ±0 and NaN payloads by bit pattern" {
    var m = LinkedHashMap(f32, i32).init(testing.allocator);
    defer m.deinit();
    _ = try m.put(std.math.nan(f32), 1);
    try testing.expectEqual(@as(?i32, 1), try m.put(std.math.nan(f32), 2));
    _ = try m.put(nanB(f32), 3);
    _ = try m.put(0.0, 4);
    _ = try m.put(-0.0, 5);
    try testing.expectEqual(@as(usize, 4), m.len());
    try testing.expectEqual(@as(?i32, 2), m.get(std.math.nan(f32)));
    try testing.expectEqual(@as(?i32, 5), m.get(-0.0));
    try testing.expectEqual(@as(?i32, 2), m.remove(std.math.nan(f32)));
    try testing.expectEqual(@as(usize, 3), m.len());
}

test "object LinkedHashSet f64: NaN, ±0 and NaN payloads by bit pattern" {
    var s = LinkedHashSet(f64).init(testing.allocator);
    defer s.deinit();
    try testing.expect(try s.add(std.math.nan(f64)));
    try testing.expect(!try s.add(std.math.nan(f64)));
    try testing.expect(try s.add(nanB(f64)));
    try testing.expect(try s.add(0.0));
    try testing.expect(try s.add(-0.0));
    try testing.expectEqual(@as(usize, 4), s.len());
    try testing.expect(s.remove(std.math.nan(f64)));
    try testing.expect(!s.contains(std.math.nan(f64)));
    try testing.expectEqual(@as(usize, 3), s.len());
}
