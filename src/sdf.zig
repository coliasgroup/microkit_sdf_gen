const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const allocPrint = std.fmt.allocPrint;

// TODO: for addresses should we use the word size of the *target* machine?
// TODO: should passing a virual address to a mapping be necessary?
// TODO: indent stuff could be done better

pub const SystemDescription = struct {
    /// Store the allocator used when creating the SystemDescirption so we
    /// can later deinit everything
    allocator: Allocator,
    /// Array holding all the bytes for the XML data
    xml_data: ArrayList(u8),
    /// We use the Writer standard library API to add to this xml_data array
    xml: ArrayList(u8).Writer,
    /// There are some architecture specific options (right now just PageSize)
    arch: Arch,
    pds: ArrayList(*ProtectionDomain),
    mrs: ArrayList(MemoryRegion),
    channels: ArrayList(Channel),

    /// Supported architectures by seL4
    pub const Arch = enum {
        aarch32,
        aarch64,
        riscv32,
        riscv64,
        ia32,
        x86_64,
    };

    pub const MemoryRegion = struct {
        name: []const u8,
        size: usize,
        phys_addr: ?usize,
        page_size: PageSize,

        pub fn create(system: *SystemDescription, name: []const u8, size: usize, phys_addr: ?usize, page_size: PageSize) MemoryRegion {
            return MemoryRegion{
                .name = system.allocator.dupe(u8, name) catch "Could not allocate name for MemoryRegion",
                .size = size,
                .phys_addr = phys_addr,
                .page_size = page_size,
            };
        }

        pub fn destroy(mr: MemoryRegion, system: *SystemDescription) void {
            system.allocator.free(mr.name);
        }

        pub fn toXml(mr: MemoryRegion, sdf: *SystemDescription, writer: ArrayList(u8).Writer, indent: []const u8, arch: Arch) !void {
            var xml = try allocPrint(sdf.allocator, "{s}<memory_region name=\"{s}\" size=\"0x{x}\" page_size=\"0x{x}\"", .{ indent, mr.name, mr.size, mr.page_size.toSize(arch) });
            defer sdf.allocator.free(xml);

            var final_xml: []const u8 = undefined;
            if (mr.phys_addr) |phys_addr| {
                final_xml = try allocPrint(sdf.allocator, "{s} phys_addr=\"0x{x}\" />\n", .{ xml, phys_addr });
            } else {
                final_xml = try allocPrint(sdf.allocator, "{s} />\n", .{xml});
            }
            defer sdf.allocator.free(final_xml);

            _ = try writer.write(final_xml);
        }

        // TODO: consider other architectures
        pub const PageSize = enum(usize) {
            small,
            large,
            huge,

            pub fn toSize(page_size: PageSize, arch: Arch) usize {
                // TODO: on RISC-V we are assuming that it's Sv39.
                switch (arch) {
                    .aarch64, .riscv64, .x86_64 => return switch (page_size) {
                        .small => 0x1000,
                        .large => 0x200000,
                        .huge => 0x40000000,
                    },
                    .aarch32, .riscv32, .ia32 => return switch (page_size) {
                        .small => 0x1000,
                        .large => 0x400000,
                        .huge => 0x40000000,
                    },
                }
            }

            pub fn fromInt(page_size: usize, arch: Arch) !PageSize {
                switch (arch) {
                    .aarch64, .riscv64 => return switch (page_size) {
                        0x1000 => .small,
                        0x200000 => .large,
                        0x40000000 => .huge,
                        else => return error.InvalidPageSize,
                    },
                    .aarch32, .riscv32 => return switch (page_size) {
                        0x1000 => .small,
                        0x400000 => .large,
                        0x40000000 => .huge,
                        else => return error.InvalidPageSize,
                    },
                }
            }
        };
    };

    pub const Map = struct {
        mr: MemoryRegion,
        vaddr: usize,
        perms: Permissions,
        cached: bool,
        // TODO: could make this a type?
        setvar_vaddr: ?[]const u8,

        pub const Permissions = packed struct {
            // TODO: the write-only mappings not being allowed
            // needs to be enforced here
            read: bool = false,
            /// On all architectures of seL4, write permissions are required
            write: bool = true,
            execute: bool = false,

            pub fn toString(perms: Permissions, buf: *[4]u8) usize {
                var i: u8 = 0;
                if (perms.read) {
                    buf[i] = 'r';
                    i += 1;
                }
                if (perms.write) {
                    buf[i] = 'w';
                    i += 1;
                }
                if (perms.execute) {
                    buf[i] = 'x';
                    i += 1;
                }

                return i;
            }

            pub fn fromString(str: []const u8) Permissions {
                const read_count = std.mem.count(u8, str, "r");
                const write_count = std.mem.count(u8, str, "w");
                const exec_count = std.mem.count(u8, str, "x");
                std.debug.assert(read_count == 0 or read_count == 1);
                std.debug.assert(write_count == 0 or write_count == 1);
                std.debug.assert(exec_count == 0 or exec_count == 1);

                var perms: Permissions = .{};
                if (read_count > 0) {
                    perms.read = true;
                }
                if (exec_count > 0) {
                    perms.execute = true;
                }

                return perms;
            }
        };

        pub fn create(mr: MemoryRegion, vaddr: usize, perms: Permissions, cached: bool, setvar_vaddr: ?[]const u8) Map {
            return Map{
                .mr = mr,
                .vaddr = vaddr,
                .perms = perms,
                .cached = cached,
                .setvar_vaddr = setvar_vaddr,
            };
        }

        pub fn toXml(map: *const Map, sdf: *SystemDescription, writer: ArrayList(u8).Writer) !void {
            const mr_str =
                \\<map mr="{s}" vaddr="0x{x}" perms="{s}" cached="{s}" />
            ;
            // TODO: use null terminated pointer from Zig?
            var perms = [_]u8{0} ** 4;
            const i = map.perms.toString(&perms);

            const cached = if (map.cached) "true" else "false";
            const xml = try allocPrint(sdf.allocator, mr_str, .{ map.mr.name, map.vaddr, perms[0..i], cached });
            defer sdf.allocator.free(xml);

            _ = try writer.write(xml);
        }
    };

    pub const VirtualMachine = struct {
        name: []const u8,
        priority: u8 = 100,
        budget: usize = 100,
        period: usize = 100,
        passive: bool = false,
        maps: ArrayList(Map),

        pub fn create(sdf: *SystemDescription, name: []const u8) VirtualMachine {
            return VirtualMachine {
                .name = name,
                .maps = ArrayList(Map).init(sdf.allocator),
            };
        }

        pub fn addMap(vm: *VirtualMachine, map: Map) !void {
            try vm.maps.append(map);
        }

        pub fn destroy(vm: *VirtualMachine) void {
            vm.maps.deinit();
        }

        pub fn toXml(vm: *VirtualMachine, sdf: *SystemDescription, writer: ArrayList(u8).Writer, indent: []const u8, id: usize) !void {
            const first_tag =
                \\ {s}<virtual_machine name="{s}" id="{}" priority="{}" budget="{}" period="{}" passive="{}" />
            ;
            const first_xml = try allocPrint(sdf.allocator, first_tag, .{ indent, vm.name, id, vm.priority, vm.budget, vm.period, vm.passive });
            defer sdf.allocator.free(first_xml);
            _ = try writer.write(first_xml);

            // Add memory region mappings as child nodes
            const inner_indent = try allocPrint(sdf.allocator, "{s}    ", .{ indent });
            defer sdf.allocator.free(inner_indent);
            for (vm.maps.items) |map| {
                _ = try writer.write(inner_indent);
                try map.toXml(sdf, writer);
            }

            const closing_tag =
                \\ {s}<virtual_machine />
            ;
            const closing_xml = try allocPrint(sdf.allocator, closing_tag, .{ indent });
            defer sdf.allocator.free(closing_xml);
            _ = try writer.write(closing_xml);
        }
    };

    pub const ProtectionDomain = struct {
        name: []const u8,
        /// Program ELF
        program_image: ?ProgramImage,
        /// Scheduling parameters
        priority: u8 = 100,
        budget: usize = 100,
        period: usize = 100,
        passive: bool = false,
        /// Whether there is an available 'protected' entry point
        pp: bool = false,
        /// Child nodes
        maps: ArrayList(Map),
        child_pds: ArrayList(*ProtectionDomain),
        irqs: ArrayList(Interrupt),
        vm: ?*VirtualMachine,
        /// Internal counter of the next available ID
        next_avail_id: usize = 0,

        pub const ProgramImage = struct {
            path: []const u8,

            pub fn create(path: []const u8) ProgramImage {
                return ProgramImage{ .path = path };
            }

            pub fn toXml(program_image: *const ProgramImage, sdf: *SystemDescription, writer: ArrayList(u8).Writer) !void {
                const xml = try allocPrint(sdf.allocator, "<program_image path=\"{s}\" />", .{ program_image.path });
                defer sdf.allocator.free(xml);
                _ = try writer.write(xml);
            }
        };

        pub fn create(sdf: *SystemDescription, name: []const u8, program_image: ?ProgramImage) ProtectionDomain {
            return ProtectionDomain{
                .name = name,
                .program_image = program_image,
                .maps = ArrayList(Map).init(sdf.allocator),
                .child_pds = ArrayList(*ProtectionDomain).init(sdf.allocator),
                .irqs = ArrayList(Interrupt).init(sdf.allocator),
                .vm = null,
            };
        }

        pub fn destroy(pd: *ProtectionDomain) void {
            pd.maps.deinit();
            for (pd.child_pds.items) |child_pd| {
                child_pd.destroy();
            }
            pd.irqs.deinit();
        }

        pub fn addVirtualMachine(pd: *ProtectionDomain, vm: *VirtualMachine) !void {
            if (pd.vm != null) return error.ProtectionDomainAlreadyHasVirtualMachine;
            pd.vm = vm;
        }

        pub fn addMap(pd: *ProtectionDomain, map: Map) !void {
            try pd.maps.append(map);
        }

        pub fn addInterrupt(pd: *ProtectionDomain, interrupt: Interrupt) !void {
            try pd.irqs.append(interrupt);
        }

        pub fn addChild(pd: *ProtectionDomain, child: *ProtectionDomain) !void {
            try pd.child_pds.append(child);
        }

        pub fn toXml(pd: *ProtectionDomain, sdf: *SystemDescription, writer: ArrayList(u8).Writer, indent: []const u8, id: ?usize) !void {
            // If we are given an ID, this PD is in fact a child PD and we have to
            // specify the ID for the root PD to use when referring to this child PD.
            // TODO: simplify this whole logic, it's quite messy right now
            const attributes_str =
                \\priority="{}" budget="{}" period="{}" passive="{}" pp="{}"
            ;
            const attributes_xml = try allocPrint(sdf.allocator, attributes_str, .{ pd.priority, pd.budget, pd.period, pd.passive, pd.pp });
            defer sdf.allocator.free(attributes_xml);
            var top: []const u8 = undefined;
            if (id) |id_val| {
                top = try allocPrint(sdf.allocator,
                    "{s}<protection_domain name=\"{s}\" id=\"{}\" {s}>", .{ indent, pd.name, id_val, attributes_xml });
            } else {
                top = try allocPrint(sdf.allocator,
                    "{s}<protection_domain name=\"{s}\" {s}>", .{ indent, pd.name, attributes_xml });
            }
            defer sdf.allocator.free(top);
            _ = try writer.write(top);

            // TODO: handle period, budget, priority, passive

            const inner_indent = try allocPrint(sdf.allocator, "\n{s}    ", .{ indent });
            defer sdf.allocator.free(inner_indent);
            // Add program image (if we have one)
            if (pd.program_image) |program_image| {
                _ = try writer.write(inner_indent);
                try program_image.toXml(sdf, writer);
            }
            // Add memory region mappins
            for (pd.maps.items) |map| {
                _ = try writer.write(inner_indent);
                try map.toXml(sdf, writer);
            }
            // Add child PDs
            for (pd.child_pds.items) |child_pd| {
                const child_pd_xml = try allocPrint(sdf.allocator, "\n{s}", .{ inner_indent });
                defer sdf.allocator.free(child_pd_xml);
                try child_pd.toXml(sdf, writer, inner_indent, pd.next_avail_id);
                _ = try writer.write(child_pd_xml);
                pd.next_avail_id += 1;
            }
            // Add virtual machine (if we have one)
            if (pd.vm) |vm| {
                try vm.toXml(sdf, writer, inner_indent, pd.next_avail_id);
                pd.next_avail_id += 1;
            }
            // Add interrupts
            for (pd.irqs.items) |irq| {
                _ = try writer.write(inner_indent);
                try irq.toXml(sdf, writer, pd.next_avail_id);
                // xml = try allocPrint(sdf.allocator, "{s}\n{s}{s}", .{ xml, inner_indent, try irq.toXml(sdf.allocator, pd.next_avail_id) });
                pd.next_avail_id += 1;
            }

            const bottom = try allocPrint(sdf.allocator, "\n{s}</protection_domain>\n", .{ indent });
            defer sdf.allocator.free(bottom);
            _ = try writer.write(bottom);
        }
    };

    pub const Channel = struct {
        pd1: *ProtectionDomain,
        pd2: *ProtectionDomain,
        pd1_end_id: usize,
        pd2_end_id: usize,

        pub fn create(pd1: *ProtectionDomain, pd2: *ProtectionDomain) Channel {
            const ch = Channel{
                .pd1 = pd1,
                .pd2 = pd2,
                .pd1_end_id = pd1.next_avail_id,
                .pd2_end_id = pd2.next_avail_id,
            };
            pd1.next_avail_id += 1;
            pd2.next_avail_id += 1;

            return ch;
        }

        pub fn toXml(ch: Channel, sdf: *SystemDescription, writer: ArrayList(u8).Writer) !void {
            const channel_str =
                \\    <channel>
                \\        <end pd="{s}" id="{}" />
                \\        <end pd="{s}" id="{}" />
                \\    </channel>
                \\
            ;
            const channel_xml = try allocPrint(sdf.allocator, channel_str, .{ ch.pd1.name, ch.pd1_end_id, ch.pd2.name, ch.pd2_end_id });
            defer sdf.allocator.free(channel_xml);

            _ = try writer.write(channel_xml);
        }
    };

    pub const Interrupt = struct {
        fixed_id: ?usize = null,
        irq: usize,
        trigger: Trigger,

        pub const Trigger = enum { edge, level };

        pub fn create(irq: usize, trigger: Trigger, id: ?usize) Interrupt {
            // TODO: if there's a fixed id then we need to check it's not allocated already
            // TODO: the XML export of a PD also needs to consider the fixed IDs
            return Interrupt{ .irq = irq, .trigger = trigger, .fixed_id = id };
        }

        pub fn toXml(irq: *const Interrupt, sdf: *SystemDescription, writer: ArrayList(u8).Writer, id: usize) !void {
            const irq_str =
                \\<irq irq="{}" trigger="{s}" id="{}" />
            ;
            const irq_id = if (irq.fixed_id) |irq_fixed_id| irq_fixed_id else id;
            const irq_xml = try allocPrint(sdf.allocator, irq_str, .{ irq.irq, @tagName(irq.trigger), irq_id });
            defer sdf.allocator.free(irq_xml);

            _ = try writer.write(irq_xml);
        }
    };

    pub fn create(allocator: Allocator, arch: Arch) !SystemDescription {
        var xml_data = ArrayList(u8).init(allocator);
        return SystemDescription {
            .allocator = allocator,
            .xml_data = xml_data,
            .xml = xml_data.writer(),
            .arch = arch,
            .pds = ArrayList(*ProtectionDomain).init(allocator),
            .mrs = ArrayList(MemoryRegion).init(allocator),
            .channels = ArrayList(Channel).init(allocator),
        };
    }

    pub fn destroy(sdf: *SystemDescription) void {
        for (sdf.pds.items) |pd| pd.destroy();
        sdf.pds.deinit();
        for (sdf.mrs.items) |mr| mr.destroy(sdf);
        sdf.mrs.deinit();
        sdf.channels.deinit();
        sdf.xml_data.deinit();
    }

    pub fn addChannel(sdf: *SystemDescription, channel: Channel) !void {
        try sdf.channels.append(channel);
    }

    pub fn addMemoryRegion(sdf: *SystemDescription, mr: MemoryRegion) !void {
        try sdf.mrs.append(mr);
    }

    pub fn addProtectionDomain(sdf: *SystemDescription, pd: *ProtectionDomain) !void {
        try sdf.pds.append(pd);
    }

    pub fn toXml(sdf: *SystemDescription) ![]const u8 {
        const writer = sdf.xml_data.writer();
        _ = try writer.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<system>\n");

        const indent = " " ** 4;
        for (sdf.mrs.items) |mr| {
            try mr.toXml(sdf, writer, indent, sdf.arch);
        }
        for (sdf.pds.items) |pd| {
            try pd.toXml(sdf, writer, indent, null);
        }
        for (sdf.channels.items) |ch| {
            try ch.toXml(sdf, writer);
        }

        _ = try writer.write("</system>\n");

        return sdf.xml_data.items;
    }

    /// Export the necessary #defines for channel IDs, IRQ IDs and child
    /// PD IDs.
    pub fn exportCHeader(sdf: *SystemDescription, allocator: Allocator, pd: *ProtectionDomain) ![]const u8 {
        var header = try allocPrint(allocator, "", .{});
        for (sdf.channels.items) |ch| {
            if (ch.pd1 == pd) {
                header = try allocPrint(allocator, "{s}#define CHANNEL {}\n", .{ header, ch.pd1_end_id });
            } else if (ch.pd2 == pd) {
                header = try allocPrint(allocator, "{s}#define CHANNEL {}\n", .{ header, ch.pd2_end_id });
            }
        }
        for (pd.irqs.items) |irq| {
            header = try allocPrint(allocator, "{s}#define IRQ {}\n", .{ header, irq.irq });
            header = try allocPrint(allocator, "{s}#define IRQ_CH {}\n", .{ header, irq.id });
        }

        return header;
    }
};
