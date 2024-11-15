const std = @import("std");
const builtin = @import("builtin");
const mod_sdf = @import("sdf.zig");
const dtb = @import("dtb");
const data = @import("data.zig");
const log = @import("log.zig");

const fs = std.fs;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const SystemDescription = mod_sdf.SystemDescription;
const Mr = SystemDescription.MemoryRegion;
const Map = SystemDescription.Map;
const Pd = SystemDescription.ProtectionDomain;
const Interrupt = SystemDescription.Interrupt;
const Channel = SystemDescription.Channel;
const SetVar = SystemDescription.SetVar;

const ConfigResources = data.Resources;

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

/// Whether or not we have probed sDDF
// TODO: should probably just happen upon `init` of sDDF, then
// we pass around sddf everywhere?
var probed = false;

fn fmt(allocator: Allocator, comptime s: []const u8, args: anytype) []u8 {
    return std.fmt.allocPrint(allocator, s, args) catch @panic("OOM");
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

pub fn wasmProbe(allocator: Allocator, driverConfigs: anytype, classConfigs: anytype) !void {
    drivers = std.ArrayList(Config.Driver).init(allocator);
    // TODO: we could init capacity with number of DeviceClassType fields
    classes = std.ArrayList(Config.DeviceClass).init(allocator);

    var i: usize = 0;
    while (i < driverConfigs.items.len) : (i += 1) {
        const config = driverConfigs.items[i].object;
        const json = try std.json.parseFromSliceLeaky(Config.Driver.Json, allocator, config.get("content").?.string, .{});
        try drivers.append(Config.Driver.fromJson(json, config.get("class").?.string));
    }
    // for (driverConfigs) |config| {
    //     const json = try std.json.parseFromSliceLeaky(Config.Driver.Json, allocator, config.get("content").?.content, .{});
    //     try drivers.append(Config.Driver.fromJson(json, config.get("class").?.name));
    // }

    i = 0;
    while (i < classConfigs.items.len) : (i += 1) {
        const config = classConfigs.items[i].object;
        const json = try std.json.parseFromSliceLeaky(Config.DeviceClass.Json, allocator, config.get("content").?.string, .{});
        try classes.append(Config.DeviceClass.fromJson(json, config.get("class").?.string));
    }
    // for (classConfigs) |config| {
    //     const json = try std.json.parseFromSliceLeaky(Config.DeviceClass.Json, allocator, config.get("content").?.content, .{});
    //     try classes.append(Config.DeviceClass.fromJson(json, config.get("class").?.name));
    // }
    probed = true;
}

/// As part of the initilisation, we want to find all the JSON configuration
/// files, parse them, and built up a data structure for us to then search
/// through whenever we want to create a driver to the system description.
pub fn probe(allocator: Allocator, path: []const u8) !void {
    drivers = std.ArrayList(Config.Driver).init(allocator);
    // TODO: we could init capacity with number of DeviceClassType fields
    classes = std.ArrayList(Config.DeviceClass).init(allocator);

    log.debug("starting sDDF probe", .{});
    log.debug("opening sDDF root dir '{s}'", .{path});
    var sddf = try std.fs.cwd().openDir(path, .{});
    defer sddf.close();

    const device_classes = comptime std.meta.fields(Config.DeviceClass.Class);
    inline for (device_classes) |device_class| {
        // Search for all the drivers. For each device class we need
        // to iterate through each directory and find the config file
        // TODO: handle this gracefully
        for (@as(Config.DeviceClass.Class, @enumFromInt(device_class.value)).dirs()) |dir| {
            const driver_dir = std.fmt.allocPrint(allocator, "drivers/{s}", .{dir}) catch @panic("OOM");
            var device_class_dir = try sddf.openDir(driver_dir, .{ .iterate = true });
            defer device_class_dir.close();
            var iter = device_class_dir.iterate();
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
                            continue;
                        },
                        else => return e,
                    }
                };
                defer config_file.close();
                const config_size = (try config_file.stat()).size;
                const config = try config_file.reader().readAllAlloc(allocator, config_size);
                // TODO; free config? we'd have to dupe the json data when populating our data structures
                assert(config.len == config_size);
                // TODO: we have no information if the parsing fails. We need to do some error output if
                // it the input is malformed.
                // TODO: should probably free the memory at some point
                // We are using an ArenaAllocator so calling parseFromSliceLeaky instead of parseFromSlice
                // is recommended.
                const json = try std.json.parseFromSliceLeaky(Config.Driver.Json, allocator, config, .{});

                try drivers.append(Config.Driver.fromJson(json, device_class.name));
            }
        }
    }

    // Probing finished
    probed = true;
}

pub const Config = struct {
    const Region = struct {
        /// Name of the region
        name: []const u8,
        /// Permissions to the region of memory once mapped in
        perms: []const u8,
        setvar_vaddr: ?[]const u8,
        size: usize,
        // Index into 'reg' property of the device tree
        dt_index: usize,
    };

    /// The actual IRQ number that gets registered with seL4
    /// is something we can determine from the device tree.
    const Irq = struct {
        channel_id: usize,
        /// Index into the 'interrupts' property of the Device Tree
        dt_index: usize,
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
            timer,
            blk,
            i2c,

            pub fn fromStr(str: []const u8) Class {
                inline for (std.meta.fields(Class)) |field| {
                    if (std.mem.eql(u8, str, field.name)) {
                        return @enumFromInt(field.value);
                    }
                }

                // TODO: don't panic
                @panic("Unexpected device class string given");
            }

            pub fn dirs(comptime self: Class) []const []const u8 {
                return switch (self) {
                    .network => &.{"network"},
                    .serial => &.{"serial"},
                    .timer => &.{"timer"},
                    .blk => &.{ "blk", "blk/mmc" },
                    .i2c => &.{"i2c"},
                };
            }
        };

        const Resources = struct {
            regions: []const Region,
        };
    };
};

