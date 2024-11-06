const std = @import("std");

// command: zig build-exe api.zig -target wasm32-freestanding -fno-entry --export=concatWithHelloWorld

export fn concatWithHelloWorld(input_ptr: [*]const u8, input_len: usize, result_ptr: [*]u8) usize {
    const input = input_ptr[0..input_len];

    const allocator = std.heap.wasm_allocator;
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, input, .{}) catch {
        return 0;
    };
    defer parsed.deinit();

    const object = parsed.value.object;
    const output = object.get("maps").?.string;

    // const suffix = " | hello world!";
    const totalLen = input.len + output.len;
    std.mem.copyForwards(u8, result_ptr[0..input.len], input);
    std.mem.copyForwards(u8, result_ptr[input.len..totalLen], output);

    return totalLen;
}
