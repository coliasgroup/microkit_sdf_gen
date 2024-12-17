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

// TODO: apply this more widely
pub const DeviceTreeIndex = u8;

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
        var checked_compatibles = std.ArrayList([]const u8).init(allocator);
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
                const config_bytes = try config_file.reader().readAllAlloc(allocator, config_size);
                // TODO; free config? we'd have to dupe the json data when populating our data structures
                assert(config_bytes.len == config_size);
                // TODO: we have no information if the parsing fails. We need to do some error output if
                // it the input is malformed.
                // TODO: should probably free the memory at some point
                // We are using an ArenaAllocator so calling parseFromSliceLeaky instead of parseFromSlice
                // is recommended.
                const json = std.json.parseFromSliceLeaky(Config.Driver.Json, allocator, config_bytes, .{}) catch |e| {
                    std.log.err("Failed to parse JSON configuration '{s}/{s}/{s}' with error '{}'", .{ path, driver_dir, config_path, e });
                    return error.JsonParse;
                };

                const config = Config.Driver.fromJson(json, device_class.name);
                try drivers.append(config);

                // Check there are no duplicate compatible strings for the same device class
                for (config.compatible) |compatible| {
                    for (checked_compatibles.items) |checked_compatible| {
                        if (std.mem.eql(u8, checked_compatible, compatible)) {
                            std.log.err("Found duplicate driver compatible: '{s}' for driver: '{s}'\n", .{ compatible, config.name });
                            return error.DuplicateDriver;
                        }
                    }
                    try checked_compatibles.append(compatible);
                }
            }
        }
    }

    // Probing finished
    probed = true;
}

fn round_up(n: usize, d: usize) usize {
    var result = d * (n / d);
    if (n % d != 0) {
        result += d;
    }
    return result;
}

fn round_to_page(n: usize) usize {
    const page_size = 4096;
    return round_up(n, page_size);
}

