// Copyright (c) 2026 Jan Kotek.
// Derived from Eclipse Collections (Copyright (c) Goldman Sachs and others).
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.
// USE AT YOUR OWN RISK — THIS SOFTWARE IS PROVIDED WITHOUT WARRANTY OF ANY KIND.

//! Concurrency module index. See the `root.zig` concurrency contract.
//!
//! - `Synchronized(C)` (L1): coarse RwLock wrapper for any collection.
//! - `ShardedHashMap(K, V)` (L2): genuinely concurrent per-shard-locked map.

pub const Synchronized = @import("synchronized.zig").Synchronized;
pub const ShardedHashMap = @import("sharded_hash_map.zig").ShardedHashMap;
pub const ComputeOp = @import("sharded_hash_map.zig").ComputeOp;

test {
    @import("std").testing.refAllDeclsRecursive(@This());
    _ = @import("synchronized.zig");
    _ = @import("sharded_hash_map.zig");
}