pub const DeviceTree = struct {
    pub fn isCompatible(device_compatibles: []const []const u8, compatibles: []const []const u8) bool {
        // Go through the given compatibles and see if they match with anything on the device.
        for (compatibles) |compatible| {
            for (device_compatibles) |device_compatible| {
                if (std.mem.eql(u8, device_compatible, compatible)) {
                    return true;
                }
            }
        }

        return false;
    }

    pub fn memory(d: *dtb.Node) ?*dtb.Node {
        for (d.children) |child| {
            const device_type = child.prop(.DeviceType);
            if (device_type != null) {
                if (std.mem.eql(u8, "memory", device_type.?)) {
                    return child;
                }
            }

            if (memory(child)) |memory_node| {
                return memory_node;
            }
        }

        return null;
    }

    /// Functionality relating the the ARM Generic Interrupt Controller.
    const ArmGicIrqType = enum {
        spi,
        ppi,
        extended_spi,
        extended_ppi,
    };

    pub const ArmGic = struct {
        const Version = enum { two, three };

        cpu_paddr: u64,
        vcpu_paddr: u64,
        vcpu_size: u64,
        version: Version,

        const compatible = compatible_v2 ++ compatible_v3;
        const compatible_v2 = [_][]const u8{ "arm,gic-v2", "arm,cortex-a15-gic", "arm,gic-400" };
        const compatible_v3 = [_][]const u8{"arm,gic-v3"};

        pub fn fromDtb(d: *dtb.Node) ArmGic {
            // Find the GIC with any compatible string, regardless of version.
            const maybe_gic_node = DeviceTree.findCompatible(d, &ArmGic.compatible);
            if (maybe_gic_node == null) {
                @panic("Cannot find ARM GIC device in device tree");
            }
            const gic_node = maybe_gic_node.?;
            // Get the GIC version first.
            const node_compatible = gic_node.prop(.Compatible).?;
            const version = blk: {
                if (isCompatible(node_compatible, &compatible_v2)) {
                    break :blk Version.two;
                } else if (isCompatible(node_compatible, &compatible_v3)) {
                    break :blk Version.three;
                } else {
                    unreachable;
                }
            };

            const vcpu_dt_index: usize = switch (version) {
                .two => 3,
                .three => 4,
            };
            const cpu_dt_index: usize = switch (version) {
                .two => 1,
                .three => 2,
            };
            // TODO: need to check indexes are valid
            const gic_reg = gic_node.prop(.Reg).?;
            const vcpu_paddr = DeviceTree.regToPaddr(gic_node, gic_reg[vcpu_dt_index][0]);
            const vcpu_size = gic_reg[vcpu_dt_index][1];
            const cpu_paddr = DeviceTree.regToPaddr(gic_node, gic_reg[cpu_dt_index][0]);

            return .{
                .cpu_paddr = cpu_paddr,
                .vcpu_paddr = vcpu_paddr,
                // TODO: down cast
                .vcpu_size = @intCast(vcpu_size),
                .version = version,
            };
        }
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
            .ppi => number + 16,
            .extended_spi, .extended_ppi => @panic("Unexpected IRQ type"),
        };
    }

    pub fn armGicSpiTrigger(trigger: usize) !Interrupt.Trigger {
        return switch (trigger) {
            0x1 => return .edge,
            0x4 => return .level,
            else => return error.InvalidTriggerValue,
        };
    }

    pub fn findCompatible(d: *dtb.Node, compatibles: []const []const u8) ?*dtb.Node {
        for (d.children) |child| {
            const device_compatibles = child.prop(.Compatible);
            // It is possible for a node to not have any compatibles
            if (device_compatibles != null) {
                for (compatibles) |compatible| {
                    for (device_compatibles.?) |device_compatible| {
                        if (std.mem.eql(u8, device_compatible, compatible)) {
                            return child;
                        }
                    }
                }
            }
            if (findCompatible(child, compatibles)) |compatible_child| {
                return compatible_child;
            }
        }

        return null;
    }

    // Given an address from a DTB node's 'reg' property, convert it to a
    // mappable MMIO address. This involves traversing any higher-level busses
    // to find the CPU visible address rather than some address relative to the
    // particular bus the address is on. We also align to the smallest page size;
    // Assumes smallest page size is 0x1000;
    pub fn regToPaddr(device: *dtb.Node, paddr: u128) u64 {
        // TODO: casting from u128 to u64
        var device_paddr: u64 = @intCast((paddr >> 12) << 12);
        // TODO: doesn't work on the maaxboard
        var parent_node_maybe: ?*dtb.Node = device.parent;
        while (parent_node_maybe) |parent_node| : (parent_node_maybe = parent_node.parent) {
            const parent_node_compatible = parent_node.prop(.Compatible);
            if (parent_node_compatible) |compatible| {
                // TODO: this is the only pattern I can notice for when this behaviour is necessary on the odroidc4
                if (isCompatible(compatible, &.{"simple-bus"})) {
                    const parent_node_reg = parent_node.prop(.Reg);
                    if (parent_node_reg) |reg| {
                        device_paddr += @intCast(reg[0][0]);
                    }
                }
            }
        }

        return device_paddr;
    }

    pub fn regToSize(size: u128) u64 {
        // TODO: store page size somewhere
        if (size < 0x1000) {
            return 0x1000;
        } else {
            // TODO: round to page size
            return @intCast(size);
        }
    }
};

pub const TimerSystem = struct {
    allocator: Allocator,
    sdf: *SystemDescription,
    /// Protection Domain that will act as the driver for the timer
    driver: *Pd,
    /// Device Tree node for the timer device
    device: *dtb.Node,
    /// Client PDs serviced by the timer driver
    clients: std.ArrayList(*Pd),

    pub fn init(allocator: Allocator, sdf: *SystemDescription, device: *dtb.Node, driver: *Pd) TimerSystem {
        // First we have to set some properties on the driver. It is currently our policy that every timer
        // driver should be passive.
        driver.passive = true;

        return .{
            .allocator = allocator,
            .sdf = sdf,
            .driver = driver,
            .device = device,
            .clients = std.ArrayList(*Pd).init(allocator),
        };
    }

    pub fn deinit(system: *TimerSystem) void {
        system.clients.deinit();
    }

    pub fn addClient(system: *TimerSystem, client: *Pd) void {
        system.clients.append(client) catch @panic("Could not add client to TimerSystem");
    }

    pub fn connect(system: *TimerSystem) !void {
        // The driver must be passive and it must be able to receive protected procedure calls
        assert(system.driver.passive);

        try createDriver(system.sdf, system.driver, system.device, .timer);
        for (system.clients.items) |client| {
            system.sdf.addChannel(Channel.create(system.driver, client, .{
                // Client needs to be able to PPC into driver
                .pp = .b,
                // Client does not need to notify driver
                .pd_b_notify = false,
            }));
        }
    }
};

