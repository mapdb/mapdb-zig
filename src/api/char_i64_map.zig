
const std = @import("std");

/// Comptime interface for read-only maps from `u21` keys to `i64` values.
///
/// Equivalent to:
///   Go:   CharI64MapIterable interface
///   Rust: CharI64Map trait
///   Java: CharI64Map interface
pub fn assertCharI64Map(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `u21` to `i64`.
pub fn assertCharI64MutableMap(comptime T: type) void {
    assertCharI64Map(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `u21` → `i64` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.char_i64_hash_map.CharI64HashMap;
    assertCharI64MutableMap(HashMap);

    const TreeMap = treemap.char_i64_tree_map.CharI64TreeMap;
    assertCharI64MutableMap(TreeMap);

    const HashBiMap = hashmap.char_i64_hash_bi_map.CharI64HashBiMap;
    assertCharI64MutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_char_i64_hash_map.ImmutableCharI64HashMap;
    assertCharI64Map(ImmutableHashMap);
}
