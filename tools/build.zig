const std = @import("std");
pub fn build(b: *std.Build) void {
    const city = b.createModule(.{ .root_source_file = b.path("../src/scene/city.zig") });
    const exe = b.addExecutable(.{
        .name = "inspect",
        .root_module = b.createModule(.{
            .root_source_file = b.path("inspect.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
            .imports = &.{.{ .name = "city", .module = city }},
        }),
    });
    b.installArtifact(exe);
    const map_exe = b.addExecutable(.{
        .name = "map",
        .root_module = b.createModule(.{
            .root_source_file = b.path("map.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
            .imports = &.{.{ .name = "city", .module = city }},
        }),
    });
    b.installArtifact(map_exe);

}
