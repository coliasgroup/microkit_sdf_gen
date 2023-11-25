const std = @import("std");
const mod_sdf = @import("sdf.zig");
const dtb = @import("dtb");
const Allocator = std.mem.Allocator;

const SystemDescription = mod_sdf.SystemDescription;
const Mr = SystemDescription.MemoryRegion;
const Map = SystemDescription.Map;
const Pd = SystemDescription.ProtectionDomain;
const ProgramImage = Pd.ProgramImage;
const Interrupt = SystemDescription.Interrupt;
const Channel = SystemDescription.Channel;

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
var drivers: std.ArrayList(Config.Driver) = undefined;
var classes: std.ArrayList(Config.DeviceClass) = undefined;

const CONFIG_FILENAME = "config.json";

/// Assumes probe() has been called
pub fn findDriver(compatibles: []const []const u8) ?Config.Driver {
    for (drivers.items) |driver| {
        // This is yet another point of weirdness with device trees. It is often
        // the case that there are multiple compatible strings for a device and
        // accompying driver. So we get the user to provide a list of compatible
        // strings, and we check for a match with any of the compatible strings
        // of a driver.
        for (compatibles) |compatible| {
            for (driver.compatible) |driver_compatible| {
                if (std.mem.eql(u8, driver_compatible, compatible)) {
                    // We have found a compatible driver
                    return driver;
                }
            }
        }
    }

    return null;
}

/// Assumes probe() has been called
pub fn compatibleDrivers(allocator: Allocator) ![]const []const u8 {
    // We already know how many drivers exist as well as all their compatible
    // strings, so we know exactly how large the array needs to be.
    var num_compatible: usize = 0;
    for (drivers.items) |driver| {
        num_compatible += driver.compatible.len;
    }
    var array = try std.ArrayList([]const u8).initCapacity(allocator, num_compatible);
    for (drivers.items) |driver| {
        for (driver.compatible) |compatible| {
            array.appendAssumeCapacity(compatible);
        }
    }

    return try array.toOwnedSlice();
}

/// As part of the initilisation, we want to find all the JSON configuration
/// files, parse them, and built up a data structure for us to then search
/// through whenever we want to create a driver to the system description.
pub fn probe(allocator: Allocator, path: []const u8) !void {
    drivers = std.ArrayList(Config.Driver).init(allocator);
    // TODO: we could init capacity with number of DeviceClassType fields
    classes = std.ArrayList(Config.DeviceClass).init(allocator);

    std.log.info("starting sDDF probe", .{});
    std.log.info("opening sDDF root dir '{s}'", .{path});
    var sddf = try std.fs.cwd().openDir(path, .{});
    defer sddf.close();

    const device_classes = comptime std.meta.fields(Config.DeviceClass.Class);
    inline for (device_classes) |device_class| {
        // Search for all the drivers. For each device class we need
        // to iterate through each directory and find the config file
        // TODO: handle this gracefully
        var device_class_dir = try sddf.openDir("drivers/" ++ device_class.name, .{ .iterate = true });
        defer device_class_dir.close();
        var iter = device_class_dir.iterate();
        std.log.info("searching through: 'drivers/{s}'", .{device_class.name});
        while (try iter.next()) |entry| {
            // Under this directory, we should find the configuration file
            const config_path = std.fmt.allocPrint(allocator, "{s}/config.json", .{entry.name}) catch @panic("OOM");
            defer allocator.free(config_path);
            // Attempt to open the configuration file. It is realistic to not
            // have every driver to have a configuration file associated with
            // it, especially during the development of sDDF.
            const config_file = device_class_dir.openFile(config_path, .{}) catch |e| {
                switch (e) {
                    error.FileNotFound => {
                        std.log.info("could not find config file at '{s}', skipping...", .{config_path});
                        continue;
                    },
                    else => return e,
                }
            };
            defer config_file.close();
            std.log.info("reading 'drivers/{s}/{s}'", .{ entry.name, CONFIG_FILENAME });
            const config_size = (try config_file.stat()).size;
            const config = try config_file.reader().readAllAlloc(allocator, config_size);
            // TODO; free config? we'd have to dupe the json data when populating our data structures
            std.debug.assert(config.len == config_size);
            // TODO: we have no information if the parsing fails. We need to do some error output if
            // it the input is malformed.
            // TODO: should probably free the memory at some point
            // We are using an ArenaAllocator so calling parseFromSliceLeaky instead of parseFromSlice
            // is recommended.
            const json = try std.json.parseFromSliceLeaky(Config.Driver.Json, allocator, config, .{});

            try drivers.append(Config.Driver.fromJson(json, device_class.name));
        }
        // Look for all the configuration files inside each of the device class
        // sub-directories.
        const class_config_path = std.fmt.allocPrint(allocator, "{s}/config.json", .{device_class.name}) catch @panic("OOM");
        defer allocator.free(class_config_path);
        if (sddf.openFile(class_config_path, .{})) |class_config_file| {
            defer class_config_file.close();

            const config_size = (try class_config_file.stat()).size;
            const config = try class_config_file.reader().readAllAlloc(allocator, config_size);

            const json = try std.json.parseFromSliceLeaky(Config.DeviceClass.Json, allocator, config, .{});
            try classes.append(Config.DeviceClass.fromJson(json, device_class.name));
        } else |err| {
            switch (err) {
                error.FileNotFound => {
                    std.log.info("could not find class config file at '{s}', skipping...", .{class_config_path});
                },
                else => {
                    std.log.info("error accessing config file ({}) at '{s}', skipping...", .{ err, class_config_path });
                },
            }
        }
    }
}

