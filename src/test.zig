const std = @import("std");

const SystemDescription = @import("sdf.zig").SystemDescription;
const ProtectionDomain = SystemDescription.ProtectionDomain;
const MemoryRegion = SystemDescription.MemoryRegion;
const Map = SystemDescription.Map;
const Interrupt = SystemDescription.Interrupt;
const Channel = SystemDescription.Channel;

const allocator = std.testing.allocator;
const test_dir = "tests/";

fn readAll(test_path: []const u8) ![]const u8 {
    const test_file = try std.fs.cwd().openFile(test_path, .{});
    const test_file_size = (try test_file.stat()).size;
    return try test_file.reader().readAllAlloc(
        allocator,
        test_file_size,
    );
}

// testing TODOs
// * channels
// * MRs/mappings
// * virtual machine (framebuffer example?)
// * sDDF example

test "basic" {
    var sdf = try SystemDescription.create(allocator, .aarch64);

    var pd = ProtectionDomain.create(&sdf, "hello", "hello.elf");

    sdf.addProtectionDomain(&pd);

    const expected = try readAll("src/tests/basic.xml");
    const output = try sdf.toXml();
    defer allocator.free(expected);
    defer sdf.destroy();

    try std.testing.expectEqualStrings(expected, output);
}

test "PD + MR + mappings + channel" {
    var sdf = try SystemDescription.create(allocator, .aarch64);
    const mr = MemoryRegion.create(&sdf, "test", 0x1000, null, .small);
    sdf.addMemoryRegion(mr);

    const image = "hello.elf";
    var pd1 = ProtectionDomain.create(&sdf, "hello-1", image);
    try pd1.addInterrupt(Interrupt.create(33, .level, null));
    pd1.addMap(Map.create(mr, 0x400000000, .r, true, null));
    pd1.addMap(Map.create(mr, 0x600000000, .x, true, null));
    pd1.addMap(Map.create(mr, 0x800000000, .rwx, true, null));

    var pd2 = ProtectionDomain.create(&sdf, "hello-2", image);

    sdf.addProtectionDomain(&pd1);
    sdf.addProtectionDomain(&pd2);

    sdf.addChannel(Channel.create(&pd1, &pd2));

    const expected = try readAll("src/tests/pd_mr_map_channel.xml");
    const output = try sdf.toXml();
    defer allocator.free(expected);
    defer sdf.destroy();

    try std.testing.expectEqualStrings(expected, output);
}
