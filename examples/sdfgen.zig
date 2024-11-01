const std = @import("std");
const builtin = @import("builtin");
const mod_sdf = @import("sdf");
const mod_vmm = mod_sdf.vmm;
const sddf = mod_sdf.sddf;
const lionsos = mod_sdf.lionsos;
const dtb = mod_sdf.dtb;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const SystemDescription = mod_sdf.sdf.SystemDescription;
const Pd = SystemDescription.ProtectionDomain;
const Vm = SystemDescription.VirtualMachine;
const Mr = SystemDescription.MemoryRegion;
const Map = SystemDescription.Map;
const Irq = SystemDescription.Interrupt;
const Channel = SystemDescription.Channel;

const VirtualMachineSystem = mod_vmm.VirtualMachineSystem;

const MicrokitBoard = enum {
    qemu_virt_aarch64,
    odroidc4,

    pub fn fromStr(str: []const u8) !MicrokitBoard {
        inline for (std.meta.fields(MicrokitBoard)) |field| {
            if (std.mem.eql(u8, str, field.name)) {
                return @enumFromInt(field.value);
            }
        }

        return error.BoardNotFound;
    }

    pub fn paddrTop(b: MicrokitBoard) u64 {
        // TODO: just get this from the DTS
        return switch (b) {
            .qemu_virt_aarch64 => 0xa0000000,
            .odroidc4 => 0x80000000,
        };
    }

    pub fn arch(b: MicrokitBoard) SystemDescription.Arch {
        return switch (b) {
            .qemu_virt_aarch64, .odroidc4 => .aarch64,
        };
    }

    pub fn printFields() void {
        comptime var i: usize = 0;
        const fields = @typeInfo(@This()).Enum.fields;
        inline while (i < fields.len) : (i += 1) {
            std.debug.print("{s}\n", .{fields[i].name});
        }
    }
};

const Example = enum {
    webserver,
    blk,
    i2c,
    serial,

    pub fn fromStr(str: []const u8) !Example {
        inline for (std.meta.fields(Example)) |field| {
            if (std.mem.eql(u8, str, field.name)) {
                return @enumFromInt(field.value);
            }
        }

        return error.ExampleNotFound;
    }

    pub fn generate(e: Example, allocator: Allocator, sdf: *SystemDescription, blob: *dtb.Node) !void {
        switch (e) {
            .webserver => try webserver(allocator, sdf, blob),
            .blk => try blk(allocator, sdf, blob),
            .i2c => try i2c(allocator, sdf, blob),
            .serial => try serial(allocator, sdf, blob),
        }
    }

    pub fn printFields() void {
        comptime var i: usize = 0;
        const fields = @typeInfo(@This()).Enum.fields;
        inline while (i < fields.len) : (i += 1) {
            std.debug.print("{s}\n", .{fields[i].name});
        }
    }
};

var xml_out_path: []const u8 = "example.system";
var sddf_path: []const u8 = "sddf";
var dtbs_path: []const u8 = "dtbs";
var board: MicrokitBoard = undefined;
var example: Example = undefined;

const usage_text =
    \\Usage sdfgen --board [BOARD] --example [EXAMPLE SYSTEM] [options]
    \\
    \\Generates a Microkit system description file programatically
    \\
    \\ Options:
    \\ --board <board>
    \\      The possible values for this option are: {s}
    \\ --example <example>
    \\      The possible values for this option are: {s}
    \\ --sdf <path>     (default: ./example.system) Path to output the generated system description file
    \\ --sddf <path>    (default: ./sddf/) Path to the sDDF repository
    \\ --dtbs <path>     (default: ./dtbs/) Path to directory of Device Tree Blobs
    \\
;

const usage_text_formatted = std.fmt.comptimePrint(usage_text, .{ MicrokitBoard.fields(), Example.fields() });

