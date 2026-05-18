
const std = @import("std");

/// Comptime interface for read-only maps from `i32` keys to `i8` values.
///
/// Equivalent to:
///   Go:   I32I8MapIterable interface
///   Rust: I32I8Map trait
///   Java: I32I8Map interface
pub fn assertI32I8Map(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `i32` to `i8`.
pub fn assertI32I8MutableMap(comptime T: type) void {
    assertI32I8Map(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `i32` → `i8` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations. See docs/zig/interface-redesign.md.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.i32_i8_hash_map.I32I8HashMap;
    assertI32I8MutableMap(HashMap);

    const TreeMap = treemap.i32_i8_tree_map.I32I8TreeMap;
    assertI32I8MutableMap(TreeMap);

    const HashBiMap = hashmap.i32_i8_hash_bi_map.I32I8HashBiMap;
    assertI32I8MutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_i32_i8_hash_map.ImmutableI32I8HashMap;
    assertI32I8Map(ImmutableHashMap);
}
