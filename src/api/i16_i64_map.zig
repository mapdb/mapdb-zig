
const std = @import("std");

/// Comptime interface for read-only maps from `i16` keys to `i64` values.
///
/// Equivalent to:
///   Go:   I16I64MapIterable interface
///   Rust: I16I64Map trait
///   Java: I16I64Map interface
pub fn assertI16I64Map(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `i16` to `i64`.
pub fn assertI16I64MutableMap(comptime T: type) void {
    assertI16I64Map(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `i16` → `i64` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.i16_i64_hash_map.I16I64HashMap;
    assertI16I64MutableMap(HashMap);

    const TreeMap = treemap.i16_i64_tree_map.I16I64TreeMap;
    assertI16I64MutableMap(TreeMap);

    const HashBiMap = hashmap.i16_i64_hash_bi_map.I16I64HashBiMap;
    assertI16I64MutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_i16_i64_hash_map.ImmutableI16I64HashMap;
    assertI16I64Map(ImmutableHashMap);
}