fn parseArgs(args: []const []const u8, allocator: Allocator) !void {
    const stdout = std.io.getStdOut();

    const board_fields = comptime std.meta.fields(MicrokitBoard);
    var board_options = ArrayList(u8).init(allocator);
    defer board_options.deinit();
    inline for (board_fields) |field| {
        try board_options.appendSlice("\n           ");
        try board_options.appendSlice(field.name);
    }
    const example_fields = comptime std.meta.fields(Example);
    var example_options = ArrayList(u8).init(allocator);
    defer example_options.deinit();
    inline for (example_fields) |field| {
        try example_options.appendSlice("\n           ");
        try example_options.appendSlice(field.name);
    }

    const usage_text_fmt = try std.fmt.allocPrint(allocator, usage_text, .{ board_options.items, example_options.items });
    defer allocator.free(usage_text_fmt);

    var board_given = false;
    var example_given = false;

    var arg_i: usize = 1;
    while (arg_i < args.len) : (arg_i += 1) {
        const arg = args[arg_i];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try stdout.writeAll(usage_text_fmt);
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--sdf")) {
            arg_i += 1;
            if (arg_i >= args.len) {
                std.debug.print("'{s}' requires an argument.\n{s}", .{ arg, usage_text_fmt });
                std.process.exit(1);
            }
            xml_out_path = args[arg_i];
            std.debug.print("xml_out_path is: {s}\n", .{xml_out_path});
        } else if (std.mem.eql(u8, arg, "--board")) {
            arg_i += 1;
            if (arg_i >= args.len) {
                std.debug.print("'{s}' requires an argument.\n{s}", .{ arg, usage_text_fmt });
                std.process.exit(1);
            }
            board = MicrokitBoard.fromStr(args[arg_i]) catch {
                std.debug.print("Invalid board '{s}' given\n", .{args[arg_i]});
                std.process.exit(1);
            };
            board_given = true;
        } else if (std.mem.eql(u8, arg, "--example")) {
            arg_i += 1;
            if (arg_i >= args.len) {
                std.debug.print("'{s}' requires an argument.\n{s}", .{ arg, usage_text_fmt });
                std.process.exit(1);
            }
            example = Example.fromStr(args[arg_i]) catch {
                std.debug.print("Invalid example '{s}' given\n", .{args[arg_i]});
                std.process.exit(1);
            };
            example_given = true;
        } else if (std.mem.eql(u8, arg, "--sddf")) {
            arg_i += 1;
            if (arg_i >= args.len) {
                std.debug.print("'{s}' requires a path to the sDDF repository.\n{s}", .{ arg, usage_text_fmt });
                std.process.exit(1);
            }
            sddf_path = args[arg_i];
        } else if (std.mem.eql(u8, arg, "--dtbs")) {
            arg_i += 1;
            if (arg_i >= args.len) {
                std.debug.print("'{s}' requires a path to the directory holding all the DTBs.\n{s}", .{ arg, usage_text_fmt });
                std.process.exit(1);
            }
            dtbs_path = args[arg_i];
        } else {
            std.debug.print("unrecognized argument: '{s}'\n{s}", .{ arg, usage_text_fmt });
            std.process.exit(1);
        }
    }

    if (arg_i == 1) {
        try stdout.writeAll(usage_text_fmt);
        std.process.exit(1);
    }

    if (!board_given) {
        std.debug.print("Missing '--board' argument\n", .{});
        std.process.exit(1);
    } else if (!example_given) {
        std.debug.print("Missing '--example' argument\n", .{});
        std.process.exit(1);
    }
}

fn i2c(allocator: Allocator, sdf: *SystemDescription, blob: *dtb.Node) !void {
    const i2c_node = switch (board) {
        .odroidc4 => blob.child("soc").?.child("bus@ffd00000").?.child("i2c@1d000").?,
        .qemu_virt_aarch64 => @panic("no i2c for qemu"),
    };

    const clk_mr = Mr.physical(allocator, sdf, "clk", 0x1000, .{ .paddr = 0xFF63C000 });
    const gpio_mr = Mr.physical(allocator, sdf, "gpio", 0x4000, .{ .paddr = 0xFF634000 });

    sdf.addMemoryRegion(clk_mr);
    sdf.addMemoryRegion(gpio_mr);

    var client = Pd.create(allocator, "client", "client.elf");
    sdf.addProtectionDomain(&client);

    var i2c_driver = Pd.create(allocator, "i2c_driver", "i2c_driver.elf");
    sdf.addProtectionDomain(&i2c_driver);
    var i2c_virt = Pd.create(allocator, "i2c_virt", "i2c_virt.elf");
    sdf.addProtectionDomain(&i2c_virt);

    var i2c_system = sddf.I2cSystem.init(allocator, sdf, i2c_node, &i2c_driver, &i2c_virt, .{});
    i2c_system.addClient(&client);

    i2c_driver.addMap(.create(clk_mr, i2c_driver.getMapVaddr(&clk_mr), .rw, false, .{}));
    i2c_driver.addMap(.create(gpio_mr, i2c_driver.getMapVaddr(&gpio_mr), .rw, false, .{}));

    _ = try i2c_system.connect();

    // try i2c_system.serialiseConfig();

    try sdf.print();
}

