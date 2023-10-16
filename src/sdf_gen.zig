const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const allocPrint = std.fmt.allocPrint;

// TODO: for addresses should we use the word size of the *target* machine?
// TODO: should passing a virual address to a mapping be necessary?
// TODO: indent stuff could be done better
// TODO: need to use the stored allocator in SystemDescription when creating PDs etc

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
    };

    pub const MemoryRegion = struct {
        name: []const u8,
        size: usize,
        phys_addr: ?usize,
        page_size: PageSize,

        pub fn create(name: []const u8, size: usize, phys_addr: ?usize, page_size: ?PageSize) MemoryRegion {
            return MemoryRegion{
                .name = name,
                .size = size,
                .phys_addr = phys_addr,
                .page_size = if (page_size) |ps| ps else PageSize.small,
            };
        }

        pub fn toXml(mr: *const MemoryRegion, allocator: Allocator, writer: ArrayList(u8).Writer, indent: []const u8, arch: Arch) !void {
            var xml = try allocPrint(allocator, "{s}<memory_region name=\"{s}\" size=\"0x{x}\" page_size=\"0x{x}\"", .{ indent, mr.name, mr.size, mr.page_size.toSize(arch) });
            defer allocator.free(xml);

            var final_xml: []const u8 = undefined;
            if (mr.phys_addr) |phys_addr| {
                final_xml = try allocPrint(allocator, "{s} phys_addr=\"0x{x}\" />\n", .{ xml, phys_addr });
            } else {
                final_xml = try allocPrint(allocator, "{s} />\n", .{xml});
            }
            defer allocator.free(final_xml);

            _ = try writer.write(final_xml);
        }

        // TODO: consider other architectures
        const PageSize = enum(usize) {
            small,
            large,
            huge,

            pub fn toSize(page_size: PageSize, arch: Arch) usize {
                switch (arch) {
                    .aarch64, .riscv64 => return switch (page_size) {
                        .small => 0x1000,
                        .large => 0x200000,
                        .huge => 0x40000000,
                    },
                    .aarch32, .riscv32 => return switch (page_size) {
                        .small => 0x1000,
                        .large => 0x400000,
                        // TODO: handle
                        else => unreachable,
                    },
                }
            }
        };
    };

    pub const Map = struct {
        mr: *const MemoryRegion,
        vaddr: usize,
        perms: Permissions,
        cached: bool,
        // TODO: could make this a type?
        setvar_vaddr: ?[]const u8,

        const Permissions = packed struct {
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
        };

        pub fn create(mr: *const MemoryRegion, vaddr: usize, perms: Permissions, cached: bool, setvar_vaddr: ?[]const u8) Map {
            return Map{
                .mr = mr,
                .vaddr = vaddr,
                .perms = perms,
                .cached = cached,
                .setvar_vaddr = setvar_vaddr,
            };
        }

        pub fn toXml(map: *const Map, allocator: Allocator, writer: ArrayList(u8).Writer) !void {
            const mr_str =
                \\<map mr="{s}" vaddr="0x{x}" perms="{s}" cached="{s}" />
            ;
            // TODO: use null terminated pointer from Zig?
            var perms = [_]u8{0} ** 4;
            const i = map.perms.toString(&perms);

            const xml = try allocPrint(allocator, mr_str,
                                  .{ map.mr.name, map.vaddr, perms[0..i], if (map.cached) "true" else "false" });
            defer allocator.free(xml);

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

        pub fn create(allocator: Allocator, name: []const u8) VirtualMachine {
            return VirtualMachine {
                .name = name,
                .maps = ArrayList(Map).init(allocator),
            };
        }

        pub fn addMap(vm: *VirtualMachine, map: Map) !void {
            try vm.maps.append(map);
        }

        pub fn destroy(vm: *VirtualMachine) void {
            vm.maps.deinit();
        }

        pub fn toXml(vm: *VirtualMachine, allocator: Allocator, writer: ArrayList(u8).Writer, indent: []const u8, id: usize) !void {
            const first_tag =
                \\ {s}<virtual_machine name="{s}" id="{}" priority="{}" budget="{}" period="{}" passive="{}" />
            ;
            const first_xml = try allocPrint(allocator, first_tag, .{ indent, vm.name, id, vm.priority, vm.budget, vm.period, vm.passive });
            defer allocator.free(first_xml);
            _ = try writer.write(first_xml);

            // Add memory region mappings as child nodes
            const inner_indent = try allocPrint(allocator, "{s}    ", .{ indent });
            defer allocator.free(inner_indent);
            for (vm.maps.items) |map| {
                _ = try writer.write(inner_indent);
                try map.toXml(allocator, writer);
            }

            const closing_tag =
                \\ {s}<virtual_machine />
            ;
            const closing_xml = try allocPrint(allocator, closing_tag, .{ indent });
            _ = try writer.write(closing_xml);
        }
    };

    pub const ProtectionDomain = struct {
        name: []const u8,
        /// Program ELF
        program_image: ?ProgramImage,
        /// Scheduling parameters
        priority: ?u8,
        budget: ?usize,
        period: ?usize,
        passive: ?bool,
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

            pub fn toXml(program_image: *const ProgramImage, allocator: Allocator, writer: ArrayList(u8).Writer) !void {
                const xml = try allocPrint(allocator, "<program_image path=\"{s}\" />", .{ program_image.path });
                defer allocator.free(xml);
                _ = try writer.write(xml);
            }
        };

        pub fn create(allocator: Allocator, name: []const u8, program_image: ?ProgramImage, priority: ?u8, budget: ?usize, period: ?usize, passive: ?bool) ProtectionDomain {
            return ProtectionDomain{
                .name = name,
                .passive = passive,
                .program_image = program_image,
                .priority = priority,
                .budget = budget,
                .period = period,
                .maps = ArrayList(Map).init(allocator),
                .child_pds = ArrayList(*ProtectionDomain).init(allocator),
                .irqs = ArrayList(Interrupt).init(allocator),
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

        pub fn toXml(pd: *ProtectionDomain, allocator: Allocator, writer: ArrayList(u8).Writer, indent: []const u8, id: ?usize) !void {
            // If we are given an ID, this PD is in fact a child PD and we have to
            // specify the ID for the root PD to use when referring to this child PD.
            // TODO: make this not undefined
            var top: []const u8 = undefined;
            if (id) |id_val| {
                top = try allocPrint(allocator, "{s}<protection_domain name=\"{s}\" id=\"{}\">", .{ indent, pd.name, id_val });
            } else {
                top = try allocPrint(allocator, "{s}<protection_domain name=\"{s}\">", .{ indent, pd.name });
            }
            _ = try writer.write(top);
            defer allocator.free(top);

            // TODO: handle period, budget, priority, passive

            const inner_indent = try allocPrint(allocator, "\n{s}    ", .{ indent });
            defer allocator.free(inner_indent);
            // Add program image (if we have one)
            if (pd.program_image) |program_image| {
                _ = try writer.write(inner_indent);
                try program_image.toXml(allocator, writer);
            }
            // Add memory region mappins
            for (pd.maps.items) |map| {
                _ = try writer.write(inner_indent);
                try map.toXml(allocator, writer);
            }
            // Add child PDs
            for (pd.child_pds.items) |child_pd| {
                const child_pd_xml = try allocPrint(allocator, "\n{s}", .{ inner_indent });
                defer allocator.free(child_pd_xml);
                try child_pd.toXml(allocator, writer, inner_indent, pd.next_avail_id);
                _ = try writer.write(child_pd_xml);
                pd.next_avail_id += 1;
            }
            // Add virtual machine (if we have one)
            if (pd.vm) |vm| {
                try vm.toXml(allocator, writer, inner_indent, pd.next_avail_id);
                pd.next_avail_id += 1;
            }
            // Add interrupts
            for (pd.irqs.items) |irq| {
                _ = try writer.write(inner_indent);
                try irq.toXml(allocator, writer, pd.next_avail_id);
                // xml = try allocPrint(allocator, "{s}\n{s}{s}", .{ xml, inner_indent, try irq.toXml(allocator, pd.next_avail_id) });
                pd.next_avail_id += 1;
            }

            const bottom = try allocPrint(allocator, "\n{s}</protection_domain>\n", .{ indent });
            defer allocator.free(bottom);
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

        pub fn toXml(ch: Channel, allocator: Allocator, writer: ArrayList(u8).Writer) !void {
            const channel_str =
                \\    <channel>
                \\        <end pd="{s}" id="{}" />
                \\        <end pd="{s}" id="{}" />
                \\    </channel>
                \\
            ;
            const channel_xml = try allocPrint(allocator, channel_str, .{ ch.pd1.name, ch.pd1_end_id, ch.pd2.name, ch.pd2_end_id });
            defer allocator.free(channel_xml);

            _ = try writer.write(channel_xml);
        }
    };

    pub const Interrupt = struct {
        name: []const u8,
        id: ?usize = null,
        irq: usize,
        trigger: Trigger,

        pub const Trigger = enum { edge, level };

        pub fn create(name: []const u8, irq: usize, trigger: Trigger) Interrupt {
            return Interrupt{ .name = name, .irq = irq, .trigger = trigger };
        }

        pub fn toXml(interrupt: *const Interrupt, allocator: Allocator, writer: ArrayList(u8).Writer, id: usize) !void {
            const irq_str =
                \\<irq irq="{}" trigger="{s}" id="{}" />
            ;
            const irq_xml = try allocPrint(allocator, irq_str, .{ interrupt.irq, @tagName(interrupt.trigger), id });
            defer allocator.free(irq_xml);

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

    pub fn toXml(sdf: *SystemDescription, allocator: Allocator) ![]const u8 {
        const writer = sdf.xml_data.writer();
        _ = try writer.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<system>\n");

        const indent = " " ** 4;
        for (sdf.mrs.items) |mr| {
            try mr.toXml(allocator, writer, indent, sdf.arch);
        }
        for (sdf.pds.items) |pd| {
            try pd.toXml(allocator, writer, indent, null);
        }
        for (sdf.channels.items) |ch| {
            try ch.toXml(allocator, writer);
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
