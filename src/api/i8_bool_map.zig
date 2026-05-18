// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.


const std = @import("std");

/// Comptime interface for read-only maps from `i8` keys to `bool` values.
///
/// Equivalent to:
///   Go:   I8BoolMapIterable interface
///   Rust: I8BoolMap trait
///   Java: I8BoolMap interface
pub fn assertI8BoolMap(comptime T: type) void {
    comptime {
        if (!@hasDecl(T, "len")) @compileError(@typeName(T) ++ " missing len()");
        if (!@hasDecl(T, "isEmpty")) @compileError(@typeName(T) ++ " missing isEmpty()");
        if (!@hasDecl(T, "containsKey")) @compileError(@typeName(T) ++ " missing containsKey()");
        if (!@hasDecl(T, "get")) @compileError(@typeName(T) ++ " missing get()");
    }
}

/// Comptime interface for mutable maps from `i8` to `bool`.
pub fn assertI8BoolMutableMap(comptime T: type) void {
    assertI8BoolMap(T);
    comptime {
        if (!@hasDecl(T, "put")) @compileError(@typeName(T) ++ " missing put()");
        if (!@hasDecl(T, "remove")) @compileError(@typeName(T) ++ " missing remove()");
        if (!@hasDecl(T, "clear")) @compileError(@typeName(T) ++ " missing clear()");
    }
}

// Compile-time verification: every concrete `i8` → `bool` map type
// satisfies the matching read-only and (where applicable) mutable interface.
//
// Imports go through per-package index files — the index is the swap point
// for alternative implementations.
comptime {
    const hashmap = @import("../hashmap/hashmap.zig");
    const treemap = @import("../treemap/treemap.zig");
    const immutable = @import("../immutable/immutable.zig");

    const HashMap = hashmap.i8_bool_hash_map.I8BoolHashMap;
    assertI8BoolMutableMap(HashMap);

    const TreeMap = treemap.i8_bool_tree_map.I8BoolTreeMap;
    assertI8BoolMutableMap(TreeMap);

    const HashBiMap = hashmap.i8_bool_hash_bi_map.I8BoolHashBiMap;
    assertI8BoolMutableMap(HashBiMap);

    const ImmutableHashMap = immutable.immutable_i8_bool_hash_map.ImmutableI8BoolHashMap;
    assertI8BoolMap(ImmutableHashMap);
}
