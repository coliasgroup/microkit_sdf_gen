const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dtbzig_dep = b.dependency("dtbzig", .{});

    const lib = b.addStaticLibrary(.{
        .name = "microkit_sdf_gen",
        .root_source_file = .{ .path = "src/sdf.zig" },
        .target = target,
        .optimize = optimize,
    });

    const sdfgen_step = b.step("sdfgen", "Utility for testing and developing examples of SDF auto-generation");
    const sdfgen = b.addExecutable(.{
        .name = "sdfgen",
        .root_source_file = .{ .path = "src/sdfgen.zig" },
        .target = target,
        .optimize = optimize,
    });

    // We want to be able to import the 'dtb.zig' library as a module.
    const dtb_module = dtbzig_dep.module("dtb");
    sdfgen.addModule("dtb", dtb_module);

    const sdfgen_cmd = b.addRunArtifact(sdfgen);
    if (b.args) |args| {
        sdfgen_cmd.addArgs(args);
    }

    sdfgen_step.dependOn(&sdfgen_cmd.step);
    const sdfgen_install = b.addInstallArtifact(sdfgen, .{});
    sdfgen_step.dependOn(&sdfgen_install.step);

    b.installArtifact(lib);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/test.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_main_tests.step);

    const modsdf = b.addModule("sdf", .{ .source_file = .{ .path = "src/sdf.zig" } });

    const pysdfgen_bin = b.option([]const u8, "pysdfgen-emit", "Name of pysdfgen library") orelse "pysdfgen.so";
    const pysdfgen = b.addSharedLibrary(.{
        .name = "pysdfgen",
        .root_source_file = .{ .path = "python/sdfgen_module.zig" },
        .target = target,
        .optimize = optimize,
    });
    pysdfgen.addIncludePath(.{ .path = "/usr/include/python3.10" });
    pysdfgen.addModule("sdf", modsdf);
    pysdfgen.linkLibC();
    // TODO: should probably check if the library exists first...
    pysdfgen.linkSystemLibrary("python3");
    b.installArtifact(pysdfgen);

    const pysdfgen_step = b.step("pysdfgen", "Library for the Python sdfgen module");
    const pysdfgen_install = b.addInstallFileWithDir(pysdfgen.getOutputSource(), .lib, pysdfgen_bin);
    pysdfgen_step.dependOn(&pysdfgen_install.step);
}
