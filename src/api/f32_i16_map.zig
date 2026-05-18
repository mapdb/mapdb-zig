
const std = @import("std");

/// Comptime interface for read-only maps from `f32` keys to `i16` values.
///
/// Equivalent to:
///   Go:   F32I16MapIterable interface
///   Rust: F32I16Map trait
///   Java: F32I16Map interface
pub fn assertF32I16Map(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `f32` to `i16`.
pub fn assertF32I16MutableMap(comptime T: type) void {
    assertF32I16Map(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `f32` → `i16` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.f32_i16_hash_map.F32I16HashMap;
    assertF32I16MutableMap(HashMap);

    const TreeMap = treemap.f32_i16_tree_map.F32I16TreeMap;
    assertF32I16MutableMap(TreeMap);

    const HashBiMap = hashmap.f32_i16_hash_bi_map.F32I16HashBiMap;
    assertF32I16MutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_f32_i16_hash_map.ImmutableF32I16HashMap;
    assertF32I16Map(ImmutableHashMap);
}
