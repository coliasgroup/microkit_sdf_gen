const std = @import("std");

/// For block sub-system:
/// Three regions for each client:
/// request, response, configuration
pub const Resources = struct {
    pub const Block = struct {
        pub const Client = extern struct {
            storage_info: u64,
            req_queue: u64,
            resp_queue: u64,
            data_vaddr: u64,
            queue_capacity: u64,
        };

        pub const Virt = extern struct {
            const MAX_NUM_CLIENTS = 62;

            pub fn create(driver: Driver, clients: []const Virt.Client) Virt {
                var clients_array = std.mem.zeroes([MAX_NUM_CLIENTS]Virt.Client);
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
            clients: [MAX_NUM_CLIENTS]Virt.Client,
        };
    };

    pub const Serial = struct {
        pub const MAX_NUM_CLIENTS = 61;

        pub const Driver = extern struct {
            rx_queue_addr: u64,
            tx_queue_addr: u64,
            rx_data_addr: u64,
            tx_data_addr: u64,
            rx_capacity: u64,
            tx_capacity: u64,
            default_baud: u64,
            rx_enabled: u8,
        };

        pub const VirtRx = extern struct {
            pub const VirtRxClient = extern struct {
                queue_addr: u64,
                data_addr: u64,
                capacity: u64,
            };

            queue_drv: u64,
            data_drv: u64,
            capacity_drv: u64,
            switch_char: u8,
            terminate_num_char: u8,
            num_clients: u64,
            clients: [MAX_NUM_CLIENTS]VirtRxClient,
        };

        pub const VirtTx = extern struct {
            pub const MAX_NAME_LEN = 64;
            pub const MAX_BEGIN_STR_LEN = 128;

            pub const VirtTxClient = extern struct {
                name: [MAX_NAME_LEN]u8,
                queue_addr: u64,
                data_addr: u64,
                capacity: u64,
            };

            queue_addr_drv: u64,
            data_addr_drv: u64,
            capacity_drv: u64,
            begin_str: [MAX_BEGIN_STR_LEN]u8,
            begin_str_len: u64,
            enable_colour: u8,
            enable_rx: u8,
            num_clients: u64,
            clients: [MAX_NUM_CLIENTS]VirtTxClient,
        };

        pub const Client = extern struct {
            rx_queue_addr: u64,
            rx_data_addr: u64,
            rx_capacity: u64,
            tx_queue_addr: u64,
            tx_data_addr: u64,
            tx_capacity: u64,
        };
    };

    pub const I2c = struct {
        pub const Virt = extern struct {
            const MAX_NUM_CLIENTS = 61;

            pub const Client = extern struct {
                request_queue: u64,
                response_queue: u64,
                driver_data_offset: u64,
                data_size: u64,
            };

            driver_request_queue: u64,
            driver_response_queue: u64,
            num_clients: u64,
            clients: [MAX_NUM_CLIENTS]Client,
        };

        pub const Driver = extern struct {
            bus_num: u64,
            request_region: u64,
            response_region: u64,
            data_region: u64,
            i2c_regs: u64,
            gpio_regs: u64,
            clk_regs: u64,
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
