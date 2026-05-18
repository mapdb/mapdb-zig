// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Comptime interface for read-only maps from `i8` keys to `i64` values.
///
/// Equivalent to:
///   Go:   I8I64MapIterable interface
///   Rust: I8I64Map trait
///   Java: I8I64Map interface
pub fn assertI8I64Map(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `i8` to `i64`.
pub fn assertI8I64MutableMap(comptime T: type) void {
    assertI8I64Map(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `i8` → `i64` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.i8_i64_hash_map.I8I64HashMap;
    assertI8I64MutableMap(HashMap);

    const TreeMap = treemap.i8_i64_tree_map.I8I64TreeMap;
    assertI8I64MutableMap(TreeMap);

    const HashBiMap = hashmap.i8_i64_hash_bi_map.I8I64HashBiMap;
    assertI8I64MutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_i8_i64_hash_map.ImmutableI8I64HashMap;
    assertI8I64Map(ImmutableHashMap);
}
