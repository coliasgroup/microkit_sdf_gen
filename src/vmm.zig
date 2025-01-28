const std = @import("std");
const builtin = @import("builtin");
const mod_sdf = @import("sdf.zig");
const dtb = @import("dtb.zig");
const mod_data = @import("data.zig");
const sddf = @import("sddf.zig");
const Allocator = std.mem.Allocator;

const fs = std.fs;

const SystemDescription = mod_sdf.SystemDescription;
const Mr = SystemDescription.MemoryRegion;
const Pd = SystemDescription.ProtectionDomain;
const Irq = SystemDescription.Irq;
const Map = SystemDescription.Map;
const Vm = SystemDescription.VirtualMachine;

const Self = @This();

allocator: Allocator,
sdf: *SystemDescription,
vmm: *Pd,
guest: *Vm,
guest_dtb: *dtb.Node,
data: Data,
/// Whether or not to map guest RAM with 1-1 mappings with physical memory
one_to_one_ram: bool,
connected: bool = false,

const Options = struct {
    one_to_one_ram: bool = false,
};

const MAX_IRQS: usize = 32;
const MAX_VCPUS: usize = 32;
const MAX_VIRTIO_MMIO_DEVICES: usize = 32;

const Data = extern struct {
    const VirtioMmioDevice = extern struct {
        pub const Type = enum(u8) {
            net = 1,
            blk = 2,
            console = 3,
            sound = 25,
        };

        type: Type,
        addr: u64,
        size: u64,
        irq: u32,
    };

    const Irq = extern struct {
        id: u8,
        irq: u32,
    };

    const Vcpu = extern struct {
        id: u8,
    };

    ram: u64,
    ram_size: u64,
    dtb: u64,
    initrd: u64,
    num_irqs: u8,
    irqs: [MAX_IRQS]Data.Irq,
    num_vcpus: u8,
    vcpus: [MAX_VCPUS]Vcpu,
    num_virtio_mmio_devices: u8,
    virtio_mmio_devices: [MAX_VIRTIO_MMIO_DEVICES]VirtioMmioDevice,
};

pub fn init(allocator: Allocator, sdf: *SystemDescription, vmm: *Pd, guest: *Vm, guest_dtb: *dtb.Node, options: Options) Self {
    return .{
        .allocator = allocator,
        .sdf = sdf,
        .vmm = vmm,
        .guest = guest,
        .guest_dtb = guest_dtb,
        .data = std.mem.zeroInit(Data, .{}),
        .one_to_one_ram = options.one_to_one_ram,
    };
}

fn fmt(allocator: Allocator, comptime s: []const u8, args: anytype) []u8 {
    return std.fmt.allocPrint(allocator, s, args) catch @panic("OOM");
}

const PassthroughOptions = struct {
    /// Indices into the Device Tree node's regions to passthrough
    regions: []const u8 = &.{},
    /// Indices into the Device Tree node's interrupts to passthrough
    irqs: []const u8 = &.{},
};

/// A currently naive approach to adding passthrough for a particular device
/// to a virtual machine.
/// This adds the required interrupts to be given to the VMM, and the TODO finish description
pub fn addPassthroughDevice(system: *Self, name: []const u8, device: *dtb.Node, options: PassthroughOptions) !void {
    const allocator = system.allocator;
    // Find the device, get it's memory regions and add it to the guest. Add its IRQs to the VMM.
    if (device.prop(.Reg)) |device_reg| {
        for (options.regions, 0..) |d, i| {
            const device_paddr = dtb.regToPaddr(device, device_reg[d][0]);
            const device_size = dtb.regToSize(device_reg[d][1]);
            var mr_name: []const u8 = undefined;
            if (device_reg.len > 1) {
                mr_name = std.fmt.allocPrint(allocator, "{s}{}", .{ name, i }) catch @panic("OOM");
                defer allocator.free(mr_name);
            } else {
                mr_name = name;
            }
            const device_mr = Mr.physical(allocator, system.sdf, mr_name, device_size, .{
                .paddr = device_paddr,
            });
            system.sdf.addMemoryRegion(device_mr);
            system.guest.addMap(.create(device_mr, device_paddr, .rw, .{ .cached = false }));
        }
    }

    const maybe_interrupts = device.prop(.Interrupts);
    if (maybe_interrupts == null and options.irqs.len != 0) {
        // TODO: improve error
        return error.InvalidIrqs;
    }

    for (options.irqs) |dt_irq| {
        const interrupts = maybe_interrupts.?;
        if (dt_irq >= interrupts.len) {
            // TODO: improve error
            return error.InvalidIrqs;
        }
        const interrupt = interrupts[dt_irq];
        var irq_id: u8 = undefined;
        var irq_number: u32 = undefined;
        if (system.sdf.arch.isArm()) {
            // Determine the IRQ trigger and (software-observable) number based on the device tree.
            const irq_type = dtb.armGicIrqType(interrupt[0]);
            const irq_trigger = dtb.armGicTrigger(interrupt[2]);
            irq_number = dtb.armGicIrqNumber(interrupt[1], irq_type);
            irq_id = try system.vmm.addIrq(.create(irq_number, .{ .trigger = irq_trigger }));
        } else if (system.sdf.arch.isRiscv()) {
            irq_number = interrupt[0];
            irq_id = try system.vmm.addIrq(.create(irq_number, .{}));
        }
        system.data.irqs[system.data.num_irqs] = .{
            .id = irq_id,
            .irq = irq_number,
        };
        system.data.num_irqs += 1;
    }
}