pub const Config = struct {
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

    /// The actual IRQ number that gets registered with seL4
    /// is something we can determine from the device tree.
    const Irq = struct {
        name: []const u8,
        channel_id: usize,
    };

    /// In the case of drivers there is some extra information we want
    /// to store that is not specified in the JSON configuration.
    /// For example, the device class that the driver belongs to.
    pub const Driver = struct {
        name: []const u8,
        class: DeviceClass.Class,
        compatible: []const []const u8,
        resources: Resources,

        const Resources = struct {
            device_regions: []const Region,
            shared_regions: []const Region,
            irqs: []const Irq,
        };

        pub const Json = struct {
            name: []const u8,
            compatible: []const []const u8,
            resources: Resources,
        };

        pub fn fromJson(json: Json, class: []const u8) Driver {
            return .{
                .name = json.name,
                .class = DeviceClass.Class.fromStr(class),
                .compatible = json.compatible,
                .resources = json.resources,
            };
        }
    };

    pub const Component = struct {
        name: []const u8,
        type: []const u8,
        // resources: Resources,
    };

    pub const DeviceClass = struct {
        class: Class,
        resources: Resources,

        const Json = struct {
            resources: Resources,
        };

        pub fn fromJson(json: Json, class: []const u8) DeviceClass {
            return .{
                .class = DeviceClass.Class.fromStr(class),
                .resources = json.resources,
            };
        }

        /// These are the sDDF device classes that we expect to exist in the
        /// repository and will be searched through.
        /// You could instead have something in the repisitory to list the
        /// device classes or organise the repository differently, but I do
        /// not see the need for that kind of complexity at this time.
        const Class = enum {
            network,
            serial,

            pub fn fromStr(str: []const u8) Class {
                inline for (std.meta.fields(Class)) |field| {
                    if (std.mem.eql(u8, str, field.name)) {
                        return @enumFromInt(field.value);
                    }
                }

                // TODO: don't panic
                @panic("Unexpected device class string given");
            }
        };

        const Resources = struct {
            regions: []const Region,
        };
    };
};

const DeviceTree = struct {
    /// Functionality relating the the ARM Generic Interrupt Controller.
    const ArmGicIrqType = enum {
        spi,
        ppi,
        extended_spi,
        extended_ppi,
    };

    pub fn armGicIrqType(irq_type: usize) !ArmGicIrqType {
        return switch (irq_type) {
            0x0 => .spi,
            0x1 => .ppi,
            0x2 => .extended_spi,
            0x3 => .extended_ppi,
            else => return error.InvalidArmIrqTypeValue,
        };
    }

    pub fn armGicIrqNumber(number: usize, irq_type: ArmGicIrqType) usize {
        return switch (irq_type) {
            .spi => number + 32,
            .ppi => number, // TODO: check this
            .extended_spi, .extended_ppi => @panic("Unexpected IRQ type"),
        };
    }

    pub fn armGicIrqTrigger(trigger: usize) !Interrupt.Trigger {
        return switch (trigger) {
            0x1 => return .edge,
            0x4 => return .level,
            else => return error.InvalidTriggerValue,
        };
    }
};

/// Create the memory regions, mappings, and channels in order to connect a
/// multiplexor with a driver
pub fn connectDriverWithMux(sdf: *SystemDescription, driver: *Pd, mux: *Pd) !void {
    // The goal here is to map in the memory regions for communicating with the driver into the multiplexor.

    // Let's say we have the example of the serial driver.
    // For a TX MUX, We need TX used, TX free, TX data. These memory regions would have already been created from
    // creating the driver and just need to be mapped into the MUX's address space.
    // One of the issues is that we do not know what kind of multiplexor is involved.

    // TODO: we assume that a single channel is sufficient. We also assume that pp does not need to be true
    const channel = Channel.create(driver, mux);
    try sdf.addChannel(channel);
}

