// Copyright (c) 2026 Jan Kotek.
// Licensed under the Eclipse Public License v1.0 and Eclipse Distribution License v1.0.
// See LICENSE-EPL-1.0.txt and LICENSE-EDL-1.0.txt.

// A diagnostic panic handler distinguishes the intended guard from an unrelated
// language trap. Removing a minimum-step guard must fail in Debug as well as
// ReleaseFast; integer-overflow panic is not evidence that the guard ran.
const std = @import("std");
const interval = @import("interval/interval_impl.zig");

const intended_exit = 73;
var expected_message: []const u8 = "";
pub const panic = std.debug.FullPanic(checkPanic);

fn checkPanic(message: []const u8, _: ?usize) noreturn {
    if (std.mem.eql(u8, message, expected_message)) std.process.exit(intended_exit);
    std.debug.print("unexpected panic: {s}\n", .{message});
    std.process.exit(74);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len == 1) {
        const self_path = try std.fs.selfExePathAlloc(allocator);
        defer allocator.free(self_path);
        for ([_][]const u8{ "i8", "i16", "i32", "i64" }) |width| {
            for ([_][]const u8{ "reverse-min", "zero-singleton" }) |operation| {
                const argv = [_][]const u8{ self_path, width, operation };
                var child = std.process.Child.init(&argv, allocator);
                child.stdin_behavior = .Ignore;
                child.stdout_behavior = .Ignore;
                child.stderr_behavior = .Inherit;
                const term = try child.spawnAndWait();
                if (term != .Exited or term.Exited != intended_exit) {
                    std.debug.print("interval guard {s}/{s}: unexpected termination {any}\n", .{ width, operation, term });
                    return error.IntendedGuardDidNotFire;
                }
            }
        }
        return;
    }
    if (args.len != 3) return error.InvalidArgs;
    inline for (.{ i8, i16, i32, i64 }) |T| {
        if (std.mem.eql(u8, args[1], @typeName(T))) {
            const Iv = interval.Interval(T);
            if (std.mem.eql(u8, args[2], "reverse-min")) {
                expected_message = "Interval: cannot reverse interval with minimum step";
                const source = Iv.fromToBy(0, std.math.minInt(T), std.math.minInt(T));
                const reversed = source.reversed();
                std.mem.doNotOptimizeAway(reversed);
                return error.IntendedGuardDidNotFire;
            }
            if (std.mem.eql(u8, args[2], "zero-singleton")) {
                expected_message = "Interval.fromToBy: step must not be zero";
                const source = Iv.fromToBy(5, 5, 0);
                std.mem.doNotOptimizeAway(source);
                return error.IntendedGuardDidNotFire;
            }
            return error.UnknownOperation;
        }
    }
    return error.UnknownWidth;
}
