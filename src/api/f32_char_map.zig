
const std = @import("std");

/// Comptime interface for read-only maps from `f32` keys to `u21` values.
///
/// Equivalent to:
///   Go:   F32CharMapIterable interface
///   Rust: F32CharMap trait
///   Java: F32CharMap interface
pub fn assertF32CharMap(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `f32` to `u21`.
pub fn assertF32CharMutableMap(comptime T: type) void {
    assertF32CharMap(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `f32` → `u21` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations. See docs/zig/interface-redesign.md.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.f32_char_hash_map.F32CharHashMap;
    assertF32CharMutableMap(HashMap);

    const TreeMap = treemap.f32_char_tree_map.F32CharTreeMap;
    assertF32CharMutableMap(TreeMap);

    const HashBiMap = hashmap.f32_char_hash_bi_map.F32CharHashBiMap;
    assertF32CharMutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_f32_char_hash_map.ImmutableF32CharHashMap;
    assertF32CharMap(ImmutableHashMap);
}
