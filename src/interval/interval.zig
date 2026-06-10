// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Aggregator for the generic interval type.
//!
//! `Interval(T)` is a single-source generic representing a virtual range of
//! signed-integer values `[from, to]` with a step, with no elements
//! materialised in memory. Interval is only applicable to signed integer
//! element types (`i8`/`i16`/`i32`/`i64`); the `bool`/`char`/`f32`/`f64`
//! members of the family were inert "not applicable" stubs and are therefore
//! intentionally absent here.
//!
//! This module exposes the named `<T>Interval` aliases that the rest of the
//! project (and the cross-language validate harness) consume, and preserves the
//! historical per-file lowercase namespaces for backward compatibility (e.g.
//! `interval.i32_interval.I32Interval`). The non-applicable stub namespaces
//! (`bool_interval`/`char_interval`/`f32_interval`/`f64_interval`) remain as
//! empty namespaces, exactly as the original stub files exposed nothing.

pub const Interval = @import("interval_impl.zig").Interval;

// ---- Named interval aliases (signed integer element types only) ----

pub const I8Interval = Interval(i8);
pub const I16Interval = Interval(i16);
pub const I32Interval = Interval(i32);
pub const I64Interval = Interval(i64);

// ---- Backward-compat per-file namespaces ----

pub const i8_interval = struct {
    pub const I8Interval = Interval(i8);
};
pub const i16_interval = struct {
    pub const I16Interval = Interval(i16);
};
pub const i32_interval = struct {
    pub const I32Interval = Interval(i32);
};
pub const i64_interval = struct {
    pub const I64Interval = Interval(i64);
};

// Interval is not applicable to bool/char/f32/f64; these stub namespaces expose
// nothing, mirroring the original "Interval is not applicable to <type>" files.
pub const bool_interval = struct {};
pub const char_interval = struct {};
pub const f32_interval = struct {};
pub const f64_interval = struct {};

comptime {
    _ = @import("interval_test.zig");
}