fn blk(allocator: Allocator, sdf: *SystemDescription, blob: *dtb.Node) !void {
    const blk_node = switch (board) {
        .odroidc4 => @panic("no block for odroidc4"),
        .qemu_virt_aarch64 => blob.child("virtio_mmio@a003e00").?,
    };

    var client = Pd.create(allocator, "client", "client.elf");
    sdf.addProtectionDomain(&client);

    var blk_driver = Pd.create(allocator, "blk_driver", "blk_driver.elf");
    sdf.addProtectionDomain(&blk_driver);
    var blk_virt = Pd.create(allocator, "blk_virt", "blk_virt.elf");
    sdf.addProtectionDomain(&blk_virt);

    var blk_system = sddf.BlockSystem.init(allocator, sdf, blk_node, &blk_driver, &blk_virt, .{});
    blk_system.addClient(&client);

    _ = try blk_system.connect();

    try blk_system.serialiseConfig("blk_virt.data");

    try sdf.print();
}

/// Webserver has the following components/subsystems
/// * serial
/// * network
/// * micropython client
/// * nfs client
fn webserver(allocator: Allocator, sdf: *SystemDescription, blob: *dtb.Node) !void {
    const uart_node = switch (board) {
        .odroidc4 => blob.child("soc").?.child("bus@ff800000").?.child("serial@3000").?,
        .qemu_virt_aarch64 => blob.child("pl011@9000000").?,
    };

    var uart_driver = Pd.create(allocator, "uart_driver", "uart_driver.elf");
    sdf.addProtectionDomain(&uart_driver);

    // var serial_virt_rx = Pd.create(allocator, "serial_virt_rx", "serial_virt_rx.elf");
    // sdf.addProtectionDomain(&serial_virt_rx);
    var serial_virt_tx = Pd.create(allocator, "serial_virt_tx", "serial_virt_tx.elf");
    sdf.addProtectionDomain(&serial_virt_tx);

    var eth_virt_rx = Pd.create(allocator, "eth_virt_rx", "network_virt_rx.elf");
    sdf.addProtectionDomain(&eth_virt_rx);
    var eth_virt_tx = Pd.create(allocator, "eth_virt_tx", "network_virt_tx.elf");
    sdf.addProtectionDomain(&eth_virt_tx);

    const timer_node = switch (board) {
        .odroidc4 => blob.child("soc").?.child("bus@ffd00000").?.child("watchdog@f0d0").?,
        .qemu_virt_aarch64 => blob.child("timer").?
    };

    var timer_driver = Pd.create(allocator, "timer_driver", "timer_driver.elf");
    sdf.addProtectionDomain(&timer_driver);

    var micropython = Pd.create(allocator, "micropython", "micropython.elf");
    sdf.addProtectionDomain(&micropython);

    var fatfs = Pd.create(allocator, "fatfs", "fatfs.elf");
    sdf.addProtectionDomain(&fatfs);

    var timer_system = sddf.TimerSystem.init(allocator, sdf, timer_node, &timer_driver);
    timer_system.addClient(&micropython);
    // timer_system.addClient(&nfs);

    var serial_system = try sddf.SerialSystem.init(allocator, sdf, uart_node, &uart_driver, &serial_virt_tx, null, .{ .rx = false });
    serial_system.addClient(&micropython);
    // serial_system.addClient(&nfs);

    const blk_node = switch (board) {
        .odroidc4 => @panic("no block for odroidc4"),
        .qemu_virt_aarch64 => blob.child("virtio_mmio@a002e00").?,
    };

    var blk_driver = Pd.create(allocator, "blk_driver", "blk_driver.elf");
    sdf.addProtectionDomain(&blk_driver);
    var blk_virt = Pd.create(allocator, "blk_virt", "blk_virt.elf");
    sdf.addProtectionDomain(&blk_virt);

    var blk_system = sddf.BlockSystem.init(allocator, sdf, blk_node, &blk_driver, &blk_virt, .{});
    blk_system.addClient(&fatfs);

    const eth_node = switch (board) {
        .odroidc4 => blob.child("soc").?.child("ethernet@ff3f0000").?,
        .qemu_virt_aarch64 => blob.child("virtio_mmio@a003e00").?,
    };
    var eth_driver = Pd.create(allocator, "eth_driver", "eth_driver.elf");
    sdf.addProtectionDomain(&eth_driver);

    var eth_copy_mp = Pd.create(allocator, "eth_copy_mp", "copy.elf");
    sdf.addProtectionDomain(&eth_copy_mp);
    // var eth_copy_nfs = Pd.create(sdf, "eth_copy_nfs", "copy.elf");
    // sdf.addProtectionDomain(&eth_copy_nfs);

    var eth_system = sddf.NetworkSystem.init(allocator, sdf, eth_node, &eth_driver, &eth_virt_rx, &eth_virt_tx, .{});
    // eth_system.addClientWithCopier(&nfs, &eth_copy_nfs);
    eth_system.addClientWithCopier(&micropython, &eth_copy_mp);

    eth_driver.priority = 110;
    eth_driver.budget = 100;
    eth_driver.period = 400;

    eth_virt_rx.priority = 108;
    eth_virt_rx.budget = 100;
    eth_virt_rx.period = 500;

    eth_virt_tx.priority = 109;
    eth_virt_tx.budget = 100;
    eth_virt_tx.period = 500;

    // eth_copy_nfs.priority = 99;
    // eth_copy_nfs.budget = 100;
    // eth_copy_nfs.period = 500;

    eth_copy_mp.priority = 97;
    eth_copy_mp.budget = 20000;

    eth_copy_mp.priority = 97;
    eth_copy_mp.budget = 20000;

    uart_driver.priority = 100;

    // nfs.priority = 98;
    // nfs.stack_size = 0x10000;

    micropython.priority = 1;

    timer_driver.priority = 150;

    serial_virt_tx.priority = 99;

    try eth_system.connect();
    try timer_system.connect();
    try serial_system.connect();
    _ = try blk_system.connect();

    const fatfs_metadata = Mr.create(allocator, "fatfs_metadata", 0x200_000, .{});
    std.debug.print("metadata vaddr {x}\n", .{ fatfs.getMapVaddr(&fatfs_metadata) });
    // TODO: fix
    fatfs.addMap(Map.create(fatfs_metadata, 0x40_000_000, .rw, true, .{ .setvar_vaddr = "fs_metadata" }));
    sdf.addMemoryRegion(fatfs_metadata);

    const fs = lionsos.FileSystem.init(allocator, sdf, &fatfs, &micropython, .{});
    fs.connect();

    try sdf.print();
}

