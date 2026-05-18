// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Comptime interface for read-only maps from `bool` keys to `u21` values.
///
/// Equivalent to:
///   Go:   BoolCharMapIterable interface
///   Rust: BoolCharMap trait
///   Java: BoolCharMap interface
pub fn assertBoolCharMap(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `bool` to `u21`.
pub fn assertBoolCharMutableMap(comptime T: type) void {
    assertBoolCharMap(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `bool` → `u21` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.bool_char_hash_map.BoolCharHashMap;
    assertBoolCharMutableMap(HashMap);

    const TreeMap = treemap.bool_char_tree_map.BoolCharTreeMap;
    assertBoolCharMutableMap(TreeMap);

    const HashBiMap = hashmap.bool_char_hash_bi_map.BoolCharHashBiMap;
    assertBoolCharMutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_bool_char_hash_map.ImmutableBoolCharHashMap;
    assertBoolCharMap(ImmutableHashMap);
}
