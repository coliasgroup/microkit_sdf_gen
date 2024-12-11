const std = @import("std");
const modsdf = @import("sdf");
// Because this is intended to be used in the context of C, we always
// use the C allocator, even though it is not the most efficient for this
// kind of program,
const allocator = std.heap.c_allocator;

const bindings = @cImport({
    @cInclude("sdfgen.h");
});

const dtb = modsdf.dtb;
const sddf = modsdf.sddf;
const lionsos = modsdf.lionsos;
const SystemDescription = modsdf.sdf.SystemDescription;
const Pd = SystemDescription.ProtectionDomain;
const Channel = SystemDescription.Channel;
const Arch = SystemDescription.Arch;

// TODO: do proper error logging
// TODO: handle passing options to sDDF systems

export fn sdfgen_create(c_arch: bindings.sdfgen_arch_t, paddr_top: u64) *anyopaque {
    const arch: Arch = @enumFromInt(c_arch);
    // Double check that there is a one-to-one mapping between the architecture for
    // the C enum and the Zig enum.
    switch (arch) {
        .aarch32 => std.debug.assert(c_arch == 0),
        .aarch64 => std.debug.assert(c_arch == 1),
        .riscv32 => std.debug.assert(c_arch == 2),
        .riscv64 => std.debug.assert(c_arch == 3),
        .x86 => std.debug.assert(c_arch == 4),
        .x86_64 => std.debug.assert(c_arch == 5),
    }
    const sdf = allocator.create(SystemDescription) catch @panic("OOM");
    sdf.* = SystemDescription.create(allocator, arch, paddr_top);

    return sdf;
}

export fn sdfgen_destroy(c_sdf: *align(8) anyopaque) void {
    const sdf: *SystemDescription = @ptrCast(c_sdf);
    sdf.destroy();
}

export fn sdfgen_add_pd(c_sdf: *align(8) anyopaque, c_pd: *align(8) anyopaque) void {
    const sdf: *SystemDescription = @ptrCast(c_sdf);
    sdf.addProtectionDomain(@ptrCast(c_pd));
}

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

