const std = @import("std");

const SystemDescription = @import("sdf_gen.zig").SystemDescription;
const ProtectionDomain = SystemDescription.ProtectionDomain;
const ProgramImage = ProtectionDomain.ProgramImage;
const MemoryRegion = SystemDescription.MemoryRegion;
const Map = SystemDescription.Map;
const Interrupt = SystemDescription.Interrupt;
const Channel = SystemDescription.Channel;

const allocator = std.testing.allocator;
const test_dir = "tests/";

fn readAll(test_path: []const u8) ![]const u8 {
    const test_file = try std.fs.cwd().openFile(test_path, .{});
    // TODO: the max buf size should just be the file size...
    return try test_file.reader().readAllAlloc(
        allocator,
        2048,
    );
}

// testing TODOs
// * channels
// * MRs/mappings
// * virtual machine (framebuffer example?)
// * sDDF example

test "basic" {
    var system = try SystemDescription.create(allocator, .aarch64);

    const image = ProgramImage.create("hello.elf");
    var pd = ProtectionDomain.create(allocator, "hello", image, null, null, null, null);

    try system.addProtectionDomain(&pd);

    const expected = try readAll("src/tests/basic.xml");
    const output = try system.toXml(allocator);
    defer allocator.free(expected);
    defer system.destroy();

    try std.testing.expectEqualStrings(expected, output);
}

test "PD + MR + mappings + channel" {
    var system = try SystemDescription.create(allocator, .aarch64);
    const mr = MemoryRegion.create("test", 0x1000, null, null);
    try system.addMemoryRegion(mr);

    const image = ProgramImage.create("hello.elf");
    var pd1 = ProtectionDomain.create(allocator, "hello-1", image, null, null, null, null);
    try pd1.addInterrupt(Interrupt.create("serial", 33, .level));
    try pd1.addMap(Map.create(&mr, 0x200000000, .{}, true));
    try pd1.addMap(Map.create(&mr, 0x400000000, .{ .read = true }, true));
    try pd1.addMap(Map.create(&mr, 0x600000000, .{ .execute = true }, true));
    try pd1.addMap(Map.create(&mr, 0x800000000, .{ .read = true, .execute = true }, true));

    var pd2 = ProtectionDomain.create(allocator, "hello-2", image, null, null, null, null);

    try system.addProtectionDomain(&pd1);
    try system.addProtectionDomain(&pd2);

    try system.addChannel(Channel.create(&pd1, &pd2));

    const expected = try readAll("src/tests/pd_mr_map_channel.xml");
    const output = try system.toXml(allocator);
    defer allocator.free(expected);
    defer system.destroy();

    try std.testing.expectEqualStrings(expected, output);
    // std.debug.assert(std.mem.eql(u8, expected, output));
}
