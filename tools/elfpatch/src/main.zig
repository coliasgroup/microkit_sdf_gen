const std = @import("std");
const Allocator = std.mem.Allocator;

const Elf = struct {
    const Segment = struct {
        vaddr: u64,
    };

    allocator: Allocator,
    segments: std.ArrayList(Segment),
    bytes: []const u8,

    const MAGIC: []const u8 = "\x7fELF";

    /// Simple wrapper over init for when the ELF is on the file system.
    pub fn from_path(allocator: Allocator, path: []const u8) !Elf {
        const file = try std.fs.cwd().openFile(path, .{});
        const file_size = (try file.stat()).size;
        const bytes = try file.reader().readAllAlloc(
            allocator,
            file_size,
        );

        return init(allocator, bytes);
    }

    pub fn init(allocator: Allocator, bytes: []const u8) !Elf {
        const magic = bytes[0..4];

        if (!std.mem.eql(u8, magic, MAGIC)) {
            return error.InvalidMagic;
        }

        const class = bytes[4..5][0];
        switch (class) {
            2 => {},
            else => {
                return error.UnsupportedClass;
            }
        }

        // TODO: dodgy alignCast
        const hdr = try std.elf.Header.parse(@alignCast(bytes[0..@sizeOf(std.elf.Elf64_Ehdr)]));

        std.debug.assert(hdr.is_64);

        var segments = try std.ArrayList(Segment).initCapacity(allocator, hdr.phnum);
        for (0..hdr.phnum) |i| {
            const phent_start = hdr.phoff + (i * hdr.phentsize);
            const phent_end = phent_start + (hdr.phentsize);
            const phent_bytes = &bytes[phent_start..phent_end];

            const phent = std.mem.bytesAsValue(std.elf.Elf64_Phdr, phent_bytes);

            if (phent.p_type != 1) {
                continue;
            }

            segments.appendAssumeCapacity(.{
                .vaddr = phent.p_vaddr,
            });

            // const phent = unsafe { bytes_to_struct::<ElfProgramHeader64>(phent_bytes) };

            // const segment_start = phent.offset;
            // const segment_end = phent.offset + phent.filesz;

            // if phent.type_ != 1 {
            //     continue;
            // }

            // const mut segment_data = vec![0; phent.memsz as usize];
            // segment_data[..phent.filesz as usize]
            //     .copy_from_slice(&bytes[segment_start..segment_end]);

            // let segment = ElfSegment {
            //     data: segment_data,
            //     phys_addr: phent.paddr,
            //     virt_addr: phent.vaddr,
            //     loadable: phent.type_ == 1,
            //     attrs: phent.flags,
            // };

            // try segments.(segment)
        }

        // TODO: do we need toOwnedSlice?
        return .{
            .allocator = allocator,
            .segments = segments,
            .bytes = bytes,
        };
    }

    pub fn deinit(elf: Elf) void {
        elf.allocator.free(elf.bytes);
        elf.segments.deinit();
    }
};

fn fmt(allocator: Allocator, comptime s: []const u8, args: anytype) []u8 {
    return std.fmt.allocPrint(allocator, s, args) catch @panic("OOM");
}

const usage_text =
    \\Usage elfpatch --symbol [SYMBOL] --in [ELF] --out [ELF] --value [INTEGER]
    \\
    \\Patches a global ELF symbol with a given value
    \\
    \\ TODO
;

const Args = struct {
    symbol: []const u8,
    elf: []const u8,

    fn parse(allocator: Allocator, args: []const []const u8) !Args {
        const stdout = std.io.getStdOut();
        const stderr = std.io.getStdErr();

        const usage_text_fmt = try std.fmt.allocPrint(allocator, usage_text, .{});
        defer allocator.free(usage_text_fmt);

        var symbol: ?[]const u8 = null;
        var elf: ?[]const u8 = null;

        var arg_i: usize = 1;
        while (arg_i < args.len) : (arg_i += 1) {
            const arg = args[arg_i];
            if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                try stdout.writeAll(usage_text_fmt);
                std.process.exit(0);
            } else if (std.mem.eql(u8, arg, "--symbol")) {
                arg_i += 1;
                if (arg_i >= args.len) {
                    try stderr.writeAll(fmt(allocator, "'{s}' requires an argument.\n{s}", .{ arg, usage_text_fmt }));
                    std.process.exit(1);
                }
                symbol = args[arg_i];
            } else if (std.mem.eql(u8, arg, "--elf")) {
                arg_i += 1;
                if (arg_i >= args.len) {
                    try stderr.writeAll(fmt(allocator, "'{s}' requires an argument.\n{s}", .{ arg, usage_text_fmt }));
                    std.process.exit(1);
                }
                elf = args[arg_i];
            } else {
                try stderr.writeAll(fmt(allocator, "unrecognized argument: '{s}'\n{s}", .{ arg, usage_text_fmt }));
                std.process.exit(1);
            }
        }

        if (arg_i == 1) {
            try stdout.writeAll(usage_text_fmt);
            std.process.exit(1);
        }

        if (symbol == null) {
            std.debug.print("Missing '--symbol' argument\n", .{});
            std.process.exit(1);
        }

        if (elf == null) {
            std.debug.print("Missing '--elf' argument\n", .{});
            std.process.exit(1);
        }

        return .{
            .symbol = symbol.?,
            .elf = elf.?,
        };
    }
};

pub fn main() !void {
    const stderr = std.io.getStdErr();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const process_args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, process_args);

    const args = try Args.parse(allocator, process_args);

    const elf = Elf.from_path(allocator, args.elf) catch |err| {
        try stderr.writeAll(fmt(allocator, "could not parse ELF: {any}\n", .{ err }));
        std.process.exit(1);
    };
    defer elf.deinit();
}
