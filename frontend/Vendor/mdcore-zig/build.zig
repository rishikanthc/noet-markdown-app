const std = @import("std");

fn configureCmark(module: *std.Build.Module, b: *std.Build, cmark_prefix: []const u8) void {
    module.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{cmark_prefix}) });
    module.linkSystemLibrary("cmark-gfm-extensions", .{ .preferred_link_mode = .static });
    module.linkSystemLibrary("cmark-gfm", .{ .preferred_link_mode = .static });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const cmark_prefix = b.option([]const u8, "cmark-prefix", "Installed cmark-gfm prefix") orelse "vendor/cmark-gfm/install";

    const core_module = b.createModule(.{
        .root_source_file = b.path("src/api.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    configureCmark(core_module, b, cmark_prefix);

    const library = b.addLibrary(.{
        .name = "mdcore",
        .linkage = .static,
        .root_module = core_module,
    });
    b.installArtifact(library);
    b.getInstallStep().dependOn(&b.addInstallHeaderFile(b.path("include/mdcore.h"), "mdcore.h").step);
    b.getInstallStep().dependOn(&b.addInstallHeaderFile(b.path("include/module.modulemap"), "module.modulemap").step);

    const renderer_module = b.createModule(.{
        .root_source_file = b.path("src/render_cli.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    configureCmark(renderer_module, b, cmark_prefix);
    const renderer = b.addExecutable(.{
        .name = "mdcore-render",
        .root_module = renderer_module,
    });
    b.installArtifact(renderer);

    const run_renderer = b.addRunArtifact(renderer);
    if (@hasField(std.Build, "args")) {
        if (@field(b, "args")) |args| run_renderer.addArgs(args);
    }
    const run_step = b.step("run", "Run mdcore-render");
    run_step.dependOn(&run_renderer.step);

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/api.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    configureCmark(test_module, b, cmark_prefix);
    const unit_tests = b.addTest(.{ .root_module = test_module });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const c_smoke = b.addExecutable(.{
        .name = "mdcore-c-smoke",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    c_smoke.root_module.addCSourceFile(.{
        .file = b.path("tests/c_abi_smoke.c"),
        .flags = &.{"-std=c11"},
    });
    c_smoke.root_module.addIncludePath(b.path("include"));
    c_smoke.root_module.linkLibrary(library);
    configureCmark(c_smoke.root_module, b, cmark_prefix);
    const run_c_smoke = b.addRunArtifact(c_smoke);

    const test_step = b.step("test", "Run Zig unit tests and C ABI smoke test");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_c_smoke.step);

    const conformance = b.addSystemCommand(&.{ "python3", "tests/conformance.py", "--renderer" });
    conformance.addArtifactArg(renderer);
    conformance.addArgs(&.{
        "vendor/cmark-gfm/src/test/spec.txt",
        "vendor/cmark-gfm/src/test/extensions.txt",
    });
    const conformance_step = b.step("conformance", "Run upstream CommonMark and GFM examples");
    conformance_step.dependOn(&conformance.step);
}
