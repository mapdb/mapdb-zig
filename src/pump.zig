// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Data pump (bulk import) — shared vocabulary.
//!
//! The data pump populates a *fresh* collection from prepared input in a single
//! O(n) pass (where the backing representation allows it), skipping the
//! per-element rebalancing / rehashing that the normal `put`/`add` path pays. It
//! is **insert-only**: it never read-modify-writes a pre-existing entry, and
//! every entry point returns a brand-new collection.
//!
//! Two surfaces, mirrored across the five mapdb ports (see the spec
//! `features/data-pump.md`):
//!   * one-shot constructors — the primary API: `fromSorted` for ordered
//!     families (TreeMap/TreeSet/TreeBag, the multimaps) and
//!     `bulkLoad` / `bulkLoadExact` for the hash families;
//!   * a streaming `Sink` (`put` / `putAll` / `create`) — provided ONLY for the
//!     ordered families, where input arrives incrementally and the Sink encodes
//!     the real append-and-validate algorithm. The one-shot `fromSorted` is a
//!     thin wrapper over the Sink so the build logic lives in exactly one place.
//!
//! Errors are reported through Zig error unions, never panics on data errors:
//!   * `error.NotSorted`     — ordered input was not strictly ascending under
//!                             the collection's own comparator;
//!   * `error.DuplicateKey`  — a duplicate key/value under `DupPolicy.err`;
//!   * `error.DuplicateValue`— a duplicate VALUE in a BiMap bulk load (the
//!                             bijection precondition was violated);
//!   * `error.CountOverflow` — a bag run length overflowed the count type.
//! All of these compose with `Allocator.Error`; a mid-load failure frees what
//! it built via `errdefer`, so no half-built collection ever escapes.

/// Duplicate handling for a bulk load.
///   * `.err`    — a duplicate key (BiMap: key OR value) is `error.DuplicateKey`
///                 (BiMap value: `error.DuplicateValue`).
///   * `.ignore` — keep the first, skip the rest (sets/maps), collapse per-key
///                 (set multimap). Bags always *count* duplicates regardless of
///                 policy — see the per-collection docs.
pub const DupPolicy = enum { err, ignore };

/// Data errors a pump can report. Composed with `Allocator.Error` at each call
/// site. `DuplicateValue` is only reachable through `HashBiMap.bulkLoad`;
/// `CountOverflow` only through the bag bulk loaders.
pub const PumpError = error{
    NotSorted,
    DuplicateKey,
    DuplicateValue,
    CountOverflow,
};
