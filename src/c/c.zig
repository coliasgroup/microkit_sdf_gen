const std = @import("std");
const modsdf = @import("sdf");
const allocator = std.heap.c_allocator;

const sddf = modsdf.sddf;
const SystemDescription = modsdf.sdf.SystemDescription;
const Pd = SystemDescription.ProtectionDomain;

var sdf: SystemDescription = undefined;

// TODO: handle deallocation
export fn sdfgen_create() *anyopaque {
    sdf = SystemDescription.create(allocator, .aarch64);
    return &sdf;
}

export fn sdfgen_destroy(_: *SystemDescription) void {}

// TODO: handle deallocation
export fn sdfgen_to_xml() [*c]u8 {
    const xml = sdf.toXml() catch @panic("Cannot convert to XML");
    return @constCast(xml);
}

// TODO: handle deallocation
export fn sdfgen_pd(name: [*c]u8, elf: [*c]u8) *anyopaque {
    const pd = allocator.create(Pd) catch @panic("OOM");
    pd.* = Pd.create(&sdf, std.mem.span(name), std.mem.span(elf));
    sdf.addProtectionDomain(pd);

    return pd;
}

export fn sdfgen_pd_set_priority(c_pd: *align(8) anyopaque, priority: u8) void {
    const pd: *Pd = @ptrCast(c_pd);
    pd.priority = priority;
}

export fn sdfgen_sddf_init(path: [*c]u8) bool {
    sddf.probe(allocator, std.mem.span(path)) catch return false;

    return true;
}

export fn sdfgen_sddf_i2c(device: *align(8) anyopaque, driver: *align(8) anyopaque, virt: *align(8) anyopaque) *anyopaque {
    const i2c = allocator.create(sddf.I2cSystem) catch @panic("OOM");
    i2c.* = sddf.I2cSystem.init(allocator, &sdf, @ptrCast(device), @ptrCast(driver), @ptrCast(virt), .{});

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
