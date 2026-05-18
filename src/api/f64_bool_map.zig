
const std = @import("std");

/// Comptime interface for read-only maps from `f64` keys to `bool` values.
///
/// Equivalent to:
///   Go:   F64BoolMapIterable interface
///   Rust: F64BoolMap trait
///   Java: F64BoolMap interface
pub fn assertF64BoolMap(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `f64` to `bool`.
pub fn assertF64BoolMutableMap(comptime T: type) void {
    assertF64BoolMap(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `f64` → `bool` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations. See docs/zig/interface-redesign.md.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.f64_bool_hash_map.F64BoolHashMap;
    assertF64BoolMutableMap(HashMap);

    const TreeMap = treemap.f64_bool_tree_map.F64BoolTreeMap;
    assertF64BoolMutableMap(TreeMap);

    const HashBiMap = hashmap.f64_bool_hash_bi_map.F64BoolHashBiMap;
    assertF64BoolMutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_f64_bool_hash_map.ImmutableF64BoolHashMap;
    assertF64BoolMap(ImmutableHashMap);
}
