const std = @import("std");
const sep = std.fs.path.sep_str;

const builtin = @import("builtin");

const exe_name = "bytec";

const pkg_folder = "pkg";

const targets: []const std.Target.Query = &.{
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .aarch64, .os_tag = .linux },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .x86_64, .os_tag = .windows },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

const imports: [1][]const u8 = .{
    "clap",
};

fn addImports(b: *std.Build, root: *std.Build.Module, args: anytype) void {
    for (imports) |import| {
        root.addImport(import, b.dependency(import, args).module(import));
    }
}

fn addProjectZon(b: *std.Build, root: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const build_zig_zon = b.createModule(.{
        .root_source_file = b.path("build.zig.zon"),
        .target = target,
        .optimize = optimize,
    });

    root.addImport("build.zig.zon", build_zig_zon);
}

pub fn build(b: *std.Build) !void {
    const native_only = b.option(bool, "native-only", "Only build the native target of the current OS/arch") orelse false;

    const optimize = std.builtin.OptimizeMode.Debug;

    if (native_only) {
        const resolved_target = b.resolveTargetQuery(.{});

        const exe = b.addExecutable(.{
            .name = exe_name,
            .root_source_file = b.path("src" ++ sep ++ "main.zig"),
            .target = resolved_target,
            .optimize = optimize,
        });

        addProjectZon(b, exe.root_module, resolved_target, optimize);
        addImports(b, exe.root_module, .{ .optimize = optimize });

        const target_output = b.addInstallArtifact(exe, .{
            .dest_dir = .{
                .override = .{
                    .custom = "",
                },
            },
        });

        b.getInstallStep().dependOn(&target_output.step);

        const run_exe = b.addRunArtifact(exe);

        const step = b.step("run", "Run the application");
        step.dependOn(&run_exe.step);

        const tests = b.createModule(.{
            .root_source_file = b.path("src" ++ sep ++ "tests.zig"),
            .target = resolved_target,
            .optimize = optimize,
        });

        const unit_tests = b.addTest(.{
            .root_module = tests,
        });

        const run_unit_tests = b.addRunArtifact(unit_tests);

        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_unit_tests.step);
    } else {
        const test_step = b.step("test", "Run unit tests");

        const package = b.step("pack", "Package the executables into zip files");

        const rm_pkg = b.addSystemCommand(&.{ "rm", "-rf", pkg_folder });

        const mkdir_pkg = b.addSystemCommand(&.{ "mkdir", pkg_folder });
        mkdir_pkg.step.dependOn(&rm_pkg.step);

        for (targets) |t| {
            const resolved_target = b.resolveTargetQuery(t);

            const exe = b.addExecutable(.{
                .name = exe_name,
                .root_source_file = b.path("src" ++ sep ++ "main.zig"),
                .target = resolved_target,
                .optimize = optimize,
            });

            addProjectZon(b, exe.root_module, resolved_target, optimize);
            addImports(b, exe.root_module, .{ .target = resolved_target, .optimize = optimize });

            const target_triple = try t.zigTriple(b.allocator);

            const target_output = b.addInstallArtifact(exe, .{
                .dest_dir = .{
                    .override = .{
                        .custom = target_triple,
                    },
                },
            });

            b.getInstallStep().dependOn(&target_output.step);

            const move_output = b.addSystemCommand(&.{
                "mv",
                try std.fmt.allocPrint(b.allocator, "zig-out" ++ sep ++ "{s}", .{target_triple}),
                ".",
            });

            move_output.step.dependOn(b.getInstallStep());

            const zip = b.addSystemCommand(&.{
                "zip",
                "-r",
                try std.fmt.allocPrint(b.allocator, "{s}" ++ sep ++ "{s}.zip", .{ pkg_folder, target_triple }),
                target_triple,
            });

            zip.step.dependOn(&mkdir_pkg.step);
            zip.step.dependOn(&move_output.step);

            const rm_exe = b.addSystemCommand(&.{ "rm", "-rf", target_triple });
            rm_exe.step.dependOn(&zip.step);

            package.dependOn(&rm_exe.step);

            if (t.os_tag == builtin.os.tag and t.cpu_arch == builtin.cpu.arch) {
                const tests = b.createModule(.{
                    .root_source_file = b.path("src" ++ sep ++ "tests.zig"),
                    .target = resolved_target,
                    .optimize = optimize,
                });

                const unit_tests = b.addTest(.{
                    .root_module = tests,
                });

                const run_unit_tests = b.addRunArtifact(unit_tests);

                test_step.dependOn(&run_unit_tests.step);
            }
        }
    }
}
