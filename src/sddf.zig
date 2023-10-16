const std = @import("std");
const sdf = @import("sdf.zig");
const Allocator = std.mem.Allocator;

const SystemDescription = sdf.SystemDescription;
const MemoryRegion = SystemDescription.MemoryRegion;
const Map = SystemDescription.Map;
const Interrupt = SystemDescription.Interrupt;
const ProtectionDomain = SystemDescription.ProtectionDomain;
const ProgramImage = ProtectionDomain.ProgramImage;

// pub fn createMux(system: *SystemDescription, mux: Mux)

const Region = struct {
    name: []const u8,
    perms: []const u8,
    // TODO: do we need cached or can we decide based on the type?
    cached: bool,
    setvar_vaddr: ?[]const u8,
    page_size: usize,
    size: usize,
};

const Irq = struct {
    irq: usize,
    id: usize,
};

const Resources = struct {
    device_regions: []const Region,
    shared_regions: []const Region,
    irqs: []const Irq,
};

pub const Driver = struct {
    name: []const u8,
    type: []const u8,
    compatible: []const u8,
    resources: Resources,
};

fn fmtPrint(allocator: Allocator, comptime fmt: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(allocator, fmt, args) catch "Could not format print!";
}

pub fn createDriver(system: *SystemDescription, driver: Driver, device_paddr: usize) !ProtectionDomain {
    // const program_image = ProgramImage.create(driver.name ++ ".elf");
    const program_image = ProgramImage.create("uart.elf");
    // TODO: deal with passive, priority, and budgets
    var pd = ProtectionDomain.create(system.allocator, driver.name, program_image, null, null, null, false);
    // Create all the memory regions
    var num_regions: usize = 0;
    for (driver.resources.shared_regions) |region| {
        const page_size = try MemoryRegion.PageSize.fromInt(region.page_size, system.arch);
        const mr_name = fmtPrint(system.allocator, "{s}_{s}", .{ driver.name, region.name });
        const mr = MemoryRegion.create(system, mr_name, region.size, null, page_size);
        try system.addMemoryRegion(mr);

        const perms = Map.Permissions.fromString(region.perms);
        // TODO: hack in terms of vaddr determination
        const map = Map.create(mr, 0x5_000_000 + 0x1_000_000 * num_regions, perms, region.cached, region.setvar_vaddr);
        try pd.addMap(map);

        num_regions += 1;
    }

    // TODO: support more than one device region, it will most likely be needed in the future.
    std.debug.assert(driver.resources.device_regions.len == 1);
    for (driver.resources.device_regions) |region| {
        const page_size = try MemoryRegion.PageSize.fromInt(region.page_size, system.arch);
        const mr_name = fmtPrint(system.allocator, "{s}_{s}", .{ driver.name, region.name });
        const mr = MemoryRegion.create(system, mr_name, region.size, device_paddr, page_size);
        std.debug.print("driver.name: {s}\n", .{ driver.name });
        std.debug.print("allocating: {s}\n", .{ mr_name });
        std.debug.print("allocating mr.name: {s}\n", .{ mr.name });
        try system.addMemoryRegion(mr);

        const perms = Map.Permissions.fromString(region.perms);
        // TODO: hack in terms of vaddr determination
        const map = Map.create(mr, 0x5_000_000 + 0x1_000_000 * num_regions, perms, region.cached, region.setvar_vaddr);
        try pd.addMap(map);

        num_regions += 1;
    }

    // Create all the IRQs
    for (driver.resources.irqs) |driver_irq| {
        // TODO: irq trigger should come from DTS
        const irq = Interrupt.create(driver_irq.irq, .level, driver_irq.id);
        try pd.addInterrupt(irq);
    }
    // Create all the channels?

    return pd;
}
