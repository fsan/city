const std = @import("std");
const city = @import("city");

// A top-down plan drawn at one pixel per metre, so the street pattern can be
// inspected as an image: water, ground, the road ribbons the renderer draws,
// and every building footprint. Pure P6 PPM, no dependencies.
const w: usize = 1320;
const h: usize = 1040;

var pixels: [w * h * 3]u8 = undefined;

fn set(x: usize, z: usize, c: [3]u8) void {
    if (x >= w or z >= h) return;
    const off = (z * w + x) * 3;
    pixels[off] = c[0];
    pixels[off + 1] = c[1];
    pixels[off + 2] = c[2];
}

fn disc(cx: f32, cz: f32, radius: f32, c: [3]u8) void {
    const x0: usize = if (cx - radius < 0) 0 else @intFromFloat(cx - radius);
    const x1: usize = if (cx + radius > @as(f32, w - 1)) w - 1 else @intFromFloat(cx + radius);
    const z0: usize = if (cz - radius < 0) 0 else @intFromFloat(cz - radius);
    const z1: usize = if (cz + radius > @as(f32, h - 1)) h - 1 else @intFromFloat(cz + radius);
    var z = z0;
    while (z <= z1) : (z += 1) {
        var x = x0;
        while (x <= x1) : (x += 1) {
            const dx = @as(f32, @floatFromInt(x)) + 0.5 - cx;
            const dz = @as(f32, @floatFromInt(z)) + 0.5 - cz;
            if (dx * dx + dz * dz <= radius * radius) set(x, z, c);
        }
    }
}

pub fn main() !void {
    const out = std.io.getStdOut().writer();
    city.init();

    // Ground, then water, then roads, then buildings.
    for (0..h) |z| for (0..w) |x| set(x, z, .{ 0xee, 0xee, 0xe8 });
    for (0..h) |z| for (0..w) |x| {
        const fx = @as(f32, @floatFromInt(x)) + 0.5;
        const fz = @as(f32, @floatFromInt(z)) + 0.5;
        if (city.River.count > 0 and city.River.inside(fx, fz)) set(x, z, .{ 0x8c, 0xb8, 0xd8 });
    };
    for (city.roads, 0..) |r, id| {
        const a = city.nodes[r.a];
        const b = city.nodes[r.b];
        const len = city.hypot(b.x - a.x, b.z - a.z);
        const steps: usize = @max(1, @as(usize, @intFromFloat(@ceil(len / 1.0))));
        const own: [3]u8 = if (r.street == city.bridge_street) .{ 0x22, 0x22, 0x22 } else if (r.class == 2) .{ 0x33, 0x33, 0x33 } else .{ 0x55, 0x55, 0x55 };
        var k: usize = 0;
        while (k <= steps) : (k += 1) {
            const t = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(steps));
            disc(a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t, 1.6, own);
        }
        _ = id;
    }
    for (city.nodes[0..city.node_count]) |n| disc(n.x, n.z, 2.7, .{ 0x22, 0x22, 0x22 });
    for (&city.buildings) |b| {
        if (b.kind == .vacant) continue;
        const x0: usize = @intFromFloat(@max(0, b.x));
        const x1: usize = @intFromFloat(@min(@as(f32, w - 1), b.x + b.width));
        const z0: usize = @intFromFloat(@max(0, b.z));
        const z1: usize = @intFromFloat(@min(@as(f32, h - 1), b.z + b.depth));
        const c: [3]u8 = switch (b.kind) {
            .home => .{ 0xc0, 0x60, 0x50 },
            .shop => .{ 0xd0, 0xa0, 0x40 },
            .office, .clinic, .hall => .{ 0x60, 0x60, 0xb0 },
            .depot => .{ 0x80, 0x40, 0x80 },
            else => .{ 0x50, 0x90, 0x50 },
        };
        var z = z0;
        while (z <= z1) : (z += 1) {
            var x = x0;
            while (x <= x1) : (x += 1) set(x, z, c);
        }
    }

    var file = try std.fs.cwd().createFile("plan.ppm", .{});
    defer file.close();
    try file.writer().print("P6\n{d} {d}\n255\n", .{ w, h });
    try file.writeAll(&pixels);
    try out.print("wrote plan.ppm {d}x{d}, nodes={d} roads={d}\n", .{ w, h, city.node_count, city.road_count });
}
