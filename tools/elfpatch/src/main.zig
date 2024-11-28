const std = @import("std");
const Allocator = std.mem.Allocator;

const Elf = struct {
    const Segment = struct {
        vaddr: u64,
        len: u64,
        data: []u8,
    };

    const SymbolInfo = struct {
        symbol: std.elf.Elf64_Sym,
        duplicate: bool,
    };

    allocator: Allocator,
    segments: std.ArrayList(Segment),
    symbols: std.StringHashMap(SymbolInfo),
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

    pub fn write_symbol(elf: *Elf, name: []const u8, data: []const u8) void {
        // TODO, do not .?
        const symbol = elf.symbols.get(name).?;
        std.debug.assert(!symbol.duplicate);
        const vaddr = symbol.symbol.st_value;
        const size = symbol.symbol.st_size;
        for (elf.segments.items) |segment| {
            if (vaddr >= segment.vaddr and vaddr + size <= segment.vaddr + segment.len) {
                const offset = vaddr - segment.vaddr;
                std.debug.assert(data.len <= size);
                @memcpy(segment.data[offset..offset + data.len], data);
            }
        }

        std.log.err("No symbol found for '{s}'", .{ name });
    }

    pub fn init(allocator: Allocator, bytes: []u8) !Elf {
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
        std.debug.print("{any}\n", .{ hdr });

        var segments = try std.ArrayList(Segment).initCapacity(allocator, hdr.phnum);
        for (0..hdr.phnum) |i| {
            std.debug.print("hdr.phoff {}\n", .{ hdr.phoff });
            const phent_start = hdr.phoff + (i * hdr.phentsize);
            const phent_end = phent_start + (hdr.phentsize);
            const phent_bytes = bytes[phent_start..phent_end];

            const phent = std.mem.bytesAsValue(std.elf.Elf64_Phdr, phent_bytes);

            if (phent.p_type != 1) {
                continue;
            }

            const segment_start = phent.p_offset;
            const segment_end = phent.p_offset + phent.p_filesz;

            segments.appendAssumeCapacity(.{
                .vaddr = phent.p_vaddr,
                .len = phent.p_filesz,
                .data = bytes[segment_start..segment_end],
            });

            std.debug.print("segment({}), vaddr: {x}\n", .{ i, phent.p_vaddr });

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

        var shents = try std.ArrayList(*align(1) const std.elf.Elf64_Shdr).initCapacity(allocator, hdr.shnum);
        var maybe_symtab_shent: ?std.elf.Elf64_Shdr = null;
        var has_shstrtab_shent = false;
        for (0..hdr.shnum) |i| {
            const shent_start = hdr.shoff + (i * hdr.shentsize);
            const shent_end = shent_start + hdr.shentsize;

            const shent_bytes = bytes[shent_start..shent_end];

            const shent = std.mem.bytesAsValue(std.elf.Elf64_Shdr, shent_bytes);
            switch (shent.sh_type) {
                2 => maybe_symtab_shent = shent.*,
                3 => has_shstrtab_shent = true,
                else => {}
            }

            shents.appendAssumeCapacity(shent);
        }

        // TODO: copied from Microkit ELF parsing, do we need this?
        if (!has_shstrtab_shent) {
            return error.MissingStringTableSection;
        }

        if (maybe_symtab_shent == null) {
            return error.MissingSymbolTableSection;
        }

        const symtab_shent = maybe_symtab_shent.?;

        // Reading the symbol table
        const symtab_start = symtab_shent.sh_offset;
        const symtab_end = symtab_start + symtab_shent.sh_size;
        const symtab = bytes[symtab_start..symtab_end];

        const symtab_str_shent = shents.items[symtab_shent.sh_link];
        const symtab_str_start = symtab_str_shent.sh_offset;
        const symtab_str_end = symtab_str_start + symtab_str_shent.sh_size;
        const symtab_str = bytes[symtab_str_start..symtab_str_end];

        const elf_symbol_size = @sizeOf(std.elf.Elf64_Sym);
        var symbols = std.StringHashMap(SymbolInfo).init(allocator);
        var offset: usize = 0;
        while (offset < symtab.len) {
            const sym_bytes = symtab[offset..offset + elf_symbol_size];
            const sym = std.mem.bytesAsValue(std.elf.Elf64_Sym, sym_bytes);
            const string_full = symtab_str[sym.st_name..];
            // Do not include null-terminator
            const string = string_full[0..std.mem.indexOf(u8, string_full, &.{ 0 }).?];

            const symbol = SymbolInfo{
                // TODO: copying the symbol
                .symbol = sym.*,
                .duplicate = symbols.contains(string),
            };

            std.debug.print("symbol {s}\n", .{ string });

            try symbols.put(string, symbol);
            offset += elf_symbol_size;
        }

        // TODO: do we need toOwnedSlice?
        return .{
            .allocator = allocator,
            .segments = segments,
            .bytes = bytes,
            .symbols = symbols,
        };
    }

    pub fn deinit(elf: *Elf) void {
        elf.allocator.free(elf.bytes);
        elf.segments.deinit();
        elf.symbols.deinit();
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
    \\
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

    var elf = Elf.from_path(allocator, args.elf) catch |err| {
        try stderr.writeAll(fmt(allocator, "could not parse ELF: {any}\n", .{ err }));
        std.process.exit(1);
    };
    defer elf.deinit();

    elf.write_symbol("hello", &std.mem.toBytes(32));
}
