
const std = @import("std");

/// Comptime interface for read-only maps from `i16` keys to `bool` values.
///
/// Equivalent to:
///   Go:   I16BoolMapIterable interface
///   Rust: I16BoolMap trait
///   Java: I16BoolMap interface
pub fn assertI16BoolMap(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `i16` to `bool`.
pub fn assertI16BoolMutableMap(comptime T: type) void {
    assertI16BoolMap(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `i16` → `bool` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations. See docs/zig/interface-redesign.md.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.i16_bool_hash_map.I16BoolHashMap;
    assertI16BoolMutableMap(HashMap);

    const TreeMap = treemap.i16_bool_tree_map.I16BoolTreeMap;
    assertI16BoolMutableMap(TreeMap);

    const HashBiMap = hashmap.i16_bool_hash_bi_map.I16BoolHashBiMap;
    assertI16BoolMutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_i16_bool_hash_map.ImmutableI16BoolHashMap;
    assertI16BoolMap(ImmutableHashMap);
}
