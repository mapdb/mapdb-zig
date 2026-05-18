
const std = @import("std");

/// Comptime interface for read-only maps from `i16` keys to `i32` values.
///
/// Equivalent to:
///   Go:   I16I32MapIterable interface
///   Rust: I16I32Map trait
///   Java: I16I32Map interface
pub fn assertI16I32Map(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `i16` to `i32`.
pub fn assertI16I32MutableMap(comptime T: type) void {
    assertI16I32Map(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `i16` → `i32` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations. See docs/zig/interface-redesign.md.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.i16_i32_hash_map.I16I32HashMap;
    assertI16I32MutableMap(HashMap);

    const TreeMap = treemap.i16_i32_tree_map.I16I32TreeMap;
    assertI16I32MutableMap(TreeMap);

    const HashBiMap = hashmap.i16_i32_hash_bi_map.I16I32HashBiMap;
    assertI16I32MutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_i16_i32_hash_map.ImmutableI16I32HashMap;
    assertI16I32Map(ImmutableHashMap);
}