pub const Config = struct {
    const Region = struct {
        /// Name of the region
        name: []const u8,
        /// Permissions to the region of memory once mapped in
        perms: ?[]const u8 = null,
        setvar_vaddr: ?[]const u8 = null,
        size: ?usize = null,
        cached: ?bool = null,
        // Index into 'reg' property of the device tree
        dt_index: ?DeviceTreeIndex = null,
    };

    /// The actual IRQ number that gets registered with seL4
    /// is something we can determine from the device tree.
    const Irq = struct {
        channel_id: ?u8 = null,
        /// Index into the 'interrupts' property of the Device Tree
        dt_index: DeviceTreeIndex,
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
            regions: []const Region,
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
    device_res: ConfigResources.Device,
    /// Client PDs serviced by the timer driver
    clients: std.ArrayList(*Pd),
    client_configs: std.ArrayList(ConfigResources.Timer.Client),

    pub fn init(allocator: Allocator, sdf: *SystemDescription, device: *dtb.Node, driver: *Pd) TimerSystem {
        // First we have to set some properties on the driver. It is currently our policy that every timer
        // driver should be passive.
        driver.passive = true;

        return .{
            .allocator = allocator,
            .sdf = sdf,
            .driver = driver,
            .device = device,
            .device_res = std.mem.zeroes(ConfigResources.Device),
            .clients = std.ArrayList(*Pd).init(allocator),
            .client_configs = std.ArrayList(ConfigResources.Timer.Client).init(allocator),
        };
    }

    pub fn deinit(system: *TimerSystem) void {
        system.clients.deinit();
    }

    pub fn addClient(system: *TimerSystem, client: *Pd) void {
        system.clients.append(client) catch @panic("Could not add client to TimerSystem");
        system.client_configs.append(std.mem.zeroes(ConfigResources.Timer.Client)) catch @panic("Could not add client to TimerSystem");
    }

    pub fn connect(system: *TimerSystem) !void {
        // The driver must be passive
        assert(system.driver.passive.?);

        try createDriver(system.sdf, system.driver, system.device, .timer, &system.device_res);
        for (system.clients.items, 0..) |client, i| {
            const ch = Channel.create(system.driver, client, .{
                // Client needs to be able to PPC into driver
                .pp = .b,
                // Client does not need to notify driver
                .pd_b_notify = false,
            });
            system.sdf.addChannel(ch);
            system.client_configs.items[i].driver_id = ch.pd_b_id;
        }
    }

    pub fn serialiseConfig(system: *TimerSystem, prefix: []const u8) !void {
        const allocator = system.allocator;

        const device_res_data_name = std.fmt.allocPrint(system.allocator, "{s}_device_resources.data", .{ system.driver.name }) catch @panic("OOM");
        const device_res_json_name = std.fmt.allocPrint(system.allocator, "{s}_device_resources.json", .{ system.driver.name }) catch @panic("OOM");
        try data.serialize(system.device_res, try std.fs.path.join(system.allocator, &.{ prefix, device_res_data_name }));
        try data.jsonify(system.device_res, try std.fs.path.join(system.allocator, &.{ prefix, device_res_json_name }), .{ .whitespace = .indent_4 });

        for (system.clients.items, 0..) |client, i| {
            const data_name = std.fmt.allocPrint(system.allocator, "timer_client_{s}.data", .{client.name}) catch @panic("OOM");
            const json_name = std.fmt.allocPrint(system.allocator, "timer_client_{s}.json", .{client.name}) catch @panic("OOM");
            try data.serialize(system.client_configs.items[i], try fs.path.join(allocator, &.{ prefix, data_name }));
            try data.jsonify(system.client_configs.items[i], try fs.path.join(allocator, &.{ prefix, json_name }), .{ .whitespace = .indent_4 });
        }
    }
};

pub const I2cSystem = struct {
    allocator: Allocator,
    sdf: *SystemDescription,
    driver: *Pd,
    device: ?*dtb.Node,
    device_res: ConfigResources.Device,
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
            .device_res = std.mem.zeroes(ConfigResources.Device),
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
        // Create a channel between the virtualiser and client
        const ch = Channel.create(virt, client, .{ .pp = .b });
        sdf.addChannel(ch);

        system.client_configs.items[i] = .{
            .request_region = client_map_req.vaddr,
            .response_region = client_map_resp.vaddr,
            .data_region = client_map_data.vaddr,
            .virt_id = ch.pd_b_id,
        };
    }

    pub fn connect(system: *I2cSystem) !void {
        const sdf = system.sdf;

        // 1. Create the device resources for the driver
        if (system.device) |device| {
            try createDriver(sdf, system.driver, device, .i2c, &system.device_res);
        }
        // 2. Connect the driver to the virtualiser
        system.connectDriver();
        // 3. Create a channel between the driver and virtualiser for notifications
        const driver_virt_ch = Channel.create(system.driver, system.virt, .{});
        sdf.addChannel(driver_virt_ch);
        // TODO: don't put this here, do it in connectDriver?
        system.driver_config.virt_id = driver_virt_ch.pd_a_id;
        system.virt_config.driver_id = driver_virt_ch.pd_b_id;
        // 4. Connect each client to the virtualiser
        for (system.clients.items, 0..) |client, i| {
            system.connectClient(client, i);
        }

        // To avoid cross-core IPC, we make the virtualiser passive
        system.virt.passive = true;
    }

    pub fn serialiseConfig(system: *I2cSystem, prefix: []const u8) !void {
        const allocator = system.allocator;

        const device_res_data_name = std.fmt.allocPrint(system.allocator, "{s}_device_resources.data", .{ system.driver.name }) catch @panic("OOM");
        const device_res_json_name = std.fmt.allocPrint(system.allocator, "{s}_device_resources.json", .{ system.driver.name }) catch @panic("OOM");
        try data.serialize(system.device_res, try std.fs.path.join(system.allocator, &.{ prefix, device_res_data_name }));
        try data.jsonify(system.device_res, try std.fs.path.join(system.allocator, &.{ prefix, device_res_json_name }), .{ .whitespace = .indent_4 });

        try data.serialize(system.driver_config, try fs.path.join(allocator, &.{ prefix, "i2c_driver.data" }));
        try data.jsonify(system.driver_config, try fs.path.join(allocator, &.{ prefix, "i2c_driver.json" }), .{ .whitespace = .indent_4 });

        try data.serialize(system.virt_config, try fs.path.join(allocator, &.{ prefix, "i2c_virt.data" }));
        try data.jsonify(system.virt_config, try fs.path.join(allocator, &.{ prefix, "i2c_virt.json" }), .{ .whitespace = .indent_4 });

        for (system.clients.items, 0..) |client, i| {
            const data_name = std.fmt.allocPrint(allocator, "i2c_client_{s}.data", .{client.name}) catch @panic("OOM");
            const json_name = std.fmt.allocPrint(allocator, "i2c_client_{s}.json", .{client.name}) catch @panic("OOM");
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
    device_res: ConfigResources.Device,
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

    const STORAGE_INFO_REGION_SIZE: usize = 0x1000;

    pub fn init(allocator: Allocator, sdf: *SystemDescription, device: *dtb.Node, driver: *Pd, virt: *Pd, _: Options) BlockSystem {
        return .{
            .allocator = allocator,
            .sdf = sdf,
            .clients = std.ArrayList(*Pd).init(allocator),
            .client_partitions = std.ArrayList(u32).init(allocator),
            .driver = driver,
            .device = device,
            .device_res = std.mem.zeroes(ConfigResources.Device),
            .virt = virt,
            // TODO: make configurable
            .queue_mr_size = 0x200_000,
            .config = .{
                .virt_clients = std.ArrayList(ConfigResources.Block.Virt.Client).init(allocator),
                .clients = std.ArrayList(ConfigResources.Block.Client).init(allocator),
            },
        };
    }

    pub fn deinit(system: *BlockSystem) void {
        system.clients.deinit();
        system.client_partitions.deinit();
        system.config.virt_clients.deinit();
        system.config.clients.deinit();
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

        const mr_storage_info = Mr.create(allocator, "blk_driver_config", STORAGE_INFO_REGION_SIZE, .{});
        const map_storage_info_driver = Map.create(mr_storage_info, system.driver.getMapVaddr(&mr_storage_info), .rw, true, .{ .setvar_vaddr = "blk_storage_info" });
        const map_storage_info_virt = Map.create(mr_storage_info, system.virt.getMapVaddr(&mr_storage_info), .r, true, .{});

        sdf.addMemoryRegion(mr_storage_info);
        driver.addMap(map_storage_info_driver);
        virt.addMap(map_storage_info_virt);

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
            .storage_info = map_storage_info_virt.vaddr,
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

        const mr_storage_info = Mr.create(allocator, fmt(allocator, "blk_client_{s}_storage_info", .{client.name}), STORAGE_INFO_REGION_SIZE, .{});
        const map_storage_info_virt = Map.create(mr_storage_info, system.virt.getMapVaddr(&mr_storage_info), .rw, true, .{});
        const map_storage_info_client = Map.create(mr_storage_info, client.getMapVaddr(&mr_storage_info), .r, true, .{});

        system.sdf.addMemoryRegion(mr_storage_info);
        system.virt.addMap(map_storage_info_virt);
        client.addMap(map_storage_info_client);

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
            .storage_info = map_storage_info_virt.vaddr,
            .data_vaddr = map_data_virt.vaddr,
            .data_paddr = mr_data.paddr.?,
            .data_size = mr_data.size,
            .queue_mr_size = queue_mr_size,
            .partition = system.client_partitions.items[i],
        }) catch @panic("could not add virt client config");

        system.config.clients.append(.{
            .storage_info = map_storage_info_client.vaddr,
            .req_queue = map_req_client.vaddr,
            .resp_queue = map_resp_client.vaddr,
            .data_vaddr = map_data_client.vaddr,
            .queue_capacity = system.queue_capacity,
        }) catch @panic("could not add client config");
    }

    pub fn connect(system: *BlockSystem) !void {
        const sdf = system.sdf;

        // 1. Create the device resources for the driver
        try createDriver(sdf, system.driver, system.device, .blk, &system.device_res);
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

        const device_res_data_name = std.fmt.allocPrint(system.allocator, "{s}_device_resources.data", .{ system.driver.name }) catch @panic("OOM");
        const device_res_json_name = std.fmt.allocPrint(system.allocator, "{s}_device_resources.json", .{ system.driver.name }) catch @panic("OOM");
        try data.serialize(system.device_res, try std.fs.path.join(system.allocator, &.{ prefix, device_res_data_name }));
        try data.jsonify(system.device_res, try std.fs.path.join(system.allocator, &.{ prefix, device_res_json_name }), .{ .whitespace = .indent_4 });

        const virt_config = ConfigResources.Block.Virt.create(system.config.virt_driver, system.config.virt_clients.items);
        try data.serialize(virt_config, try fs.path.join(allocator, &.{ prefix, "blk_virt.data" }));
        try data.jsonify(virt_config, try fs.path.join(allocator, &.{ prefix, "blk_virt.json" }), .{ .whitespace = .indent_4 });

        for (system.config.clients.items, 0..) |config, i| {
            const client_data = fmt(allocator, "blk_client_{s}.data", .{ system.clients.items[i].name });
            const client_json = fmt(allocator, "blk_client_{s}.json", .{ system.clients.items[i].name });
            try data.serialize(config, try fs.path.join(allocator, &.{ prefix, client_data }));
            try data.jsonify(config, try fs.path.join(allocator, &.{ prefix, client_json }), .{ .whitespace = .indent_4 });
        }
    }
};

