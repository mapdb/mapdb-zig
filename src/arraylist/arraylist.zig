// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Aggregator for the generic array list type.
//!
//! `ArrayList(T)` is a single-source generic backed by `std.ArrayListUnmanaged`,
//! with element-type-branched bit-equality, ordering, and sum widening. This
//! module exposes the named `<T>ArrayList` aliases that the rest of the project
//! (and the cross-language validate harness) consume, and preserves the
//! historical per-file lowercase namespaces for backward compatibility (e.g.
//! `arraylist.i32_array_list.I32ArrayList`).

pub const ArrayList = @import("array_list.zig").ArrayList;

// ---- Named array list aliases ----

pub const BoolArrayList = ArrayList(bool);
pub const CharArrayList = ArrayList(u21);
pub const F32ArrayList = ArrayList(f32);
pub const F64ArrayList = ArrayList(f64);
pub const I8ArrayList = ArrayList(i8);
pub const I16ArrayList = ArrayList(i16);
pub const I32ArrayList = ArrayList(i32);
pub const I64ArrayList = ArrayList(i64);

// ---- Backward-compat per-file namespaces ----

pub const bool_array_list = struct {
    pub const BoolArrayList = ArrayList(bool);
};
pub const char_array_list = struct {
    pub const CharArrayList = ArrayList(u21);
};
pub const f32_array_list = struct {
    pub const F32ArrayList = ArrayList(f32);
};
pub const f64_array_list = struct {
    pub const F64ArrayList = ArrayList(f64);
};
pub const i8_array_list = struct {
    pub const I8ArrayList = ArrayList(i8);
};
pub const i16_array_list = struct {
    pub const I16ArrayList = ArrayList(i16);
};
pub const i32_array_list = struct {
    pub const I32ArrayList = ArrayList(i32);
};
pub const i64_array_list = struct {
    pub const I64ArrayList = ArrayList(i64);
};
