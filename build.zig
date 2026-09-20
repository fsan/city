const std = @import("std");
pub fn build(b: *std.Build) void {
    const game = b.addExecutable(.{
        .name = "city",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
            .optimize = b.standardOptimizeOption(.{}),
        }),
    });
    game.entry = .disabled;
    game.rdynamic = true;
    b.installArtifact(game);
}
