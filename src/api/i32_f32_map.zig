// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Comptime interface for read-only maps from `i32` keys to `f32` values.
///
/// Equivalent to:
///   Go:   I32F32MapIterable interface
///   Rust: I32F32Map trait
///   Java: I32F32Map interface
pub fn assertI32F32Map(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `i32` to `f32`.
pub fn assertI32F32MutableMap(comptime T: type) void {
    assertI32F32Map(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `i32` → `f32` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.i32_f32_hash_map.I32F32HashMap;
    assertI32F32MutableMap(HashMap);

    const TreeMap = treemap.i32_f32_tree_map.I32F32TreeMap;
    assertI32F32MutableMap(TreeMap);

    const HashBiMap = hashmap.i32_f32_hash_bi_map.I32F32HashBiMap;
    assertI32F32MutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_i32_f32_hash_map.ImmutableI32F32HashMap;
    assertI32F32Map(ImmutableHashMap);
}
