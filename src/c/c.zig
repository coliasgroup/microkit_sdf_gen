const std = @import("std");
const modsdf = @import("sdf");
// Because this is intended to be used in the context of C, we always
// use the C allocator, even though it might not be the most efficient.
const allocator = std.heap.c_allocator;

const bindings = @cImport({
    @cInclude("sdfgen.h");
});

const dtb = modsdf.dtb;
const sddf = modsdf.sddf;
const lionsos = modsdf.lionsos;
const SystemDescription = modsdf.sdf.SystemDescription;
const Pd = SystemDescription.ProtectionDomain;
const Vm = SystemDescription.VirtualMachine;
const Channel = SystemDescription.Channel;
const Mr = SystemDescription.MemoryRegion;
const Map = SystemDescription.Map;
const Arch = SystemDescription.Arch;

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

export fn sdfgen_add_mr(c_sdf: *align(8) anyopaque, c_mr: *align(8) anyopaque) void {
    const sdf: *SystemDescription = @ptrCast(c_sdf);
    const mr: *Mr = @ptrCast(c_mr);
    sdf.addMemoryRegion(mr.*);
}

export fn sdfgen_add_channel(c_sdf: *align(8) anyopaque, c_ch: *align(8) anyopaque) void {
    const sdf: *SystemDescription = @ptrCast(c_sdf);
    const ch: *Channel = @ptrCast(c_ch);
    sdf.addChannel(ch.*);
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

export fn sdfgen_pd_add_map(c_pd: *align(8) anyopaque, c_map: *align(8) anyopaque) void {
    const pd: *Pd = @ptrCast(c_pd);
    const map: *Map = @ptrCast(c_map);

    pd.addMap(map.*);
}

export fn sdfgen_pd_set_priority(c_pd: *align(8) anyopaque, priority: u8) void {
    const pd: *Pd = @ptrCast(c_pd);
    pd.priority = priority;
}

export fn sdfgen_pd_set_budget(c_pd: *align(8) anyopaque, budget: u32) void {
    const pd: *Pd = @ptrCast(c_pd);
    pd.budget = budget;
}

export fn sdfgen_pd_set_period(c_pd: *align(8) anyopaque, period: u32) void {
    const pd: *Pd = @ptrCast(c_pd);
    pd.period = period;
}

export fn sdfgen_pd_set_stack_size(c_pd: *align(8) anyopaque, stack_size: u32) void {
    const pd: *Pd = @ptrCast(c_pd);
    pd.stack_size = stack_size;
}

export fn sdfgen_pd_set_cpu(c_pd: *align(8) anyopaque, cpu: u8) void {
    const pd: *Pd = @ptrCast(c_pd);
    pd.cpu = cpu;
}

export fn sdfgen_pd_set_passive(c_pd: *align(8) anyopaque, passive: bool) void {
    const pd: *Pd = @ptrCast(c_pd);
    pd.passive = passive;
}

export fn sdfgen_pd_set_virtual_machine(c_pd: *align(8) anyopaque, c_vm: *align(8) anyopaque) bool {
    const pd: *Pd = @ptrCast(c_pd);
    const vm: *Vm = @ptrCast(c_vm);
    pd.setVirtualMachine(vm) catch return false;

    return true;
}

export fn sdfgen_vm_create(name: [*c]u8, c_vcpus: [*c]*align(8) anyopaque, num_vcpus: u32) ?*anyopaque {
    var vcpus = std.ArrayList(Vm.Vcpu).initCapacity(allocator, num_vcpus) catch @panic("OOM");
    defer vcpus.deinit();

    var i: usize = 0;
    while (i < num_vcpus) : (i += 1) {
        const vcpu: *Vm.Vcpu = @ptrCast(c_vcpus[i]);
        vcpus.appendAssumeCapacity(vcpu.*);
    }

    const vm = allocator.create(Vm) catch @panic("OOM");
    vm.* = Vm.create(allocator, std.mem.span(name), vcpus.items, .{}) catch return null;

    return vm;
}

export fn sdfgen_vm_destroy(c_vm: *align(8) anyopaque) void {
    const vm: *Vm = @ptrCast(c_vm);
    vm.destroy();
    allocator.destroy(vm);
}

export fn sdfgen_vm_vcpu_create(id: u8, cpu: u16) *anyopaque {
    const vcpu: *Vm.Vcpu = allocator.create(Vm.Vcpu) catch @panic("OOM");
    vcpu.* = Vm.Vcpu{ .id = id, .cpu = cpu };

    return vcpu;
}

export fn sdfgen_vm_vcpu_destroy(c_vcpu: *align(8) anyopaque) void {
    const vcpu: *Vm.Vcpu = @ptrCast(c_vcpu);
    allocator.destroy(vcpu);
}

export fn sdfgen_vm_add_map(c_vm: *align(8) anyopaque, c_map: *align(8) anyopaque) void {
    const vm: *Vm = @ptrCast(c_vm);
    const map: *Map = @ptrCast(c_map);
    vm.addMap(map.*);
}

export fn sdfgen_sddf_init(path: [*c]u8) bool {
    sddf.probe(allocator, std.mem.span(path)) catch |e| {
        std.log.err("sDDF init failed on path {s}: {}", .{ path, e });
        return false;
    };

    return true;
}

export fn sdfgen_mr_create(name: [*c]u8, size: u64) *anyopaque {
    const mr = allocator.create(Mr) catch @panic("OOM");
    mr.* = Mr.create(allocator, std.mem.span(name), size, .{});

    return mr;
}

export fn sdfgen_mr_create_physical(name: [*c]u8, size: u64, paddr: u64) *anyopaque {
    const mr = allocator.create(Mr) catch @panic("OOM");
    mr.* = Mr.create(allocator, std.mem.span(name), size, .{});
    mr.paddr = paddr;

    return mr;
}

export fn sdfgen_mr_destroy(c_mr: *align(8) anyopaque) void {
    const mr: *Mr = @ptrCast(c_mr);
    allocator.destroy(mr);
}

export fn sdfgen_map_create(c_mr: *align(8) anyopaque, vaddr: u64, c_perms: bindings.sdfgen_map_perms_t, cached: bool) *anyopaque {
    const mr: *Mr = @ptrCast(c_mr);

    var perms: Map.Perms = .{};
    if (c_perms & 0b001 != 0) {
        perms.read = true;
    }
    if (c_perms & 0b010 != 0) {
        perms.write = true;
    }
    if (c_perms & 0b100 != 0) {
        perms.execute = true;
    }

    const map = allocator.create(Map) catch @panic("OOM");
    // TODO: I think we got some memory problems if we're dereferencing this stuff since
    // we need MemoryRegion to still be valid the whole time since we depend on it
    map.* = Map.create(mr.*, vaddr, perms, .{ .cached = cached });

    return map;
}

export fn sdfgen_map_destroy(c_map: *align(8) anyopaque) void {
    const map: *Map = @ptrCast(c_map);
    allocator.destroy(map);
}

// TODO: handle specifying channel parameters
export fn sdfgen_channel_create(pd_a: *align(8) anyopaque, pd_b: *align(8) anyopaque) *anyopaque {
    const ch = allocator.create(Channel) catch @panic("OOM");
    ch.* = Channel.create(@ptrCast(pd_a), @ptrCast(pd_b), .{}) catch @panic("TODO");

    return ch;
}

export fn sdfgen_channel_get_pd_a_id(c_ch: *align(8) anyopaque) u8 {
    const ch: *Channel = @ptrCast(c_ch);
    return ch.pd_a_id;
}

export fn sdfgen_channel_get_pd_b_id(c_ch: *align(8) anyopaque) u8 {
    const ch: *Channel = @ptrCast(c_ch);
    return ch.pd_b_id;
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

export fn sdfgen_sddf_timer_add_client(system: *align(8) anyopaque, client: *align(8) anyopaque) bindings.sdfgen_sddf_status_t {
    const timer: *sddf.TimerSystem = @ptrCast(system);
    timer.addClient(@ptrCast(client)) catch |e| {
        switch (e) {
            sddf.TimerSystem.Error.DuplicateClient => return 1,
            sddf.TimerSystem.Error.InvalidClient => return 2,
            // Should never happen when adding a client
            sddf.TimerSystem.Error.NotConnected => @panic("internal error"),
        }
    };

    return 0;
}

export fn sdfgen_sddf_timer_connect(system: *align(8) anyopaque) bool {
    const timer: *sddf.TimerSystem = @ptrCast(system);
    timer.connect() catch return false;

    return true;
}

export fn sdfgen_sddf_timer_serialise_config(system: *align(8) anyopaque, output_dir: [*c]u8) bool {
    const timer: *sddf.TimerSystem = @ptrCast(system);
    timer.serialiseConfig(std.mem.span(output_dir)) catch return false;

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

export fn sdfgen_sddf_serial_add_client(system: *align(8) anyopaque, client: *align(8) anyopaque) bindings.sdfgen_sddf_status_t {
    const serial: *sddf.SerialSystem = @ptrCast(system);
    serial.addClient(@ptrCast(client)) catch |e| {
        switch (e) {
            sddf.SerialSystem.Error.DuplicateClient => return 1,
            sddf.SerialSystem.Error.InvalidClient => return 2,
            // Should never happen when adding a client
            sddf.SerialSystem.Error.NotConnected => @panic("internal error"),
        }
    };

    return 0;
}

export fn sdfgen_sddf_serial_connect(system: *align(8) anyopaque) bool {
    const serial: *sddf.SerialSystem = @ptrCast(system);
    serial.connect() catch return false;

    return true;
}

export fn sdfgen_sddf_serial_serialise_config(system: *align(8) anyopaque, output_dir: [*c]u8) bool {
    const serial: *sddf.SerialSystem = @ptrCast(system);
    serial.serialiseConfig(std.mem.span(output_dir)) catch return false;
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

export fn sdfgen_sddf_i2c_add_client(system: *align(8) anyopaque, client: *align(8) anyopaque) bindings.sdfgen_sddf_status_t {
    const i2c: *sddf.I2cSystem = @ptrCast(system);
    i2c.addClient(@ptrCast(client)) catch |e| {
        switch (e) {
            sddf.I2cSystem.Error.DuplicateClient => return 1,
            sddf.I2cSystem.Error.InvalidClient => return 2,
            // Should never happen when adding a client
            sddf.I2cSystem.Error.NotConnected => @panic("internal error"),
        }
    };

    return 0;
}

export fn sdfgen_sddf_i2c_connect(system: *align(8) anyopaque) bool {
    const i2c: *sddf.I2cSystem = @ptrCast(system);
    i2c.connect() catch return false;

    return true;
}

export fn sdfgen_sddf_i2c_serialise_config(system: *align(8) anyopaque, output_dir: [*c]u8) bool {
    const i2c: *sddf.I2cSystem = @ptrCast(system);
    i2c.serialiseConfig(std.mem.span(output_dir)) catch return false;
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
    block.deinit();
    allocator.destroy(block);
}

export fn sdfgen_sddf_block_add_client(system: *align(8) anyopaque, client: *align(8) anyopaque, partition: u32) bindings.sdfgen_sddf_status_t {
    const block: *sddf.BlockSystem = @ptrCast(system);
    block.addClient(@ptrCast(client), partition) catch |e| {
        switch (e) {
            sddf.BlockSystem.Error.DuplicateClient => return 1,
            sddf.BlockSystem.Error.InvalidClient => return 2,
            // Should never happen when adding a client
            sddf.BlockSystem.Error.NotConnected => @panic("internal error"),
        }
    };

    return 0;
}

export fn sdfgen_sddf_block_connect(system: *align(8) anyopaque) bool {
    const block: *sddf.BlockSystem = @ptrCast(system);
    block.connect() catch return false;

    return true;
}

export fn sdfgen_sddf_block_serialise_config(system: *align(8) anyopaque, output_dir: [*c]u8) bool {
    const block: *sddf.BlockSystem = @ptrCast(system);
    block.serialiseConfig(std.mem.span(output_dir)) catch return false;

    return true;
}

export fn sdfgen_sddf_net(c_sdf: *align(8) anyopaque, c_device: *align(8) anyopaque, driver: *align(8) anyopaque, virt_tx: *align(8) anyopaque, virt_rx: *align(8) anyopaque) *anyopaque {
    const sdf: *SystemDescription = @ptrCast(c_sdf);
    const net = allocator.create(sddf.NetworkSystem) catch @panic("OOM");
    net.* = sddf.NetworkSystem.init(allocator, sdf, @ptrCast(c_device), @ptrCast(driver), @ptrCast(virt_tx), @ptrCast(virt_rx), .{});

    return net;
}

export fn sdfgen_sddf_net_add_client_with_copier(system: *align(8) anyopaque, client: *align(8) anyopaque, copier: *align(8) anyopaque, mac_addr: [*c]u8) bindings.sdfgen_sddf_status_t {
    const net: *sddf.NetworkSystem = @ptrCast(system);
    var options: sddf.NetworkSystem.ClientOptions = .{};
    if (mac_addr) |a| {
        options.mac_addr = std.mem.span(a);
    }
    net.addClientWithCopier(@ptrCast(client), @ptrCast(copier), options) catch |e| {
        switch (e) {
            sddf.NetworkSystem.Error.DuplicateClient => return 1,
            sddf.NetworkSystem.Error.InvalidClient => return 2,
            sddf.NetworkSystem.Error.DuplicateCopier => return 100,
            sddf.NetworkSystem.Error.DuplicateMacAddr => return 101,
            sddf.NetworkSystem.Error.InvalidMacAddr => return 102,
            // Should never happen when adding a client
            sddf.NetworkSystem.Error.NotConnected => @panic("internal error"),
        }
    };

    return 0;
}

export fn sdfgen_sddf_net_connect(system: *align(8) anyopaque) bool {
    const net: *sddf.NetworkSystem = @ptrCast(system);
    net.connect() catch return false;

    return true;
}

export fn sdfgen_sddf_net_serialise_config(system: *align(8) anyopaque, output_dir: [*c]u8) bool {
    const net: *sddf.NetworkSystem = @ptrCast(system);
    net.serialiseConfig(std.mem.span(output_dir)) catch return false;
    return true;
}

export fn sdfgen_sddf_net_destroy(system: *align(8) anyopaque) void {
    const net: *sddf.NetworkSystem = @ptrCast(system);
    allocator.destroy(net);
}

export fn sdfgen_sddf_gpu(c_sdf: *align(8) anyopaque, c_device: *align(8) anyopaque, driver: *align(8) anyopaque, virt: *align(8) anyopaque) *anyopaque {
    const sdf: *SystemDescription = @ptrCast(c_sdf);
    const gpu = allocator.create(sddf.GpuSystem) catch @panic("OOM");
    gpu.* = sddf.GpuSystem.init(allocator, sdf, @ptrCast(c_device), @ptrCast(driver), @ptrCast(virt), .{});

    return gpu;
}

export fn sdfgen_sddf_gpu_destroy(system: *align(8) anyopaque) void {
    const gpu: *sddf.GpuSystem = @ptrCast(system);
    gpu.deinit();
    allocator.destroy(gpu);
}

export fn sdfgen_sddf_gpu_add_client(system: *align(8) anyopaque, client: *align(8) anyopaque) bindings.sdfgen_sddf_status_t {
    const gpu: *sddf.GpuSystem = @ptrCast(system);
    gpu.addClient(@ptrCast(client)) catch |e| {
        switch (e) {
            sddf.GpuSystem.Error.DuplicateClient => return 1,
            sddf.GpuSystem.Error.InvalidClient => return 2,
            // Should never happen when adding a client
            sddf.GpuSystem.Error.NotConnected => @panic("internal error"),
        }
    };

    return 0;
}

export fn sdfgen_sddf_gpu_connect(system: *align(8) anyopaque) bool {
    const gpu: *sddf.GpuSystem = @ptrCast(system);
    gpu.connect() catch return false;

    return true;
}

export fn sdfgen_sddf_gpu_serialise_config(system: *align(8) anyopaque, output_dir: [*c]u8) bool {
    const gpu: *sddf.GpuSystem = @ptrCast(system);
    gpu.serialiseConfig(std.mem.span(output_dir)) catch return false;

    return true;
}

export fn sdfgen_lionsos_fs_fat(c_sdf: *align(8) anyopaque, c_fs: *align(8) anyopaque, c_client: *align(8) anyopaque) *anyopaque {
    const sdf: *SystemDescription = @ptrCast(c_sdf);
    const fs = allocator.create(lionsos.FileSystem.Fat) catch @panic("OOM");
    fs.* = lionsos.FileSystem.Fat.init(allocator, sdf, @ptrCast(c_fs), @ptrCast(c_client), .{}) catch @panic("TODO");

    return fs;
}

export fn sdfgen_lionsos_fs_fat_connect(system: *align(8) anyopaque) bool {
    const fs: *lionsos.FileSystem = @ptrCast(system);
    fs.connect();

    return true;
}

export fn sdfgen_lionsos_fs_nfs(c_sdf: *align(8) anyopaque, c_fs: *align(8) anyopaque, c_client: *align(8) anyopaque, c_net: *align(8) anyopaque, c_net_copier: *align(8) anyopaque) *anyopaque {
    const sdf: *SystemDescription = @ptrCast(c_sdf);
    const fs = allocator.create(lionsos.FileSystem.Nfs) catch @panic("OOM");
    fs.* = lionsos.FileSystem.Nfs.init(allocator, sdf, @ptrCast(c_fs), @ptrCast(c_client), @ptrCast(c_net), @ptrCast(c_net_copier), .{}) catch @panic("TODO");

    return fs;
}

export fn sdfgen_lionsos_fs_nfs_connect(system: *align(8) anyopaque) bool {
    const nfs: *lionsos.FileSystem.Nfs = @ptrCast(system);
    nfs.connect();

    return true;
}
