/// set this to true to link libc
const should_link_libc = false;

const PROBLEMS_NUM = 856;

const required_zig_version = std.SemanticVersion.parse("0.12.0-dev.2750+5f9255829") catch unreachable;

fn linkObject(b: *Build, obj: *CompileStep) void {
    if (should_link_libc) obj.linkLibC();
    _ = b;

    // Add linking for packages or third party libraries here
}

pub fn build(b: *Build) void {
    if (comptime @import("builtin").zig_version.order(required_zig_version) == .lt) {
        std.debug.print("Warning: Your version of Zig too old. You will need to download a newer build\n", .{});
        std.os.exit(1);
    }

    const target = b.standardTargetOptions(.{});
    const mode = b.standardOptimizeOption(.{});

    const install_all = b.step("install_all", "Install all problems");
    const run_all = b.step("run_all", "Run all problems");

    const generate = b.step("generate", "Generate stub files from template/template.zig");
    const build_generate = b.addExecutable(.{
        .name = "generate",
        .root_source_file = .{ .path = "template/generate.zig" },
        .target = target,
        .optimize = .ReleaseSafe,
    });

    const exe_options = b.addOptions();
    build_generate.root_module.addOptions("build_options", exe_options);

    const problem_num: u32 = b.option(u32, "problem-num", "How many problems to generate") orelse PROBLEMS_NUM;

    exe_options.addOption(u32, "problem_num", problem_num);

    const run_generate = b.addRunArtifact(build_generate);
    run_generate.setCwd(.{ .path = std.fs.path.dirname(@src().file).? });
    generate.dependOn(&run_generate.step);

    // Set up an exe for each problem
    var problem: u32 = 1;
    while (problem <= problem_num) : (problem += 1) {
        const problemString = b.fmt("problem{:0>3}", .{problem});
        const zigFile = b.fmt("src/{s}.zig", .{problemString});

        const exe = b.addExecutable(.{
            .name = problemString,
            .root_source_file = .{ .path = zigFile },
            .target = target,
            .optimize = mode,
        });
        linkObject(b, exe);

        const install_cmd = b.addInstallArtifact(exe, .{});

        const build_test = b.addTest(.{
            .root_source_file = .{ .path = zigFile },
            .target = target,
            .optimize = mode,
        });
        linkObject(b, build_test);

        const run_test = b.addRunArtifact(build_test);

        {
            const step_key = b.fmt("install_{s}", .{problemString});
            const step_desc = b.fmt("Install {s}.exe", .{problemString});
            const install_step = b.step(step_key, step_desc);
            install_step.dependOn(&install_cmd.step);
            install_all.dependOn(&install_cmd.step);
        }

        {
            const step_key = b.fmt("test_{s}", .{problemString});
            const step_desc = b.fmt("Run tests in {s}", .{zigFile});
            const step = b.step(step_key, step_desc);
            step.dependOn(&run_test.step);
        }

        const run_cmd = b.addRunArtifact(exe);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_desc = b.fmt("Run {s}", .{problemString});
        const run_step = b.step(problemString, run_desc);
        run_step.dependOn(&run_cmd.step);
        run_all.dependOn(&run_cmd.step);
    }

    // Set up tests for util.zig
    {
        const test_util = b.step("test_util", "Run tests in util.zig");
        const test_cmd = b.addTest(.{
            .root_source_file = .{ .path = "src/util.zig" },
            .target = target,
            .optimize = mode,
        });
        linkObject(b, test_cmd);
        test_util.dependOn(&test_cmd.step);
    }
}

const std = @import("std");

const Build = std.Build;
const CompileStep = std.Build.Step.Compile;
