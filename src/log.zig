const std = @import("std");
const builtin = @import("builtin");

pub fn debug(comptime s: []const u8, args: anytype) void {
    if (!builtin.target.cpu.arch.isWasm()) {
        std.log.debug(s, args);
    }
}

pub fn info(comptime s: []const u8, args: anytype) void {
    if (!builtin.target.cpu.arch.isWasm()) {
        std.log.info(s, args);
    }
}

pub fn err(comptime s: []const u8, args: anytype) void {
    if (!builtin.target.cpu.arch.isWasm()) {
        std.log.err(s, args);
    }
}
