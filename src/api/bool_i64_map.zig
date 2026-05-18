// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Comptime interface for read-only maps from `bool` keys to `i64` values.
///
/// Equivalent to:
///   Go:   BoolI64MapIterable interface
///   Rust: BoolI64Map trait
///   Java: BoolI64Map interface
pub fn assertBoolI64Map(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `bool` to `i64`.
pub fn assertBoolI64MutableMap(comptime T: type) void {
    assertBoolI64Map(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `bool` → `i64` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.bool_i64_hash_map.BoolI64HashMap;
    assertBoolI64MutableMap(HashMap);

    const TreeMap = treemap.bool_i64_tree_map.BoolI64TreeMap;
    assertBoolI64MutableMap(TreeMap);

    const HashBiMap = hashmap.bool_i64_hash_bi_map.BoolI64HashBiMap;
    assertBoolI64MutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_bool_i64_hash_map.ImmutableBoolI64HashMap;
    assertBoolI64Map(ImmutableHashMap);
}