pub const I2cSystem = struct {
    allocator: Allocator,
    sdf: *SystemDescription,
    driver: *Pd,
    device: ?*dtb.Node,
    virt: *Pd,
    clients: std.ArrayList(*Pd),
    region_req_size: usize,
    region_resp_size: usize,
    region_data_size: usize,
    driver_config: ConfigResources.I2c.Driver,
    virt_config: ConfigResources.I2c.Virt,
    client_configs: std.ArrayList(ConfigResources.I2c.Client),

    pub const Options = struct {
        region_req_size: usize = 0x1000,
        region_resp_size: usize = 0x1000,
        region_data_size: usize = 0x1000,
    };

    pub fn init(allocator: Allocator, sdf: *SystemDescription, device: ?*dtb.Node, driver: *Pd, virt: *Pd, options: Options) I2cSystem {
        return .{
            .allocator = allocator,
            .sdf = sdf,
            .clients = std.ArrayList(*Pd).init(allocator),
            .driver = driver,
            .device = device,
            .virt = virt,
            .region_req_size = options.region_req_size,
            .region_resp_size = options.region_resp_size,
            .region_data_size = options.region_data_size,
            .driver_config = std.mem.zeroes(ConfigResources.I2c.Driver),
            .virt_config = std.mem.zeroes(ConfigResources.I2c.Virt),
            .client_configs = std.ArrayList(ConfigResources.I2c.Client).init(allocator),
        };
    }

    pub fn addClient(system: *I2cSystem, client: *Pd) void {
        system.clients.append(client) catch @panic("Could not add client to I2cSystem");
        system.client_configs.append(std.mem.zeroes(ConfigResources.I2c.Client)) catch @panic("Could not add client to I2cSystem");
    }

    pub fn connectDriver(system: *I2cSystem) void {
        const allocator = system.allocator;
        var sdf = system.sdf;
        var driver = system.driver;
        var virt = system.virt;

        // Create all the MRs between the driver and virtualiser
        const mr_req = Mr.create(allocator, "i2c_driver_request", system.region_req_size, .{});
        const mr_resp = Mr.create(allocator, "i2c_driver_response", system.region_resp_size, .{});

        sdf.addMemoryRegion(mr_req);
        sdf.addMemoryRegion(mr_resp);

        const driver_map_req = Map.create(mr_req, driver.getMapVaddr(&mr_req), .rw, true, .{});
        driver.addMap(driver_map_req);
        const driver_map_resp = Map.create(mr_resp, driver.getMapVaddr(&mr_resp), .rw, true, .{});
        driver.addMap(driver_map_resp);

        const virt_map_req = Map.create(mr_req, virt.getMapVaddr(&mr_req), .rw, true, .{});
        virt.addMap(virt_map_req);
        const virt_map_resp = Map.create(mr_resp, virt.getMapVaddr(&mr_resp), .rw, true, .{});
        virt.addMap(virt_map_resp);

        system.driver_config.request_region = driver_map_req.vaddr;
        system.driver_config.response_region = driver_map_resp.vaddr;
        system.virt_config.driver_request_queue = virt_map_req.vaddr;
        system.virt_config.driver_response_queue = virt_map_resp.vaddr;
    }

    pub fn connectClient(system: *I2cSystem, client: *Pd, i: usize) void {
        const allocator = system.allocator;
        var sdf = system.sdf;
        const virt = system.virt;
        var driver = system.driver;

        system.virt_config.num_clients += 1;

        // TODO: use optimal size
        const mr_req = Mr.create(allocator, fmt(allocator, "i2c_client_request_{s}", .{client.name}), system.region_req_size, .{});
        const mr_resp = Mr.create(allocator, fmt(allocator, "i2c_client_response_{s}", .{client.name}), system.region_resp_size, .{});
        const mr_data = Mr.create(allocator, fmt(allocator, "i2c_client_data_{s}", .{client.name}), system.region_data_size, .{});

        sdf.addMemoryRegion(mr_req);
        sdf.addMemoryRegion(mr_resp);
        sdf.addMemoryRegion(mr_data);

        const driver_map_data = Map.create(mr_data, system.driver.getMapVaddr(&mr_data), .rw, true, .{});
        driver.addMap(driver_map_data);

        const virt_map_req = Map.create(mr_req, system.virt.getMapVaddr(&mr_req), .rw, true, .{});
        virt.addMap(virt_map_req);
        const virt_map_resp = Map.create(mr_resp, system.virt.getMapVaddr(&mr_resp), .rw, true, .{});
        virt.addMap(virt_map_resp);

        const client_map_req = Map.create(mr_req, client.getMapVaddr(&mr_req), .rw, true, .{});
        client.addMap(client_map_req);
        const client_map_resp = Map.create(mr_resp, client.getMapVaddr(&mr_resp), .rw, true, .{});
        client.addMap(client_map_resp);
        const client_map_data = Map.create(mr_data, client.getMapVaddr(&mr_data), .rw, true, .{});
        client.addMap(client_map_data);

        system.virt_config.clients[i] = .{
            .driver_data_offset = i * system.region_data_size,
            .request_queue = virt_map_req.vaddr,
            .response_queue = virt_map_resp.vaddr,
            .data_size = system.region_data_size,
        };
        if (i == 0) {
            system.driver_config.data_region = driver_map_data.vaddr;
        }
        system.client_configs.items[i] = .{
            .request_region = client_map_req.vaddr,
            .response_region = client_map_resp.vaddr,
            .data_region = client_map_data.vaddr,
        };

        // Create a channel between the virtualiser and client
        sdf.addChannel(.create(virt, client, .{ .pp = .b }));
    }

    pub fn connect(system: *I2cSystem) !void {
        const sdf = system.sdf;

        // 1. Create the device resources for the driver
        if (system.device) |device| {
            try createDriver(sdf, system.driver, device, .i2c);
        }
        // 2. Connect the driver to the virtualiser
        system.connectDriver();
        // 3. Create a channel between the driver and virtualiser for notifications
        sdf.addChannel(.create(system.driver, system.virt, .{}));
        // 4. Connect each client to the virtualiser
        for (system.clients.items, 0..) |client, i| {
            system.connectClient(client, i);
        }

        // To avoid cross-core IPC, we make the virtualiser passive
        system.virt.passive = true;
    }

    pub fn serialiseConfig(system: *I2cSystem, prefix: []const u8) !void {
        const allocator = system.allocator;

        try data.serialize(system.driver_config, try fs.path.join(allocator, &.{ prefix, "i2c_driver.data" }));
        try data.jsonify(system.driver_config, try fs.path.join(allocator, &.{ prefix, "i2c_driver.json" }), .{ .whitespace = .indent_4 });

        try data.serialize(system.virt_config, try fs.path.join(allocator, &.{ prefix, "i2c_virt.data" }));
        try data.jsonify(system.virt_config, try fs.path.join(allocator, &.{ prefix, "i2c_virt.json" }), .{ .whitespace = .indent_4 });

        for (system.clients.items, 0..) |client, i| {
            const data_name = std.fmt.allocPrint(allocator, "i2c_{s}.data", .{client.name}) catch @panic("OOM");
            const json_name = std.fmt.allocPrint(allocator, "i2c_{s}.json", .{client.name}) catch @panic("OOM");
            try data.serialize(system.client_configs.items[i], try fs.path.join(allocator, &.{ prefix, data_name }));
            try data.jsonify(system.client_configs.items[i], try fs.path.join(allocator, &.{ prefix, json_name }), .{ .whitespace = .indent_4 });
        }
    }
};

