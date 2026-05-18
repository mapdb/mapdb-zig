
const std = @import("std");

/// Comptime interface for read-only maps from `i32` keys to `bool` values.
///
/// Equivalent to:
///   Go:   I32BoolMapIterable interface
///   Rust: I32BoolMap trait
///   Java: I32BoolMap interface
pub fn assertI32BoolMap(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `i32` to `bool`.
pub fn assertI32BoolMutableMap(comptime T: type) void {
    assertI32BoolMap(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `i32` → `bool` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.i32_bool_hash_map.I32BoolHashMap;
    assertI32BoolMutableMap(HashMap);

    const TreeMap = treemap.i32_bool_tree_map.I32BoolTreeMap;
    assertI32BoolMutableMap(TreeMap);

    const HashBiMap = hashmap.i32_bool_hash_bi_map.I32BoolHashBiMap;
    assertI32BoolMutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_i32_bool_hash_map.ImmutableI32BoolHashMap;
    assertI32BoolMap(ImmutableHashMap);
}
