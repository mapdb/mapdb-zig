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

---

# Post-v2 breaking changes (this branch)

The v2 pass above is closed. The changes below land *after* it and are also
source-breaking, so they need their own migration record. Where the section
above and this one disagree, this one wins — notably the `*anyopaque` callback
contexts described above have been replaced by comptime contexts.

Every item here is a **compile error** on the old call, not a silent behavior
change, so the compiler points at each site that needs updating.

- **`format` takes just a writer.** All 14 public `format` implementations moved
  from the old `format(self, comptime fmt, options, writer)` to the Zig 0.15
  shape `format(self, writer)`. Required by the toolchain's new formatting
  contract. Only direct callers of `.format(...)` are affected; `{f}`-style
  formatting through `std.fmt` is unchanged.

- **Lazy hash containers `init` is infallible.** `HashMap.init(allocator)` and
  `HashSet.init(allocator)` (and the bags/bimaps built on them) now return
  `Self` rather than `Allocator.Error!Self` — they allocate nothing until the
  first insert. Drop the `try`:
  `var m = try HashMap(i64, i64).init(a);` → `var m = HashMap(i64, i64).init(a);`
  The eager `initWithCapacity` / `initForElements` stay fallible.

- **`object` `removeRange` no longer takes an allocator.** `removeRange(range,
  allocator)` → `removeRange(range)` on the object `TreeMap`/`TreeSet`, aligning
  them with the "takes-allocator ⇔ owns" rule: these collections already own
  their allocator, so passing a second one was both redundant and a way to free
  from the wrong one.

- **`ArrayDeque.slice()` takes `*Self`, not `*const Self`.** The deque is now a
  real ring buffer, so returning one contiguous `[]const T` may first normalize
  the wrap point in place. The returned slice is still read-only; the receiver
  had to become mutable. A `const` deque can no longer call `slice()`.

- **`object` `TreeMap`/`TreeSet` `init` takes a comparator *context*.**
  `init(allocator, cmp)` → `init(allocator, ctx_or_cmp)`, which accepts either a
  comptime context type (ordering baked into the type, no indirect call) or, via
  the preserved dynamic alias, the old comparator function pointer — so existing
  fn-pointer callers keep compiling. `comparator()` remains callable on the
  dynamic alias only; comptime-context maps use `comparatorContext()`, which
  round-trips through `init` for snapshot rebuilds like `subMap`.

- **Hash table internals are structure-of-arrays.** The table stores `keys[]`,
  `values[]` and an occupancy bitset instead of an array of entry structs. Public
  field access to the old interleaved layout is gone; the method surface is
  unchanged.

Additive, not breaking, but new in the same line: `concurrent.Synchronized` and
`concurrent.ShardedHashMap` (two concurrency tiers), bounded-LRU read-time TTL
(`getAt`/`getOrDefaultAt`) and owning-value teardown (`clearWith`). The
bounded-LRU additions and the removal of Zig's `size()` are **not yet reflected
in the shared cross-language spec** — they are Zig-local until that spec is
updated and the siblings are ported.

Verification:

- `zig build`
- `zig build test` (Debug, ReleaseSafe, ReleaseFast)
- `zig build nanprobe` / `trapprobe` / `hashtrapprobe`
- `cross-language-validation/validate.sh --skip-java`
