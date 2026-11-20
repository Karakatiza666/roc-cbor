const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const zbor = b.dependency("zbor", .{ .target = target, .optimize = .ReleaseFast });
    const mod = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
    });
    mod.addImport("zbor", zbor.module("zbor"));
    b.installArtifact(b.addExecutable(.{ .name = "cbor-bench", .root_module = mod }));
}
