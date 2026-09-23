const std = @import("std");

// Slice 13: the Tiber-like river that runs through the seeded town.
//
// The module is deliberately data-first and imports nothing, so the scene can
// drive it while the scene is being built and so a future water-flow or weather
// module can depend on the river alone.
//
// What exists today: an authored centreline with a pronounced bend, a
// half-width, a water surface level, a bed depth and a discharge per point, and
// the geometry helpers the rest of the game needs (`inside`, `nearest`,
// `crosses`, `surfaceAt`). The only gameplay effect is impassability: the
// channel is carved into the terrain, no building or street may stand in the
// water, and the only roads that cross are the seeded bridges.
//
// What the fields are for: `flow_factor` and `discharges` are read by nothing
// yet. The weather system planned for a later slice will drive them; rising
// discharge will raise `levels`, which raises the water surface, floods the low
// bank and can eventually close a bridge. Keep them as the only inputs a flow
// model needs to write, and keep the surface a plain function of them.

pub const Vec = struct { x: f32, z: f32 };

// The channel is a polyline of at most forty points; the authored curve below
// uses fewer. The arrays are parallel.
pub const max_points = 40;
pub var count: usize = 0;
pub var points: [max_points]Vec = undefined;
pub var half_width: [max_points]f32 = undefined;
pub var levels: [max_points]f32 = undefined;
pub var discharges: [max_points]f32 = undefined;
pub var length: f32 = 0;

// Bounded shape constants. The bank is the sloping ground between the water
// edge and the ordinary terrain, and it is what the carve ramps through.
pub const bank_width: f32 = 15;
pub const bank_height: f32 = 2.6;
pub const depth: f32 = 4.6;

// Future weather input. A flow model raises this above one to swell the river;
// nothing reads it yet, so the river is statically unchanged.
pub var flow_factor: f32 = 1;

const control = [_]Vec{
    .{ .x = 712, .z = 16 }, .{ .x = 664, .z = 120 },  .{ .x = 612, .z = 212 },
    .{ .x = 586, .z = 320 }, .{ .x = 592, .z = 430 }, .{ .x = 618, .z = 540 },
    .{ .x = 648, .z = 650 }, .{ .x = 668, .z = 760 }, .{ .x = 660, .z = 870 },
    .{ .x = 628, .z = 960 }, .{ .x = 604, .z = 1024 },
};

fn blend(a: f32, b: f32, c: f32, d: f32, t: f32) f32 {
    const t2 = t * t;
    const t3 = t2 * t;
    return 0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3);
}

pub fn init() void {
    count = 0;
    length = 0;
    flow_factor = 1;
    // Catmull-Rom through the control points, three samples per span, so the
    // bend is smooth but the polyline stays short.
    const last = control.len - 1;
    for (0..control.len) |i| {
        const a = control[if (i == 0) 0 else i - 1];
        const b = control[i];
        const c = control[if (i == last) last else i + 1];
        const d = control[if (i + 2 > last) last else i + 2];
        const steps: usize = if (i == last) 1 else 3;
        for (0..steps) |step| {
            if (count >= max_points) break;
            const t = @as(f32, @floatFromInt(step)) / 3;
            points[count] = .{ .x = blend(a.x, b.x, c.x, d.x, t), .z = blend(a.z, b.z, c.z, d.z, t) };
            // The river is widest through the bend and narrows north and south,
            // and its discharge follows the same shape.
            const phase = @as(f32, @floatFromInt(count)) * 0.62;
            half_width[count] = 25 + 9 * @sin(phase) * 0.5 + 4 * @sin(phase * 0.37);
            discharges[count] = 230 + 40 * @sin(phase * 0.8);
            levels[count] = 0; // filled by the scene from its own terrain
            count += 1;
        }
    }
    for (1..count) |i| length += hypot(points[i].x - points[i - 1].x, points[i].z - points[i - 1].z);
}

pub fn hypot(x: f32, z: f32) f32 {
    return @sqrt(x * x + z * z);
}

