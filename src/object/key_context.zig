// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Key contexts for the object-tier hash collections (`HashMap`, `HashSet`,
//! `HashBag`, `HashBiMap`, `LinkedHashMap`, `LinkedHashSet`).
//!
//! These collections are backed by `std.HashMapUnmanaged` /
//! `std.ArrayHashMapUnmanaged`. For every non-float key type the context is
//! exactly the std `AutoContext(K)` the collections used before, so hashing,
//! equality and the resulting map type are unchanged. For float key types the
//! std auto context does not compile (`std.hash.autoHash` rejects `.float`),
//! so a float key is identified by its **bit pattern** (spec algorithms.md,
//! "NaN must hash and compare by bit pattern"): NaN is findable and replaces
//! itself, distinct NaN payloads are distinct keys, and +0.0 / -0.0 are two
//! keys. The float hash is the port's 64-bit Fibonacci hash
//! (`hash_table.hashKey`) over the same-width unsigned bit pattern.

const std = @import("std");
const hash_table = @import("../hash_table.zig");

fn isFloat(comptime K: type) bool {
    return @typeInfo(K) == .float;
}

fn Bits(comptime K: type) type {
    return std.meta.Int(.unsigned, @bitSizeOf(K));
}

inline fn floatHash(comptime K: type, key: K) u64 {
    return hash_table.hashKey(Bits(K), @bitCast(key));
}

inline fn floatEql(comptime K: type, a: K, b: K) bool {
    return @as(Bits(K), @bitCast(a)) == @as(Bits(K), @bitCast(b));
}

/// Bit-pattern context for float keys in `std.HashMapUnmanaged`.
fn FloatContext(comptime K: type) type {
    return struct {
        pub fn hash(_: @This(), key: K) u64 {
            return floatHash(K, key);
        }
        pub fn eql(_: @This(), a: K, b: K) bool {
            return floatEql(K, a, b);
        }
    };
}

/// Bit-pattern context for float keys in `std.ArrayHashMapUnmanaged`.
fn FloatArrayContext(comptime K: type) type {
    return struct {
        pub fn hash(_: @This(), key: K) u32 {
            return @truncate(floatHash(K, key));
        }
        pub fn eql(_: @This(), a: K, b: K, _: usize) bool {
            return floatEql(K, a, b);
        }
    };
}

/// `std.HashMapUnmanaged` context: bit-pattern identity for float `K`,
/// `std.hash_map.AutoContext(K)` otherwise.
pub fn HashContext(comptime K: type) type {
    return if (isFloat(K)) FloatContext(K) else std.hash_map.AutoContext(K);
}

/// `std.ArrayHashMapUnmanaged` context: bit-pattern identity for float `K`,
/// `std.array_hash_map.AutoContext(K)` otherwise.
pub fn ArrayHashContext(comptime K: type) type {
    return if (isFloat(K)) FloatArrayContext(K) else std.array_hash_map.AutoContext(K);
}

/// Drop-in for `std.AutoHashMapUnmanaged(K, V)` that also accepts float keys.
/// Identical type to the std alias for every non-float `K`.
pub fn AutoHashMapUnmanaged(comptime K: type, comptime V: type) type {
    return std.HashMapUnmanaged(K, V, HashContext(K), std.hash_map.default_max_load_percentage);
}

/// Drop-in for `std.AutoArrayHashMapUnmanaged(K, V)` that also accepts float
/// keys. Identical type to the std alias for every non-float `K`.
pub fn AutoArrayHashMapUnmanaged(comptime K: type, comptime V: type) type {
    return std.ArrayHashMapUnmanaged(K, V, ArrayHashContext(K), !std.array_hash_map.autoEqlIsCheap(K));
}

test "non-float keys keep the exact std map types" {
    try std.testing.expect(AutoHashMapUnmanaged(i32, u8) == std.AutoHashMapUnmanaged(i32, u8));
    try std.testing.expect(AutoHashMapUnmanaged([]const u8, void) == std.AutoHashMapUnmanaged([]const u8, void));
    try std.testing.expect(AutoArrayHashMapUnmanaged(u64, i32) == std.AutoArrayHashMapUnmanaged(u64, i32));
}

test "float context: bit-pattern hash and equality" {
    const C = HashContext(f32);
    const nan1: f32 = @bitCast(@as(u32, 0x7FC00000));
    const nan2: f32 = @bitCast(@as(u32, 0x7FC00001));
    try std.testing.expect(C.eql(.{}, nan1, nan1));
    try std.testing.expect(!C.eql(.{}, nan1, nan2));
    try std.testing.expect(!C.eql(.{}, 0.0, -0.0));
    try std.testing.expectEqual(C.hash(.{}, nan1), C.hash(.{}, nan1));
    try std.testing.expectEqual(hash_table.hashKey(f32, nan1), C.hash(.{}, nan1));
    const D = HashContext(f64);
    try std.testing.expectEqual(hash_table.hashKey(f64, -0.0), D.hash(.{}, -0.0));
}
