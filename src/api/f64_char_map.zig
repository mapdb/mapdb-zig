
const std = @import("std");

/// Comptime interface for read-only maps from `f64` keys to `u21` values.
///
/// Equivalent to:
///   Go:   F64CharMapIterable interface
///   Rust: F64CharMap trait
///   Java: F64CharMap interface
pub fn assertF64CharMap(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `f64` to `u21`.
pub fn assertF64CharMutableMap(comptime T: type) void {
    assertF64CharMap(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `f64` → `u21` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations. See docs/zig/interface-redesign.md.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.f64_char_hash_map.F64CharHashMap;
    assertF64CharMutableMap(HashMap);

    const TreeMap = treemap.f64_char_tree_map.F64CharTreeMap;
    assertF64CharMutableMap(TreeMap);

    const HashBiMap = hashmap.f64_char_hash_bi_map.F64CharHashBiMap;
    assertF64CharMutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_f64_char_hash_map.ImmutableF64CharHashMap;
    assertF64CharMap(ImmutableHashMap);
}
