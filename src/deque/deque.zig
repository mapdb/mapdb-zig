// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Aggregator for the generic array deque type.
//!
//! `ArrayDeque(T)` is a single-source generic backed by `std.ArrayListUnmanaged`.
//! This module exposes the named `<T>ArrayDeque` aliases that the rest of the
//! project (and the cross-language validate harness) consume, and preserves the
//! historical per-file lowercase namespaces for backward compatibility (e.g.
//! `deque.i32_array_deque.I32ArrayDeque`).

pub const ArrayDeque = @import("array_deque.zig").ArrayDeque;

// ---- Named array deque aliases ----

pub const BoolArrayDeque = ArrayDeque(bool);
pub const CharArrayDeque = ArrayDeque(u21);
pub const F32ArrayDeque = ArrayDeque(f32);
pub const F64ArrayDeque = ArrayDeque(f64);
pub const I8ArrayDeque = ArrayDeque(i8);
pub const I16ArrayDeque = ArrayDeque(i16);
pub const I32ArrayDeque = ArrayDeque(i32);
pub const I64ArrayDeque = ArrayDeque(i64);

// ---- Backward-compat per-file namespaces ----

pub const bool_array_deque = struct {
    pub const BoolArrayDeque = ArrayDeque(bool);
};
pub const char_array_deque = struct {
    pub const CharArrayDeque = ArrayDeque(u21);
};
pub const f32_array_deque = struct {
    pub const F32ArrayDeque = ArrayDeque(f32);
};
pub const f64_array_deque = struct {
    pub const F64ArrayDeque = ArrayDeque(f64);
};
pub const i8_array_deque = struct {
    pub const I8ArrayDeque = ArrayDeque(i8);
};
pub const i16_array_deque = struct {
    pub const I16ArrayDeque = ArrayDeque(i16);
};
pub const i32_array_deque = struct {
    pub const I32ArrayDeque = ArrayDeque(i32);
};
pub const i64_array_deque = struct {
    pub const I64ArrayDeque = ArrayDeque(i64);
};
