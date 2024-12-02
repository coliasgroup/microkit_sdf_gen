const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const allocPrint = std.fmt.allocPrint;
const log = @import("log.zig");

// TODO: for addresses should we use the word size of the *target* machine, rather than 'usize' for everything?
// TODO: indent stuff could be done better

pub const SystemDescription = struct {
    /// Store the allocator used when creating the SystemDescirption so we
    /// can later deinit everything
    allocator: Allocator,
    /// Array holding all the bytes for the XML data
    xml_data: ArrayList(u8),
    /// We use the Writer standard library API to add to this xml_data array
    xml: ArrayList(u8).Writer,
    /// There are some architecture specific options
    arch: Arch,
    /// Protection Domains that should be exported
    pds: ArrayList(*ProtectionDomain),
    /// Memory Regions that should be exported
    mrs: ArrayList(MemoryRegion),
    /// Channels that should be exported
    channels: ArrayList(Channel),
    /// Highest allocatable physical address on the platform
    paddr_top: u64,

    /// Supported architectures by seL4
    pub const Arch = enum(c_int) {
        aarch32,
        aarch64,
        riscv32,
        riscv64,
        x86,
        x86_64,
    };

    pub const SetVar = struct {
        symbol: []const u8,
        name: []const u8,

        pub fn create(symbol: []const u8, mr: *const MemoryRegion) SetVar {
            return SetVar{
                .symbol = symbol,
                .name = mr.name,
            };
        }

        pub fn toXml(setvar: SetVar, sdf: *SystemDescription, writer: ArrayList(u8).Writer, separator: []const u8) !void {
            const xml = try allocPrint(sdf.allocator, "{s}<setvar symbol=\"{s}\" region_paddr=\"{s}\" />\n", .{ separator, setvar.symbol, setvar.name });
            defer sdf.allocator.free(xml);

            _ = try writer.write(xml);
        }
    };

    pub const MemoryRegion = struct {
        allocator: Allocator,
        name: []const u8,
        size: usize,
        paddr: ?u64,
        page_size: ?PageSize,

        const Options = struct {
            page_size: ?PageSize = null,
        };

        const OptionsPhysical = struct {
            paddr: ?u64 = null,
            page_size: ?PageSize = null,
        };

        // TODO: change to two API:
        // MemoryRegion.virtual()
        // MemoryRegion.physical()
        pub fn create(allocator: Allocator, name: []const u8, size: usize, options: Options) MemoryRegion {
            return MemoryRegion{
                .allocator = allocator,
                .name = allocator.dupe(u8, name) catch "Could not allocate name for MemoryRegion",
                .size = size,
                .page_size = options.page_size,
                .paddr = null,
            };
        }

        /// Creates a memory region at a specific physical address. Allocates the physical address automatically.
        pub fn physical(allocator: Allocator, sdf: *SystemDescription, name: []const u8, size: usize, options: OptionsPhysical) MemoryRegion {
            const paddr = if (options.paddr) |fixed_paddr| fixed_paddr else sdf.paddr_top - size;
            // TODO: handle alignment if people specify a page size.
            if (options.paddr == null) {
                sdf.paddr_top = paddr;
            }
            return MemoryRegion{
                .allocator = allocator,
                .name = allocator.dupe(u8, name) catch "Could not allocate name for MemoryRegion",
                .size = size,
                .paddr = paddr,
                .page_size = options.page_size,
            };
        }

        pub fn destroy(mr: MemoryRegion) void {
            mr.allocator.free(mr.name);
        }

        pub fn toXml(mr: MemoryRegion, sdf: *SystemDescription, writer: ArrayList(u8).Writer, separator: []const u8) !void {
            const xml = try allocPrint(sdf.allocator, "{s}<memory_region name=\"{s}\" size=\"0x{x}\"", .{ separator, mr.name, mr.size });
            defer sdf.allocator.free(xml);

            _ = try writer.write(xml);

            if (mr.paddr) |paddr| {
                const paddr_xml = try allocPrint(sdf.allocator, " phys_addr=\"0x{x}\"", .{paddr});
                defer sdf.allocator.free(paddr_xml);
                _ = try writer.write(paddr_xml);
            }

            if (mr.page_size) |page_size| {
                const page_size_xml = try allocPrint(sdf.allocator, " page_size=\"0x{x}\"", .{page_size.toInt(sdf.arch)});
                defer sdf.allocator.free(page_size_xml);
                _ = try writer.write(page_size_xml);
            }

            _ = try writer.write(" />\n");
        }

        pub const PageSize = enum(usize) {
            small,
            large,
            // huge,

            pub fn toInt(page_size: PageSize, arch: Arch) usize {
                // TODO: on RISC-V we are assuming that it's Sv39. For example if you
                // had a 64-bit system with Sv32, the page sizes would be different...
                switch (arch) {
                    .aarch64, .riscv64, .x86_64 => return switch (page_size) {
                        .small => 0x1000,
                        .large => 0x200000,
                        // .huge => 0x40000000,
                    },
                    .aarch32, .riscv32, .x86 => return switch (page_size) {
                        .small => 0x1000,
                        .large => 0x400000,
                        // .huge => 0x40000000,
                    },
                }
            }

            pub fn fromInt(page_size: usize, arch: Arch) !PageSize {
                switch (arch) {
                    .aarch64, .riscv64, .x86_64 => return switch (page_size) {
                        0x1000 => .small,
                        0x200000 => .large,
                        // 0x40000000 => .huge,
                        else => return error.InvalidPageSize,
                    },
                    .aarch32, .riscv32, .x86 => return switch (page_size) {
                        0x1000 => .small,
                        0x400000 => .large,
                        // 0x40000000 => .huge,
                        else => return error.InvalidPageSize,
                    },
                }
            }

            pub fn optimal(arch: Arch, region_size: usize) PageSize {
                // TODO would be better if we did some meta programming in case the
                // number of elements in PageSize change
                // if (region_size % PageSize.huge.toSize(sdf.arch) == 0) return .huge;
                if (region_size % PageSize.large.toInt(arch) == 0) return .large;

                return .small;
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

        const Options = struct {
            setvar_vaddr: ?[]const u8 = null,
        };

        pub const Permissions = packed struct {
            // TODO: check that perms are not write-only
            read: bool = false,
            write: bool = false,
            execute: bool = false,

            pub const r = Permissions{ .read = true };
            pub const x = Permissions{ .execute = true };
            pub const rw = Permissions{ .read = true, .write = true };
            pub const rx = Permissions{ .read = true, .execute = true };
            pub const rwx = Permissions{ .read = true, .write = true, .execute = true };

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
                if (write_count > 0) {
                    perms.write = true;
                }
                if (exec_count > 0) {
                    perms.execute = true;
                }

                return perms;
            }
        };

        // TODO: make vaddr optional so its easier to allocate it automatically
        pub fn create(mr: MemoryRegion, vaddr: usize, perms: Permissions, cached: bool, options: Options) Map {
            // const vaddr = if (options.vaddr) |fixed_vaddr| fixed_vaddr else ;
            return Map{
                .mr = mr,
                .vaddr = vaddr,
                .perms = perms,
                .cached = cached,
                .setvar_vaddr = options.setvar_vaddr,
            };
        }

        pub fn toXml(map: *const Map, sdf: *SystemDescription, writer: ArrayList(u8).Writer, separator: []const u8) !void {
            const mr_str =
                \\{s}<map mr="{s}" vaddr="0x{x}" perms="{s}" cached="{s}" />
                \\
            ;
            const mr_str_with_setvar =
                \\{s}<map mr="{s}" vaddr="0x{x}" perms="{s}" cached="{s}" setvar_vaddr="{s}" />
                \\
            ;
            // TODO: use null terminated pointer from Zig?
            var perms = [_]u8{0} ** 4;
            const i = map.perms.toString(&perms);

            const cached = if (map.cached) "true" else "false";
            var xml: []const u8 = undefined;
            if (map.setvar_vaddr) |setvar_vaddr| {
                xml = try allocPrint(sdf.allocator, mr_str_with_setvar, .{ separator, map.mr.name, map.vaddr, perms[0..i], cached, setvar_vaddr });
            } else {
                xml = try allocPrint(sdf.allocator, mr_str, .{ separator, map.mr.name, map.vaddr, perms[0..i], cached });
            }
            defer sdf.allocator.free(xml);

            _ = try writer.write(xml);
        }
    };

    pub const VirtualMachine = struct {
        name: []const u8,
        priority: u8 = 100,
        // TODO: this budget and period is worng, the period needs to be the same as
        // the budget
        budget: usize = 100,
        period: usize = 100,
        vcpus: []const Vcpu,
        maps: ArrayList(Map),

        const Vcpu = struct {
            id: usize,
            /// Physical core the vCPU will run on
            cpu: usize = 0,
        };

        pub fn create(allocator: Allocator, name: []const u8, vcpus: []const Vcpu) VirtualMachine {
            return VirtualMachine{
                .name = name,
                .vcpus = vcpus,
                .maps = ArrayList(Map).init(allocator),
            };
        }

        pub fn addMap(vm: *VirtualMachine, map: Map) void {
            vm.maps.append(map) catch @panic("Could not add Map to VirtualMachine");
        }

        pub fn destroy(vm: *VirtualMachine) void {
            vm.maps.deinit();
        }

        pub fn toXml(vm: *VirtualMachine, sdf: *SystemDescription, writer: ArrayList(u8).Writer, separator: []const u8) !void {
            const first_tag =
                \\{s}<virtual_machine name="{s}" priority="{}" budget="{}" period="{}" >
            ;
            const first_xml = try allocPrint(sdf.allocator, first_tag, .{ separator, vm.name, vm.priority, vm.budget, vm.period });
            defer sdf.allocator.free(first_xml);
            _ = try writer.write(first_xml);
            _ = try writer.write("\n");

            // Add memory region mappings as child nodes
            const child_separator = try allocPrint(sdf.allocator, "{s}    ", .{separator});
            defer sdf.allocator.free(child_separator);

            for (vm.vcpus) |vcpu| {
                const vcpu_xml = try allocPrint(sdf.allocator, "{s}<vcpu id=\"{}\" cpu=\"{}\" />", .{ child_separator, vcpu.id, vcpu.cpu });
                defer sdf.allocator.free(vcpu_xml);
                _ = try writer.write(vcpu_xml);
                _ = try writer.write("\n");
            }

            for (vm.maps.items) |map| {
                try map.toXml(sdf, writer, child_separator);
            }

            const closing_tag =
                \\{s}</virtual_machine>
            ;
            const closing_xml = try allocPrint(sdf.allocator, closing_tag, .{separator});
            defer sdf.allocator.free(closing_xml);
            _ = try writer.write(closing_xml);
            _ = try writer.write("\n");
        }
    };

    pub const ProtectionDomain = struct {
        name: []const u8,
        /// Program ELF
        program_image: ?[]const u8,
        /// Scheduling parameters
        /// The policy here is to follow the default values that Microkit uses.
        priority: u8,
        budget: usize,
        period: usize,
        passive: bool,
        stack_size: usize,
        /// Memory mappings
        maps: ArrayList(Map),
        /// The length of this array is bound by the maximum number of child PDs a PD can have.
        child_pds: ArrayList(*ProtectionDomain),
        /// The length of this array is bound by the maximum number of IRQs a PD can have.
        irqs: ArrayList(Interrupt),
        vm: ?*VirtualMachine,
        /// Keeping track of what IDs are available for channels, IRQs, etc
        ids: std.bit_set.StaticBitSet(MAX_IDS),
        /// Whether or not ARM SMC is available
        arm_smc: bool,
        /// If this PD is a child of another PD, this ID identifies it to its parent PD
        child_id: ?usize,

        setvars: ArrayList(SetVar),

        // Matches Microkit implementation
        const MAX_IDS = 62;
        const MAX_IRQS = MAX_IDS;
        const MAX_CHILD_PDS = MAX_IDS;

        const Options = struct {
            passive: bool = false,
            priority: u8 = 100,
            budget: ?usize = null,
            period: ?usize = null,
            stack_size: usize = 0x1000,
            arm_smc: bool = false,
        };

        pub fn create(allocator: Allocator, name: []const u8, program_image: ?[]const u8, options: Options) ProtectionDomain {
            const budget = if (options.budget) |budget| budget else 100;
            const period = if (options.period) |period| period else budget;

            return ProtectionDomain{
                .name = name,
                .program_image = program_image,
                .maps = ArrayList(Map).init(allocator),
                .child_pds = ArrayList(*ProtectionDomain).initCapacity(allocator, MAX_CHILD_PDS) catch @panic("Could not allocate child_pds"),
                .irqs = ArrayList(Interrupt).initCapacity(allocator, MAX_IRQS) catch @panic("Could not allocate irqs"),
                .vm = null,
                .ids = std.bit_set.StaticBitSet(MAX_IDS).initEmpty(),
                .setvars = ArrayList(SetVar).init(allocator),
                .priority = options.priority,
                .passive = options.passive,
                .budget = budget,
                .period = period,
                .arm_smc = options.arm_smc,
                .stack_size = options.stack_size,
                .child_id = null,
            };
        }

        pub fn destroy(pd: *ProtectionDomain) void {
            pd.maps.deinit();
            pd.child_pds.deinit();
            for (pd.child_pds.items) |child_pd| {
                child_pd.destroy();
            }
            if (pd.vm) |vm| {
                vm.destroy();
            }
            pd.irqs.deinit();
        }

        /// There may be times where PD resources with an ID, such as a channel
        /// or IRQ require a fixed ID while others do not. One example might be
        /// that an IRQ needs to be at a particular ID while the channel numbers
        /// do not matter.
        /// This function is used to allocate an ID for use by one of those
        /// resources ensuring there are no clashes or duplicates.
        pub fn allocateId(pd: *ProtectionDomain, id: ?usize) !usize {
            if (id) |chosen_id| {
                if (pd.ids.isSet(chosen_id)) {
                    log.err("attempting to allocate id '{}' in PD '{s}'", .{ chosen_id, pd.name });
                    return error.AlreadyAllocatedId;
                } else {
                    pd.ids.setValue(chosen_id, true);
                    return chosen_id;
                }
            } else {
                for (0..MAX_IDS) |i| {
                    if (!pd.ids.isSet(i)) {
                        pd.ids.setValue(i, true);
                        return i;
                    }
                }

                return error.NoMoreIds;
            }
        }

        pub fn setVirtualMachine(pd: *ProtectionDomain, vm: *VirtualMachine) !void {
            if (pd.vm != null) return error.ProtectionDomainAlreadyHasVirtualMachine;
            pd.vm = vm;
        }

        pub fn addMap(pd: *ProtectionDomain, map: Map) void {
            pd.maps.append(map) catch @panic("Could not add Map to ProtectionDomain");
        }

        pub fn addInterrupt(pd: *ProtectionDomain, irq: Interrupt) !usize {
            // If the IRQ ID is already set, then we check that we can allocate it with
            // the PD.
            if (irq.id) |id| {
                _ = try pd.allocateId(id);
                try pd.irqs.append(irq);
                return id;
            } else {
                var irq_with_id = irq;
                irq_with_id.id = try pd.allocateId(null);
                try pd.irqs.append(irq_with_id);
                return irq_with_id.id.?;
            }
        }

        pub fn addSetVar(pd: *ProtectionDomain, setvar: SetVar) void {
            pd.setvars.append(setvar) catch @panic("Could not add SetVar to ProtectionDomain");
        }

        pub fn addChild(pd: *ProtectionDomain, child: *ProtectionDomain) !usize {
            try pd.child_pds.append(child);
            child.child_id = try pd.allocateId(null);
            return child.child_id.?;
        }

        // TODO: get rid of this extra arg?
        pub fn getMapVaddr(pd: *ProtectionDomain, mr: *const MemoryRegion) usize {
            // TODO: should make sure we don't have a way of giving an invalid vaddr back (e.g on 32-bit systems this is more of a concern)

            // The approach for this is fairly simple and naive, we just loop
            // over all the maps and find the largest next available address.
            // We could extend this in the future to actually look for space
            // between mappings in the case they are not just sorted.
            var next_vaddr: usize = 0x20_000_000;
            for (pd.maps.items) |map| {
                if (map.vaddr >= next_vaddr) {
                    next_vaddr = map.vaddr + map.mr.size;
                    // TODO: fix this
                    const page_size = MemoryRegion.PageSize.optimal(.aarch64, mr.size).toInt(.aarch64);
                    // TODO: Use builtins like @rem
                    const diff = next_vaddr % page_size;
                    if (diff != 0) {
                        // In the case the next virtual address is not page aligned, we need
                        // to increase it further.
                        next_vaddr += page_size - diff;
                    }
                }
            }

            return next_vaddr;
        }

        pub fn toXml(pd: *ProtectionDomain, sdf: *SystemDescription, writer: ArrayList(u8).Writer, separator: []const u8, id: ?usize) !void {
            // If we are given an ID, this PD is in fact a child PD and we have to
            // specify the ID for the root PD to use when referring to this child PD.
            // TODO: simplify this whole logic, it's quite messy right now
            // TODO: find a better way of caluclating the period
            const attributes_str =
                \\priority="{}" budget="{}" period="{}" passive="{}" stack_size="0x{x}" smc="{}"
            ;
            const attributes_xml = try allocPrint(sdf.allocator, attributes_str, .{ pd.priority, pd.budget, pd.period, pd.passive, pd.stack_size, pd.arm_smc });
            defer sdf.allocator.free(attributes_xml);
            var top: []const u8 = undefined;
            if (id) |id_val| {
                top = try allocPrint(sdf.allocator, "{s}<protection_domain name=\"{s}\" id=\"{}\" {s}>\n", .{ separator, pd.name, id_val, attributes_xml });
            } else {
                top = try allocPrint(sdf.allocator, "{s}<protection_domain name=\"{s}\" {s}>\n", .{ separator, pd.name, attributes_xml });
            }
            defer sdf.allocator.free(top);
            _ = try writer.write(top);

            const child_separator = try allocPrint(sdf.allocator, "{s}    ", .{separator});
            defer sdf.allocator.free(child_separator);
            // Add program image (if we have one)
            if (pd.program_image) |program_image| {
                const image_xml = try allocPrint(sdf.allocator, "{s}<program_image path=\"{s}\" />\n", .{ child_separator, program_image });
                defer sdf.allocator.free(image_xml);
                _ = try writer.write(image_xml);
            }
            // Add memory region mappins
            for (pd.maps.items) |map| {
                try map.toXml(sdf, writer, child_separator);
            }
            // Add child PDs
            for (pd.child_pds.items) |child_pd| {
                try child_pd.toXml(sdf, writer, child_separator, child_pd.child_id.?);
            }
            // Add virtual machine (if we have one)
            if (pd.vm) |vm| {
                try vm.toXml(sdf, writer, child_separator);
            }
            // Add interrupts
            for (pd.irqs.items) |irq| {
                try irq.toXml(sdf, writer, child_separator);
            }
            // Add setvars
            for (pd.setvars.items) |setvar| {
                try setvar.toXml(sdf, writer, child_separator);
            }

            const bottom = try allocPrint(sdf.allocator, "{s}</protection_domain>\n", .{separator});
            defer sdf.allocator.free(bottom);
            _ = try writer.write(bottom);
        }
    };

    // TODO: add options for fixed channel ID
    pub const Channel = struct {
        pd_a: *ProtectionDomain,
        pd_b: *ProtectionDomain,
        pd_a_id: usize,
        pd_b_id: usize,
        pd_a_notify: bool,
        pd_b_notify: bool,
        pp: ?End,

        const End = enum { a, b };

        const Options = struct {
            pd_a_notify: bool = true,
            pd_b_notify: bool = true,
            pp: ?End = null,
            pd_a_id: ?usize = null,
            pd_b_id: ?usize = null,
        };

        pub fn create(pd_a: *ProtectionDomain, pd_b: *ProtectionDomain, options: Options) Channel {
            return .{
                .pd_a = pd_a,
                .pd_b = pd_b,
                .pd_a_id = pd_a.allocateId(options.pd_a_id) catch @panic("Could not allocate ID for channel"),
                .pd_b_id = pd_b.allocateId(options.pd_b_id) catch @panic("Could not allocate ID for channel"),
                .pd_a_notify = options.pd_a_notify,
                .pd_b_notify = options.pd_b_notify,
                .pp = options.pp,
            };
        }

        pub fn toXml(ch: Channel, sdf: *SystemDescription, writer: ArrayList(u8).Writer, separator: []const u8) !void {
            const child_separator = try allocPrint(sdf.allocator, "{s}    ", .{separator});
            defer sdf.allocator.free(child_separator);
            const channel_str =
                \\{s}<channel>{s}{s}<end pd="{s}" id="{}" notify="{}" pp="{}" />{s}{s}<end pd="{s}" id="{}" notify="{}" pp="{}" />{s}{s}</channel>
            ;

            const pp_end_a = if (ch.pp) |pp| pp == .a else false;
            const pp_end_b = if (ch.pp) |pp| pp == .b else false;

            const channel_xml = try allocPrint(sdf.allocator, channel_str, .{ separator, "\n", child_separator, ch.pd_a.name, ch.pd_a_id, ch.pd_a_notify, pp_end_a, "\n", child_separator, ch.pd_b.name, ch.pd_b_id, ch.pd_b_notify, pp_end_b, "\n", separator });
            defer sdf.allocator.free(channel_xml);

            _ = try writer.write(channel_xml);
            _ = try writer.write("\n");
        }
    };

    pub const Interrupt = struct {
        id: ?usize = null,
        /// IRQ number that will be registered with seL4. That means that this
        /// number needs to map onto what seL4 observes (e.g the numbers in the
        /// device tree do not necessarily map onto what seL4 sees on ARM).
        irq: usize,
        // TODO: there is a potential edge-case. There exist platforms
        // supported by seL4 that do not allow for an IRQ trigger to be set.
        trigger: Trigger,

        pub const Trigger = enum { edge, level };

        pub fn create(irq: usize, trigger: Trigger, id: ?usize) Interrupt {
            return Interrupt{ .irq = irq, .trigger = trigger, .id = id };
        }

        pub fn toXml(irq: *const Interrupt, sdf: *SystemDescription, writer: ArrayList(u8).Writer, separator: []const u8) !void {
            // By the time we get here, something should have populated the 'id' field.
            std.debug.assert(irq.id != null);

            const irq_str =
                \\{s}<irq irq="{}" trigger="{s}" id="{}" />
            ;

            const irq_xml = try allocPrint(sdf.allocator, irq_str, .{ separator, irq.irq, @tagName(irq.trigger), irq.id.? });
            defer sdf.allocator.free(irq_xml);

            _ = try writer.write(irq_xml);
            _ = try writer.write("\n");
        }
    };

    pub fn create(allocator: Allocator, arch: Arch, paddr_top: u64) SystemDescription {
        var xml_data = ArrayList(u8).init(allocator);
        return SystemDescription{
            .allocator = allocator,
            .xml_data = xml_data,
            .xml = xml_data.writer(),
            .arch = arch,
            .pds = ArrayList(*ProtectionDomain).init(allocator),
            .mrs = ArrayList(MemoryRegion).init(allocator),
            .channels = ArrayList(Channel).init(allocator),
            .paddr_top = paddr_top,
        };
    }

    pub fn destroy(sdf: *SystemDescription) void {
        for (sdf.pds.items) |pd| pd.destroy();
        sdf.pds.deinit();
        for (sdf.mrs.items) |mr| mr.destroy();
        sdf.mrs.deinit();
        sdf.channels.deinit();
        sdf.xml_data.deinit();
    }

    pub fn addChannel(sdf: *SystemDescription, channel: Channel) void {
        sdf.channels.append(channel) catch @panic("Could not add Channel to SystemDescription");
    }

    pub fn addMemoryRegion(sdf: *SystemDescription, mr: MemoryRegion) void {
        sdf.mrs.append(mr) catch @panic("Could not add MemoryRegion to SystemDescription");
    }

    pub fn addProtectionDomain(sdf: *SystemDescription, protection_domain: *ProtectionDomain) void {
        sdf.pds.append(protection_domain) catch @panic("Could not add ProtectionDomain to SystemDescription");
    }

    pub fn addPd(sdf: *SystemDescription, name: []const u8, program_image: ?[]const u8) ProtectionDomain {
        var pd = ProtectionDomain.create(sdf, name, program_image);
        sdf.addProtectionDomain(&pd);

        return pd;
    }

    pub fn findPd(sdf: *SystemDescription, name: []const u8) ?*ProtectionDomain {
        for (sdf.pds.items) |pd| {
            if (std.mem.eql(u8, name, pd.name)) {
                return pd;
            }
        }

        return null;
    }

    pub fn toXml(sdf: *SystemDescription) ![:0]const u8 {
        const writer = sdf.xml_data.writer();
        _ = try writer.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<system>\n");

        // Use 4-space indent for the XML
        const separator = "    ";
        for (sdf.mrs.items) |mr| {
            try mr.toXml(sdf, writer, separator);
        }
        for (sdf.pds.items) |pd| {
            try pd.toXml(sdf, writer, separator, null);
        }
        for (sdf.channels.items) |ch| {
            try ch.toXml(sdf, writer, separator);
        }

        // Given that this is library code, it is better for us to provide a zero-terminated
        // array of bytes for consumption by langauges like C.
        _ = try writer.write("</system>" ++ "\x00");

        return sdf.xml_data.items[0 .. sdf.xml_data.items.len - 1 :0];
    }

    pub fn print(sdf: *SystemDescription) !void {
        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll(try sdf.toXml());
        try stdout.writeAll("\n");
    }
};