pub const BlockSystem = struct {
    allocator: Allocator,
    sdf: *SystemDescription,
    driver: *Pd,
    device: *dtb.Node,
    virt: *Pd,
    clients: std.ArrayList(*Pd),
    client_partitions: std.ArrayList(u32),
    connected: bool = false,
    // TODO: make this configurable per component
    queue_mr_size: usize,
    // TODO: make configurable
    queue_capacity: usize = 128,
    config: SerialiseConfig,

    const SerialiseConfig = struct {
        virt_driver: ConfigResources.Block.Virt.Driver = undefined,
        virt_clients: std.ArrayList(ConfigResources.Block.Virt.Client),
        clients: std.ArrayList(ConfigResources.Block.Client),
    };

    pub const Options = struct {};

    const REGION_CONFIG_SIZE: usize = 0x1000;

    pub fn init(allocator: Allocator, sdf: *SystemDescription, device: *dtb.Node, driver: *Pd, virt: *Pd, _: Options) BlockSystem {
        return .{
            .allocator = allocator,
            .sdf = sdf,
            .clients = std.ArrayList(*Pd).init(allocator),
            .client_partitions = std.ArrayList(u32).init(allocator),
            .driver = driver,
            .device = device,
            .virt = virt,
            // TODO: make configurable
            .queue_mr_size = 0x200_000,
            .config = .{
                .virt_clients = std.ArrayList(ConfigResources.Block.Virt.Client).init(allocator),
                .clients = std.ArrayList(ConfigResources.Block.Client).init(allocator),
            },
        };
    }

    pub fn addClient(system: *BlockSystem, client: *Pd, partition: u32) void {
        system.clients.append(client) catch @panic("Could not add client to BlockSystem");
        system.client_partitions.append(partition) catch @panic("Could not add client to BlockSystem");
    }

    pub fn connectDriver(system: *BlockSystem) void {
        const sdf = system.sdf;
        const allocator = system.allocator;
        const driver = system.driver;
        const virt = system.virt;
        // TODO: temporary for virtIO driver
        if (std.mem.eql(u8, system.device.prop(.Compatible).?[0], "virtio,mmio")) {
            const virtio_headers_mr = Mr.create(allocator, "blk_virtio_headers", 0x10_000, .{});
            const virtio_metadata = Mr.create(allocator, "blk_driver_metadata", 0x200_000, .{});

            system.sdf.addMemoryRegion(virtio_headers_mr);
            system.sdf.addMemoryRegion(virtio_metadata);

            system.driver.addMap(.create(virtio_headers_mr, system.driver.getMapVaddr(&virtio_headers_mr), .rw, false, .{ .setvar_vaddr = "virtio_headers_vaddr" }));
            system.driver.addMap(.create(virtio_metadata, system.driver.getMapVaddr(&virtio_metadata), .rw, false, .{ .setvar_vaddr = "requests_vaddr" }));

            system.driver.addSetVar(.create("virtio_headers_paddr", &virtio_headers_mr));
            system.driver.addSetVar(.create("requests_paddr", &virtio_metadata));
        }
        const mr_config = Mr.create(allocator, "blk_driver_config", REGION_CONFIG_SIZE, .{});
        const map_config_driver = Map.create(mr_config, system.driver.getMapVaddr(&mr_config), .rw, true, .{ .setvar_vaddr = "blk_storage_info" });
        const map_config_virt = Map.create(mr_config, system.virt.getMapVaddr(&mr_config), .r, true, .{});

        sdf.addMemoryRegion(mr_config);
        driver.addMap(map_config_driver);
        virt.addMap(map_config_virt);

        // TODO: deal with size
        const mr_req = Mr.create(allocator, "blk_driver_request", 0x200_000, .{});
        const map_req_driver = Map.create(mr_req, driver.getMapVaddr(&mr_req), .rw, true, .{ .setvar_vaddr = "blk_req_queue" });
        const map_req_virt = Map.create(mr_req, virt.getMapVaddr(&mr_req), .rw, true, .{});

        sdf.addMemoryRegion(mr_req);
        driver.addMap(map_req_driver);
        virt.addMap(map_req_virt);

        const mr_resp = Mr.create(allocator, "blk_driver_response", 0x200_000, .{});
        const map_resp_driver = Map.create(mr_resp, driver.getMapVaddr(&mr_resp), .rw, true, .{ .setvar_vaddr = "blk_resp_queue" });
        const map_resp_virt = Map.create(mr_resp, virt.getMapVaddr(&mr_resp), .rw, true, .{});

        sdf.addMemoryRegion(mr_resp);
        driver.addMap(map_resp_driver);
        virt.addMap(map_resp_virt);

        const mr_data = Mr.physical(allocator, sdf, "blk_driver_data", 0x200_000, .{});
        const map_data_virt = Map.create(mr_data, virt.getMapVaddr(&mr_data), .rw, true, .{});

        sdf.addMemoryRegion(mr_data);
        virt.addMap(map_data_virt);

        system.sdf.addChannel(.create(system.virt, system.driver, .{}));

        system.config.virt_driver = .{
            .storage_info = map_config_virt.vaddr,
            .req_queue = map_req_virt.vaddr,
            .resp_queue = map_resp_virt.vaddr,
            .data_vaddr = map_data_virt.vaddr,
            // We have allocated an MR at a fixed physical address so this is valid.
            .data_paddr = mr_data.paddr.?,
            .data_size = map_data_virt.mr.size,
        };
    }

    pub fn connectClient(system: *BlockSystem, client: *Pd, i: usize) void {
        const sdf = system.sdf;
        const allocator = system.allocator;
        const queue_mr_size = system.queue_mr_size;

        const mr_config = Mr.create(allocator, fmt(allocator, "blk_client_{s}_config", .{client.name}), REGION_CONFIG_SIZE, .{});
        const map_config_virt = Map.create(mr_config, system.virt.getMapVaddr(&mr_config), .rw, true, .{});
        const map_config_client = Map.create(mr_config, client.getMapVaddr(&mr_config), .r, true, .{});

        system.sdf.addMemoryRegion(mr_config);
        system.virt.addMap(map_config_virt);
        client.addMap(map_config_client);

        const mr_req = Mr.create(allocator, fmt(allocator, "blk_client_{s}_request", .{client.name}), queue_mr_size, .{});
        const map_req_virt = Map.create(mr_req, system.virt.getMapVaddr(&mr_req), .rw, true, .{});
        const map_req_client = Map.create(mr_req, client.getMapVaddr(&mr_req), .rw, true, .{});

        system.sdf.addMemoryRegion(mr_req);
        system.virt.addMap(map_req_virt);
        client.addMap(map_req_client);

        const mr_resp = Mr.create(allocator, fmt(allocator, "blk_client_{s}_response", .{client.name}), queue_mr_size, .{});
        const map_resp_virt = Map.create(mr_resp, system.virt.getMapVaddr(&mr_resp), .rw, true, .{});
        const map_resp_client = Map.create(mr_resp, client.getMapVaddr(&mr_resp), .rw, true, .{});

        system.sdf.addMemoryRegion(mr_resp);
        system.virt.addMap(map_resp_virt);
        client.addMap(map_resp_client);

        const mr_data = Mr.physical(allocator, sdf, fmt(allocator, "blk_client_{s}_data", .{client.name}), queue_mr_size, .{});
        const map_data_virt = Map.create(mr_data, system.virt.getMapVaddr(&mr_data), .rw, true, .{});
        const map_data_client = Map.create(mr_data, client.getMapVaddr(&mr_data), .rw, true, .{});

        system.sdf.addMemoryRegion(mr_data);
        system.virt.addMap(map_data_virt);
        client.addMap(map_data_client);

        system.sdf.addChannel(.create(system.virt, client, .{}));

        system.config.virt_clients.append(.{
            .req_queue = map_req_virt.vaddr,
            .resp_queue = map_resp_virt.vaddr,
            .storage_info = map_config_virt.vaddr,
            .data_vaddr = map_data_virt.vaddr,
            .data_paddr = mr_data.paddr.?,
            .data_size = mr_data.size,
            .queue_mr_size = queue_mr_size,
            .partition = system.client_partitions.items[i],
        }) catch @panic("could not add virt client config");

        system.config.clients.append(.{
            .storage_info = map_config_client.vaddr,
            .req_queue = map_req_client.vaddr,
            .resp_queue = map_resp_client.vaddr,
            .data_vaddr = map_data_client.vaddr,
            .queue_capacity = system.queue_capacity,
        }) catch @panic("could not add client config");
    }

    pub fn connect(system: *BlockSystem) !void {
        const sdf = system.sdf;

        // 1. Create the device resources for the driver
        try createDriver(sdf, system.driver, system.device, .blk);
        // 2. Connect the driver to the virtualiser
        system.connectDriver();
        // 3. Connect each client to the virtualiser
        for (system.clients.items, 0..) |client, i| {
            system.connectClient(client, i);
        }

        system.connected = true;
    }

    pub fn serialiseConfig(system: *BlockSystem, prefix: []const u8) !void {
        if (!system.connected) return error.SystemNotConnected;

        const allocator = system.allocator;

        const virt_config = ConfigResources.Block.Virt.create(system.config.virt_driver, system.config.virt_clients.items);
        try data.serialize(virt_config, try fs.path.join(allocator, &.{ prefix, "blk_virt.data" }));
        try data.jsonify(virt_config, try fs.path.join(allocator, &.{ prefix, "blk_virt.json" }), .{ .whitespace = .indent_4 });

        for (system.config.clients.items, 0..) |config, i| {
            const client_data = fmt(allocator, "{s}.data", .{ system.clients.items[i].name });
            const client_json = fmt(allocator, "{s}.json", .{ system.clients.items[i].name });
            try data.serialize(config, try fs.path.join(allocator, &.{ prefix, client_data }));
            try data.jsonify(config, try fs.path.join(allocator, &.{ prefix, client_json }), .{ .whitespace = .indent_4 });
        }
    }
};

