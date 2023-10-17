const std = @import("std");
const mod_sdf = @import("sdf.zig");
const Allocator = std.mem.Allocator;

const SystemDescription = mod_sdf.SystemDescription;
const Mr = SystemDescription.MemoryRegion;
const Map = SystemDescription.Map;
const Pd = SystemDescription.ProtectionDomain;
const ProgramImage = Pd.ProgramImage;

///
/// Expected sDDF repository layout:
///     -- network/
///     -- serial/
///     -- drivers/
///         -- network/
///         -- serial/
///
/// Essentially there should be a top-level directory for a
/// device class and aa directory for each device class inside
/// 'drivers/'.
///

var drivers: std.ArrayList(Driver) = undefined;

const CONFIG_FILE = "config.json";

pub fn findDriver(compatible: []const u8) ?*Driver {
    // TODO: assumes probe has been called
    for (drivers.items) |driver| {
        if (std.mem.eql(u8, driver.compatible, compatible)) {
            // We have found a compatible driver
            return &driver;
        }
    }

    return null;
}

pub fn compatibleDrivers(allocator: Allocator) ![]const []const u8 {
    var array = try std.ArrayList([]const u8).initCapacity(allocator, drivers.items.len);
    for (drivers.items) |driver| {
        array.appendAssumeCapacity(driver.compatible);
    }

    return try array.toOwnedSlice();
}

/// As part of the initilisation, we want to find all the JSON configuration
/// files, parse them, and built up a data structure for us to then search
/// through whenever we want to create a driver to the system description.
pub fn probe(allocator: Allocator, path: []const u8) !void {
    drivers = std.ArrayList(Driver).init(allocator);

    std.log.info("starting sDDF probe", .{});
    // TODO: what if we get an absolute path?
    var sddf = try std.fs.cwd().openDir(path, .{});
    defer sddf.close();

    const device_classes = comptime std.meta.fields(DeviceClasses);
    inline for (device_classes) |device_class| {
        // Search for all the drivers. For each device class we need
        // to iterate through each directory and find the config file
        var device_class_dir = try sddf.openIterableDir("drivers/" ++ device_class.name, .{});
        defer device_class_dir.close();
        var iter = device_class_dir.iterate();
        std.log.info("searching through: 'drivers/{s}'", .{ device_class.name });
        while (try iter.next()) |entry| {
            // Under this directory, we should find the configuration file
            std.log.info("reading 'drivers/{s}/{s}'", .{ entry.name, CONFIG_FILE });
            const config_path = std.fmt.allocPrint(allocator, "{s}/config.json", .{ entry.name }) catch @panic("OOM");
            const config_file = device_class_dir.dir.openFile(config_path, .{}) catch |e| {
                switch (e) {
                    error.FileNotFound => {
                        std.log.warn("Could not find config file at '{s}', skipping...", .{ config_path });
                        continue;
                    },
                    else => return e,
                }
            };
            const config_size = (try config_file.stat()).size;
            const config = try config_file.reader().readAllAlloc(allocator, config_size);
            std.debug.assert(config.len == config_size);
            // TODO: we have no information if the parsing fails. We need to do some error output if
            // it the input is malformed.
            const json = try std.json.parseFromSlice(Driver, allocator, config, .{});
            // std.debug.print("{}\n", .{ std.json.fmt(json.value, .{ .whitespace = .indent_2 }) });

            try drivers.append(json.value);
        }
        // Look for all the configuration files inside each of the
        // device class sub-directories.
    }
}

/// These are the sDDF device classes that we expect to exist in the
/// repository and will be searched through.
/// You could instead have something in the repisitory to list the
/// device classes or organise the repository differently, but I do
/// not see the need for that kind of complexity at this time.
const DeviceClasses = enum {
    network,
    serial
};

const Region = struct {
    /// Name of the region
    name: []const u8,
    /// Permissions to the region of memory once mapped in
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

pub const Component = struct {
    name: []const u8,
    type: []const u8,
    resources: Resources,
};

pub fn createDriver(sdf: *SystemDescription, driver: Driver, device_paddr: usize) !Pd {
    // const program_image = ProgramImage.create(driver.name ++ ".elf");
    const program_image = ProgramImage.create("uart.elf");
    // TODO: deal with passive, priority, and budgets
    var pd = Pd.create(sdf, driver.name, program_image);
    // Create all the memory regions
    var num_regions: usize = 0;
    for (driver.resources.shared_regions) |region| {
        const page_size = try Mr.PageSize.fromInt(region.page_size, sdf.arch);
        const mr_name = std.fmt.allocPrint(sdf.allocator, "{s}_{s}", .{ driver.name, region.name }) catch @panic("OOM");
        const mr = Mr.create(sdf, mr_name, region.size, null, page_size);
        try sdf.addMemoryRegion(mr);

        const perms = Map.Permissions.fromString(region.perms);
        // TODO: hack in terms of vaddr determination
        const map = Map.create(mr, 0x5_000_000 + 0x1_000_000 * num_regions, perms, region.cached, region.setvar_vaddr);
        try pd.addMap(map);

        num_regions += 1;
    }

    // TODO: support more than one device region, it will most likely be needed in the future.
    std.debug.assert(driver.resources.device_regions.len == 1);
    for (driver.resources.device_regions) |region| {
        const page_size = try Mr.PageSize.fromInt(region.page_size, sdf.arch);
        const mr_name = std.fmt.allocPrint(sdf.allocator, "{s}_{s}", .{ driver.name, region.name }) catch @panic("OOM");
        const mr = Mr.create(sdf, mr_name, region.size, device_paddr, page_size);
        try sdf.addMemoryRegion(mr);

        const perms = Map.Permissions.fromString(region.perms);
        // TODO: hack in terms of vaddr determination
        const map = Map.create(mr, 0x5_000_000 + 0x1_000_000 * num_regions, perms, region.cached, region.setvar_vaddr);
        try pd.addMap(map);

        num_regions += 1;
    }

    // Create all the IRQs
    for (driver.resources.irqs) |driver_irq| {
        // TODO: irq trigger should come from DTS
        const irq = SystemDescription.Interrupt.create(driver_irq.irq, .level, driver_irq.id);
        try pd.addInterrupt(irq);
    }
    // Create all the channels?

    return pd;
}