fn addVirtioMmioDevice(system: *Self, device: *dtb.Node, t: Data.VirtioMmioDevice.Type) !void {
    // TODO: check that .Reg exists
    // TODO: check device_reg[0] exists and that device_reg.len == 1
    const device_reg = device.prop(.Reg).?;
    if (device_reg.len != 1) {
        // TODO: improve error
        return error.InvalidVirtioDevice;
    }
    if (system.sdf.arch != .aarch64) {
        @panic("TODO");
    }
    const device_paddr = dtb.regToPaddr(device, device_reg[0][0]);
    const device_size = dtb.regToSize(device_reg[0][1]);
    // TODO: check interrupts exist and that there is one interrupt only
    const interrupts = device.prop(.Interrupts).?;
    const irq = dtb.armGicIrqNumber(interrupts[0][1], dtb.armGicIrqType(interrupts[0][0]));
    // TODO: maybe use device resources like everything else? idk
    system.data.virtio_mmio_devices[system.data.num_virtio_mmio_devices] = .{
        .type = t,
        .addr = device_paddr,
        .size = device_size,
        .irq = irq,
    };
    system.data.num_virtio_mmio_devices += 1;
}

pub fn addVirtioMmioConsole(system: *Self, device: *dtb.Node, serial: *sddf.Serial) !void {
    try serial.addClient(system.vmm);
    try system.addVirtioMmioDevice(device, .console);
}

pub fn addVirtioMmioBlk(system: *Self, device: *dtb.Node, blk: *sddf.Blk, options: sddf.Blk.ClientOptions) !void {
    try blk.addClient(system.vmm, options);
    try system.addVirtioMmioDevice(device, .blk);
}

// pub fn addVirtioNet(system: *Self, device: *dtb.Node, net: *sddf.Net, options: sddf.Net.Options) !void {
//     try net.addClient(system.vmm, options);
//     try system.addVirtioDevice(device);
// }

pub fn addPassthroughIrq(system: *Self, irq: Irq) !void {
    const irq_id = try system.vmm.addIrq(irq);
    system.data.irqs[system.data.num_irqs] = .{
        .id = irq_id,
        .irq = irq.irq,
    };
    system.data.num_irqs += 1;
}

// TODO: deal with the general problem of having multiple gic vcpu mappings but only one MR.
// Two options, find the GIC vcpu mr and if it it doesn't exist, create it, if it does, use it.
// other option is to have each a 'VirtualMachineSystem' that is responsible for every single VM.
pub fn connect(system: *Self) !void {
    const allocator = system.allocator;
    var sdf = system.sdf;
    const vmm = system.vmm;
    const guest = system.guest;
    try vmm.setVirtualMachine(guest);

    if (sdf.arch.isArm()) {
        // On ARM, map in the GIC vCPU device as the GIC CPU device in the guest's memory.
        const gic = dtb.ArmGic.fromDtb(system.guest_dtb);
        if (gic.hasMmioCpuInterface()) {
            const gic_vcpu_mr = Mr.physical(allocator, sdf, "gic_vcpu", gic.vcpu_size.?, .{ .paddr = gic.vcpu_paddr.? });
            const gic_guest_map = Map.create(gic_vcpu_mr, gic.cpu_paddr.?, .rw, .{ .cached = false });
            sdf.addMemoryRegion(gic_vcpu_mr);
            guest.addMap(gic_guest_map);
        }
    }

    const memory_node = dtb.memory(system.guest_dtb).?;
    const memory_reg = memory_node.prop(.Reg).?;
    // TODO
    std.debug.assert(memory_reg.len == 1);
    const memory_paddr: u64 = @intCast(memory_reg[0][0]);
    const guest_mr_name = std.fmt.allocPrint(allocator, "guest_ram_{s}", .{guest.name}) catch @panic("OOM");
    defer allocator.free(guest_mr_name);
    const guest_ram_size: u64 = @intCast(memory_reg[0][1]);

    const guest_ram_mr = blk: {
        if (system.one_to_one_ram) {
            break :blk Mr.physical(allocator, sdf, guest_mr_name, guest_ram_size, .{ .paddr = memory_paddr });
        } else {
            break :blk Mr.create(allocator, guest_mr_name, guest_ram_size, .{});
        }
    };
    sdf.addMemoryRegion(guest_ram_mr);
    vmm.addMap(.create(guest_ram_mr, memory_paddr, .rw, .{}));
    guest.addMap(.create(guest_ram_mr, memory_paddr, .rwx, .{}));

    system.data.ram = memory_paddr;
    system.data.ram_size = guest_ram_size;
    // TODO: fix this
    system.data.dtb = 0x4f000000;

    for (system.guest.vcpus) |vcpu| {
        system.data.vcpus[system.data.num_vcpus] = .{
            .id = vcpu.id,
        };
        system.data.num_vcpus += 1;
    }

    if (system.guest_dtb.propAt(&.{"chosen"}, .LinuxInitrdStart)) |initrd_start| {
        system.data.initrd = initrd_start;
    } else {
        return error.MissingInitrd;
    }

    system.connected = true;
}

pub fn serialiseConfig(system: *Self, prefix: []const u8) !void {
    if (!system.connected) return error.NotConnected;

    const allocator = system.allocator;
    const data_name = fmt(allocator, "vmm_{s}.data", .{system.vmm.name});

    try mod_data.serialize(system.data, try fs.path.join(allocator, &.{ prefix, data_name }));
    if (mod_data.emit_json) {
        const json_name = fmt(allocator, "vmm_{s}.data", .{system.vmm.name});
        try mod_data.jsonify(system.data, try fs.path.join(allocator, &.{ prefix, json_name }));
    }
}
