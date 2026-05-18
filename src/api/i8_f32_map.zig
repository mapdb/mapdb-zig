
const std = @import("std");

/// Comptime interface for read-only maps from `i8` keys to `f32` values.
///
/// Equivalent to:
///   Go:   I8F32MapIterable interface
///   Rust: I8F32Map trait
///   Java: I8F32Map interface
pub fn assertI8F32Map(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `i8` to `f32`.
pub fn assertI8F32MutableMap(comptime T: type) void {
    assertI8F32Map(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `i8` → `f32` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.i8_f32_hash_map.I8F32HashMap;
    assertI8F32MutableMap(HashMap);

    const TreeMap = treemap.i8_f32_tree_map.I8F32TreeMap;
    assertI8F32MutableMap(TreeMap);

    const HashBiMap = hashmap.i8_f32_hash_bi_map.I8F32HashBiMap;
    assertI8F32MutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_i8_f32_hash_map.ImmutableI8F32HashMap;
    assertI8F32Map(ImmutableHashMap);
}
