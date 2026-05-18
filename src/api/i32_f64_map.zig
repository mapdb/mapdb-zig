// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Comptime interface for read-only maps from `i32` keys to `f64` values.
///
/// Equivalent to:
///   Go:   I32F64MapIterable interface
///   Rust: I32F64Map trait
///   Java: I32F64Map interface
pub fn assertI32F64Map(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `i32` to `f64`.
pub fn assertI32F64MutableMap(comptime T: type) void {
    assertI32F64Map(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `i32` → `f64` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.i32_f64_hash_map.I32F64HashMap;
    assertI32F64MutableMap(HashMap);

    const TreeMap = treemap.i32_f64_tree_map.I32F64TreeMap;
    assertI32F64MutableMap(TreeMap);

    const HashBiMap = hashmap.i32_f64_hash_bi_map.I32F64HashBiMap;
    assertI32F64MutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_i32_f64_hash_map.ImmutableI32F64HashMap;
    assertI32F64Map(ImmutableHashMap);
}
