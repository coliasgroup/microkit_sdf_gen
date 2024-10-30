const std = @import("std");

/// For block sub-system:
/// Three regions for each client:
/// request, response, configuration

const Resources = struct {
    const Block = struct {
        const Virt = extern struct {
            const MAX_NUM_CLIENTS = 62;

            const Client = extern struct {
                req_queue: u64,
                resp_queue: u64,
                storage_info: u64,
                data_vaddr: u64,
                data_paddr: u64,
                data_size: u64,
                queue_capacity: u64,
                partition: u32,
            };

            num_clients: u64,
            driver_storage_info: u64,
            driver_req_queue: u64,
            driver_resp_queue: u64,
            driver_data_vaddr: u64,
            driver_data_paddr: u64,
            driver_data_size: u64,
            clients: [MAX_NUM_CLIENTS]Client,
        };
    };
};

const myStruct = struct {
    x: usize,
    y: usize,
};

pub fn serialize(s: anytype, path: []const u8) !void {
    const bytes = std.mem.toBytes(s);
    const serialize_file = try std.fs.cwd().createFile(path, .{});
    defer serialize_file.close();
    std.debug.print("bytes len: {}, bytes: {any}\n", .{ bytes.len, bytes });
    try serialize_file.writeAll(&bytes);
}

pub fn main() !void {
    const clients = [_]Resources.Block.Virt.Client{.{
        .req_queue = 0x7000,
        .resp_queue = 0x8000,
        .storage_info = 0x9000,
        .data_vaddr = 0x10000,
        .data_paddr = 0x11000,
        .queue_capacity = 0x12000,
        .data_size = 0x1000000000,
        .partition = 0,
    }} ** 62;
    const virt_metadata: Resources.Block.Virt = .{
        .num_clients = 1,
        .driver_storage_info = 0x1000,
        .driver_req_queue = 0x2000,
        .driver_resp_queue = 0x3000,
        .driver_data_vaddr = 0x4000,
        .driver_data_paddr = 0x5000,
        .driver_data_size = 0x6000,
        .clients = clients,
    };

    try serialize(virt_metadata, "virt.data");
}
