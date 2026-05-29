// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Parallel and splittable iteration — the Zig port of Eclipse Collections'
//! parallel surface.
//!
//! Two of the three Eclipse abstractions are provided here:
//!
//!   1. `Spliterator(T)` — the splittable-iterator decomposition primitive
//!      (`java.util.Spliterator`), in `spliterator.zig`. No threads.
//!   2. `BatchIterable` — fixed-section iteration plus a fixed-chunk batch
//!      parallel executor on `std.Thread` (no work stealing), in `batch.zig`.
//!
//! The work-stealing `ParallelIterable` is intentionally omitted: Zig has no
//! work-stealing runtime to build it on.

pub const spliterator = @import("spliterator.zig");
pub const batch = @import("batch.zig");

pub const Spliterator = spliterator.Spliterator;
pub const characteristics = spliterator.characteristics;

pub const DEFAULT_MIN_FORK_SIZE = batch.DEFAULT_MIN_FORK_SIZE;
pub const getBatchCount = batch.getBatchCount;
pub const sectionBounds = batch.sectionBounds;
pub const batchForEach = batch.batchForEach;
pub const defaultTaskCount = batch.defaultTaskCount;
pub const forEach = batch.forEach;
pub const forEachWith = batch.forEachWith;
pub const map = batch.map;
pub const filter = batch.filter;
pub const count = batch.count;

comptime {
    _ = @import("spliterator.zig");
    _ = @import("batch.zig");
}

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