/// Create the memory regions, mappings, and channels in order to connect a
/// multiplexor with a client
// pub fn connectMuxWithClient()

/// Given the DTB node for the device and the SDF program image, we can figure
/// all the resources that need to be added to the system description.
pub fn createDriver(sdf: *SystemDescription, pd: *Pd, device: *dtb.Node) !void {
    // First thing to do is find the driver configuration for the device given.
    // The way we do that is by searching for the compatible string described in the DTB node.
    const compatible = device.prop(.Compatible).?;

    // TODO: It is expected for a lot of devices to have multiple compatible strings,
    // we need to deal with that here.
    std.log.debug("Creating driver for device: '{s}'", .{device.name});
    std.log.debug("Compatible with:", .{});
    for (compatible) |c| {
        std.log.debug("     '{s}'", .{c});
    }

    const driver = findDriver(compatible).?;
    std.log.debug("Found compatible driver '{s}'", .{driver.name});
    // TODO: fix, this should be from the DTS

    const device_reg = device.prop(.Reg).?;
    const interrupts = device.prop(.Interrupts).?;
    // TODO: casting from u128 to usize
    var device_paddr: usize = @intCast(device_reg[0][0]);

    // Why is this logic needed? Well it turns out device trees are great and the
    // region of memory that a device occupies in physical memory is... not in the
    // 'reg' property of the device's node in the tree. So here what we do is, as
    // long as there is a parent node, we look and see if it has a memory address
    // and add it to the device's declared 'address'. This needs to be done because
    // some device trees have nodes which are offsets of the parent nodes, this is
    // common with buses. For example, with the Odroid-C4 the main UART is 0x3000
    // offset of the parent bus. We are only interested in the full physical address,
    // hence this logic.
    var parent_node_maybe: ?*dtb.Node = device.parent;
    while (parent_node_maybe) |parent_node| : (parent_node_maybe = parent_node.parent) {
        const parent_node_reg = parent_node.prop(.Reg);
        if (parent_node_reg) |reg| {
            device_paddr += @intCast(reg[0][0]);
        }
    }

    // TODO: handle multiple interrupts. This is not as simple as just looking
    // at the device tree, coordination with the driver configuration is needed.
    std.debug.assert(interrupts.len == 1);
    std.debug.assert(driver.resources.irqs.len == 1);

    // For each set of interrupt values in the device tree 'interrupts' property
    // we expect three entries.
    //      1st is the IRQ type.
    //      2nd is the IRQ number.
    //      3rd is the IRQ trigger.
    // Note that this is specific to the ARM architecture. Fucking DTS people couldn't
    // make it easy to distinguish based on architecture. :((
    for (interrupts) |interrupt| {
        std.debug.assert(interrupt.len == 3);
    }

    // IRQ device tree handling is currently ARM specific.
    std.debug.assert(sdf.arch == .aarch64 or sdf.arch == .aarch32);

    // Determine the IRQ trigger and (software-observable) number based on the device tree.
    const irq_type = try DeviceTree.armGicIrqType(interrupts[0][0]);
    const irq_number = DeviceTree.armGicIrqNumber(interrupts[0][1], irq_type);
    const irq_trigger = try DeviceTree.armGicIrqTrigger(interrupts[0][2]);

    // Create all the memory regions
    var num_regions: usize = 0;
    for (driver.resources.shared_regions) |region| {
        const page_size = try Mr.PageSize.fromInt(region.page_size, sdf.arch);
        const mr_name = std.fmt.allocPrint(sdf.allocator, "{s}_{s}", .{ driver.name, region.name }) catch @panic("OOM");
        const mr = Mr.create(sdf, mr_name, region.size, null, page_size);
        try sdf.addMemoryRegion(mr);

        const perms = Map.Permissions.fromString(region.perms);
        const vaddr = pd.getMapableVaddr(mr.size);
        const map = Map.create(mr, vaddr, perms, region.cached, region.setvar_vaddr);
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
        const vaddr = pd.getMapableVaddr(mr.size);
        const map = Map.create(mr, vaddr, perms, region.cached, region.setvar_vaddr);
        try pd.addMap(map);

        num_regions += 1;
    }

    // Create all the IRQs
    for (driver.resources.irqs) |driver_irq| {
        const irq = SystemDescription.Interrupt.create(irq_number, irq_trigger, driver_irq.channel_id);
        try pd.addInterrupt(irq);
    }
}