/// TODO: these functions do very little error checking
pub const SerialSystem = struct {
    allocator: Allocator,
    sdf: *SystemDescription,
    data_size: usize,
    queue_size: usize,
    driver: *Pd,
    device: *dtb.Node,
    device_res: ConfigResources.Device,
    virt_rx: ?*Pd,
    virt_tx: *Pd,
    clients: std.ArrayList(*Pd),

    driver_config: ConfigResources.Serial.Driver,
    virt_rx_config: ConfigResources.Serial.VirtRx,
    virt_tx_config: ConfigResources.Serial.VirtTx,
    client_configs: std.ArrayList(ConfigResources.Serial.Client),

    pub const Options = struct {
        data_size: usize = 0x10000,
        queue_size: usize = 0x1000,
        virt_rx: ?*Pd = null,
    };

    pub fn init(allocator: Allocator, sdf: *SystemDescription, device: *dtb.Node, driver: *Pd, virt_tx: *Pd, options: Options) SerialSystem {
        return .{
            .allocator = allocator,
            .sdf = sdf,
            .data_size = options.data_size,
            .queue_size = options.queue_size,
            .clients = std.ArrayList(*Pd).init(allocator),
            .driver = driver,
            .device = device,
            .device_res = std.mem.zeroes(ConfigResources.Device),
            .virt_rx = options.virt_rx,
            .virt_tx = virt_tx,

            .driver_config = std.mem.zeroes(ConfigResources.Serial.Driver),
            .virt_rx_config = std.mem.zeroes(ConfigResources.Serial.VirtRx),
            .virt_tx_config = std.mem.zeroes(ConfigResources.Serial.VirtTx),
            .client_configs = std.ArrayList(ConfigResources.Serial.Client).init(allocator),
        };
    }

    pub fn deinit(_: *SerialSystem) void {
        // TODO
    }

    pub fn addClient(system: *SerialSystem, client: *Pd) void {
        system.clients.append(client) catch @panic("Could not add client to SerialSystem");
        system.client_configs.append(std.mem.zeroes(ConfigResources.Serial.Client)) catch @panic("Could not add client to SerialSystem");
    }

    fn hasRx(system: *SerialSystem) bool {
        return system.virt_rx != null;
    }

    fn createConnection(system: *SerialSystem, server: *Pd, client: *Pd, server_conn: *ConfigResources.Serial.Connection, client_conn: *ConfigResources.Serial.Connection) void {
        const queue_mr_name = std.fmt.allocPrint(system.allocator, "{s}/serial/queue/{s}/{s}", .{system.device.name, server.name, client.name}) catch @panic("OOM");
        const queue_mr = Mr.create(system.allocator, queue_mr_name, system.queue_size, .{});
        system.sdf.addMemoryRegion(queue_mr);

        const queue_mr_server_map = Map.create(queue_mr, server.getMapVaddr(&queue_mr), .rw, true, .{});
        server.addMap(queue_mr_server_map);
        server_conn.queue = ConfigResources.Region.createFromMap(queue_mr_server_map);

        const queue_mr_client_map = Map.create(queue_mr, client.getMapVaddr(&queue_mr), .rw, true, .{});
        client.addMap(queue_mr_client_map);
        client_conn.queue = ConfigResources.Region.createFromMap(queue_mr_client_map);

        const data_mr_name = std.fmt.allocPrint(system.allocator, "{s}/serial/data/{s}/{s}", .{system.device.name, server.name, client.name}) catch @panic("OOM");
        const data_mr = Mr.create(system.allocator, data_mr_name, system.data_size, .{});
        system.sdf.addMemoryRegion(data_mr);

        const data_mr_server_map = Map.create(data_mr, server.getMapVaddr(&data_mr), .rw, true, .{});
        server.addMap(data_mr_server_map);
        server_conn.data = ConfigResources.Region.createFromMap(data_mr_server_map);

        const data_mr_client_map = Map.create(data_mr, client.getMapVaddr(&data_mr), .rw, true, .{});
        client.addMap(data_mr_client_map);
        client_conn.data = ConfigResources.Region.createFromMap(data_mr_client_map);

        const channel = Channel.create(server, client, .{});
        system.sdf.addChannel(channel);
        server_conn.id = channel.pd_a_id;
        client_conn.id = channel.pd_b_id;
    }

    pub fn connect(system: *SerialSystem) !void {
        try createDriver(system.sdf, system.driver, system.device, .serial, &system.device_res);

        system.driver_config.default_baud = 115200;

        if (system.hasRx()) {
            system.createConnection(system.driver, system.virt_rx.?, &system.driver_config.rx, &system.virt_rx_config.driver);

            system.virt_rx_config.num_clients = @intCast(system.clients.items.len);
            for (system.clients.items, 0..) |client, i| {
                system.createConnection(system.virt_rx.?, client, &system.virt_rx_config.clients[i], &system.client_configs.items[i].rx);
            }

            system.driver_config.rx_enabled = 1;

            system.virt_rx_config.switch_char = 28;
            system.virt_rx_config.terminate_num_char = '\r';

            system.virt_tx_config.enable_rx = 1;
        }

        system.createConnection(system.driver, system.virt_tx, &system.driver_config.tx, &system.virt_tx_config.driver);

        system.virt_tx_config.num_clients = @intCast(system.clients.items.len);
        for (system.clients.items, 0..) |client, i| {
            // assuming name is null-terminated
            @memcpy(system.virt_tx_config.clients[i].name[0..client.name.len], client.name);
            assert(client.name.len < ConfigResources.Serial.VirtTx.MAX_NAME_LEN);
            assert(system.virt_tx_config.clients[i].name[client.name.len] == 0);

            system.createConnection(system.virt_tx, client, &system.virt_tx_config.clients[i].conn, &system.client_configs.items[i].tx);
        }

        system.virt_tx_config.enable_colour = 1;

        const begin_str = "Begin input\n";
        @memcpy(system.virt_tx_config.begin_str[0..begin_str.len], begin_str);
        assert(system.virt_tx_config.begin_str[begin_str.len] == 0);

        system.virt_tx_config.begin_str_len = begin_str.len;
    }

    pub fn serialiseConfig(system: *SerialSystem, prefix: []const u8) !void {
        const allocator = system.allocator;

        const device_res_data_name = std.fmt.allocPrint(system.allocator, "{s}_device_resources.data", .{ system.driver.name }) catch @panic("OOM");
        const device_res_json_name = std.fmt.allocPrint(system.allocator, "{s}_device_resources.json", .{ system.driver.name }) catch @panic("OOM");
        try data.serialize(system.device_res, try std.fs.path.join(system.allocator, &.{ prefix, device_res_data_name }));
        try data.jsonify(system.device_res, try std.fs.path.join(system.allocator, &.{ prefix, device_res_json_name }), .{ .whitespace = .indent_4 });

        try data.serialize(system.driver_config, try fs.path.join(allocator, &.{ prefix, "serial_driver_config.data" }));
        try data.jsonify(system.driver_config, try fs.path.join(allocator, &.{ prefix, "serial_driver_config.json"}), .{ .whitespace = .indent_4 });

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

pub const NetworkSystem = struct {
    const BUFFER_SIZE = 2048;

    pub const Options = struct {
        rx_buffers: usize = 512,
    };

    pub const ClientOptions = struct {
        rx_buffers: usize = 512,
        tx_buffers: usize = 512,
        mac_addr: ?[]const u8 = null,
    };

    pub const ClientInfo = struct {
        rx_buffers: usize = 512,
        tx_buffers: usize = 512,
        mac_addr: ?[6]u8 = null,
    };

    allocator: Allocator,
    sdf: *SystemDescription,
    device: *dtb.Node,

    driver: *Pd,
    virt_rx: *Pd,
    virt_tx: *Pd,
    copiers: std.ArrayList(*Pd),
    clients: std.ArrayList(*Pd),

    device_res: ConfigResources.Device,
    driver_config: ConfigResources.Net.Driver,
    virt_rx_config: ConfigResources.Net.VirtRx,
    virt_tx_config: ConfigResources.Net.VirtTx,
    copy_configs: std.ArrayList(ConfigResources.Net.Copy),
    client_configs: std.ArrayList(ConfigResources.Net.Client),

    rx_buffers: usize,
    client_info: std.ArrayList(ClientInfo),

    pub fn init(allocator: Allocator, sdf: *SystemDescription, device: *dtb.Node, driver: *Pd, virt_tx: *Pd, virt_rx: *Pd, options: Options) NetworkSystem {
        return .{
            .allocator = allocator,
            .sdf = sdf,
            .clients = std.ArrayList(*Pd).init(allocator),
            .copiers = std.ArrayList(*Pd).init(allocator),
            .driver = driver,
            .device = device,
            .device_res = std.mem.zeroes(ConfigResources.Device),
            .virt_rx = virt_rx,
            .virt_tx = virt_tx,

            .driver_config = std.mem.zeroes(ConfigResources.Net.Driver),
            .virt_rx_config = std.mem.zeroes(ConfigResources.Net.VirtRx),
            .virt_tx_config = std.mem.zeroes(ConfigResources.Net.VirtTx),
            .copy_configs = std.ArrayList(ConfigResources.Net.Copy).init(allocator),
            .client_configs = std.ArrayList(ConfigResources.Net.Client).init(allocator),

            .client_info = std.ArrayList(ClientInfo).init(allocator),
            .rx_buffers = options.rx_buffers,
        };
    }

    fn parseMacAddr(mac_str: []const u8) ![6]u8 {
        var mac_arr = std.mem.zeroes([6]u8);
        var it = std.mem.splitScalar(u8, mac_str, ':');
        for (0..6) |i| {
            mac_arr[i] = try std.fmt.parseInt(u8, it.next().?, 16);
        }
        return mac_arr;
    }

    pub fn addClientWithCopier(system: *NetworkSystem, client: *Pd, copier: *Pd, options: ClientOptions) !void {
        const client_idx = system.clients.items.len;

        // Check that the MAC address isn't present already
        if (options.mac_addr) |a| {
            for (0..client_idx) |i| {
                if (system.client_info.items[i].mac_addr) |b| {
                    if (std.mem.eql(u8, a, &b)) {
                        return error.DuplicateMacAddr;
                    }
                }
            }
        }
        // Check that the client does not already exist
        for (system.clients.items) |existing_client| {
            if (std.mem.eql(u8, existing_client.name, client.name)) {
                return error.DuplicateClient;
            }
        }
        // Check that the copier does not already exist
        for (system.copiers.items) |existing_copier| {
            if (std.mem.eql(u8, existing_copier.name, copier.name)) {
                return error.DuplicateCopier;
            }
        }

        system.clients.append(client) catch @panic("Could not add client with copier to NetworkSystem");
        system.copiers.append(copier) catch @panic("Could not add client with copier to NetworkSystem");
        system.client_configs.append(std.mem.zeroes(ConfigResources.Net.Client)) catch @panic("Could not add client with copier to NetworkSystem");
        system.copy_configs.append(std.mem.zeroes(ConfigResources.Net.Copy)) catch @panic("Could not add client with copier to NetworkSystem");

        system.client_info.append(std.mem.zeroes(ClientInfo)) catch @panic("Could not add client with copier to NetworkSystem");
        if (options.mac_addr) |mac_addr| {
            system.client_info.items[client_idx].mac_addr = parseMacAddr(mac_addr) catch return error.InvalidMacAddr;
        }
        system.client_info.items[client_idx].rx_buffers = options.rx_buffers;
        system.client_info.items[client_idx].tx_buffers = options.tx_buffers;
    }

    fn queueMrSize(n_buffers: usize) usize {
        return round_to_page(8 + 16 * n_buffers);
    }

    fn createConnection(system: *NetworkSystem, server: *Pd, client: *Pd, server_conn: *ConfigResources.Net.Connection, client_conn: *ConfigResources.Net.Connection, num_buffers: u64) void {
        const queue_mr_size = queueMrSize(num_buffers);

        server_conn.num_buffers = @intCast(num_buffers);
        client_conn.num_buffers = @intCast(num_buffers);

        const free_mr_name = std.fmt.allocPrint(system.allocator, "{s}/net/queue/{s}/{s}/free", .{system.device.name, server.name, client.name}) catch @panic("OOM");
        const free_mr = Mr.create(system.allocator, free_mr_name, queue_mr_size, .{});
        system.sdf.addMemoryRegion(free_mr);

        const free_mr_server_map = Map.create(free_mr, server.getMapVaddr(&free_mr), .rw, true, .{});
        server.addMap(free_mr_server_map);
        server_conn.free_queue = ConfigResources.Region.createFromMap(free_mr_server_map);

        const free_mr_client_map = Map.create(free_mr, client.getMapVaddr(&free_mr), .rw, true, .{});
        client.addMap(free_mr_client_map);
        client_conn.free_queue = ConfigResources.Region.createFromMap(free_mr_client_map);

        const active_mr_name = std.fmt.allocPrint(system.allocator, "{s}/net/queue/{s}/{s}/active", .{system.device.name, server.name, client.name}) catch @panic("OOM");
        const active_mr = Mr.create(system.allocator, active_mr_name, queue_mr_size, .{});
        system.sdf.addMemoryRegion(active_mr);

        const active_mr_server_map = Map.create(active_mr, server.getMapVaddr(&active_mr), .rw, true, .{});
        server.addMap(active_mr_server_map);
        server_conn.active_queue = ConfigResources.Region.createFromMap(active_mr_server_map);

        const active_mr_client_map = Map.create(active_mr, client.getMapVaddr(&active_mr), .rw, true, .{});
        client.addMap(active_mr_client_map);
        client_conn.active_queue = ConfigResources.Region.createFromMap(active_mr_client_map);

        const channel = Channel.create(server, client, .{});
        system.sdf.addChannel(channel);
        server_conn.id = channel.pd_a_id;
        client_conn.id = channel.pd_b_id;
    }

    fn rxConnectDriver(system: *NetworkSystem) Mr {
        system.createConnection(system.driver, system.virt_rx, &system.driver_config.virt_rx, &system.virt_rx_config.driver, system.rx_buffers);

        const rx_dma_mr_name = std.fmt.allocPrint(system.allocator, "{s}/net/rx/data/device", .{system.device.name}) catch @panic("OOM");
        const rx_dma_mr_size = round_to_page(system.rx_buffers * BUFFER_SIZE);
        const rx_dma_mr = Mr.physical(system.allocator, system.sdf, rx_dma_mr_name, rx_dma_mr_size, .{});
        system.sdf.addMemoryRegion(rx_dma_mr);
        const rx_dma_virt_map = Map.create(rx_dma_mr, system.virt_rx.getMapVaddr(&rx_dma_mr), .rw, true, .{});
        system.virt_rx.addMap(rx_dma_virt_map);
        system.virt_rx_config.data_region = ConfigResources.Device.Region.createFromMap(rx_dma_virt_map);

        const virt_rx_metadata_mr_name = std.fmt.allocPrint(system.allocator, "{s}/net/rx/virt_metadata", .{system.device.name}) catch @panic("OOM");
        const virt_rx_metadata_mr_size = round_to_page(system.rx_buffers * 4);
        const virt_rx_metadata_mr = Mr.create(system.allocator, virt_rx_metadata_mr_name, virt_rx_metadata_mr_size, .{});
        system.sdf.addMemoryRegion(virt_rx_metadata_mr);
        const virt_rx_metadata_map = Map.create(virt_rx_metadata_mr, system.virt_rx.getMapVaddr(&virt_rx_metadata_mr), .rw, true, .{});
        system.virt_rx.addMap(virt_rx_metadata_map);
        system.virt_rx_config.buffer_metadata = ConfigResources.Region.createFromMap(virt_rx_metadata_map);

        return rx_dma_mr;
    }

    fn txConnectDriver(system: *NetworkSystem) void {
        var num_buffers: usize = 0;
        for (system.client_info.items) |client_info| {
            num_buffers += client_info.tx_buffers;
        }

        system.createConnection(system.driver, system.virt_tx, &system.driver_config.virt_tx, &system.virt_tx_config.driver, num_buffers);
    }

    fn clientRxConnect(system: *NetworkSystem, rx_dma: Mr, client_idx: usize) void {
        const client_info = system.client_info.items[client_idx];
        const client = system.clients.items[client_idx];
        const copier = system.copiers.items[client_idx];
        var client_config = &system.client_configs.items[client_idx];
        var copier_config = &system.copy_configs.items[client_idx];
        var virt_client_config = &system.virt_rx_config.clients[client_idx];

        system.createConnection(system.virt_rx, copier, &virt_client_config.conn, &copier_config.virt_rx, system.rx_buffers);
        system.createConnection(copier, client, &copier_config.client, &client_config.rx, client_info.rx_buffers);

        const rx_dma_copier_map = Map.create(rx_dma, copier.getMapVaddr(&rx_dma), .rw, true, .{});
        copier.addMap(rx_dma_copier_map);
        copier_config.device_data = ConfigResources.Region.createFromMap(rx_dma_copier_map);

        const client_data_mr_size = round_to_page(system.rx_buffers * BUFFER_SIZE);
        const client_data_mr_name = std.fmt.allocPrint(system.allocator, "{s}/net/rx/data/client/{s}", .{system.device.name, client.name}) catch @panic("OOM");
        const client_data_mr = Mr.create(system.allocator, client_data_mr_name, client_data_mr_size, .{});
        system.sdf.addMemoryRegion(client_data_mr);

        const client_data_client_map = Map.create(client_data_mr, client.getMapVaddr(&client_data_mr), .rw, true, .{});
        client.addMap(client_data_client_map);
        client_config.rx_data = ConfigResources.Region.createFromMap(client_data_client_map);

        const client_data_copier_map = Map.create(client_data_mr, copier.getMapVaddr(&client_data_mr), .rw, true, .{});
        copier.addMap(client_data_copier_map);
        copier_config.client_data = ConfigResources.Region.createFromMap(client_data_copier_map);
    }

    fn clientTxConnect(system: *NetworkSystem, client_id: usize) void {
        const client_info = &system.client_info.items[client_id];
        const client = system.clients.items[client_id];
        var client_config = &system.client_configs.items[client_id];
        const virt_client_config = &system.virt_tx_config.clients[client_id];

        system.createConnection(system.virt_tx, client, &virt_client_config.conn, &client_config.tx, client_info.tx_buffers);

        const data_mr_size = round_to_page(client_info.tx_buffers * BUFFER_SIZE);
        const data_mr_name = std.fmt.allocPrint(system.allocator, "{s}/net/tx/data/client/{s}", .{system.device.name, client.name}) catch @panic("OOM");
        const data_mr = Mr.physical(system.allocator, system.sdf, data_mr_name, data_mr_size, .{});
        system.sdf.addMemoryRegion(data_mr);

        const data_mr_virt_map = Map.create(data_mr, system.virt_tx.getMapVaddr(&data_mr), .rw, true, .{});
        system.virt_tx.addMap(data_mr_virt_map);
        virt_client_config.data = ConfigResources.Device.Region.createFromMap(data_mr_virt_map);

        const data_mr_client_map = Map.create(data_mr, client.getMapVaddr(&data_mr), .rw, true, .{});
        client.addMap(data_mr_client_map);
        client_config.tx_data = ConfigResources.Region.createFromMap(data_mr_client_map);
    }

    pub fn generateMacAddrs(system: *NetworkSystem) void {
        const rand = std.crypto.random;
        for (system.clients.items, 0..) |_, i| {
            if (system.client_info.items[i].mac_addr == null) {
                var mac_addr: [6]u8 = undefined;
                while (true) {
                    rand.bytes(&mac_addr);
                    var unique = true;
                    for (0..i) |j| {
                        const b = system.client_info.items[j].mac_addr.?;
                        if (std.mem.eql(u8, &mac_addr, &b)) {
                            unique = false;
                        }
                    }
                    if (unique) {
                        break;
                    }
                }
                system.client_info.items[i].mac_addr = mac_addr;
            }
        }
    }

    pub fn connect(system: *NetworkSystem) !void {
        try createDriver(system.sdf, system.driver, system.device, .network, &system.device_res);

        const rx_dma_mr = system.rxConnectDriver();
        system.txConnectDriver();

        system.generateMacAddrs();

        system.virt_tx_config.num_clients = @intCast(system.clients.items.len);
        system.virt_rx_config.num_clients = @intCast(system.clients.items.len);
        for (system.clients.items, 0..) |_, i| {
            // TODO: we have an assumption that all copiers are RX copiers
            system.clientRxConnect(rx_dma_mr, i);
            system.clientTxConnect(i);

            system.virt_rx_config.clients[i].mac_addr = system.client_info.items[i].mac_addr.?;
            system.client_configs.items[i].mac_addr = system.client_info.items[i].mac_addr.?;
        }
    }

    pub fn serialiseConfig(system: *NetworkSystem, prefix: []const u8) !void {
        const allocator = system.allocator;

        const device_res_data_name = std.fmt.allocPrint(allocator, "{s}_device_resources.data", .{ system.driver.name }) catch @panic("OOM");
        try data.serialize(system.device_res, try std.fs.path.join(allocator, &.{ prefix, device_res_data_name }));
        const device_res_json_name = std.fmt.allocPrint(allocator, "{s}_device_resources.json", .{ system.driver.name }) catch @panic("OOM");
        try data.jsonify(system.device_res, try std.fs.path.join(allocator, &.{ prefix, device_res_json_name }), .{ .whitespace = .indent_4 });

        try data.serialize(system.driver_config, try fs.path.join(allocator, &.{ prefix, "net_driver.data" }));
        try data.jsonify(system.driver_config, try fs.path.join(allocator, &.{ prefix, "net_driver.json"}), .{ .whitespace = .indent_4 });

        try data.serialize(system.virt_rx_config, try fs.path.join(allocator, &.{ prefix, "net_virt_rx.data" }));
        try data.jsonify(system.virt_rx_config, try fs.path.join(allocator, &.{ prefix, "net_virt_rx.json" }), .{ .whitespace = .indent_4 });

        try data.serialize(system.virt_tx_config, try fs.path.join(allocator, &.{ prefix, "net_virt_tx.data" }));
        try data.jsonify(system.virt_tx_config, try fs.path.join(allocator, &.{ prefix, "net_virt_tx.json" }), .{ .whitespace = .indent_4 });

        for (system.copiers.items, 0..) |copier, i| {
            const data_name = std.fmt.allocPrint(allocator, "net_copy_{s}.data", .{copier.name}) catch @panic("OOM");
            try data.serialize(system.copy_configs.items[i], try fs.path.join(allocator, &.{ prefix, data_name }));
            const json_name = std.fmt.allocPrint(allocator, "net_copy_{s}.json", .{copier.name}) catch @panic("OOM");
            try data.jsonify(system.copy_configs.items[i], try fs.path.join(allocator, &.{ prefix, json_name }), .{ .whitespace = .indent_4 });
        }

        for (system.clients.items, 0..) |client, i| {
            const data_name = std.fmt.allocPrint(allocator, "net_client_{s}.data", .{client.name}) catch @panic("OOM");
            try data.serialize(system.client_configs.items[i], try fs.path.join(allocator, &.{ prefix, data_name }));
            const json_name = std.fmt.allocPrint(allocator, "net_client_{s}.json", .{client.name}) catch @panic("OOM");
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
pub fn createDriver(sdf: *SystemDescription, pd: *Pd, device: *dtb.Node, class: Config.DeviceClass.Class, device_res: *ConfigResources.Device) !void {
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

    // TODO: check for duplicate dt index on irqs and regions
    for (driver.resources.regions) |region_resource| {
        if (region_resource.dt_index == null and region_resource.size == null) {
            log.err("driver '{s}' has region resource '{s}'' which specifies neither dt_index nor size: one or both must be specified", .{ driver.name, region_resource.name });
        }

        if (region_resource.dt_index != null and region_resource.cached != null and region_resource.cached.? == true) {
            log.err("driver '{s}' has region resource '{s}' which tries to map MMIO region as cached", .{ driver.name, region_resource.name });
        }

        const mr_name = std.fmt.allocPrint(sdf.allocator, "{s}/{s}/{s}", .{ device.name, driver.name, region_resource.name }) catch @panic("OOM");

        var mr: ?Mr = null;
        if (region_resource.dt_index != null) {
            const dt_reg = device.prop(.Reg).?;
            assert(region_resource.dt_index.? < dt_reg.len);

            const dt_reg_entry = dt_reg[region_resource.dt_index.?];
            assert(dt_reg_entry.len == 2);
            const dt_reg_paddr = dt_reg_entry[0];
            const dt_reg_size = round_to_page(@intCast(dt_reg_entry[1]));

            if (region_resource.size != null and dt_reg_size < region_resource.size.?) {
                log.err("device '{s}' has config region size for dt_index '{?}' that is too small (0x{x} bytes)", .{ device.name, region_resource.dt_index, dt_reg_size });
                return error.InvalidConfig;
            }

            if (region_resource.size != null and region_resource.size.? & ((1 << 12) - 1) != 0) {
                log.err("device '{s}' has config region size not aligned to page size for dt_index '{?}'", .{ device.name, region_resource.dt_index });
                return error.InvalidConfig;
            }

            if (dt_reg_size & ((1 << 12) - 1) != 0) {
                log.err("device '{s}' has DTB region size not aligned to page size for dt_index '{?}'", .{ device.name, region_resource.dt_index });
                return error.InvalidConfig;
            }

            const mr_size = if (region_resource.size != null) region_resource.size.? else dt_reg_size;

            const device_paddr = DeviceTree.regToPaddr(device, dt_reg_paddr);

            // TODO: hack when we have multiple virtIO devices. Need to come up with
            // a proper solution.
            for (sdf.mrs.items) |existing_mr| {
                if (existing_mr.paddr) |paddr| {
                    if (paddr == device_paddr) {
                        mr = existing_mr;
                    }
                }
            }
            if (mr == null) {
                mr = Mr.physical(sdf.allocator, sdf, mr_name, mr_size, .{ .paddr = device_paddr });
                sdf.addMemoryRegion(mr.?);
            }
        } else {
            const mr_size = region_resource.size.?;
            mr = Mr.physical(sdf.allocator, sdf, mr_name, mr_size, .{});
            sdf.addMemoryRegion(mr.?);
        }

        const perms = if (region_resource.perms != null) Map.Perms.fromString(region_resource.perms.?) else Map.Perms.rw;
        const cached = if (region_resource.cached != null) region_resource.cached.? else false;
        const map = Map.create(mr.?, pd.getMapVaddr(&mr.?), perms, cached, .{ .setvar_vaddr = region_resource.setvar_vaddr });
        pd.addMap(map);
        device_res.regions[device_res.num_regions] = ConfigResources.Device.Region.createFromMap(map);
        device_res.num_regions += 1;
    }

    // For all driver IRQs, find the corresponding entry in the device tree and
    // process it for the SDF.
    for (driver.resources.irqs) |driver_irq| {
        if (driver_irq.dt_index >= interrupts.len) {
            std.log.err("invalid device tree index '{}' when creating driver for '{s}'", .{ driver_irq.dt_index, driver.name });
            return error.InvalidDeviceTreeIndex;
        }
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

        const irq_channel = try pd.addInterrupt(irq);

        device_res.irqs[device_res.num_irqs] = .{
            .id = irq_channel,
        };
        device_res.num_irqs += 1;
    }
}
