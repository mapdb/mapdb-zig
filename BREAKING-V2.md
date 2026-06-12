# Zig v2 breaking idioms — DONE

The v2 breaking-idiom line has been cut. Phase 7d added a uniform pull-based
`iterator()` additively; this v2 pass applies the deferred source-breaking Zig
API cleanup.

- **DONE: propagate `Allocator.Error!` instead of panicking on OOM.** Fallible
  constructors, mutators, fluent methods, result-building combinators, and
  `*ToSlice` APIs now return allocator errors to the caller. Tests, validation,
  nanprobe, and examples were updated to use `try`.

- **DONE: context-carrying callbacks.** `forEach`, predicate callbacks, counts,
  detection, selection/rejection, and folds now accept a `ctx: *anyopaque`
  parameter where callback state is needed.

- **DONE: remove dead `AllocatorConfig` plumbing.** Collections use one base
  allocator, public `initWithConfig`/`config` access is gone, and the dead
  `allocator_config` root export was removed.

- **DONE: make `iterator()` canonical and demote bare `forEach`.** Remaining
  callback-style traversal uses context-aware signatures; pull iterators remain
  the non-allocating canonical traversal API.

- **RESOLVED additively (2026-06-12 decision): pointer-yielding mutable
  iterators as a SEPARATE interface, safe surfaces only.** The canonical
  `iterator()` stays immutable (value-yielding `next() ?T` / entry-by-value,
  unchanged — this is NOT a breaking change). A separate `mutIterator()` is
  added *only* on the surfaces where in-place mutation cannot corrupt structure
  invariants:
  - **list / stack / deque** (primitive; plus `object/` list + stack — there is
    no `object/` deque): `mutIterator()` yields `*T` element pointers
    (`MutIterator.next() ?*T`). A list/stack/deque imposes no hash/order
    invariant on its elements.
  - **mutable maps** — primitive hash + tree maps, plus the `object/`-only
    linked and strategy hash maps (there are no primitive linked/strategy map
    variants): `mutIterator()` yields `{ key, value_ptr: *V }` (`MutEntry`). The key is
    yielded BY VALUE — mutating a key in place would change its hash/slot or
    sort position and silently corrupt the map — so only the value is exposed
    mutably, and the value is never part of the hash/ordering computation.
  - **Excluded — no `mutIterator()`:** sets, bags, tree sets, bi-maps, priority
    queues, multimaps, and the set-like `BitSet` (element/key is identity, or
    the value is itself a key / heap-ordered / a nested collection). The
    exclusion and its rationale are documented at each excluded *mutable*
    family's `iterator()` definition, and a static `@hasDecl` guard in
    `src/mut_iterator_test.zig` asserts the surface stays safe-only. The
    **immutable families** are excluded by construction — they expose no
    mutation API at all — so they carry no per-site note.

  Same invalidation contract as `iterator()`: structural mutation of the
  container during iteration is illegal. Runtime coverage in
  `src/mut_iterator_test.zig` mutates through the pointers and asserts the
  container observes the writes (including distinct NaN / signed-zero float bit
  patterns, and — for maps — that the key set and lookups are unaffected).

Verification:

- `zig build`
- `zig build test`
- `zig fmt --check build.zig bench_zig.zig bench_all_methods.zig src`
- `cross-language-validation/validate.sh` — 57/57 all ports
