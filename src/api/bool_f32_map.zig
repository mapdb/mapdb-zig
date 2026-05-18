
const std = @import("std");

/// Comptime interface for read-only maps from `bool` keys to `f32` values.
///
/// Equivalent to:
///   Go:   BoolF32MapIterable interface
///   Rust: BoolF32Map trait
///   Java: BoolF32Map interface
pub fn assertBoolF32Map(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `bool` to `f32`.
pub fn assertBoolF32MutableMap(comptime T: type) void {
    assertBoolF32Map(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `bool` → `f32` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.bool_f32_hash_map.BoolF32HashMap;
    assertBoolF32MutableMap(HashMap);

    const TreeMap = treemap.bool_f32_tree_map.BoolF32TreeMap;
    assertBoolF32MutableMap(TreeMap);

    const HashBiMap = hashmap.bool_f32_hash_bi_map.BoolF32HashBiMap;
    assertBoolF32MutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_bool_f32_hash_map.ImmutableBoolF32HashMap;
    assertBoolF32Map(ImmutableHashMap);
}