/// TODO: these functions do very little error checking
pub const SerialSystem = struct {
    allocator: Allocator,
    sdf: *SystemDescription,
    driver_data_size: usize,
    client_data_size: usize,
    queue_size: usize,
    driver: *Pd,
    device: *dtb.Node,
    virt_rx: ?*Pd,
    virt_tx: *Pd,
    clients: std.ArrayList(*Pd),
    rx: bool,

    driver_config: ConfigResources.Serial.Driver,
    virt_rx_config: ConfigResources.Serial.VirtRx,
    virt_tx_config: ConfigResources.Serial.VirtTx,
    client_configs: std.ArrayList(ConfigResources.Serial.Client),

    pub const Options = struct {
        driver_data_size: usize = 0x10000,
        client_data_size: usize = 0x10000,
        queue_size: usize = 0x1000,
        rx: bool = true,
    };

    const Region = enum {
        data,
        queue,
    };

    pub fn init(allocator: Allocator, sdf: *SystemDescription, device: *dtb.Node, driver: *Pd, virt_tx: *Pd, virt_rx: ?*Pd, options: Options) !SerialSystem {
        if (options.rx and virt_rx == null) {
            return error.SerialMissingVirtRx;
        }
        return .{
            .allocator = allocator,
            .sdf = sdf,
            .driver_data_size = options.driver_data_size,
            .client_data_size = options.client_data_size,
            .queue_size = options.queue_size,
            .rx = options.rx,
            .clients = std.ArrayList(*Pd).init(allocator),
            .driver = driver,
            .device = device,
            .virt_rx = virt_rx,
            .virt_tx = virt_tx,

            .driver_config = std.mem.zeroes(ConfigResources.Serial.Driver),
            .virt_rx_config = std.mem.zeroes(ConfigResources.Serial.VirtRx),
            .virt_tx_config = std.mem.zeroes(ConfigResources.Serial.VirtTx),
            .client_configs = std.ArrayList(ConfigResources.Serial.Client).init(allocator),
        };
    }

    pub fn addClient(system: *SerialSystem, client: *Pd) void {
        system.clients.append(client) catch @panic("Could not add client to SerialSystem");
        system.client_configs.append(std.mem.zeroes(ConfigResources.Serial.Client)) catch @panic("Could not add client to SerialSystem");
    }

    fn rxConnectDriver(system: *SerialSystem) void {
        const allocator = system.allocator;
        inline for (std.meta.fields(Region)) |region| {
            const mr_name = std.fmt.allocPrint(system.allocator, "serial_driver_rx_{s}", .{region.name}) catch @panic("OOM");
            const mr_size = blk: {
                if (@as(Region, @enumFromInt(region.value)) == .data) {
                    break :blk system.driver_data_size;
                } else {
                    break :blk system.queue_size;
                }
            };
            const mr = Mr.create(allocator, mr_name, mr_size, .{});
            system.sdf.addMemoryRegion(mr);
            const virt_vaddr = system.virt_rx.?.getMapVaddr(&mr);
            const virt_map = Map.create(mr, virt_vaddr, .rw, true, .{});
            system.virt_rx.?.addMap(virt_map);

            const driver_vaddr = system.driver.getMapVaddr(&mr);
            const driver_map = Map.create(mr, driver_vaddr, .rw, true, .{});
            system.driver.addMap(driver_map);

            if (@as(Region, @enumFromInt(region.value)) == .data) {
                system.virt_rx_config.data_drv = virt_vaddr;
                system.virt_rx_config.capacity_drv = mr_size;
                system.driver_config.rx_data_addr = driver_vaddr;
                system.driver_config.rx_capacity = mr_size;
            } else {
                system.virt_rx_config.queue_drv = virt_vaddr;

                system.driver_config.rx_queue_addr = driver_vaddr;
                system.driver_config.rx_enabled = 1;
            }
        }

        system.virt_rx_config.switch_char = 28;
        system.virt_rx_config.terminate_num_char = '\r';

        system.virt_tx_config.enable_rx = 1;
    }

    fn txConnectDriver(system: *SerialSystem) void {
        const allocator = system.allocator;
        inline for (std.meta.fields(Region)) |region| {
            const mr_name = std.fmt.allocPrint(system.allocator, "serial_driver_tx_{s}", .{region.name}) catch @panic("OOM");
            const mr_size = blk: {
                if (@as(Region, @enumFromInt(region.value)) == .data) {
                    break :blk system.driver_data_size;
                } else {
                    break :blk system.queue_size;
                }
            };
            const mr = Mr.create(allocator, mr_name, mr_size, .{});
            system.sdf.addMemoryRegion(mr);
            const virt_vaddr = system.virt_tx.getMapVaddr(&mr);
            const virt_map = Map.create(mr, virt_vaddr, .rw, true, .{});
            system.virt_tx.addMap(virt_map);

            const driver_vaddr = system.driver.getMapVaddr(&mr);
            const driver_map = Map.create(mr, driver_vaddr, .rw, true, .{});
            system.driver.addMap(driver_map);

            if (@as(Region, @enumFromInt(region.value)) == .data) {
                system.virt_tx_config.data_addr_drv = virt_vaddr;
                system.virt_tx_config.capacity_drv = mr_size;

                system.driver_config.tx_data_addr = driver_vaddr;
                system.driver_config.tx_capacity = mr_size;
            } else {
                system.virt_tx_config.queue_addr_drv = virt_vaddr;

                system.driver_config.tx_queue_addr = driver_vaddr;
            }
        }

        system.virt_tx_config.enable_colour = 1;
        const begin_str = "Begin input\n";
        @memcpy(system.virt_tx_config.begin_str[0..begin_str.len], begin_str);
        assert(system.virt_tx_config.begin_str[begin_str.len] == 0);
        system.virt_tx_config.begin_str_len = begin_str.len;

        system.driver_config.default_baud = 115200;
    }

    fn rxConnectClient(system: *SerialSystem, client: *Pd, client_config: *ConfigResources.Serial.Client, i: usize) void {
        const allocator = system.allocator;

        inline for (std.meta.fields(Region)) |region| {
            const mr_name = std.fmt.allocPrint(system.allocator, "serial_virt_rx_{s}_{s}", .{ client.name, region.name }) catch @panic("OOM");
            const mr_size = blk: {
                if (@as(Region, @enumFromInt(region.value)) == .data) {
                    break :blk system.driver_data_size;
                } else {
                    break :blk system.queue_size;
                }
            };
            const mr = Mr.create(allocator, mr_name, mr_size, .{});
            system.sdf.addMemoryRegion(mr);
            const virt_vaddr = system.virt_rx.?.getMapVaddr(&mr);
            const virt_map = Map.create(mr, virt_vaddr, .rw, true, .{});
            system.virt_rx.?.addMap(virt_map);

            const client_vaddr = client.getMapVaddr(&mr);
            const client_map = Map.create(mr, client_vaddr, .rw, true, .{});
            client.addMap(client_map);

            if (@as(Region, @enumFromInt(region.value)) == .data) {
                system.virt_rx_config.clients[i].data_addr = virt_vaddr;
                system.virt_rx_config.clients[i].capacity = mr_size;

                client_config.rx_data_addr = client_vaddr;
                client_config.rx_capacity = mr_size;
            } else {
                system.virt_rx_config.clients[i].queue_addr = virt_vaddr;

                client_config.rx_queue_addr = client_vaddr;
            }
        }
    }

    fn txConnectClient(system: *SerialSystem, client: *Pd, client_config: *ConfigResources.Serial.Client, i: usize) void {
        const allocator = system.allocator;
        // assuming name is null-terminated
        @memcpy(system.virt_tx_config.clients[i].name[0..client.name.len], client.name);
        assert(client.name.len < ConfigResources.Serial.VirtTx.MAX_NAME_LEN);
        assert(system.virt_tx_config.clients[i].name[client.name.len] == 0);

        inline for (std.meta.fields(Region)) |region| {
            const mr_name = std.fmt.allocPrint(system.allocator, "serial_virt_tx_{s}_{s}", .{ client.name, region.name }) catch @panic("OOM");
            const mr_size = blk: {
                if (@as(Region, @enumFromInt(region.value)) == .data) {
                    break :blk system.driver_data_size;
                } else {
                    break :blk system.queue_size;
                }
            };
            const mr = Mr.create(allocator, mr_name, mr_size, .{});
            system.sdf.addMemoryRegion(mr);
            const virt_vaddr = system.virt_tx.getMapVaddr(&mr);
            const virt_map = Map.create(mr, virt_vaddr, .rw, true, .{});
            system.virt_tx.addMap(virt_map);

            const client_vaddr = client.getMapVaddr(&mr);
            const client_map = Map.create(mr, client_vaddr, .rw, true, .{});
            client.addMap(client_map);

            if (@as(Region, @enumFromInt(region.value)) == .data) {
                system.virt_tx_config.clients[i].data_addr = virt_vaddr;
                system.virt_tx_config.clients[i].capacity = mr_size;

                client_config.tx_data_addr = client_vaddr;
                client_config.tx_capacity = mr_size;
            } else {
                system.virt_tx_config.clients[i].queue_addr = virt_vaddr;

                client_config.tx_queue_addr = client_vaddr;
            }
        }
    }

    pub fn connect(system: *SerialSystem) !void {
        var sdf = system.sdf;

        // 1. Create all the channels
        // 1.1 Create channels between driver and virtualisers
        try createDriver(sdf, system.driver, system.device, .serial);
        const ch_driver_virt_tx = Channel.create(system.driver, system.virt_tx, .{});
        sdf.addChannel(ch_driver_virt_tx);
        if (system.rx) {
            const ch_driver_virt_rx = Channel.create(system.driver, system.virt_rx.?, .{});
            sdf.addChannel(ch_driver_virt_rx);
        }
        // 1.2 Create channels between virtualisers and clients
        for (system.clients.items) |client| {
            const ch_virt_tx_client = Channel.create(system.virt_tx, client, .{});
            sdf.addChannel(ch_virt_tx_client);

            if (system.rx) {
                const ch_virt_rx_client = Channel.create(system.virt_rx.?, client, .{});
                sdf.addChannel(ch_virt_rx_client);
            }
        }
        if (system.rx) {
            system.rxConnectDriver();
        }
        system.txConnectDriver();
        for (system.clients.items, 0..) |client, i| {
            if (system.rx) {
                system.rxConnectClient(client, &system.client_configs.items[i], i);
            }
            system.txConnectClient(client, &system.client_configs.items[i], i);
        }
    }

    pub fn serialiseConfig(system: *SerialSystem, prefix: []const u8) !void {
        const allocator = system.allocator;

        try data.serialize(system.driver_config, try fs.path.join(allocator, &.{ prefix, "serial_driver.data" }));
        try data.jsonify(system.driver_config, try fs.path.join(allocator, &.{ prefix, "serial_driver.json"}), .{ .whitespace = .indent_4 });

        try data.serialize(system.virt_rx_config, try fs.path.join(allocator, &.{ prefix, "serial_virt_rx.data" }));
        try data.jsonify(system.virt_rx_config, try fs.path.join(allocator, &.{ prefix, "serial_virt_rx.json" }), .{ .whitespace = .indent_4 });

        try data.serialize(system.virt_tx_config, try fs.path.join(allocator, &.{ prefix, "serial_virt_tx.data" }));
        try data.jsonify(system.virt_tx_config, try fs.path.join(allocator, &.{ prefix, "serial_virt_tx.json" }), .{ .whitespace = .indent_4 });

        for (system.clients.items, 0..) |client, i| {
            const data_name = std.fmt.allocPrint(system.allocator, "serial_client_{s}.data", .{client.name}) catch @panic("OOM");
            const json_name = std.fmt.allocPrint(system.allocator, "serial_client_{s}.json", .{client.name}) catch @panic("OOM");
            try data.serialize(system.client_configs.items[i], try fs.path.join(allocator, &.{ prefix, data_name }));
            try data.jsonify(system.client_configs.items[i], try fs.path.join(allocator, &.{ prefix, json_name }), .{ .whitespace = .indent_4 });
        }
    }
};

