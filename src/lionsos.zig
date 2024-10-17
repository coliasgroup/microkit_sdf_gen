const std = @import("std");
const mod_sdf = @import("sdf.zig");
const Allocator = std.mem.Allocator;

const SystemDescription = mod_sdf.SystemDescription;
const Pd = SystemDescription.ProtectionDomain;
const Mr = SystemDescription.MemoryRegion;
const Map = SystemDescription.Map;
const Channel = SystemDescription.Channel;

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

    pub fn init(allocator: Allocator, sdf: *SystemDescription, fs: *Pd, client: *Pd, options: Options) FileSystem {
        return .{
            .allocator = allocator,
            .sdf = sdf,
            .fs = fs,
            .client = client,
            .data_mr = options.data_mr,
            .data_size = options.data_size,
            .completion_queue_size = options.completion_queue_size,
            .command_queue_size = options.command_queue_size,
        };
    }

    pub fn connect(system: *const FileSystem) void {
        const allocator = system.allocator;
        const fs = system.fs;
        const client = system.client;

        const fs_command_queue = Mr.create(allocator, "fs_command_queue", system.command_queue_size, null, .small);
        const fs_completion_queue = Mr.create(allocator, "fs_completion_queue", system.completion_queue_size, null, .small);

        system.sdf.addMemoryRegion(fs_command_queue);
        system.sdf.addMemoryRegion(fs_completion_queue);

        const fs_share = blk: {
            if (system.data_mr) |data_mr| {
                break :blk data_mr;
            } else {
                const mr = Mr.create(allocator, "fs_share", system.data_size, null, .large);
                system.sdf.addMemoryRegion(mr);
                break :blk mr;
            }
        };

        fs.addMap(.create(fs_command_queue, fs.getMapVaddr(&fs_command_queue), .rw, true, "fs_command_queue"));
        fs.addMap(.create(fs_completion_queue, fs.getMapVaddr(&fs_completion_queue), .rw, true, "fs_completion_queue"));
        fs.addMap(.create(fs_share, fs.getMapVaddr(&fs_share), .rw, true, "fs_share"));

        client.addMap(.create(fs_command_queue, client.getMapVaddr(&fs_command_queue), .rw, true, "fs_command_queue"));
        client.addMap(.create(fs_completion_queue, client.getMapVaddr(&fs_completion_queue), .rw, true, "fs_completion_queue"));
        client.addMap(.create(fs_share, client.getMapVaddr(&fs_share), .rw, true, "fs_share"));

        system.sdf.addChannel(Channel.create(fs, client));
    }
};
