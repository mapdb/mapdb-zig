
const std = @import("std");

/// Comptime interface for read-only maps from `i8` keys to `u21` values.
///
/// Equivalent to:
///   Go:   I8CharMapIterable interface
///   Rust: I8CharMap trait
///   Java: I8CharMap interface
pub fn assertI8CharMap(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `i8` to `u21`.
pub fn assertI8CharMutableMap(comptime T: type) void {
    assertI8CharMap(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `i8` → `u21` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.i8_char_hash_map.I8CharHashMap;
    assertI8CharMutableMap(HashMap);

    const TreeMap = treemap.i8_char_tree_map.I8CharTreeMap;
    assertI8CharMutableMap(TreeMap);

    const HashBiMap = hashmap.i8_char_hash_bi_map.I8CharHashBiMap;
    assertI8CharMutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_i8_char_hash_map.ImmutableI8CharHashMap;
    assertI8CharMap(ImmutableHashMap);
}
