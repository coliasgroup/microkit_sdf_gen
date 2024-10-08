const std = @import("std");
const modsdf = @import("sdf");
// Because this is intended to be used in the context of C, we always
// use the C allocator, even though it is not the most efficient for this
// kind of program,
const allocator = std.heap.c_allocator;

const dtb = modsdf.dtb;
const sddf = modsdf.sddf;
const SystemDescription = modsdf.sdf.SystemDescription;
const Pd = SystemDescription.ProtectionDomain;

// TODO: do proper error logging

// TODO: handle deallocation
// TODO: handle architecture
export fn sdfgen_create() *anyopaque {
    const sdf = allocator.create(SystemDescription) catch @panic("OOM");
    sdf.* = SystemDescription.create(allocator, .aarch64);

    return sdf;
}

// TODO
export fn sdfgen_destroy(_: *SystemDescription) void {}

// TODO: handle deallocation
export fn sdfgen_to_xml(c_sdf: *align(8) anyopaque) [*c]u8 {
    const sdf: *SystemDescription = @ptrCast(c_sdf);
    const xml = sdf.toXml() catch @panic("Cannot convert to XML");
    return @constCast(xml);
}

export fn sdfgen_dtb_parse(path: [*c]u8) ?*anyopaque {
    const file = std.fs.cwd().openFile(std.mem.span(path), .{}) catch |e| {
        std.log.err("could not open DTB '{s}' for parsing with error: {any}", .{ path, e });
        return null;
    };
    const stat = file.stat() catch |e| {
        std.log.err("could not stat DTB '{s}' for parsing with error: {any}", .{ path, e });
        return null;
    };
    const bytes = file.reader().readAllAlloc(allocator, stat.size) catch |e| {
        std.log.err("could not read DTB '{s}' for parsing with error: {any}", .{ path, e });
        return null;
    };
    const blob = modsdf.dtb.parse(allocator, bytes) catch |e| {
        std.log.err("could not parse DTB '{s}' with error: {any}", .{ path, e });
        return null;
    };

    return blob;
}

export fn sdfgen_dtb_node(c_blob: *align(8) anyopaque, c_node: [*c]u8) ?*anyopaque {
    const blob: *dtb.Node = @ptrCast(c_blob);
    const node = std.mem.span(c_node);
    var it = std.mem.splitSequence(u8, node, "/");
    var curr_node: *dtb.Node = blob;
    while (it.next()) |n| {
        if (curr_node.child(n)) |child| {
            curr_node = child;
        } else {
            return null;
        }
    }

    return curr_node;
}

export fn sdfgen_dtb_destroy(c_blob: *align(8) anyopaque) void {
    const blob: *dtb.Node = @ptrCast(c_blob);
    blob.deinit(allocator);
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

export fn sdfgen_sddf_i2c(c_sdf: *align(8) anyopaque, c_device: ?*align(8) anyopaque, driver: *align(8) anyopaque, virt: *align(8) anyopaque) *anyopaque {
    const sdf: *SystemDescription = @ptrCast(c_sdf);
    const i2c = allocator.create(sddf.I2cSystem) catch @panic("OOM");
    i2c.* = sddf.I2cSystem.init(allocator, sdf, @ptrCast(c_device), @ptrCast(driver), @ptrCast(virt), .{});

    return i2c;
}

export fn sdfgen_sddf_i2c_add_client(system: *align(8) anyopaque, client: *align(8) anyopaque) void {
    const i2c: *sddf.I2cSystem = @ptrCast(system);
    i2c.addClient(@ptrCast(client));
}

export fn sdfgen_sddf_i2c_connect(system: *align(8) anyopaque) bool {
    const i2c: *sddf.I2cSystem = @ptrCast(system);
    i2c.connect() catch return false;

    return true;
}

export fn sdfgen_sddf_block(c_sdf: *align(8) anyopaque, c_device: ?*align(8) anyopaque, driver: *align(8) anyopaque, virt: *align(8) anyopaque) *anyopaque {
    const sdf: *SystemDescription = @ptrCast(c_sdf);
    const block = allocator.create(sddf.BlockSystem) catch @panic("OOM");
    block.* = sddf.BlockSystem.init(allocator, sdf, @ptrCast(c_device), @ptrCast(driver), @ptrCast(virt), .{});

    return block;
}

export fn sdfgen_sddf_block_add_client(system: *align(8) anyopaque, client: *align(8) anyopaque) void {
    const i2c: *sddf.BlockSystem = @ptrCast(system);
    i2c.addClient(@ptrCast(client));
}

export fn sdfgen_sddf_block_connect(system: *align(8) anyopaque) bool {
    const blk: *sddf.BlockSystem = @ptrCast(system);
    blk.connect() catch return false;

    return true;
}