fn kitty(allocator: Allocator, sdf: *SystemDescription, blob: *dtb.Node) !void {
    const uart_node = switch (board) {
        .odroidc4 => blob.child("soc").?.child("bus@ff800000").?.child("serial@3000").?,
        .qemu_virt_aarch64 => blob.child("pl011@9000000").?,
    };

    var uart_driver = Pd.create(sdf, "uart_driver", "uart_driver.elf");
    sdf.addProtectionDomain(&uart_driver);

    var serial_virt_rx = Pd.create(sdf, "serial_virt_rx", "serial_virt_rx.elf");
    sdf.addProtectionDomain(&serial_virt_rx);
    var serial_virt_tx = Pd.create(sdf, "serial_virt_tx", "serial_virt_tx.elf");
    sdf.addProtectionDomain(&serial_virt_tx);

    var serial_system = sddf.SerialSystem.init(allocator, sdf, uart_node, &uart_driver, &serial_virt_rx, &serial_virt_tx, .{});

    const timer_node = switch (board) {
        .odroidc4 => blob.child("soc").?.child("bus@ffd00000").?.child("watchdog@f0d0").?,
        else => @panic("Don't know timer node for platform")
    };

    var timer_client = Pd.create(sdf, "timer_client", "timer_client.elf");
    sdf.addProtectionDomain(&timer_client);

    var timer_driver = Pd.create(sdf, "timer_driver", "timer_driver.elf");
    sdf.addProtectionDomain(&timer_driver);

    var timer_system = sddf.TimerSystem.init(allocator, sdf, &timer_driver, timer_node);
    timer_system.addClient(&timer_client);
    try timer_system.connect();

    try serial_system.connect();
    const xml = try sdf.toXml();
    std.debug.print("{s}", .{xml});
}

