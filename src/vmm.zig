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

// TODO: handle freeing of arraylists
pub const VirtualMachineSystem = struct {
    allocator: Allocator,
    sdf: *SystemDescription,
    vmm: *Pd,
    vm: *Vm,
    guest_dtb: *dtb.Node,

    pub fn init(allocator: Allocator, sdf: *SystemDescription, vmm: *Pd, vm: *Vm, guest_dtb: *dtb.Node) VirtualMachineSystem {
        return .{
            .allocator = allocator,
            .sdf = sdf,
            .vmm = vmm,
            .vm = vm,
            .guest_dtb = guest_dtb,
        };
    }

    /// A currently naive approach to adding passthrough for a particular device
    /// to a virtual machine.
    /// This adds the required interrupts to be given to the VMM, and the
    pub fn addPassthrough(system: *VirtualMachineSystem, name: []const u8, device: *dtb.Node) !void {
        // Find the device, get it's memory regions and add it to the guest. Add its IRQs to the VMM.
        const interrupts = device.prop(.Interrupts).?;
        if (device.prop(.Reg)) |device_reg| {
            const device_paddr: u64 = @intCast((device_reg[0][0] >> 12) << 12);
            const device_mr = Mr.create(system.sdf, name, 0x1000, device_paddr, .small);
            system.sdf.addMemoryRegion(device_mr);
            system.vm.addMap(Map.create(device_mr, device_paddr, .rw, false, null));
        }

        // Determine the IRQ trigger and (software-observable) number based on the device tree.
        const irq_type = try sddf.DeviceTree.armGicIrqType(interrupts[0][0]);
        const irq_number = sddf.DeviceTree.armGicIrqNumber(interrupts[0][1], irq_type);
        // Assume trigger is level if we are dealing with an IRQ that is not an SPI.
        // TODO: come back to this, do we need to care about the trigger for non-SPIs?
        const irq_trigger = if (irq_type == .spi) try sddf.DeviceTree.armGicSpiTrigger(interrupts[0][2]) else .level;

        try system.vmm.addInterrupt(.create(irq_number, irq_trigger, null));
    }

    pub fn connect(system: *VirtualMachineSystem) !void {
        var sdf = system.sdf;
        if (sdf.arch != .aarch64) {
            std.debug.print("Unsupported architecture: '{}'", .{ system.sdf.arch });
            return error.UnsupportedArch;
        }
        const vmm = system.vmm;
        const vm = system.vm;
        try vmm.setVirtualMachine(vm);
        // TODO; get this information from the DTB of the guest
        const gic_vcpu = Mr.create(sdf, "gic_vcpu", 0x1000, 0x8040000, .small);
        sdf.addMemoryRegion(gic_vcpu);
        // TODO: I think this mapping stays the same so we only need to create it once
        // TODO: get the vaddr information from DTB
        const gic_vcpu_perms: Map.Permissions = .{ .read = true, .write = true };
        const gic_vcpu_map = Map.create(gic_vcpu, 0x8010000, gic_vcpu_perms, false, null);
        const memory_node = system.guest_dtb.child("memory@40000000").?;
        const memory_reg = memory_node.prop(.Reg).?;
        const memory_paddr: usize = @intCast(memory_reg[0][0]);
        std.debug.print("memory_paddr: {}\n", .{ memory_paddr });
        // TODO: should free the name at some point....
        const guest_mr_name = std.fmt.allocPrint(system.allocator, "guest_ram_{s}", .{ vm.name }) catch @panic("OOM");
        // TODO: get RAM size from the memory node from DTB
        const guest_ram_size = 1024 * 1024 * 256;
        const guest_ram_mr = Mr.create(sdf, guest_mr_name, guest_ram_size, null, Mr.PageSize.optimal(sdf, guest_ram_size));
        sdf.addMemoryRegion(guest_ram_mr);
        // TODO: vaddr should come from the memory node from DTB
        const vm_guest_ram_perms: Map.Permissions = .{ .read = true, .write = true, .execute = true };
        const vmm_guest_ram_perms: Map.Permissions = .{ .read = true, .write = true };
        const vm_guest_ram_map = Map.create(guest_ram_mr, memory_paddr, vm_guest_ram_perms, true, null);
        const vmm_guest_ram_map = Map.create(guest_ram_mr, memory_paddr, vmm_guest_ram_perms, true, "guest_ram_vaddr");
        vmm.addMap(vmm_guest_ram_map);
        vm.addMap(vm_guest_ram_map);
        vm.addMap(gic_vcpu_map);
    }
};

// Given a device tree node, will add the corresponding interrupts to the
// VMM PD and map the memory associated with the device to the virtual machine.
// pub fn addPassthrough(vmm: *Pd, vm: *VirtualMachine, device: *dtb.Node) !void {
// }
