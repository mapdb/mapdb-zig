
const std = @import("std");

/// Comptime interface for read-only maps from `i64` keys to `bool` values.
///
/// Equivalent to:
///   Go:   I64BoolMapIterable interface
///   Rust: I64BoolMap trait
///   Java: I64BoolMap interface
pub fn assertI64BoolMap(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `i64` to `bool`.
pub fn assertI64BoolMutableMap(comptime T: type) void {
    assertI64BoolMap(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `i64` → `bool` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.i64_bool_hash_map.I64BoolHashMap;
    assertI64BoolMutableMap(HashMap);

    const TreeMap = treemap.i64_bool_tree_map.I64BoolTreeMap;
    assertI64BoolMutableMap(TreeMap);

    const HashBiMap = hashmap.i64_bool_hash_bi_map.I64BoolHashBiMap;
    assertI64BoolMutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_i64_bool_hash_map.ImmutableI64BoolHashMap;
    assertI64BoolMap(ImmutableHashMap);
}