// One by one we will figure it out.
/// DONE: 1. Driver is correct and has the right resources
/// 2. Virtualisers are correct and have the right resources
/// 3. Copiers are correct and have the right resources
/// 4. Clients are correct and have the right resources
/// 5. Benchmark program stuff
/// Do not worry about the abstraction stuff. First reproduce the echo server,
/// then consider whether the abstractions are correct.
fn echo_server(allocator: Allocator, sdf: *SystemDescription, blob: *dtb.Node) !void {
    const image = "uart_driver.elf";
    var driver = Pd.create(sdf, "uart_driver", image);
    sdf.addProtectionDomain(&driver);

    var uart_node: ?*dtb.Node = undefined;
    // TODO: We would probably want some helper functionality that just takes
    // the full node name such as "/soc/bus@ff8000000/serial@3000" and would
    // find the DTB node info that we need. For now, this fine.
    switch (board) {
        .odroidc4 => {
            const soc_node = blob.child("soc").?;
            const bus_node = soc_node.child("bus@ff800000").?;
            uart_node = bus_node.child("serial@3000");
        },
        .qemu_virt_aarch64 => {
            uart_node = blob.child("pl011@9000000");
        },
    }

    if (uart_node == null) {
        std.log.err("Could not find UART node '{s}'", .{"pl011@9000000"});
        std.process.exit(1);
    }

    var serial_virt_rx = Pd.create(sdf, "serial_virt_rx", "serial_virt_rx.elf");
    sdf.addProtectionDomain(&serial_virt_rx);

    var serial_virt_tx = Pd.create(sdf, "serial_virt_tx", "serial_virt_tx.elf");
    sdf.addProtectionDomain(&serial_virt_tx);

    var serial_system = sddf.SerialSystem.init(allocator, sdf, uart_node.?, &driver, &serial_virt_tx, &serial_virt_rx, .{});

    const ethernet = switch (board) {
        .odroidc4 => blk: {
            const soc_node = blob.child("soc").?;
            break :blk soc_node.child("ethernet@ff3f0000").?;
        },
        .qemu_virt_aarch64 => @panic("TODO"),
    };

    var eth_driver = Pd.create(sdf, "eth_driver", "eth_driver.elf");
    eth_driver.budget = 100;
    eth_driver.period = 400;
    eth_driver.priority = 101;
    sdf.addProtectionDomain(&eth_driver);

    var net_virt_tx = Pd.create(sdf, "net_virt_tx", "net_virt_tx.elf");
    net_virt_tx.priority = 100;
    net_virt_tx.budget = 20000;
    sdf.addProtectionDomain(&net_virt_tx);

    var net_virt_rx = Pd.create(sdf, "net_virt_rx", "net_virt_rx.elf");
    net_virt_tx.priority = 99;
    sdf.addProtectionDomain(&net_virt_rx);

    var net_copier0_rx = Pd.create(sdf, "net_copier0_rx", "net_copier_rx.elf");
    sdf.addProtectionDomain(&net_copier0_rx);
    var net_copier1_rx = Pd.create(sdf, "net_copier1_rx", "net_copier_rx.elf");
    sdf.addProtectionDomain(&net_copier1_rx);

    var client0 = Pd.create(sdf, "client0", "lwip.elf");
    sdf.addProtectionDomain(&client0);
    var client1 = Pd.create(sdf, "client1", "lwip.elf");
    sdf.addProtectionDomain(&client1);

    var ethernet_system = sddf.NetworkSystem.init(allocator, sdf, ethernet, &eth_driver, &net_virt_rx, &net_virt_tx, .{
        .region_size = 0x200_000
    });
    ethernet_system.addClientWithCopier(&client0, &net_copier0_rx);
    ethernet_system.addClientWithCopier(&client1, &net_copier1_rx);

    var timer_driver = Pd.create(sdf, "timer_driver", "timer_driver.elf");
    sdf.addProtectionDomain(&timer_driver);

    const timer = switch (board) {
        .odroidc4 => blob.child("soc").?.child("bus@ffd00000").?.child("watchdog@f0d0").?,
        .qemu_virt_aarch64 => @panic("TODO"),
    };

    var timer_system = sddf.TimerSystem.init(allocator, sdf, &timer_driver, timer);

    serial_system.addClient(&client0);
    serial_system.addClient(&client1);

    timer_system.addClient(&client0);
    timer_system.addClient(&client1);

    try ethernet_system.connect();
    try timer_system.connect();
    try serial_system.connect();

    const xml = try sdf.toXml();
    std.debug.print("{s}", .{xml});

    const file = try std.fs.cwd().createFile("echo_server.system", .{});
    defer file.close();
    _ = try file.writeAll(xml);
}

