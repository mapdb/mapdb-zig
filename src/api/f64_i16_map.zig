
const std = @import("std");

/// Comptime interface for read-only maps from `f64` keys to `i16` values.
///
/// Equivalent to:
///   Go:   F64I16MapIterable interface
///   Rust: F64I16Map trait
///   Java: F64I16Map interface
pub fn assertF64I16Map(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `f64` to `i16`.
pub fn assertF64I16MutableMap(comptime T: type) void {
    assertF64I16Map(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `f64` → `i16` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.f64_i16_hash_map.F64I16HashMap;
    assertF64I16MutableMap(HashMap);

    const TreeMap = treemap.f64_i16_tree_map.F64I16TreeMap;
    assertF64I16MutableMap(TreeMap);

    const HashBiMap = hashmap.f64_i16_hash_bi_map.F64I16HashBiMap;
    assertF64I16MutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_f64_i16_hash_map.ImmutableF64I16HashMap;
    assertF64I16Map(ImmutableHashMap);
}
