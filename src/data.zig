const std = @import("std");

/// For block sub-system:
/// Three regions for each client:
/// request, response, configuration

pub const Resources = struct {
    pub const Block = struct {
        pub const Virt = extern struct {
            const MAX_NUM_CLIENTS = 62;

            pub fn create(driver: Driver, clients: []const Client) Virt {
                var clients_array = std.mem.zeroes([MAX_NUM_CLIENTS]Client);
                for (clients, 0..) |client, i| {
                    clients_array[i] = client;
                }
                return .{
                    .num_clients = clients.len,
                    .driver = driver,
                    .clients = clients_array,
                };
            }

            pub const Client = extern struct {
                req_queue: u64,
                resp_queue: u64,
                storage_info: u64,
                data_vaddr: u64,
                data_paddr: u64,
                data_size: u64,
                queue_mr_size: u64,
                partition: u32,
            };

            pub const Driver = extern struct {
                storage_info: u64,
                req_queue: u64,
                resp_queue: u64,
                data_vaddr: u64,
                data_paddr: u64,
                data_size: u64,
            };

            num_clients: u64,
            driver: Driver,
            clients: [MAX_NUM_CLIENTS]Client,
        };
    };
};

pub fn serialize(s: anytype, path: []const u8) !void {
    const bytes = std.mem.toBytes(s);
    const serialize_file = try std.fs.cwd().createFile(path, .{});
    defer serialize_file.close();
    try serialize_file.writeAll(&bytes);
}

pub fn jsonify(s: anytype, path: []const u8, options: std.json.StringifyOptions) !void {
    const json_file = try std.fs.cwd().createFile(path, .{});
    defer json_file.close();

    const writer = json_file.writer();

    try std.json.stringify(s, options, writer);
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
        .driver = .{
            .storage_info = 0x1000,
            .req_queue = 0x2000,
            .resp_queue = 0x3000,
            .data_vaddr = 0x4000,
            .data_paddr = 0x5000,
            .data_size = 0x6000,
        },
        .clients = clients,
    };

    try serialize(virt_metadata, "virt.data");
}
