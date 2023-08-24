const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const allocPrint = std.fmt.allocPrint;

// TODO: for addresses should we use the word size of the *target* machine?
// TODO: should passing a virual address to a mapping be necessary?
// TODO: indent stuff could be done better

pub const SystemDescription = struct {
    arch: Arch,
    pds: ArrayList(*ProtectionDomain),
    mrs: ArrayList(MemoryRegion),
    channels: ArrayList(Channel),

    pub const Arch = enum {
        aarch64,
        riscv32,
        riscv64,
    };

    pub const MemoryRegion = struct {
        // TODO: consider other architectures
        const PageSize = enum(usize) {
            small,
            large,

            pub fn toSize(page_size: PageSize, arch: Arch) usize {
                switch (arch) {
                    .aarch64, .riscv64 =>
                        return switch (page_size) {
                            .small => 0x1000,
                            .large => 0x200000,
                        },
                    .riscv32 =>
                        return switch (page_size) {
                            .small => 0x1000,
                            .large => 0x400000,
                        },
                }
            }
        };

        name: []const u8,
        size: usize,
        phys_addr: ?usize,
        page_size: PageSize,

        pub fn create(name: []const u8, size: usize, phys_addr: ?usize, page_size: ?PageSize) MemoryRegion {
            return MemoryRegion {
                .name = name,
                .size = size,
                .phys_addr = phys_addr,
                .page_size = if (page_size) |ps| ps else PageSize.small,
            };
        }

        pub fn toXml(mr: *const MemoryRegion, allocator: Allocator, indent: []const u8, arch: Arch) ![]const u8 {
            var xml = try allocPrint(allocator,
                "{s}<memory_region name=\"{s}\" size=\"0x{x}\" page_size=\"0x{x}\"",
                .{ indent, mr.name, mr.size, mr.page_size.toSize(arch) }
            );

            if (mr.phys_addr) |phys_addr| {
               xml = try allocPrint(allocator, "{s} phys_addr=\"{}\"", .{ xml, phys_addr });
            }

            xml = try allocPrint(allocator, "{s} />\n", .{ xml });

            return xml;
        }
    };

    pub const Map = struct {
        mr: *const MemoryRegion,
        vaddr: usize,
        perms: Permissions,
        cached: bool,

        const Permissions = packed struct {
            read: bool = false,
            /// On all architectures of seL4, write permissions are required
            write: bool = true,
            execute: bool = false,

            pub fn toString(perms: Permissions, buf: *[3]u8) void {
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
            }
        };

        pub fn create(mr: *const MemoryRegion, vaddr: usize, perms: Permissions, cached: bool) Map {
            return Map {
                .mr = mr,
                .vaddr = vaddr,
                .perms = perms,
                .cached = cached,
            };
        }

        pub fn toXml(map: *const Map, allocator: Allocator) ![]const u8 {
            var perms = [_]u8{0} ** 3;
            map.perms.toString(&perms);
            return try allocPrint(allocator,
                "<map mr=\"{s}\" vaddr=\"0x{x}\" perms=\"{s}\" cached=\"{s}\" />",
                .{ map.mr.name,
                   map.vaddr,
                   perms,
                   if (map.cached) "true" else "false"
                }
            );
        }
    };

    const VirtualMachine = struct {
        name: []const u8,
        maps: ArrayList(Map),
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
        vm: ?VirtualMachine,
        /// Internal counter of the next available ID
        next_avail_id: usize = 0,

        pub const ProgramImage = struct {
            path: []const u8,

            pub fn create(path: []const u8) ProgramImage {
                return ProgramImage { .path = path };
            }

            pub fn toXml(program_image: *const ProgramImage, allocator: Allocator) ![]const u8 {
                return try allocPrint(allocator, "<program_image path=\"{s}\" />", .{ program_image.path });
            }
        };

        pub fn create(allocator: Allocator, name: []const u8, program_image: ?ProgramImage, priority: ?u8, budget: ?usize, period: ?usize, passive: ?bool) ProtectionDomain {
            return ProtectionDomain {
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

        pub fn addVirtualMachine(pd: *ProtectionDomain, vm: VirtualMachine) !void {
            if (pd.vm != null) return error.ProtectionDomainAlreadyHasVirtualMachine;
            pd.vm = vm;
        }

        pub fn addMap(pd: *ProtectionDomain, map: Map) !void {
            try pd.maps.append(map);
        }

        pub fn addInterrupt(pd: *ProtectionDomain, interrupt: Interrupt) !void {
            // interrupt.id = pd.next_avail_id;
            // pd.next_avail_id += 1;
            try pd.irqs.append(interrupt);
        }

        pub fn toXml(pd: *ProtectionDomain, allocator: Allocator, indent: []const u8, id: ?usize) ![]const u8 {
            var xml = try allocPrint(allocator, "{s}<protection_domain name=\"{s}\"", .{ indent, pd.name });
            if (id) |i| {
                xml = try allocPrint(allocator, "{s} id=\"{}\"", .{ xml, i });
            }
            xml = try allocPrint(allocator, "{s} >", .{ xml });

            const inner_indent = try allocPrint(allocator, "{s}    ", .{ indent });
            // Add program image (if we have one)
            if (pd.program_image) |p| {
                xml = try allocPrint(allocator, "{s}\n{s}{s}", .{ xml, inner_indent, try p.toXml(allocator) });
            }
            // Add memory region mappins
            for (pd.maps.items) |m| {
                xml = try allocPrint(allocator, "{s}\n{s}{s}", .{ xml, inner_indent, try m.toXml(allocator) });
            }
            // Add child PDs
            for (pd.child_pds.items) |child_pd| {
                xml = try allocPrint(allocator, "{s}\n{s}{s}", .{ xml, inner_indent, try child_pd.toXml(allocator, inner_indent, pd.next_avail_id) });
                pd.next_avail_id += 1;
            }
            // Add interrupts
            for (pd.irqs.items) |irq| {
                xml = try allocPrint(allocator, "{s}\n{s}{s}", .{ xml, inner_indent, try irq.toXml(allocator, pd.next_avail_id) });
                pd.next_avail_id += 1;
            }

            xml = try allocPrint(allocator, "{s}\n{s}</protection_domain>\n", .{ xml, indent });

            return xml;
        }
    };

    pub const Channel = struct {
        pd1: *ProtectionDomain,
        pd2: *ProtectionDomain,
        pd1_end_id: usize,
        pd2_end_id: usize,

        pub fn create(pd1: *ProtectionDomain, pd2: *ProtectionDomain) Channel {
            const ch = Channel {
                .pd1 = pd1,
                .pd2 = pd2,
                .pd1_end_id = pd1.next_avail_id,
                .pd2_end_id = pd2.next_avail_id,
            };
            pd1.next_avail_id += 1;
            pd2.next_avail_id += 1;

            return ch;
        }

        pub fn toXml(ch: Channel, allocator: Allocator) ![]const u8 {
            const channel_str =
                \\    <channel>
                \\        <end pd="{s}" id="{}" />
                \\        <end pd="{s}" id="{}" />
                \\    </channel>
            ;
            const channel_xml = try allocPrint(allocator, channel_str, .{ ch.pd1.name, ch.pd1_end_id, ch.pd2.name, ch.pd2_end_id });

            return channel_xml;
        }
    };

    pub const Interrupt = struct {
        name: []const u8,
        id: ?usize = null,
        irq: usize,
        trigger: Trigger,

        const Trigger = enum {
            edge,
            level
        };

        pub fn create(name: []const u8, irq: usize, trigger: Trigger) Interrupt {
            return Interrupt {
                .name = name,
                .irq = irq,
                .trigger = trigger
            };
        }

        pub fn toXml(interrupt: *const Interrupt, allocator: Allocator, id: usize) ![]const u8 {
            const irq_str =
                \\<irq id="{}" trigger="{s}" id="{}" />
            ;
            return try allocPrint(allocator, irq_str, .{ interrupt.irq, @tagName(interrupt.trigger), id });
        }
    };

    pub fn create(allocator: Allocator, arch: Arch) !SystemDescription {
        return SystemDescription {
            .arch = arch,
            .pds = ArrayList(*ProtectionDomain).init(allocator),
            .mrs = ArrayList(MemoryRegion).init(allocator),
            .channels = ArrayList(Channel).init(allocator),
        };
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
        var array = ArrayList(u8).init(allocator);
        var xml = array.writer();
        _ = try xml.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<system>\n");

        const indent = " " ** 4;
        for (sdf.mrs.items) |mr| {
            _ = try xml.write(try mr.toXml(allocator, indent, sdf.arch));
        }
        for (sdf.pds.items) |pd| {
            _ = try xml.write(try pd.toXml(allocator, indent, null));
        }
        for (sdf.channels.items) |ch| {
            _ = try xml.write(try ch.toXml(allocator));
        }

        _ = try xml.write("\n</system>\n");

        return array.items;
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
