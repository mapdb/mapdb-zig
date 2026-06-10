// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Aggregator for the compile-time collection / map interface layer.
//!
//! The 72 per-(K,V) / per-type interface-assertion files (`<k>_<v>_map.zig`,
//! `<t>_collection.zig`) have been collapsed into a single
//! `api_assert.zig`: the `@hasDecl` method-name checks were identical across
//! every element type, so they are now generic, type-erased functions
//! (`assertMap`, `assertMutableMap`, `assertCollection`, `assertList`, …), and
//! the per-file conformance blocks (which concrete production types must
//! satisfy which interface) are reproduced as comptime loops in that file over
//! every named aggregator alias.
//!
//! Referencing `api_assert` here (and forcing it in the `comptime` block) makes
//! every `@compileError`-based conformance check run whenever the api layer is
//! compiled.

pub const api_assert = @import("api_assert.zig");

// Re-export the generic interface assertions at the top level.
pub const assertMap = api_assert.assertMap;
pub const assertMutableMap = api_assert.assertMutableMap;
pub const assertCollection = api_assert.assertCollection;
pub const assertMutableCollection = api_assert.assertMutableCollection;
pub const assertList = api_assert.assertList;
pub const assertMutableList = api_assert.assertMutableList;
pub const assertSet = api_assert.assertSet;
pub const assertMutableSet = api_assert.assertMutableSet;
pub const assertBag = api_assert.assertBag;
pub const assertMutableBag = api_assert.assertMutableBag;
pub const assertStack = api_assert.assertStack;
pub const assertMutableStack = api_assert.assertMutableStack;

comptime {
    // Force the conformance comptime blocks (and the self-test) to compile.
    _ = api_assert;
}
