const std = @import("std");
const mod_sdf = @import("sdf.zig");
const mod_sddf = @import("sddf.zig");
const data = @import("data.zig");
const Allocator = std.mem.Allocator;

const SystemDescription = mod_sdf.SystemDescription;
const Pd = SystemDescription.ProtectionDomain;
const Mr = SystemDescription.MemoryRegion;
const Map = SystemDescription.Map;
const Channel = SystemDescription.Channel;

const ConfigResources = data.Resources;

const NetworkSystem = mod_sddf.NetworkSystem;
const SerialSystem = mod_sddf.SerialSystem;
const TimerSystem = mod_sddf.TimerSystem;

fn fmt(allocator: Allocator, comptime s: []const u8, args: anytype) []u8 {
    return std.fmt.allocPrint(allocator, s, args) catch @panic("OOM");
}

pub const FileSystem = struct {
    allocator: Allocator,
    sdf: *SystemDescription,
    fs: *Pd,
    client: *Pd,
    // The user can optionally override the data region MR
    data_mr: ?Mr,
    data_size: usize,
    completion_queue_size: usize,
    command_queue_size: usize,

    server_config: ConfigResources.Fs.Server,
    client_config: ConfigResources.Fs.Client,

    const Options = struct {
        data_mr: ?Mr = null,
        data_size: usize = 1024 * 1024 * 64,
        // TODO: do the queue sizes need to be the same?
        completion_queue_size: usize = 0x8000,
        command_queue_size: usize = 0x8000,
    };

    const Region = enum {
        data,
        command_queue,
        completion_queue,
    };

    const Error = error{
        InvalidClient,
    };

    pub fn init(allocator: Allocator, sdf: *SystemDescription, fs: *Pd, client: *Pd, options: Options) Error!FileSystem {
        if (std.mem.eql(u8, fs.name, client.name)) {
            std.log.err("invalid file system client, same name as file system PD '{s}", .{client.name});
            return Error.InvalidClient;
        }
        return .{
            .allocator = allocator,
            .sdf = sdf,
            .fs = fs,
            .client = client,
            .data_mr = options.data_mr,
            .data_size = options.data_size,
            .completion_queue_size = options.completion_queue_size,
            .command_queue_size = options.command_queue_size,

            .server_config = std.mem.zeroInit(ConfigResources.Fs.Server, .{}),
            .client_config = std.mem.zeroInit(ConfigResources.Fs.Client, .{}),
        };
    }

    pub fn connect(system: *FileSystem) void {
        const allocator = system.allocator;
        const fs = system.fs;
        const client = system.client;

        const fs_command_queue = Mr.create(allocator, fmt(allocator, "fs_{s}_command_queue", .{fs.name}), system.command_queue_size, .{});
        const fs_completion_queue = Mr.create(allocator, fmt(allocator, "fs_{s}_completion_queue", .{fs.name}), system.completion_queue_size, .{});

        system.sdf.addMemoryRegion(fs_command_queue);
        system.sdf.addMemoryRegion(fs_completion_queue);

        const fs_share = blk: {
            if (system.data_mr) |data_mr| {
                break :blk data_mr;
            } else {
                const mr = Mr.create(allocator, fmt(allocator, "fs_{s}_share", .{fs.name}), system.data_size, .{});
                system.sdf.addMemoryRegion(mr);
                break :blk mr;
            }
        };

        const server_command_map = Map.create(fs_command_queue, fs.getMapVaddr(&fs_command_queue), .rw, .{});
        fs.addMap(server_command_map);
        system.server_config.client.command_queue = .createFromMap(server_command_map);

        const server_completion_map = Map.create(fs_completion_queue, fs.getMapVaddr(&fs_completion_queue), .rw, .{});
        system.server_config.client.completion_queue = .createFromMap(server_completion_map);
        fs.addMap(server_completion_map);

        const server_share_map = Map.create(fs_share, fs.getMapVaddr(&fs_share), .rw, .{});
        fs.addMap(server_share_map);
        system.server_config.client.share = .createFromMap(server_share_map);

        const client_command_map = Map.create(fs_command_queue, client.getMapVaddr(&fs_command_queue), .rw, .{});
        system.client.addMap(client_command_map);
        system.client_config.server.command_queue = .createFromMap(client_command_map);

        const client_completion_map = Map.create(fs_completion_queue, client.getMapVaddr(&fs_completion_queue), .rw, .{});

        system.client.addMap(client_completion_map);
        system.client_config.server.completion_queue = .createFromMap(client_completion_map);

        const client_share_map = Map.create(fs_share, client.getMapVaddr(&fs_share), .rw, .{});
        system.client.addMap(client_share_map);
        system.client_config.server.share = .createFromMap(client_share_map);

        system.server_config.client.queue_len = 512;
        system.client_config.server.queue_len = 512;

        const channel = Channel.create(system.fs, system.client, .{}) catch @panic("failed to create connection channel");
        system.sdf.addChannel(channel);
        system.server_config.client.id = channel.pd_a_id;
        system.client_config.server.id = channel.pd_b_id;
    }

    pub fn serialiseConfig(system: *FileSystem, prefix: []const u8) !void {
        const allocator = system.allocator;

        const server_config_data_name = fmt(allocator, "fs_server_{s}.data", .{system.fs.name});
        try data.serialize(system.server_config, try std.fs.path.join(allocator, &.{ prefix, server_config_data_name }));
        const server_config_json_name = fmt(allocator, "fs_server_{s}.json", .{system.fs.name});
        try data.jsonify(system.server_config, try std.fs.path.join(allocator, &.{ prefix, server_config_json_name }));

        const client_config_data_name = fmt(allocator, "fs_client_{s}.data", .{system.client.name});
        try data.serialize(system.client_config, try std.fs.path.join(allocator, &.{ prefix, client_config_data_name }));
        const client_config_json_name = fmt(allocator, "fs_client_{s}.json", .{system.client.name});
        try data.jsonify(system.client_config, try std.fs.path.join(allocator, &.{ prefix, client_config_json_name }));
    }

    pub const Nfs = struct {
        fs: FileSystem,

        const Error = FileSystem.Error || NetworkSystem.Error;

        pub const Options = struct {
            mac_addr: ?[]const u8 = null,
        };

        pub fn init(allocator: Allocator, sdf: *SystemDescription, fs: *Pd, client: *Pd, net: *NetworkSystem, net_copier: *Pd, serial: *SerialSystem, timer: *TimerSystem, options: Nfs.Options) Nfs.Error!Nfs {
            // NFS depends on being connected via the network, serial, and timer sub-sytems.
            try net.addClientWithCopier(fs, net_copier, .{
                .mac_addr = options.mac_addr,
            });
            try serial.addClient(fs);
            try timer.addClient(fs);

            return .{
                .fs = try FileSystem.init(allocator, sdf, fs, client, .{}),
            };
        }

        pub fn connect(nfs: *Nfs) void {
            nfs.fs.connect();
        }

        pub fn serialiseConfig(nfs: *Nfs, prefix: []const u8) !void {
            nfs.fs.serialiseConfig(prefix) catch @panic("Could not serialise config");
        }
    };

    pub const Fat = struct {
        fs: FileSystem,

        pub fn init(allocator: Allocator, sdf: *SystemDescription, fs: *Pd, client: *Pd, options: Options) Error!Fat {
            return .{
                .fs = try FileSystem.init(allocator, sdf, fs, client, options),
            };
        }

        pub fn connect(fat: *Fat) void {
            fat.fs.connect();

            const allocator = fat.fs.allocator;
            const sdf = fat.fs.sdf;
            const fs = fat.fs.fs;

            // Special things for FATFS
            const fatfs_metadata = Mr.create(allocator, fmt(allocator, "{s}_metadata", .{fs.name}), 0x200_000, .{});
            fs.addMap(Map.create(fatfs_metadata, 0x40_000_000, .rw, .{ .setvar_vaddr = "fs_metadata" }));
            sdf.addMemoryRegion(fatfs_metadata);
            const stack1 = Mr.create(allocator, fmt(allocator, "{s}_stack1", .{fs.name}), 0x40_000, .{});
            const stack2 = Mr.create(allocator, fmt(allocator, "{s}_stack2", .{fs.name}), 0x40_000, .{});
            const stack3 = Mr.create(allocator, fmt(allocator, "{s}_stack3", .{fs.name}), 0x40_000, .{});
            const stack4 = Mr.create(allocator, fmt(allocator, "{s}_stack4", .{fs.name}), 0x40_000, .{});
            sdf.addMemoryRegion(stack1);
            sdf.addMemoryRegion(stack2);
            sdf.addMemoryRegion(stack3);
            sdf.addMemoryRegion(stack4);
            fs.addMap(.create(stack1, 0xA0_000_000, .rw, .{ .setvar_vaddr = "worker_thread_stack_one" }));
            fs.addMap(.create(stack2, 0xB0_000_000, .rw, .{ .setvar_vaddr = "worker_thread_stack_two" }));
            fs.addMap(.create(stack3, 0xC0_000_000, .rw, .{ .setvar_vaddr = "worker_thread_stack_three" }));
            fs.addMap(.create(stack4, 0xD0_000_000, .rw, .{ .setvar_vaddr = "worker_thread_stack_four" }));
        }
    };
};
