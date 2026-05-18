
const std = @import("std");

/// Comptime interface for read-only maps from `u21` keys to `bool` values.
///
/// Equivalent to:
///   Go:   CharBoolMapIterable interface
///   Rust: CharBoolMap trait
///   Java: CharBoolMap interface
pub fn assertCharBoolMap(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `u21` to `bool`.
pub fn assertCharBoolMutableMap(comptime T: type) void {
    assertCharBoolMap(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `u21` → `bool` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.char_bool_hash_map.CharBoolHashMap;
    assertCharBoolMutableMap(HashMap);

    const TreeMap = treemap.char_bool_tree_map.CharBoolTreeMap;
    assertCharBoolMutableMap(TreeMap);

    const HashBiMap = hashmap.char_bool_hash_bi_map.CharBoolHashBiMap;
    assertCharBoolMutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_char_bool_hash_map.ImmutableCharBoolHashMap;
    assertCharBoolMap(ImmutableHashMap);
}
