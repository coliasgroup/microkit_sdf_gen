const std = @import("std");
const mod_sdf = @import("sdf.zig");
const dtb = @import("dtb");
const sddf = @import("sddf.zig");
const Allocator = std.mem.Allocator;

const SystemDescription = mod_sdf.SystemDescription;
const Mr = SystemDescription.MemoryRegion;
const Pd = SystemDescription.ProtectionDomain;
const Map = SystemDescription.Map;
const Vm = SystemDescription.VirtualMachine;

const DeviceTree = sddf.DeviceTree;
const ArmGic = DeviceTree.ArmGic;

pub const VirtualMachineSystem = struct {
    allocator: Allocator,
    sdf: *SystemDescription,
    vmm: *Pd,
    vm: *Vm,
    guest_dtb: *dtb.Node,
    /// Whether or not to map guest RAM with 1-1 mappings with physical memory
    one_to_one_ram: bool,

    const Options = struct {
        one_to_one_ram: bool = false,
    };

    pub fn init(allocator: Allocator, sdf: *SystemDescription, vmm: *Pd, vm: *Vm, guest_dtb: *dtb.Node, options: Options) VirtualMachineSystem {
        return .{
            .allocator = allocator,
            .sdf = sdf,
            .vmm = vmm,
            .vm = vm,
            .guest_dtb = guest_dtb,
            .one_to_one_ram = options.one_to_one_ram,
        };
    }

    /// A currently naive approach to adding passthrough for a particular device
    /// to a virtual machine.
    /// This adds the required interrupts to be given to the VMM, and the TODO finish description
    pub fn addPassthrough(system: *VirtualMachineSystem, name: []const u8, device: *dtb.Node, irqs: bool) !void {
        // Find the device, get it's memory regions and add it to the guest. Add its IRQs to the VMM.
        if (device.prop(.Reg)) |device_reg| {
            for (device_reg, 0..) |d, i| {
                // TODO: use function for this
                const device_paddr = DeviceTree.regToPaddr(device, d[0]);
                const device_size = DeviceTree.regToSize(d[1]);
                var mr_name: []const u8 = undefined;
                if (device_reg.len > 1) {
                    // TODO: deallocate?
                    mr_name = std.fmt.allocPrint(system.allocator, "{s}{}", .{ name, i }) catch @panic("OOM");
                } else {
                    mr_name = name;
                }
                const device_mr = Mr.create(system.sdf, mr_name, device_size, device_paddr, .small);
                system.sdf.addMemoryRegion(device_mr);
                system.vm.addMap(Map.create(device_mr, device_paddr, .rw, false, null));
            }
        }

        if (irqs) {
            const maybe_interrupts = device.prop(.Interrupts);
            if (maybe_interrupts) |interrupts| {
                for (interrupts) |interrupt| {
                    // Determine the IRQ trigger and (software-observable) number based on the device tree.
                    const irq_type = try sddf.DeviceTree.armGicIrqType(interrupt[0]);
                    const irq_number = sddf.DeviceTree.armGicIrqNumber(interrupt[1], irq_type);
                    // Assume trigger is level if we are dealing with an IRQ that is not an SPI.
                    // TODO: come back to this, do we need to care about the trigger for non-SPIs?
                    const irq_trigger = if (irq_type == .spi) try sddf.DeviceTree.armGicSpiTrigger(interrupt[2]) else .level;
                    try system.vmm.addInterrupt(.create(irq_number, irq_trigger, null));
                }
            }
        }
    }

    pub fn addPassthroughRegion(system: *VirtualMachineSystem, name: []const u8, device: *dtb.Node, reg_index: u64) !void {
        const device_reg = device.prop(.Reg).?;
        const device_paddr = DeviceTree.regToPaddr(device, device_reg[reg_index][0]);
        const device_size = DeviceTree.regToSize(device_reg[reg_index][1]);
        const device_mr = Mr.create(system.sdf, name, device_size, device_paddr, .small);
        system.sdf.addMemoryRegion(device_mr);
        system.vm.addMap(Map.create(device_mr, device_paddr, .rw, false, null));
    }

    // TODO: deal with the general problem of having multiple gic vcpu mappings but only one MR.
    // Two options, find the GIC vcpu mr and if it it doesn't exist, create it, if it does, use it.
    // other option is to have each a 'VirtualMachineSystem' that is responsible for every single VM.
    pub fn connect(system: *VirtualMachineSystem) !void {
        var sdf = system.sdf;
        if (sdf.arch != .aarch64) {
            std.debug.print("Unsupported architecture: '{}'", .{ system.sdf.arch });
            return error.UnsupportedArch;
        }
        const vmm = system.vmm;
        const vm = system.vm;
        try vmm.setVirtualMachine(vm);

        // On ARM, map in the GIC vCPU device as the GIC CPU device in the guest's memory.
        if (sdf.arch == .aarch64) {
            const gic = ArmGic.fromDtb(system.guest_dtb);
            // TODO: fix size
            const gic_vcpu_mr = Mr.create(sdf, "gic_vcpu", 0x1000, gic.vcpu_paddr, .small);
            const gic_guest_map = Map.create(gic_vcpu_mr, gic.cpu_paddr, .rw, false, null);
            sdf.addMemoryRegion(gic_vcpu_mr);
            vm.addMap(gic_guest_map);
        }

        const memory_node = DeviceTree.memory(system.guest_dtb).?;
        const memory_reg = memory_node.prop(.Reg).?;
        // TODO
        std.debug.assert(memory_reg.len == 1);
        const memory_paddr: usize = @intCast(memory_reg[0][0]);
        // TODO: should free the name at some point....
        const guest_mr_name = std.fmt.allocPrint(system.allocator, "guest_ram_{s}", .{ vm.name }) catch @panic("OOM");
        // TODO: get RAM size from the memory node from DTB
        const guest_ram_size: usize = @intCast(memory_reg[0][1]);
        const guest_ram_phys_addr: ?usize = if (system.one_to_one_ram) memory_paddr else null;
        const guest_ram_mr = Mr.create(sdf, guest_mr_name, guest_ram_size, guest_ram_phys_addr, Mr.PageSize.optimal(sdf, guest_ram_size));
        sdf.addMemoryRegion(guest_ram_mr);
        // TODO: vaddr should come from the memory node from DTB
        const vm_guest_ram_perms: Map.Permissions = .{ .read = true, .write = true, .execute = true };
        const vmm_guest_ram_perms: Map.Permissions = .{ .read = true, .write = true };
        const vm_guest_ram_map = Map.create(guest_ram_mr, memory_paddr, vm_guest_ram_perms, true, null);
        const vmm_guest_ram_map = Map.create(guest_ram_mr, memory_paddr, vmm_guest_ram_perms, true, null);
        vmm.addMap(vmm_guest_ram_map);
        vm.addMap(vm_guest_ram_map);
    }
};
