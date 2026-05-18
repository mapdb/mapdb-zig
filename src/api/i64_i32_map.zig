
const std = @import("std");

/// Comptime interface for read-only maps from `i64` keys to `i32` values.
///
/// Equivalent to:
///   Go:   I64I32MapIterable interface
///   Rust: I64I32Map trait
///   Java: I64I32Map interface
pub fn assertI64I32Map(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `i64` to `i32`.
pub fn assertI64I32MutableMap(comptime T: type) void {
    assertI64I32Map(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `i64` → `i32` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.i64_i32_hash_map.I64I32HashMap;
    assertI64I32MutableMap(HashMap);

    const TreeMap = treemap.i64_i32_tree_map.I64I32TreeMap;
    assertI64I32MutableMap(TreeMap);

    const HashBiMap = hashmap.i64_i32_hash_bi_map.I64I32HashBiMap;
    assertI64I32MutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_i64_i32_hash_map.ImmutableI64I32HashMap;
    assertI64I32Map(ImmutableHashMap);
}
