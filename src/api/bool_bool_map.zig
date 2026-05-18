
const std = @import("std");

/// Comptime interface for read-only maps from `bool` keys to `bool` values.
///
/// Equivalent to:
///   Go:   BoolBoolMapIterable interface
///   Rust: BoolBoolMap trait
///   Java: BoolBoolMap interface
pub fn assertBoolBoolMap(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `bool` to `bool`.
pub fn assertBoolBoolMutableMap(comptime T: type) void {
    assertBoolBoolMap(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `bool` → `bool` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations. See docs/zig/interface-redesign.md.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.bool_bool_hash_map.BoolBoolHashMap;
    assertBoolBoolMutableMap(HashMap);

    const TreeMap = treemap.bool_bool_tree_map.BoolBoolTreeMap;
    assertBoolBoolMutableMap(TreeMap);

    const HashBiMap = hashmap.bool_bool_hash_bi_map.BoolBoolHashBiMap;
    assertBoolBoolMutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_bool_bool_hash_map.ImmutableBoolBoolHashMap;
    assertBoolBoolMap(ImmutableHashMap);
}
