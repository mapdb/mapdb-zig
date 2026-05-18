
const std = @import("std");

/// Comptime interface for read-only maps from `f32` keys to `bool` values.
///
/// Equivalent to:
///   Go:   F32BoolMapIterable interface
///   Rust: F32BoolMap trait
///   Java: F32BoolMap interface
pub fn assertF32BoolMap(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `f32` to `bool`.
pub fn assertF32BoolMutableMap(comptime T: type) void {
    assertF32BoolMap(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `f32` → `bool` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations. See docs/zig/interface-redesign.md.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.f32_bool_hash_map.F32BoolHashMap;
    assertF32BoolMutableMap(HashMap);

    const TreeMap = treemap.f32_bool_tree_map.F32BoolTreeMap;
    assertF32BoolMutableMap(TreeMap);

    const HashBiMap = hashmap.f32_bool_hash_bi_map.F32BoolHashBiMap;
    assertF32BoolMutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_f32_bool_hash_map.ImmutableF32BoolHashMap;
    assertF32BoolMap(ImmutableHashMap);
}