// TODO: connect functions look disgusting because I'm doing weird looping stuff with the
// Region enum
pub const NetworkSystem = struct {
    pub const Options = struct {
        region_size: usize = 0x200_000,
    };

    allocator: Allocator,
    sdf: *SystemDescription,
    region_size: usize,
    driver: *Pd,
    device: *dtb.Node,
    virt_rx: *Pd,
    virt_tx: *Pd,
    copiers: std.ArrayList(*Pd),
    clients: std.ArrayList(*Pd),

    driver_config: ConfigResources.Net.Driver,
    virt_rx_config: ConfigResources.Net.VirtRx,
    virt_tx_config: ConfigResources.Net.VirtTx,
    copy_configs: std.ArrayList(ConfigResources.Net.Copy),
    client_configs: std.ArrayList(ConfigResources.Net.Client),

    const QueueRegion = enum {
        active,
        free,
    };

    pub fn init(allocator: Allocator, sdf: *SystemDescription, device: *dtb.Node, driver: *Pd, virt_rx: *Pd, virt_tx: *Pd, options: Options) NetworkSystem {
        return .{
            .allocator = allocator,
            .sdf = sdf,
            .region_size = options.region_size,
            .clients = std.ArrayList(*Pd).init(allocator),
            .copiers = std.ArrayList(*Pd).init(allocator),
            .driver = driver,
            .device = device,
            .virt_rx = virt_rx,
            .virt_tx = virt_tx,

            .driver_config = std.mem.zeroes(ConfigResources.Net.Driver),
            .virt_rx_config = std.mem.zeroes(ConfigResources.Net.VirtRx),
            .virt_tx_config = std.mem.zeroes(ConfigResources.Net.VirtTx),
            .copy_configs = std.ArrayList(ConfigResources.Net.Copy).init(allocator),
            .client_configs = std.ArrayList(ConfigResources.Net.Client).init(allocator),
        };
    }

    pub fn addClientWithCopier(system: *NetworkSystem, client: *Pd, copier: *Pd) void {
        system.clients.append(client) catch @panic("Could not add client with copier to NetworkSystem");
        system.copiers.append(copier) catch @panic("Could not add client with copier to NetworkSystem");
        system.client_configs.append(std.mem.zeroes(ConfigResources.Net.Client)) catch @panic("Could not add client with copier to NetworkSystem");
        system.copy_configs.append(std.mem.zeroes(ConfigResources.Net.Copy)) catch @panic("Could not add client with copier to NetworkSystem");
    }

    fn rxConnectDriver(system: *NetworkSystem) Mr {
        const allocator = system.allocator;

        const rx_dma_mr = Mr.physical(allocator, system.sdf, "net_rx_dma", system.region_size, .{});
        system.sdf.addMemoryRegion(rx_dma_mr);

        const rx_dma_virt_vaddr = system.virt_rx.getMapVaddr(&rx_dma_mr);
        const rx_dma_virt_map = Map.create(rx_dma_mr, rx_dma_virt_vaddr, .r, true, .{});
        system.virt_rx.addMap(rx_dma_virt_map);
        system.virt_rx_config.buffer_data_vaddr = rx_dma_virt_vaddr;
        system.virt_rx_config.buffer_data_paddr = rx_dma_mr.paddr.?;

        const free_mr = Mr.create(allocator, "net_driver_virt_rx_free", system.region_size, .{});
        system.sdf.addMemoryRegion(free_mr);

        const free_driver_vaddr = system.driver.getMapVaddr(&free_mr);
        const free_driver_map = Map.create(free_mr, free_driver_vaddr, .rw, true, .{});
        system.driver.addMap(free_driver_map);
        system.driver_config.rx_free = free_driver_vaddr;

        const free_virt_vaddr = system.virt_rx.getMapVaddr(&free_mr);
        const free_virt_map = Map.create(free_mr, free_virt_vaddr, .rw, true, .{});
        system.virt_rx.addMap(free_virt_map);
        system.virt_rx_config.free_drv = free_virt_map.vaddr;

        const active_mr = Mr.create(allocator, "net_driver_virt_rx_active", system.region_size, .{});
        system.sdf.addMemoryRegion(active_mr);

        const active_driver_vaddr = system.driver.getMapVaddr(&active_mr);
        const active_driver_map = Map.create(active_mr, active_driver_vaddr, .rw, true, .{});
        system.driver.addMap(active_driver_map);
        system.driver_config.rx_active = active_driver_vaddr;

        const active_virt_vaddr = system.virt_rx.getMapVaddr(&active_mr);
        const active_virt_map = Map.create(active_mr, active_virt_vaddr, .rw, true, .{});
        system.virt_rx.addMap(active_virt_map);
        system.virt_rx_config.active_drv = active_virt_vaddr;

        return rx_dma_mr;
    }

    fn txConnectDriver(system: *NetworkSystem) void {
        const allocator = system.allocator;

        const free_mr = Mr.create(allocator, "net_driver_virt_tx_free", system.region_size, .{});
        system.sdf.addMemoryRegion(free_mr);

        const free_driver_map = Map.create(free_mr, system.driver.getMapVaddr(&free_mr), .rw, true, .{});
        system.driver.addMap(free_driver_map);
        system.driver_config.tx_free = free_driver_map.vaddr;

        const free_virt_map = Map.create(free_mr, system.virt_tx.getMapVaddr(&free_mr), .rw, true, .{});
        system.virt_tx.addMap(free_virt_map);
        system.virt_tx_config.free_drv = free_virt_map.vaddr;

        const active_mr = Mr.create(allocator, "net_driver_virt_tx_active", system.region_size, .{});
        system.sdf.addMemoryRegion(active_mr);

        const active_driver_map = Map.create(active_mr, system.driver.getMapVaddr(&active_mr), .rw, true, .{});
        system.driver.addMap(active_driver_map);
        system.driver_config.tx_active = active_driver_map.vaddr;

        const active_virt_map = Map.create(active_mr, system.virt_tx.getMapVaddr(&active_mr), .rw, true, .{});
        system.virt_tx.addMap(active_virt_map);
        system.virt_tx_config.active_drv = active_virt_map.vaddr;
    }

    fn clientRxConnect(system: *NetworkSystem, rx_dma: Mr, client_idx: usize) void {
        const allocator = system.allocator;

        var client = system.clients.items[client_idx];
        var copier = system.copiers.items[client_idx];
        var client_config = &system.client_configs.items[client_idx];
        var copier_config = &system.copy_configs.items[client_idx];

        const rx_dma_copier_map = Map.create(rx_dma, copier.getMapVaddr(&rx_dma), .r, true, .{});
        copier.addMap(rx_dma_copier_map);
        copier_config.virt_data = rx_dma_copier_map.vaddr;

        const client_data_mr_name = std.fmt.allocPrint(system.allocator, "net_rx_data_{s}", .{client.name}) catch @panic("OOM");
        const client_data_mr = Mr.create(allocator, client_data_mr_name, system.region_size, .{});
        system.sdf.addMemoryRegion(client_data_mr);

        const client_data_client_map = Map.create(client_data_mr, client.getMapVaddr(&client_data_mr), .rw, true, .{});
        client.addMap(client_data_client_map);
        client_config.rx_buffer_data_region = client_data_client_map.vaddr;

        const client_data_copier_map = Map.create(client_data_mr, copier.getMapVaddr(&client_data_mr), .rw, true, .{});
        copier.addMap(client_data_copier_map);
        copier_config.cli_data = client_data_copier_map.vaddr;

        const copier_free_mr_name = std.fmt.allocPrint(system.allocator, "net_rx_free_{s}", .{ copier.name }) catch @panic("OOM");
        const copier_free_mr = Mr.create(allocator, copier_free_mr_name, system.region_size, .{});
        system.sdf.addMemoryRegion(copier_free_mr);

        const copier_free_virt_map = Map.create(copier_free_mr, system.virt_rx.getMapVaddr(&copier_free_mr), .rw, true, .{});
        system.virt_rx.addMap(copier_free_virt_map);
        system.virt_rx_config.clients[client_idx].free = copier_free_virt_map.vaddr;

        const copier_free_copier_map = Map.create(copier_free_mr, copier.getMapVaddr(&copier_free_mr), .rw, true, .{});
        copier.addMap(copier_free_copier_map);
        copier_config.virt_free = copier_free_copier_map.vaddr;

        const copier_active_mr_name = std.fmt.allocPrint(system.allocator, "net_rx_active_{s}", .{ copier.name }) catch @panic("OOM");
        const copier_active_mr = Mr.create(allocator, copier_active_mr_name, system.region_size, .{});
        system.sdf.addMemoryRegion(copier_active_mr);

        const copier_active_virt_map = Map.create(copier_active_mr, system.virt_rx.getMapVaddr(&copier_active_mr), .rw, true, .{});
        system.virt_rx.addMap(copier_active_virt_map);
        system.virt_rx_config.clients[client_idx].active = copier_active_virt_map.vaddr;

        const copier_active_copier_map = Map.create(copier_active_mr, copier.getMapVaddr(&copier_active_mr), .rw, true, .{});
        copier.addMap(copier_active_copier_map);
        copier_config.virt_active = copier_active_copier_map.vaddr;

        const client_free_mr_name = std.fmt.allocPrint(system.allocator, "net_rx_free_{s}", .{ client.name }) catch @panic("OOM");
        const client_free_mr = Mr.create(allocator, client_free_mr_name, system.region_size, .{});
        system.sdf.addMemoryRegion(client_free_mr);

        const client_free_copier_map = Map.create(client_free_mr, copier.getMapVaddr(&client_free_mr), .rw, true, .{});
        copier.addMap(client_free_copier_map);
        copier_config.cli_free = client_free_copier_map.vaddr;

        const client_free_client_map = Map.create(client_free_mr, client.getMapVaddr(&client_free_mr), .rw, true, .{});
        client.addMap(client_free_client_map);
        client_config.rx_free = client_free_client_map.vaddr;

        const client_active_mr_name = std.fmt.allocPrint(system.allocator, "net_rx_active_{s}", .{ client.name }) catch @panic("OOM");
        const client_active_mr = Mr.create(allocator, client_active_mr_name, system.region_size, .{});
        system.sdf.addMemoryRegion(client_active_mr);

        const client_active_copier_map = Map.create(client_active_mr, copier.getMapVaddr(&client_active_mr), .rw, true, .{});
        copier.addMap(client_active_copier_map);
        copier_config.cli_active = client_active_copier_map.vaddr;

        const client_active_client_map = Map.create(client_active_mr, client.getMapVaddr(&client_active_mr), .rw, true, .{});
        client.addMap(client_active_client_map);
        client_config.rx_active = client_active_client_map.vaddr;
    }

    fn clientTxConnect(system: *NetworkSystem, client_id: usize) void {
        const allocator = system.allocator;

        var client = system.clients.items[client_id];
        var client_config = &system.client_configs.items[client_id];

        const data_mr_name = std.fmt.allocPrint(system.allocator, "net_tx_data_{s}", .{client.name}) catch @panic("OOM");
        const data_mr = Mr.physical(allocator, system.sdf, data_mr_name, system.region_size, .{});
        system.sdf.addMemoryRegion(data_mr);

        const data_virt_map = Map.create(data_mr, system.virt_tx.getMapVaddr(&data_mr), .rw, true, .{});
        client.addMap(data_virt_map);
        system.virt_tx_config.clients[client_id].buffer_data_region_vaddr = data_virt_map.vaddr;
        system.virt_tx_config.clients[client_id].buffer_data_region_paddr = data_mr.paddr.?;

        const data_client_map = Map.create(data_mr, client.getMapVaddr(&data_mr), .rw, true, .{});
        client.addMap(data_client_map);
        client_config.tx_buffer_data_region = data_client_map.vaddr;

        const free_mr_name = std.fmt.allocPrint(system.allocator, "net_tx_free_{s}", .{ client.name }) catch @panic("OOM");
        const free_mr = Mr.create(allocator, free_mr_name, system.region_size, .{});
        system.sdf.addMemoryRegion(free_mr);

        const free_virt_map = Map.create(free_mr, system.virt_tx.getMapVaddr(&free_mr), .rw, true, .{});
        system.virt_tx.addMap(free_virt_map);
        system.virt_tx_config.clients[client_id].free = free_virt_map.vaddr;

        const free_client_map = Map.create(free_mr, client.getMapVaddr(&free_mr), .rw, true, .{});
        client.addMap(free_client_map);
        client_config.tx_free = free_client_map.vaddr;

        const active_mr_name = std.fmt.allocPrint(system.allocator, "net_tx_active_{s}", .{ client.name }) catch @panic("OOM");
        const active_mr = Mr.create(allocator, active_mr_name, system.region_size, .{});
        system.sdf.addMemoryRegion(active_mr);

        const active_virt_map = Map.create(active_mr, system.virt_tx.getMapVaddr(&active_mr), .rw, true, .{});
        system.virt_tx.addMap(active_virt_map);
        system.virt_tx_config.clients[client_id].active = active_virt_map.vaddr;

        const active_client_map = Map.create(active_mr, client.getMapVaddr(&active_mr), .rw, true, .{});
        client.addMap(active_client_map);
        client_config.tx_active = active_client_map.vaddr;
    }

    pub fn connect(system: *NetworkSystem) !void {
        const allocator = system.allocator;
        var sdf = system.sdf;
        try createDriver(sdf, system.driver, system.device, .network);

        // TODO: The driver needs the HW ring buffer memory region as well. In the future
        // we should make this configurable but right no we'll just add it here
        const hw_ring_buffer_mr = Mr.create(allocator, "hw_ring_buffer", 0x10_000, .{});
        system.sdf.addMemoryRegion(hw_ring_buffer_mr);
        system.driver.addMap(Map.create(hw_ring_buffer_mr, system.driver.getMapVaddr(&hw_ring_buffer_mr), .rw, false, .{}));

        sdf.addChannel(.create(system.driver, system.virt_tx, .{}));
        sdf.addChannel(.create(system.driver, system.virt_rx, .{}));

        const rx_dma_mr = system.rxConnectDriver();
        system.txConnectDriver();

        system.virt_tx_config.num_clients = @truncate(system.clients.items.len);
        system.virt_rx_config.num_clients = @truncate(system.clients.items.len);
        for (system.clients.items, 0..) |client, i| {
            // TODO: we have an assumption that all copiers are RX copiers
            sdf.addChannel(.create(system.copiers.items[i], client, .{}));
            sdf.addChannel(.create(system.virt_tx, client, .{}));
            sdf.addChannel(.create(system.copiers.items[i], system.virt_rx, .{}));

            system.clientRxConnect(rx_dma_mr, i);
            system.clientTxConnect(i);
        }
    }

    pub fn serialiseConfig(system: *NetworkSystem, prefix: []const u8) !void {
        const allocator = system.allocator;

        try data.serialize(system.driver_config, try fs.path.join(allocator, &.{ prefix, "net_driver.data" }));
        try data.jsonify(system.driver_config, try fs.path.join(allocator, &.{ prefix, "net_driver.json"}), .{ .whitespace = .indent_4 });

        try data.serialize(system.virt_rx_config, try fs.path.join(allocator, &.{ prefix, "net_virt_rx.data" }));
        try data.jsonify(system.virt_rx_config, try fs.path.join(allocator, &.{ prefix, "net_virt_rx.json" }), .{ .whitespace = .indent_4 });

        try data.serialize(system.virt_tx_config, try fs.path.join(allocator, &.{ prefix, "net_virt_tx.data" }));
        try data.jsonify(system.virt_tx_config, try fs.path.join(allocator, &.{ prefix, "net_virt_tx.json" }), .{ .whitespace = .indent_4 });

        for (system.copiers.items, 0..) |copier, i| {
            const data_name = std.fmt.allocPrint(system.allocator, "{s}.data", .{copier.name}) catch @panic("OOM");
            const json_name = std.fmt.allocPrint(system.allocator, "{s}.json", .{copier.name}) catch @panic("OOM");
            try data.serialize(system.copy_configs.items[i], try fs.path.join(allocator, &.{ prefix, data_name }));
            try data.jsonify(system.copy_configs.items[i], try fs.path.join(allocator, &.{ prefix, json_name }), .{ .whitespace = .indent_4 });
        }

        for (system.clients.items, 0..) |client, i| {
            const data_name = std.fmt.allocPrint(system.allocator, "net_client_{s}.data", .{client.name}) catch @panic("OOM");
            const json_name = std.fmt.allocPrint(system.allocator, "net_client_{s}.json", .{client.name}) catch @panic("OOM");
            try data.serialize(system.client_configs.items[i], try fs.path.join(allocator, &.{ prefix, data_name }));
            try data.jsonify(system.client_configs.items[i], try fs.path.join(allocator, &.{ prefix, json_name }), .{ .whitespace = .indent_4 });
        }
    }
};

