// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Aggregator for the generic hash set type.
//!
//! `HashSet(T)` is a single-source generic backed by `OpenHashSet(T)`. This
//! module exposes the named `<T>HashSet` aliases that the rest of the project
//! (and the cross-language validate harness) consume, and preserves the
//! historical per-file lowercase namespaces for backward compatibility (e.g.
//! `hashset.i32_hash_set.I32HashSet`).

pub const HashSet = @import("hash_set.zig").HashSet;

// ---- Named hash set aliases ----

pub const BoolHashSet = HashSet(bool);
pub const CharHashSet = HashSet(u21);
pub const F32HashSet = HashSet(f32);
pub const F64HashSet = HashSet(f64);
pub const I8HashSet = HashSet(i8);
pub const I16HashSet = HashSet(i16);
pub const I32HashSet = HashSet(i32);
pub const I64HashSet = HashSet(i64);

// ---- Backward-compat per-file namespaces ----

pub const bool_hash_set = struct {
    pub const BoolHashSet = HashSet(bool);
};
pub const char_hash_set = struct {
    pub const CharHashSet = HashSet(u21);
};
pub const f32_hash_set = struct {
    pub const F32HashSet = HashSet(f32);
};
pub const f64_hash_set = struct {
    pub const F64HashSet = HashSet(f64);
};
pub const i8_hash_set = struct {
    pub const I8HashSet = HashSet(i8);
};
pub const i16_hash_set = struct {
    pub const I16HashSet = HashSet(i16);
};
pub const i32_hash_set = struct {
    pub const I32HashSet = HashSet(i32);
};
pub const i64_hash_set = struct {
    pub const I64HashSet = HashSet(i64);
};
