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

- **Deferred by design: pointer-yielding mutable iterators.** The v2 pass keeps
  the established copy-safe `Iterator.next() ?T` / entry-by-value shape to avoid
  introducing a second iterator model without a larger mutable-iterator design.

Verification:

- `zig build`
- `zig build test`
- `zig fmt --check build.zig bench_zig.zig bench_all_methods.zig src`
- `cross-language-validation/validate.sh` — 57/57 all ports