// The nearest point on the centreline, the interpolated channel shape there and
// the perpendicular distance from it. Every other helper is written on top of
// this one, so a flow model only has to keep the arrays consistent.
pub const Sample = struct {
    index: usize = 0,
    t: f32 = 0,
    distance: f32 = 1e9,
    half_width: f32 = 0,
    level: f32 = 0,
    chainage: f32 = 0,
};

pub fn nearest(x: f32, z: f32) Sample {
    var best: Sample = .{};
    if (count == 0) return best;
    var walked: f32 = 0;
    for (0..count - 1) |i| {
        const a = points[i];
        const b = points[i + 1];
        const dx = b.x - a.x;
        const dz = b.z - a.z;
        const span = dx * dx + dz * dz;
        const span_length = @sqrt(span);
        const t = if (span < 0.0001) 0 else std.math.clamp(((x - a.x) * dx + (z - a.z) * dz) / span, 0, 1);
        const px = a.x + dx * t;
        const pz = a.z + dz * t;
        const d = hypot(x - px, z - pz);
        if (d < best.distance) {
            best = .{
                .index = i,
                .t = t,
                .distance = d,
                .half_width = half_width[i] + (half_width[i + 1] - half_width[i]) * t,
                .level = levels[i] + (levels[i + 1] - levels[i]) * t,
                .chainage = walked + span_length * t,
            };
        }
        walked += span_length;
    }
    return best;
}

pub fn inside(x: f32, z: f32) bool {
    if (count == 0) return false;
    const s = nearest(x, z);
    return s.distance < s.half_width;
}

// Distance from the centreline, used by the road tool and the parcel seeder to
// keep a margin between the water and anything built.
pub fn distance(x: f32, z: f32) f32 {
    return nearest(x, z).distance;
}

pub fn surfaceAt(x: f32, z: f32) f32 {
    return nearest(x, z).level;
}

// True when the straight span from a to b passes over the water. Sampled at a
// bounded one-metre step, which is finer than any bridge or street segment in
// the authored town. The road tool refuses a crossing; the seeded bridges are
// the only spans that may return true.
pub fn crosses(ax: f32, az: f32, bx: f32, bz: f32) bool {
    if (count == 0) return false;
    const span = hypot(bx - ax, bz - az);
    if (span < 0.0001) return inside(ax, az);
    const steps: usize = @intFromFloat(@min(400, @ceil(span)));
    for (0..steps + 1) |step| {
        const t = @as(f32, @floatFromInt(step)) / @as(f32, @floatFromInt(steps));
        if (inside(ax + (bx - ax) * t, az + (bz - az) * t)) return true;
    }
    return false;
}

// Water surface elevation at a centreline index, after any future flow model
// has written `flow_factor`. A swell raises the surface; nothing raises it yet.
pub fn levelAt(index: usize) f32 {
    if (index >= count) return 0;
    return levels[index] + (flow_factor - 1) * 0.5;
}

// A point on the centreline at a given chainage in metres, with the local
// direction, width and level. Used to lay the riverside roads and the bridges.
pub const Point = struct { x: f32, z: f32, dx: f32, dz: f32, half_width: f32, level: f32 };

pub fn atChainage(chainage: f32) Point {
    if (count < 2) return .{ .x = 0, .z = 0, .dx = 1, .dz = 0, .half_width = 0, .level = 0 };
    var walked: f32 = 0;
    for (0..count - 1) |i| {
        const a = points[i];
        const b = points[i + 1];
        const dx = b.x - a.x;
        const dz = b.z - a.z;
        const span = hypot(dx, dz);
        if (walked + span >= chainage or i + 2 == count) {
            const t = if (span < 0.0001) 0 else std.math.clamp((chainage - walked) / span, 0, 1);
            return .{
                .x = a.x + dx * t,
                .z = a.z + dz * t,
                .dx = dx,
                .dz = dz,
                .half_width = half_width[i] + (half_width[i + 1] - half_width[i]) * t,
                .level = levels[i] + (levels[i + 1] - levels[i]) * t,
            };
        }
        walked += span;
    }
    return .{ .x = points[count - 1].x, .z = points[count - 1].z, .dx = 1, .dz = 0, .half_width = half_width[count - 1], .level = levels[count - 1] };
}
