const allocator = std.testing.allocator;
const Elf = @import("main.zig").Elf;

fn readAll(test_path: []const u8) ![]const u8 {
    const test_file = try std.fs.cwd().openFile(test_path, .{});
    const test_file_size = (try test_file.stat()).size;
    return try test_file.reader().readAllAlloc(
        allocator,
        test_file_size,
    );
}

test "simple variable patch" {
    const test_elf = try Elf.
}

