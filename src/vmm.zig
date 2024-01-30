const std = @import("std");
const mod_sdf = @import("sdf.zig");
const dtb = @import("dtb");
const Allocator = std.mem.Allocator;

const SystemDescription = mod_sdf.SystemDescription;

/// Given a device tree node, will add the corresponding interrupts to the
/// VMM PD and map the memory associated with the device to the virtual machine.
pub fn addPassthrough(vmm: *Pd, vm: *VirtualMachine, device: *dtb.Node) !void {
}
