
const std = @import("std");

/// Comptime interface for read-only maps from `bool` keys to `i32` values.
///
/// Equivalent to:
///   Go:   BoolI32MapIterable interface
///   Rust: BoolI32Map trait
///   Java: BoolI32Map interface
pub fn assertBoolI32Map(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `bool` to `i32`.
pub fn assertBoolI32MutableMap(comptime T: type) void {
    assertBoolI32Map(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `bool` → `i32` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.bool_i32_hash_map.BoolI32HashMap;
    assertBoolI32MutableMap(HashMap);

    const TreeMap = treemap.bool_i32_tree_map.BoolI32TreeMap;
    assertBoolI32MutableMap(TreeMap);

    const HashBiMap = hashmap.bool_i32_hash_bi_map.BoolI32HashBiMap;
    assertBoolI32MutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_bool_i32_hash_map.ImmutableBoolI32HashMap;
    assertBoolI32Map(ImmutableHashMap);
}