fn serial(allocator: Allocator, sdf: *SystemDescription, blob: *dtb.Node) !void {
    const uart_node = switch (board) {
        .odroidc4 => blob.child("soc").?.child("bus@ff800000").?.child("serial@3000").?,
        .qemu_virt_aarch64 => blob.child("pl011@9000000").?,
    };

    var uart_driver = Pd.create(allocator, "uart_driver", "uart_driver.elf");
    sdf.addProtectionDomain(&uart_driver);

    var serial_virt_rx = Pd.create(allocator, "serial_virt_rx", "serial_virt_rx.elf");
    sdf.addProtectionDomain(&serial_virt_rx);
    var serial_virt_tx = Pd.create(allocator, "serial_virt_tx", "serial_virt_tx.elf");
    sdf.addProtectionDomain(&serial_virt_tx);

    var client0 = Pd.create(allocator, "client0", "serial_server.elf");
    sdf.addProtectionDomain(&client0);
    var client1 = Pd.create(allocator, "client1", "serial_server.elf");
    sdf.addProtectionDomain(&client1);

    var serial_system = try sddf.SerialSystem.init(allocator, sdf, uart_node, &uart_driver, &serial_virt_tx, &serial_virt_rx, .{ .rx = true });
    serial_system.addClient(&client0);
    serial_system.addClient(&client1);

    uart_driver.priority = 100;
    serial_virt_tx.priority = 99;
    serial_virt_rx.priority = 98;

    try serial_system.connect();
    try serial_system.serialiseConfig();
    try sdf.print();
}

pub fn main() !void {
    // An arena allocator makes much more sense for our purposes, all we're doing is doing a bunch
    // of allocations in a linear fashion and then just tearing everything down. This has better
    // performance than something like the General Purpose Allocator.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    try parseArgs(args, allocator);

    // Check that path to sDDF exists
    std.fs.cwd().access(sddf_path, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => {
                std.debug.print("Path to sDDF '{s}' does not exist\n", .{sddf_path});
                std.process.exit(1);
            },
            else => {
                std.debug.print("Could not access sDDF directory '{s}' due to error: {}\n", .{ sddf_path, err });
                std.process.exit(1);
            },
        }
    };

    // Check that path to DTB exists
    const board_dtb_path = try std.fmt.allocPrint(allocator, "{s}/{s}.dtb", .{ dtbs_path, @tagName(board) });
    defer allocator.free(board_dtb_path);
    std.fs.cwd().access(board_dtb_path, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => {
                std.debug.print("Path to board DTB '{s}' does not exist\n", .{board_dtb_path});
                std.process.exit(1);
            },
            else => {
                std.debug.print("Could not access DTB directory '{s}' due to error: {}\n", .{ board_dtb_path, err });
                std.process.exit(1);
            },
        }
    };

    // Read the DTB contents
    const dtb_file = try std.fs.cwd().openFile(board_dtb_path, .{});
    const dtb_size = (try dtb_file.stat()).size;
    const blob_bytes = try dtb_file.reader().readAllAlloc(allocator, dtb_size);
    // Parse the DTB
    var blob = try dtb.parse(allocator, blob_bytes);
    // TODO: the allocator should already be known by the DTB...
    defer blob.deinit(allocator);

    try sddf.probe(allocator, sddf_path);

    const compatible_drivers = try sddf.compatibleDrivers(allocator);
    defer allocator.free(compatible_drivers);

    std.debug.print("sDDF drivers found:\n", .{});
    for (compatible_drivers) |driver| {
        std.debug.print("   - {s}\n", .{driver});
    }

    var sdf = SystemDescription.create(allocator, board.arch(), board.paddrTop());
    try example.generate(allocator, &sdf, blob);
}
