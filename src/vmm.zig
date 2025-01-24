const std = @import("std");
const builtin = @import("builtin");
const mod_sdf = @import("sdf.zig");
const mod_dtb = @import("dtb");
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

const DeviceTree = sddf.DeviceTree;
const ArmGic = DeviceTree.ArmGic;

// TODO: repeated with sddf.zig
/// Only emit JSON versions of the serialised configuration data
/// in debug mode.
const serialise_emit_json = builtin.mode == .Debug;

const Self = @This();

allocator: Allocator,
sdf: *SystemDescription,
vmm: *Pd,
vm: *Vm,
dtb: *mod_dtb.Node,
data: Data,
/// Whether or not to map guest RAM with 1-1 mappings with physical memory
one_to_one_ram: bool,

const Options = struct {
    one_to_one_ram: bool = false,
};

const MAX_IRQS: usize = 32;
const MAX_VCPUS: usize = 32;

const Data = extern struct {
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
};

pub fn init(allocator: Allocator, sdf: *SystemDescription, vmm: *Pd, vm: *Vm, dtb: *mod_dtb.Node, options: Options) Self {
    return .{
        .allocator = allocator,
        .sdf = sdf,
        .vmm = vmm,
        .vm = vm,
        .dtb = dtb,
        .data = std.mem.zeroInit(Data, .{}),
        .one_to_one_ram = options.one_to_one_ram,
    };
}

fn fmt(allocator: Allocator, comptime s: []const u8, args: anytype) []u8 {
    return std.fmt.allocPrint(allocator, s, args) catch @panic("OOM");
}

/// A currently naive approach to adding passthrough for a particular device
/// to a virtual machine.
/// This adds the required interrupts to be given to the VMM, and the TODO finish description
pub fn addPassthroughDevice(system: *Self, name: []const u8, device: *mod_dtb.Node, irqs: bool) !void {
    const allocator = system.allocator;
    // Find the device, get it's memory regions and add it to the guest. Add its IRQs to the VMM.
    if (device.prop(.Reg)) |device_reg| {
        for (device_reg, 0..) |d, i| {
            const device_paddr = DeviceTree.regToPaddr(device, d[0]);
            const device_size = DeviceTree.regToSize(d[1]);
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
            system.vm.addMap(.create(device_mr, device_paddr, .rw, .{ .cached = false }));
        }
    }

    if (irqs) {
        const maybe_interrupts = device.prop(.Interrupts);
        if (maybe_interrupts) |interrupts| {
            for (interrupts) |interrupt| {
                // Determine the IRQ trigger and (software-observable) number based on the device tree.
                const irq_type = sddf.DeviceTree.armGicIrqType(interrupt[0]);
                const irq_number = sddf.DeviceTree.armGicIrqNumber(interrupt[1], irq_type);
                const irq_trigger = DeviceTree.armGicTrigger(interrupt[2]);
                const irq_id = try system.vmm.addIrq(.create(irq_number, .{
                    .trigger = irq_trigger
                }));
                system.data.irqs[system.data.num_irqs] = .{
                    .id = irq_id,
                    .irq = irq_number,
                };
                system.data.num_irqs += 1;
            }
        }
    }
}

pub fn addPassthroughRegion(system: *Self, name: []const u8, device: *mod_dtb.Node, reg_index: u64) !void {
    const device_reg = device.prop(.Reg).?;
    const device_paddr = DeviceTree.regToPaddr(device, device_reg[reg_index][0]);
    const device_size = DeviceTree.regToSize(device_reg[reg_index][1]);
    const device_mr = Mr.create(system.allocator, name, device_size, device_paddr, .small);
    system.sdf.addMemoryRegion(device_mr);
    system.vm.addMap(Map.create(device_mr, device_paddr, .rw, false, null));
}

pub fn addPassthroughIrq(system: *Self, irq: Irq) !void {
    const irq_id = try system.vmm.addIrq(irq);
    system.data.irqs[system.data.num_irqs] = .{
        .id = irq_id,
        .irq = irq.irq,
    };
    system.data.num_irqs +=  1;
}

// TODO: deal with the general problem of having multiple gic vcpu mappings but only one MR.
// Two options, find the GIC vcpu mr and if it it doesn't exist, create it, if it does, use it.
// other option is to have each a 'VirtualMachineSystem' that is responsible for every single VM.
pub fn connect(system: *Self) !void {
    const allocator = system.allocator;
    var sdf = system.sdf;
    if (sdf.arch != .aarch64) {
        std.debug.print("Unsupported architecture: '{}'", .{system.sdf.arch});
        return error.UnsupportedArch;
    }
    const vmm = system.vmm;
    const vm = system.vm;
    try vmm.setVirtualMachine(vm);

    // On ARM, map in the GIC vCPU device as the GIC CPU device in the guest's memory.
    if (sdf.arch.isArm()) {
        const gic = ArmGic.fromDtb(system.dtb);

        if (gic.hasMmioCpuInterface()) {
            const gic_vcpu_mr = Mr.physical(allocator, sdf, "gic_vcpu", gic.vcpu_size.?, .{ .paddr = gic.vcpu_paddr.? });
            const gic_guest_map = Map.create(gic_vcpu_mr, gic.cpu_paddr.?, .rw, .{ .cached = false });
            sdf.addMemoryRegion(gic_vcpu_mr);
            vm.addMap(gic_guest_map);
        }
    }

    const memory_node = DeviceTree.memory(system.dtb).?;
    const memory_reg = memory_node.prop(.Reg).?;
    // TODO
    std.debug.assert(memory_reg.len == 1);
    const memory_paddr: u64 = @intCast(memory_reg[0][0]);
    const guest_mr_name = std.fmt.allocPrint(allocator, "guest_ram_{s}", .{vm.name}) catch @panic("OOM");
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
    vm.addMap(.create(guest_ram_mr, memory_paddr, .rwx, .{}));

    // var chosen: ?*mod_dtb.Node = null;
    // for (system.dtb.children) |child| {
    //     if (std.mem.eql(u8, child.name, "chosen")) {
    //         chosen = child;
    //     }
    // }
    // if (chosen == null) {
    //     @panic("TODO");
    // }

    system.data.ram = memory_paddr;
    system.data.ram_size = guest_ram_size;
    // TODO: fix this
    system.data.dtb = 0x4f000000;
    system.data.initrd = 0x4d000000;

    for (system.vm.vcpus) |vcpu| {
        system.data.vcpus[system.data.num_vcpus] = .{
            .id = vcpu.id,
        };
        system.data.num_vcpus += 1;
    }

    // for (chosen.?.props) |prop| {
    //     if (p == .Unknown) {
    //         const initrd_start_prop = @field(p, .Unknown);
    //     }
    // }

    // const initrd_start = system.dtb.propAt(&.{ "chosen" }, .Unknown{ .name = "linux,initrd-start" });
    // std.log.info("initrd_start: 0x{x}", .{ initrd_start });
}

pub fn serialiseConfig(system: *Self, prefix: []const u8) !void {
    // TODO: check connected
    const allocator = system.allocator;
    const data_name = fmt(allocator, "vmm_{s}.data", .{ system.vmm.name });

    try mod_data.serialize(system.data, try fs.path.join(allocator, &.{ prefix, data_name }));
    if (serialise_emit_json) {
        const json_name = fmt(allocator, "vmm_{s}.data", .{ system.vmm.name });
        try mod_data.jsonify(system.data, try fs.path.join(allocator, &.{ prefix, json_name }));
    }
}
