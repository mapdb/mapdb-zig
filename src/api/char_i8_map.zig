
const std = @import("std");

/// Comptime interface for read-only maps from `u21` keys to `i8` values.
///
/// Equivalent to:
///   Go:   CharI8MapIterable interface
///   Rust: CharI8Map trait
///   Java: CharI8Map interface
pub fn assertCharI8Map(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `u21` to `i8`.
pub fn assertCharI8MutableMap(comptime T: type) void {
    assertCharI8Map(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `u21` → `i8` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations. See docs/zig/interface-redesign.md.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.char_i8_hash_map.CharI8HashMap;
    assertCharI8MutableMap(HashMap);

    const TreeMap = treemap.char_i8_tree_map.CharI8TreeMap;
    assertCharI8MutableMap(TreeMap);

    const HashBiMap = hashmap.char_i8_hash_bi_map.CharI8HashBiMap;
    assertCharI8MutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_char_i8_hash_map.ImmutableCharI8HashMap;
    assertCharI8Map(ImmutableHashMap);
}
