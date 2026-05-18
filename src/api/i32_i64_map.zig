
const std = @import("std");

/// Comptime interface for read-only maps from `i32` keys to `i64` values.
///
/// Equivalent to:
///   Go:   I32I64MapIterable interface
///   Rust: I32I64Map trait
///   Java: I32I64Map interface
pub fn assertI32I64Map(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `i32` to `i64`.
pub fn assertI32I64MutableMap(comptime T: type) void {
    assertI32I64Map(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `i32` → `i64` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.i32_i64_hash_map.I32I64HashMap;
    assertI32I64MutableMap(HashMap);

    const TreeMap = treemap.i32_i64_tree_map.I32I64TreeMap;
    assertI32I64MutableMap(TreeMap);

    const HashBiMap = hashmap.i32_i64_hash_bi_map.I32I64HashBiMap;
    assertI32I64MutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_i32_i64_hash_map.ImmutableI32I64HashMap;
    assertI32I64Map(ImmutableHashMap);
}
