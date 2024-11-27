const std = @import("std");
const sdf = @import("sdf.zig");

// TODO: apply this more widely
pub const DeviceTreeIndex = u8;

pub const Resources = struct {
    /// Provides information to a component about a memory region that is mapped into its address space
    pub const Region = extern struct {
        pub fn create(vaddr: usize, size: usize) Region {
            return .{
                .vaddr = vaddr,
                .paddr = 0, // null
                .size = size,
            };
        }

        pub fn createWithPaddr(vaddr: u64, paddr: u64, size: usize) Region {
            return .{
                .vaddr = vaddr,
                .paddr = paddr,
                .size = size,
            };
        }

        pub fn createFromMap(map: sdf.SystemDescription.Map) Region {
            return create(map.vaddr, map.mr.size);
        }

        pub fn createFromMapWithPaddr(map: sdf.SystemDescription.Map) !Region {
            return createWithPaddr(map.vaddr, map.mr.paddr.?, map.mr.size);
        }

        vaddr: u64,
        /// paddr can be left null if it is not needed
        paddr: u64,
        size: u64,
    };

    /// Resources to be injected into the driver, need to match with code definition.
    pub const Device = extern struct {
        pub const MaxRegions = 64;
        pub const MaxIrqs = 64;

        pub const Irq = extern struct {
            id: u8,
        };

        num_regions: u8,
        num_irqs: u8,
        regions: [MaxRegions]Region,
        irqs: [MaxIrqs]Irq,
    };

    /// For block sub-system:
    /// Three regions for each client:
    /// request, response, configuration
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
            rx_id: u8,
            tx_id: u8,
        };

        pub const VirtRx = extern struct {
            pub const VirtRxClient = extern struct {
                queue_addr: u64,
                data_addr: u64,
                capacity: u64,
                id: u8,
            };

            queue_drv: u64,
            data_drv: u64,
            capacity_drv: u64,
            switch_char: u8,
            terminate_num_char: u8,
            num_clients: u64,
            driver_id: u8,
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
                id: u8,
            };

            queue_addr_drv: u64,
            data_addr_drv: u64,
            capacity_drv: u64,
            begin_str: [MAX_BEGIN_STR_LEN]u8,
            begin_str_len: u64,
            enable_colour: u8,
            enable_rx: u8,
            num_clients: u64,
            driver_id: u8,
            clients: [MAX_NUM_CLIENTS]VirtTxClient,
        };

        pub const Client = extern struct {
            rx_queue_addr: u64,
            rx_data_addr: u64,
            rx_capacity: u64,
            tx_queue_addr: u64,
            tx_data_addr: u64,
            tx_capacity: u64,
            rx_id: u8,
            tx_id: u8,
        };
    };

    pub const I2c = struct {
        pub const Virt = extern struct {
            const MAX_NUM_CLIENTS = 61;

            pub const VirtClient = extern struct {
                request_queue: u64,
                response_queue: u64,
                driver_data_offset: u64,
                data_size: u64,
            };

            driver_request_queue: u64,
            driver_response_queue: u64,
            num_clients: u64,
            clients: [MAX_NUM_CLIENTS]VirtClient,
        };

        pub const Driver = extern struct {
            bus_num: u64,
            request_region: u64,
            response_region: u64,
            data_region: u64,
        };

        pub const Client = extern struct {
            request_region: u64,
            response_region: u64,
            data_region: u64,
        };
    };

    pub const Net = struct {
        pub const MAX_NUM_CLIENTS = 61;

        pub const Connection = extern struct {
            free_queue: Region,
            active_queue: Region,
            num_buffers: u16,
            id: u8,
        };

        pub const Driver = extern struct {
            virt_rx: Connection,
            virt_tx: Connection,
        };

        pub const VirtRx = extern struct {
            pub const VirtRxClient = extern struct {
                conn: Connection,
                mac_addr: [6]u8,
            };

            driver: Connection,
            data_region: Region,
            buffer_metadata: Region,
            clients: [MAX_NUM_CLIENTS]VirtRxClient,
            num_clients: u8,
        };

        pub const VirtTx = extern struct {
            pub const VirtTxClient = extern struct {
                conn: Connection,
                data: Region,
            };

            driver: Connection,
            clients: [MAX_NUM_CLIENTS]VirtTxClient,
            num_clients: u8,
        };

        pub const Copy = extern struct {
            virt_rx: Connection,
            device_data: Region,

            client: Connection,
            client_data: Region,
        };

        pub const Client = extern struct {
            rx: Connection,
            rx_data: Region,

            tx: Connection,
            tx_data: Region,

            mac_addr: [6]u8,
        };
    };

    pub const Timer = struct {
        pub const MAX_NUM_CLIENTS = 61;

        pub const Client = extern struct {
            driver_id: u8,
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
