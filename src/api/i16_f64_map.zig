
const std = @import("std");

/// Comptime interface for read-only maps from `i16` keys to `f64` values.
///
/// Equivalent to:
///   Go:   I16F64MapIterable interface
///   Rust: I16F64Map trait
///   Java: I16F64Map interface
pub fn assertI16F64Map(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `i16` to `f64`.
pub fn assertI16F64MutableMap(comptime T: type) void {
    assertI16F64Map(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `i16` → `f64` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.i16_f64_hash_map.I16F64HashMap;
    assertI16F64MutableMap(HashMap);

    const TreeMap = treemap.i16_f64_tree_map.I16F64TreeMap;
    assertI16F64MutableMap(TreeMap);

    const HashBiMap = hashmap.i16_f64_hash_bi_map.I16F64HashBiMap;
    assertI16F64MutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_i16_f64_hash_map.ImmutableI16F64HashMap;
    assertI16F64Map(ImmutableHashMap);
}
