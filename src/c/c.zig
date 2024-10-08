const std = @import("std");
const modsdf = @import("sdf");
// Because this is intended to be used in the context of C, we always
// use the C allocator, even though it is not the most efficient for this
// kind of program,
const allocator = std.heap.c_allocator;

const sddf = modsdf.sddf;
const SystemDescription = modsdf.sdf.SystemDescription;
const Pd = SystemDescription.ProtectionDomain;

// TODO: handle deallocation
// TODO: handle architecture
export fn sdfgen_create() *anyopaque {
    const sdf = allocator.create(SystemDescription) catch @panic("OOM");
    sdf.* = SystemDescription.create(allocator, .aarch64);

    return sdf;
}

export fn sdfgen_destroy(_: *SystemDescription) void {}

// TODO: handle deallocation
export fn sdfgen_to_xml(c_sdf: *align(8) anyopaque) [*c]u8 {
    const sdf: *SystemDescription = @ptrCast(c_sdf);
    const xml = sdf.toXml() catch @panic("Cannot convert to XML");
    return @constCast(xml);
}

// TODO: handle deallocation
export fn sdfgen_pd_create(name: [*c]u8, elf: [*c]u8) *anyopaque {
    const pd = allocator.create(Pd) catch @panic("OOM");
    pd.* = Pd.create(allocator, std.mem.span(name), std.mem.span(elf));

    return pd;
}

export fn sdfgen_pd_add(c_sdf: *align(8) anyopaque, c_pd: *align(8) anyopaque) void {
    const sdf: *SystemDescription = @ptrCast(c_sdf);
    sdf.addProtectionDomain(@ptrCast(c_pd));
}

export fn sdfgen_pd_set_priority(c_pd: *align(8) anyopaque, priority: u8) void {
    const pd: *Pd = @ptrCast(c_pd);
    pd.priority = priority;
}

export fn sdfgen_sddf_init(path: [*c]u8) bool {
    sddf.probe(allocator, std.mem.span(path)) catch return false;

    return true;
}

export fn sdfgen_sddf_i2c(c_sdf: *align(8) anyopaque, device: *align(8) anyopaque, driver: *align(8) anyopaque, virt: *align(8) anyopaque) *anyopaque {
    const sdf: *SystemDescription = @ptrCast(c_sdf);
    const i2c = allocator.create(sddf.I2cSystem) catch @panic("OOM");
    i2c.* = sddf.I2cSystem.init(allocator, sdf, @ptrCast(device), @ptrCast(driver), @ptrCast(virt), .{});

    return i2c;
}

export fn sdfgen_sddf_i2c_client_add(i2c_system: *align(8) anyopaque, client: *align(8) anyopaque) void {
    const i2c: *sddf.I2cSystem = @ptrCast(i2c_system);
    i2c.addClient(@ptrCast(client));
}

export fn sdfgen_sddf_i2c_connect(i2c_system: *align(8) anyopaque) bool {
    const i2c: *sddf.I2cSystem = @ptrCast(i2c_system);
    i2c.connect() catch return false;

    return true;
}
