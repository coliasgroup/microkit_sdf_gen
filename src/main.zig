const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const SystemDescription = @import("sdf_gen.zig").SystemDescription;
const ProtectionDomain = SystemDescription.ProtectionDomain;
const ProgramImage = ProtectionDomain.ProgramImage;
const MemoryRegion = SystemDescription.MemoryRegion;
const Map = SystemDescription.Map;
const Interrupt = SystemDescription.Interrupt;
const Channel = SystemDescription.Channel;

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    var system = try SystemDescription.create(gpa, .aarch64);
    const mr = MemoryRegion.create("test", 0x1000, null, null);
    try system.addMemoryRegion(mr);

    const image = ProgramImage.create("hello.elf");
    var pd1 = ProtectionDomain.create(gpa, "hello-1", image, null, null, null, null);
    try pd1.addInterrupt(Interrupt.create("serial", 33, .level));
    try pd1.addMap(Map.create(&mr, 0x200000000, .{}, true));
    try pd1.addMap(Map.create(&mr, 0x400000000, .{ .read = true }, true));
    try pd1.addMap(Map.create(&mr, 0x600000000, .{ .execute = true }, true));
    try pd1.addMap(Map.create(&mr, 0x800000000, .{ .read = true, .execute = true }, true));

    var pd2 = ProtectionDomain.create(gpa, "hello-2", image, null, null, null, null);

    try system.addProtectionDomain(&pd1);
    try system.addProtectionDomain(&pd2);

    try system.addChannel(Channel.create(&pd1, &pd2));

    std.debug.print("{s}", .{ try system.toXml(gpa) });
    // std.debug.print("HEADER: \n{s}", .{ try system.exportCHeader(gpa, &pd1) });
}
