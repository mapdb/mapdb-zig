// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Comptime interface for read-only maps from `f64` keys to `i8` values.
///
/// Equivalent to:
///   Go:   F64I8MapIterable interface
///   Rust: F64I8Map trait
///   Java: F64I8Map interface
pub fn assertF64I8Map(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `f64` to `i8`.
pub fn assertF64I8MutableMap(comptime T: type) void {
    assertF64I8Map(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `f64` → `i8` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.f64_i8_hash_map.F64I8HashMap;
    assertF64I8MutableMap(HashMap);

    const TreeMap = treemap.f64_i8_tree_map.F64I8TreeMap;
    assertF64I8MutableMap(TreeMap);

    const HashBiMap = hashmap.f64_i8_hash_bi_map.F64I8HashBiMap;
    assertF64I8MutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_f64_i8_hash_map.ImmutableF64I8HashMap;
    assertF64I8Map(ImmutableHashMap);
}
