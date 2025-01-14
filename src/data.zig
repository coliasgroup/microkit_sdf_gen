const std = @import("std");
const sdf = @import("sdf.zig");

pub const Resources = struct {
    /// Provides information to a component about a memory region that is mapped into its address space
    pub const Region = extern struct {
        pub fn create(vaddr: u64, size: u64) Region {
            return .{
                .vaddr = vaddr,
                .size = size,
            };
        }

        pub fn createFromMap(map: sdf.SystemDescription.Map) Region {
            return create(map.vaddr, map.mr.size);
        }

        vaddr: u64,
        size: u64,
    };

    /// Resources to be injected into the driver, need to match with code definition.
    pub const Device = extern struct {
        pub const MaxRegions = 64;
        pub const MaxIrqs = 64;

        pub const Region = extern struct {
            region: Resources.Region,
            io_addr: u64,

            pub fn create(vaddr: u64, size: u64, io_addr: u64) Device.Region {
                return .{
                    .region = Resources.Region.create(vaddr, size),
                    .io_addr = io_addr,
                };
            }

            pub fn createFromMap(map: sdf.SystemDescription.Map) Device.Region {
                std.debug.assert(map.mr.paddr != null);
                return create(map.vaddr, map.mr.size, map.mr.paddr.?);
            }
        };

        pub const Irq = extern struct {
            id: u8,
        };

        num_regions: u8,
        num_irqs: u8,
        regions: [MaxRegions]Device.Region,
        irqs: [MaxIrqs]Irq,
    };

    /// For block sub-system:
    /// Three regions for each client:
    /// request, response, configuration
    pub const Block = struct {
        pub const Connection = extern struct {
            storage_info: Region,
            req_queue: Region,
            resp_queue: Region,
            num_buffers: u16,
            id: u8,
        };

        pub const Client = extern struct {
            virt: Connection,
            data: Region,
        };

        pub const Virt = extern struct {
            const MAX_NUM_CLIENTS = 61;

            pub fn create(driver: Virt.Driver, clients: []const Virt.Client) Virt {
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
                conn: Connection,
                data: Device.Region,
                partition: u32,
            };

            pub const Driver = extern struct {
                conn: Connection,
                data: Device.Region,
            };

            num_clients: u64,
            driver: Virt.Driver,
            clients: [MAX_NUM_CLIENTS]Virt.Client,
        };

        pub const Driver = extern struct {
            virt: Connection,
        };
    };

    pub const Serial = struct {
        pub const MAX_NUM_CLIENTS = 61;

        pub const Connection = extern struct {
            queue: Region,
            data: Region,
            id: u8,
        };

        pub const Driver = extern struct {
            rx: Connection,
            tx: Connection,
            default_baud: u64,
            rx_enabled: u8,
        };

        pub const VirtRx = extern struct {
            driver: Connection,
            clients: [MAX_NUM_CLIENTS]Connection,
            num_clients: u8,
            switch_char: u8,
            terminate_num_char: u8,
        };

        pub const VirtTx = extern struct {
            pub const MAX_NAME_LEN = 64;
            pub const MAX_BEGIN_STR_LEN = 128;

            pub const VirtTxClient = extern struct {
                conn: Connection,
                name: [MAX_NAME_LEN]u8,
            };

            driver: Connection,
            clients: [MAX_NUM_CLIENTS]VirtTxClient,
            num_clients: u8,
            begin_str: [MAX_BEGIN_STR_LEN]u8,
            begin_str_len: u8,
            enable_colour: u8,
            enable_rx: u8,
        };

        pub const Client = extern struct {
            rx: Connection,
            tx: Connection,
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
            driver_id: u8,
            num_clients: u64,
            clients: [MAX_NUM_CLIENTS]VirtClient,
        };

        pub const Driver = extern struct {
            bus_num: u64,
            request_region: u64,
            response_region: u64,
            data_region: u64,
            virt_id: u8,
        };

        pub const Client = extern struct {
            request_region: u64,
            response_region: u64,
            data_region: u64,
            virt_id: u8,
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
            data_region: Device.Region,
            buffer_metadata: Region,
            clients: [MAX_NUM_CLIENTS]VirtRxClient,
            num_clients: u8,
        };

        pub const VirtTx = extern struct {
            pub const VirtTxClient = extern struct {
                conn: Connection,
                data: Device.Region,
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
    const bytes = std.mem.asBytes(&s);
    const serialize_file = try std.fs.cwd().createFile(path, .{});
    defer serialize_file.close();
    try serialize_file.writeAll(bytes);
}

pub fn jsonify(s: anytype, path: []const u8, options: std.json.StringifyOptions) !void {
    const json_file = try std.fs.cwd().createFile(path, .{});
    defer json_file.close();

    const writer = json_file.writer();

    try std.json.stringify(s, options, writer);
}
