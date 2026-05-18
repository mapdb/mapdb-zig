
const std = @import("std");

/// Comptime interface for read-only maps from `u21` keys to `u21` values.
///
/// Equivalent to:
///   Go:   CharCharMapIterable interface
///   Rust: CharCharMap trait
///   Java: CharCharMap interface
pub fn assertCharCharMap(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `u21` to `u21`.
pub fn assertCharCharMutableMap(comptime T: type) void {
    assertCharCharMap(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `u21` → `u21` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations. See docs/zig/interface-redesign.md.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.char_char_hash_map.CharCharHashMap;
    assertCharCharMutableMap(HashMap);

    const TreeMap = treemap.char_char_tree_map.CharCharTreeMap;
    assertCharCharMutableMap(TreeMap);

    const HashBiMap = hashmap.char_char_hash_bi_map.CharCharHashBiMap;
    assertCharCharMutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_char_char_hash_map.ImmutableCharCharHashMap;
    assertCharCharMap(ImmutableHashMap);
}