export fn sdfgen_dtb_parse_from_bytes(bytes: [*c]u8, size: u32) ?*anyopaque {
    const blob = modsdf.dtb.parse(allocator, bytes[0..size]) catch |e| {
        std.log.err("could not parse DTB from bytes with error: {any}", .{e});
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

// TODO: handle options
export fn sdfgen_pd_create(name: [*c]u8, program_image: [*c]u8) *anyopaque {
    const pd = allocator.create(Pd) catch @panic("OOM");
    pd.* = Pd.create(allocator, std.mem.span(name), std.mem.span(program_image), .{});

    return pd;
}

export fn sdfgen_pd_destroy(c_pd: *align(8) anyopaque) void {
    const pd: *Pd = @ptrCast(c_pd);
    allocator.destroy(pd);
}

export fn sdfgen_pd_add_child(c_pd: *align(8) anyopaque, c_child_pd: *align(8) anyopaque, c_child_id: ?*u8) u8 {
    const pd: *Pd = @ptrCast(c_pd);
    const child_pd: *Pd = @ptrCast(c_child_pd);
    const child_id = if (c_child_id) |c| c.* else null;

    return pd.addChild(child_pd, .{ .id = child_id }) catch @panic("TODO");
}

export fn sdfgen_pd_set_priority(c_pd: *align(8) anyopaque, priority: u8) void {
    const pd: *Pd = @ptrCast(c_pd);
    pd.priority = priority;
}

export fn sdfgen_pd_set_budget(c_pd: *align(8) anyopaque, budget: u8) void {
    const pd: *Pd = @ptrCast(c_pd);
    pd.budget = budget;
}

export fn sdfgen_pd_set_period(c_pd: *align(8) anyopaque, period: u8) void {
    const pd: *Pd = @ptrCast(c_pd);
    pd.period = period;
}

export fn sdfgen_pd_set_stack_size(c_pd: *align(8) anyopaque, stack_size: u32) void {
    const pd: *Pd = @ptrCast(c_pd);
    pd.stack_size = stack_size;
}

export fn sdfgen_sddf_init(path: [*c]u8) bool {
    sddf.probe(allocator, std.mem.span(path)) catch return false;

    return true;
}

// TODO: handle specifying channel parameters
export fn sdfgen_channel_create(pd_a: *align(8) anyopaque, pd_b: *align(8) anyopaque) *anyopaque {
    const ch = allocator.create(Channel) catch @panic("OOM");
    ch.* = Channel.create(@ptrCast(pd_a), @ptrCast(pd_b), .{});

    return ch;
}

// export fn sdfgen_channel_set_options(c_ch: *align(8) anyopaque, pp_a: bool, pp_b: bool, notify_a: bool, notify_b: bool) void {
//     const ch: *Channel = @ptrCast(c_ch);
//     ch.pp_a = pp_a;
//     ch.pp_b = pp_b;
//     ch.notify_a = notify_a;
//     ch.notify_b = notify_b;
// }

export fn sdfgen_channel_destroy(c_ch: *align(8) anyopaque) void {
    const ch: *Channel = @ptrCast(c_ch);
    allocator.destroy(ch);
}

// TODO: is this a problem since we're copying instead of passing a pointer?
export fn sdfgen_channel_add(c_sdf: *align(8) anyopaque, c_ch: *align(8) anyopaque) void {
    const sdf: *SystemDescription = @ptrCast(c_sdf);
    const ch: *Channel = @ptrCast(c_ch);
    sdf.addChannel(ch.*);
}

export fn sdfgen_sddf_timer(c_sdf: *align(8) anyopaque, c_device: ?*align(8) anyopaque, driver: *align(8) anyopaque) *anyopaque {
    const sdf: *SystemDescription = @ptrCast(c_sdf);
    const timer = allocator.create(sddf.TimerSystem) catch @panic("OOM");
    timer.* = sddf.TimerSystem.init(allocator, sdf, @ptrCast(c_device), @ptrCast(driver));

    return timer;
}

export fn sdfgen_sddf_timer_destroy(system: *align(8) anyopaque) void {
    const timer: *sddf.TimerSystem = @ptrCast(system);
    allocator.destroy(timer);
}

export fn sdfgen_sddf_timer_add_client(system: *align(8) anyopaque, client: *align(8) anyopaque) void {
    const timer: *sddf.TimerSystem = @ptrCast(system);
    timer.addClient(@ptrCast(client));
}

export fn sdfgen_sddf_timer_connect(system: *align(8) anyopaque) bool {
    const timer: *sddf.TimerSystem = @ptrCast(system);
    timer.connect() catch return false;

    return true;
}

export fn sdfgen_sddf_timer_serialise_config(system: *align(8) anyopaque, output: [*c]u8) bool {
    const timer: *sddf.TimerSystem = @ptrCast(system);
    timer.serialiseConfig(std.mem.span(output)) catch return false;

    return true;
}

export fn sdfgen_sddf_serial(c_sdf: *align(8) anyopaque, c_device: ?*align(8) anyopaque, driver: *align(8) anyopaque, virt_tx: *align(8) anyopaque, virt_rx: ?*align(8) anyopaque) *anyopaque {
    const sdf: *SystemDescription = @ptrCast(c_sdf);
    const serial = allocator.create(sddf.SerialSystem) catch @panic("OOM");
    serial.* = sddf.SerialSystem.init(allocator, sdf, @ptrCast(c_device), @ptrCast(driver), @ptrCast(virt_tx), .{ .virt_rx = @ptrCast(virt_rx) });

    return serial;
}

export fn sdfgen_sddf_serial_destroy(system: *align(8) anyopaque) void {
    const serial: *sddf.SerialSystem = @ptrCast(system);
    serial.deinit();
}

export fn sdfgen_sddf_serial_add_client(system: *align(8) anyopaque, client: *align(8) anyopaque) void {
    const serial: *sddf.SerialSystem = @ptrCast(system);
    serial.addClient(@ptrCast(client));
}

export fn sdfgen_sddf_serial_connect(system: *align(8) anyopaque) bool {
    const serial: *sddf.SerialSystem = @ptrCast(system);
    serial.connect() catch return false;

    return true;
}

export fn sdfgen_sddf_serial_serialise_config(system: *align(8) anyopaque, output: [*c]u8) bool {
    const serial: *sddf.SerialSystem = @ptrCast(system);
    serial.serialiseConfig(std.mem.span(output)) catch return false;
    return true;
}

export fn sdfgen_sddf_i2c(c_sdf: *align(8) anyopaque, c_device: ?*align(8) anyopaque, driver: *align(8) anyopaque, virt: *align(8) anyopaque) *anyopaque {
    const sdf: *SystemDescription = @ptrCast(c_sdf);
    const i2c = allocator.create(sddf.I2cSystem) catch @panic("OOM");
    i2c.* = sddf.I2cSystem.init(allocator, sdf, @ptrCast(c_device), @ptrCast(driver), @ptrCast(virt), .{});

    return i2c;
}

export fn sdfgen_sddf_i2c_destroy(system: *align(8) anyopaque) void {
    const i2c: *sddf.I2cSystem = @ptrCast(system);
    allocator.destroy(i2c);
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

export fn sdfgen_sddf_block(c_sdf: *align(8) anyopaque, c_device: *align(8) anyopaque, driver: *align(8) anyopaque, virt: *align(8) anyopaque) *anyopaque {
    const sdf: *SystemDescription = @ptrCast(c_sdf);
    const block = allocator.create(sddf.BlockSystem) catch @panic("OOM");
    block.* = sddf.BlockSystem.init(allocator, sdf, @ptrCast(c_device), @ptrCast(driver), @ptrCast(virt), .{});

    return block;
}

export fn sdfgen_sddf_block_destroy(system: *align(8) anyopaque) void {
    const block: *sddf.BlockSystem = @ptrCast(system);
    allocator.destroy(block);
}

export fn sdfgen_sddf_block_add_client(system: *align(8) anyopaque, client: *align(8) anyopaque, partition: u32) void {
    const block: *sddf.BlockSystem = @ptrCast(system);
    block.addClient(@ptrCast(client), partition);
}

export fn sdfgen_sddf_block_connect(system: *align(8) anyopaque) bool {
    const block: *sddf.BlockSystem = @ptrCast(system);
    block.connect() catch return false;

    return true;
}

export fn sdfgen_sddf_net(c_sdf: *align(8) anyopaque, c_device: *align(8) anyopaque, driver: *align(8) anyopaque, virt_tx: *align(8) anyopaque, virt_rx: *align(8) anyopaque) *anyopaque {
    const sdf: *SystemDescription = @ptrCast(c_sdf);
    const net = allocator.create(sddf.NetworkSystem) catch @panic("OOM");
    net.* = sddf.NetworkSystem.init(allocator, sdf, @ptrCast(c_device), @ptrCast(driver), @ptrCast(virt_tx), @ptrCast(virt_rx), .{});

    return net;
}

export fn sdfgen_sddf_net_add_client_with_copier(system: *align(8) anyopaque, client: *align(8) anyopaque, copier: *align(8) anyopaque, mac_addr: [*c]u8) bindings.sdfgen_sddf_error_t {
    const net: *sddf.NetworkSystem = @ptrCast(system);
    var options: sddf.NetworkSystem.ClientOptions = .{};
    if (mac_addr) |a| {
        options.mac_addr = std.mem.span(a);
    }
    net.addClientWithCopier(@ptrCast(client), @ptrCast(copier), options) catch |e| {
        switch (e) {
            error.DuplicateMacAddr => return 1,
            error.DuplicateClient => return 2,
            error.DuplicateCopier => return 3,
            error.InvalidMacAddr => return 4,
        }
    };

    return 0;
}

export fn sdfgen_sddf_net_connect(system: *align(8) anyopaque) bool {
    const net: *sddf.NetworkSystem = @ptrCast(system);
    net.connect() catch return false;

    return true;
}

export fn sdfgen_sddf_net_serialise_config(system: *align(8) anyopaque, output: [*c]u8) bool {
    const net: *sddf.NetworkSystem = @ptrCast(system);
    net.serialiseConfig(std.mem.span(output)) catch return false;
    return true;
}

export fn sdfgen_sddf_net_destroy(system: *align(8) anyopaque) void {
    const net: *sddf.NetworkSystem = @ptrCast(system);
    allocator.destroy(net);
}

export fn sdfgen_lionsos_fs(c_sdf: *align(8) anyopaque, c_fs: *align(8) anyopaque, c_client: *align(8) anyopaque) *anyopaque {
    const sdf: *SystemDescription = @ptrCast(c_sdf);
    const fs = allocator.create(lionsos.FileSystem) catch @panic("OOM");
    fs.* = lionsos.FileSystem.init(allocator, sdf, @ptrCast(c_fs), @ptrCast(c_client), .{});

    return fs;
}

export fn sdfgen_lionsos_fs_connect(system: *align(8) anyopaque) bool {
    const fs: *lionsos.FileSystem = @ptrCast(system);
    fs.connect();

    return true;
}
