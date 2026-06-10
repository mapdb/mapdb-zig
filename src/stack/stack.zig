// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Aggregator for the generic array stack type.
//!
//! `ArrayStack(T)` is a single-source generic backed by `std.ArrayListUnmanaged`.
//! This module exposes the named `<T>ArrayStack` aliases that the rest of the
//! project (and the cross-language validate harness) consume, and preserves the
//! historical per-file lowercase namespaces for backward compatibility (e.g.
//! `stack.i32_array_stack.I32ArrayStack`).

pub const ArrayStack = @import("array_stack.zig").ArrayStack;

// ---- Named array stack aliases ----

pub const BoolArrayStack = ArrayStack(bool);
pub const CharArrayStack = ArrayStack(u21);
pub const F32ArrayStack = ArrayStack(f32);
pub const F64ArrayStack = ArrayStack(f64);
pub const I8ArrayStack = ArrayStack(i8);
pub const I16ArrayStack = ArrayStack(i16);
pub const I32ArrayStack = ArrayStack(i32);
pub const I64ArrayStack = ArrayStack(i64);

// ---- Backward-compat per-file namespaces ----

pub const bool_array_stack = struct {
    pub const BoolArrayStack = ArrayStack(bool);
};
pub const char_array_stack = struct {
    pub const CharArrayStack = ArrayStack(u21);
};
pub const f32_array_stack = struct {
    pub const F32ArrayStack = ArrayStack(f32);
};
pub const f64_array_stack = struct {
    pub const F64ArrayStack = ArrayStack(f64);
};
pub const i8_array_stack = struct {
    pub const I8ArrayStack = ArrayStack(i8);
};
pub const i16_array_stack = struct {
    pub const I16ArrayStack = ArrayStack(i16);
};
pub const i32_array_stack = struct {
    pub const I32ArrayStack = ArrayStack(i32);
};
pub const i64_array_stack = struct {
    pub const I64ArrayStack = ArrayStack(i64);
};