/// Assumes probe() has been called
fn findDriver(compatibles: []const []const u8, class: Config.DeviceClass.Class) ?Config.Driver {
    assert(probed);
    for (drivers.items) |driver| {
        // This is yet another point of weirdness with device trees. It is often
        // the case that there are multiple compatible strings for a device and
        // accompying driver. So we get the user to provide a list of compatible
        // strings, and we check for a match with any of the compatible strings
        // of a driver.
        for (compatibles) |compatible| {
            for (driver.compatible) |driver_compatible| {
                if (std.mem.eql(u8, driver_compatible, compatible) and driver.class == class) {
                    // We have found a compatible driver
                    return driver;
                }
            }
        }
    }

    return null;
}

/// Given the DTB node for the device and the SDF program image, we can figure
/// all the resources that need to be added to the system description.
pub fn createDriver(sdf: *SystemDescription, pd: *Pd, device: *dtb.Node, class: Config.DeviceClass.Class) !void {
    if (!probed) return error.CalledBeforeProbe;
    // First thing to do is find the driver configuration for the device given.
    // The way we do that is by searching for the compatible string described in the DTB node.
    const compatible = device.prop(.Compatible).?;

    // TODO: It is expected for a lot of devices to have multiple compatible strings,
    // we need to deal with that here.
    log.debug("Creating driver for device: '{s}'", .{device.name});
    log.debug("Compatible with:", .{});
    for (compatible) |c| {
        log.debug("     '{s}'", .{c});
    }
    // Get the driver based on the compatible string are given, assuming we can
    // find it.
    const driver = if (findDriver(compatible, class)) |d| d else {
        log.err("Cannot find driver matching '{s}' for class '{s}'", .{ device.name, @tagName(class) });
        return error.UnknownDevice;
    };
    log.debug("Found compatible driver '{s}'", .{driver.name});

    // If a status property does exist, we should check that it is 'okay'
    if (device.prop(.Status)) |status| {
        if (status != .Okay) {
            log.err("Device '{s}' has invalid status: '{s}'", .{ device.name, status });
            return error.DeviceStatusInvalid;
        }
    }

    const interrupts = device.prop(.Interrupts).?;

    // If we have more device regions in the config file than there are in the DTB node,
    // the config file is invalid.
    const num_dt_regs = if (device.prop(.Reg)) |r| r.len else 0;
    if (num_dt_regs < driver.resources.device_regions.len) {
        log.err("device '{s}' has {} DTB node reg entries, but {} config device regions", .{ device.name, num_dt_regs, driver.resources.device_regions.len });
        return error.InvalidConfig;
    }

    // TODO: support more than one device region, it will most likely be needed in the future.
    assert(driver.resources.device_regions.len <= 1);
    if (driver.resources.device_regions.len > 0) {
        for (driver.resources.device_regions) |region| {
            const reg = device.prop(.Reg).?;
            assert(region.dt_index < reg.len);

            const reg_entry = reg[region.dt_index];
            assert(reg_entry.len == 2);
            const reg_paddr = reg_entry[0];
            // In case the device region is less than a page
            const reg_size = if (reg_entry[1] < 0x1000) 0x1000 else reg_entry[1];

            if (reg_size < region.size) {
                log.err("device '{s}' has config region size for dt_index '{}' that is too small (0x{x} bytes)", .{ device.name, region.dt_index, reg_size });
                return error.InvalidConfig;
            }

            if (region.size & ((1 << 12) - 1) != 0) {
                log.err("device '{s}' has config region size not aligned to page size for dt_index '{}'", .{ device.name, region.dt_index });
                return error.InvalidConfig;
            }

            if (reg_size & ((1 << 12) - 1) != 0) {
                log.err("device '{s}' has DTB region size not aligned to page size for dt_index '{}'", .{ device.name, region.dt_index });
                return error.InvalidConfig;
            }

            const device_paddr = DeviceTree.regToPaddr(device, reg_paddr);

            // TODO: hack when we have multiple virtIO devices. Need to come up with
            // a proper solution.
            var device_mr: ?Mr = null;
            for (sdf.mrs.items) |mr| {
                if (mr.paddr) |mr_paddr| {
                    if (mr_paddr == device_paddr) {
                        device_mr = mr;
                    }
                }
            }

            if (device_mr == null) {
                const mr_name = std.fmt.allocPrint(sdf.allocator, "{s}_{s}", .{ driver.name, region.name }) catch @panic("OOM");
                device_mr = Mr.physical(sdf.allocator, sdf, mr_name, region.size, .{ .paddr = device_paddr });
                sdf.addMemoryRegion(device_mr.?);
            }

            const perms = Map.Permissions.fromString(region.perms);
            const vaddr = pd.getMapVaddr(&device_mr.?);
            // Never map MMIO device regions as cached
            const map = Map.create(device_mr.?, vaddr, perms, false, .{ .setvar_vaddr = region.setvar_vaddr });
            pd.addMap(map);
        }
    }

    // For all driver IRQs, find the corresponding entry in the device tree and
    // process it for the SDF.
    for (driver.resources.irqs) |driver_irq| {
        const dt_irq = interrupts[driver_irq.dt_index];

        const irq = blk: switch (sdf.arch) {
            .aarch64, .aarch32 => {
                std.debug.assert(dt_irq.len == 3);
                // Determine the IRQ trigger and (software-observable) number based on the device tree.
                const irq_type = try DeviceTree.armGicIrqType(dt_irq[0]);
                const irq_number = DeviceTree.armGicIrqNumber(dt_irq[1], irq_type);
                // Assume trigger is level if we are dealing with an IRQ that is not an SPI.
                // TODO: come back to this, do we need to care about the trigger for non-SPIs?
                const irq_trigger = if (irq_type == .spi) try DeviceTree.armGicSpiTrigger(dt_irq[2]) else .level;

                break :blk SystemDescription.Interrupt.create(irq_number, irq_trigger, driver_irq.channel_id);
            },
            .riscv64, .riscv32 => {
                std.debug.assert(dt_irq.len == 1);
                const irq_number = dt_irq[0];
                const irq_trigger = .level;
                break :blk SystemDescription.Interrupt.create(irq_number, irq_trigger, driver_irq.channel_id);
            },
            else => @panic("device driver IRQ handling is unimplemented for given arch"),
        };

        try pd.addInterrupt(irq);
    }
}
