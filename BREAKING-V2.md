# Breaking Zig-idiom changes deferred to v2

Phase 7d added a uniform pull-based `iterator()` additively. The changes below
are the idiomatic-Zig improvements that were intentionally **NOT** made because
each one is source-breaking (alters a public signature or removes a public
decl). They are batched here for a future v2 major bump. Do **not** apply these
without a coordinated major-version change across the cross-language harness.

- **Propagate `Allocator.Error!` instead of `catch @panic("out of memory")`.**
  Every fallible method (`push`, `put`, `add`, `of`, `addAll`, fluent `with*`,
  the functional combinators that build a result collection, `*ToSlice`, etc.)
  currently swallows allocation failure with `@panic`. The Zig idiom is to
  return `Allocator.Error!T` and let the caller handle OOM. Breaking: it changes
  the return type (and call sites) of essentially every mutating method on every
  collection — the single largest API break.

- **Context-carrying callbacks: `*const fn (ctx: *anyopaque, T) void` instead of
  `*const fn (T) void`.** The current `forEach` / `select` / predicate callbacks
  are bare function pointers with no closure environment, forcing callers to
  smuggle state through `var` globals (see `object/treeset.zig`'s `forEach`
  wrapper). Adding a context parameter enables real closures. Breaking: changes
  the type of every callback parameter across `forEach`, `forEachWithIndex`,
  `forEachKey/Value/WithOccurrences`, `select`, `reject`, `detect`,
  `any/all/noneSatisfy`, `count`, `injectInto`.

- **Remove the dead `AllocatorConfig` multi-allocator plumbing.** Several
  generics carry a full `AllocatorConfig` (keys/values/index allocators) of
  which the production paths only ever use a single base allocator, and the
  hash-backed collections collapse all three to one anyway. Removing the unused
  `initWithConfig` / per-region allocator accessors and the struct field would
  simplify construction. Breaking: removes public `initWithConfig` and the
  `config` field from the collection structs.

- **Make `iterator()` the canonical traversal and demote `forEach`.** Now that a
  non-allocating pull iterator exists for every family, `forEach` (push-based,
  no early-exit, no closure capture) is redundant. v2 could deprecate/remove the
  bare-fn `forEach` variants in favor of `iterator()`. Breaking: removes public
  `forEach` overloads.

- **Yield entries by pointer (`*const T` / key+value pointers) from iterators**
  to avoid copying large element types and to permit in-place mutation via a
  mutable iterator. The v1 iterators added here yield **by value** for a simple,
  copy-safe API. Breaking if retrofitted onto the same `Iterator.next` return
  type.
