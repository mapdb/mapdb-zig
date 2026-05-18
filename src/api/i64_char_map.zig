
const std = @import("std");

/// Comptime interface for read-only maps from `i64` keys to `u21` values.
///
/// Equivalent to:
///   Go:   I64CharMapIterable interface
///   Rust: I64CharMap trait
///   Java: I64CharMap interface
pub fn assertI64CharMap(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `i64` to `u21`.
pub fn assertI64CharMutableMap(comptime T: type) void {
    assertI64CharMap(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `i64` → `u21` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations. See docs/zig/interface-redesign.md.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.i64_char_hash_map.I64CharHashMap;
    assertI64CharMutableMap(HashMap);

    const TreeMap = treemap.i64_char_tree_map.I64CharTreeMap;
    assertI64CharMutableMap(TreeMap);

    const HashBiMap = hashmap.i64_char_hash_bi_map.I64CharHashBiMap;
    assertI64CharMutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_i64_char_hash_map.ImmutableI64CharHashMap;
    assertI64CharMap(ImmutableHashMap);
}
