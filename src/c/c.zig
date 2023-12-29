const std = @import("std");
const modsdf = @import("sdf");
const allocator = std.heap.c_allocator;

const SystemDescription = modsdf.SystemDescription;

export fn sdfgen_create(arch: SystemDescription.Arch) [*c]SystemDescription {
    return SystemDescription.create(allocator, arch) catch null;
}

export fn sdfgen_destroy(_: *SystemDescription) void {}

export fn sdfgen_to_xml() void {}

export fn sdfgen_pd_init() void {}

export fn sdfgen_pd_add() void {}
