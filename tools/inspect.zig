const std = @import("std");
const city = @import("city");

fn nearRoad(x: f32, z: f32) f32 {
    var best: f32 = 1e9;
    for (city.roads) |r| {
        const a = city.nodes[r.a];
        const b = city.nodes[r.b];
        const u = city.projection(.{ .x = x, .z = z }, a, b);
        const px = a.x + (b.x - a.x) * u;
        const pz = a.z + (b.z - a.z) * u;
        best = @min(best, city.hypot(px - x, pz - z));
    }
    return best;
}

fn footprintInWater(b: city.Building) bool {
    var sx: f32 = 0;
    while (sx <= 1.0001) : (sx += 0.25) {
        var sz: f32 = 0;
        while (sz <= 1.0001) : (sz += 0.25) {
            if (city.inWater(b.x + b.width * sx, b.z + b.depth * sz)) return true;
            sz += 0.25;
        }
    }
    return false;
}

// Count the enclosed faces the parcels module would recognise as blocks: a
// closed walk of roads with a negative signed area. This is the player-visible
// "section" count, so it is the number the density fix has to move.
fn countBlocks() usize {
    var visited: [city.max_roads * 2]bool = @splat(false);
    var blocks: usize = 0;
    for (0..city.road_count) |rid| for (0..2) |direction| {
        const initial = rid * 2 + direction;
        if (visited[initial]) continue;
        var key = initial;
        var area: f32 = 0;
        var count: usize = 0;
        var closed = false;
        for (0..city.max_roads * 2) |_| {
            if (visited[key]) {
                closed = key == initial;
                break;
            }
            visited[key] = true;
            const edge = city.roads[key / 2];
            const from = if (key % 2 == 0) edge.a else edge.b;
            const to = if (key % 2 == 0) edge.b else edge.a;
            count += 1;
            area += city.nodes[from].x * city.nodes[to].z - city.nodes[to].x * city.nodes[from].z;
            const back = std.math.atan2(city.nodes[from].z - city.nodes[to].z, city.nodes[from].x - city.nodes[to].x);
            var best: f32 = 10;
            var next_key = key ^ 1;
            for (0..city.road_count) |j| {
                const r = city.roads[j];
                if (r.a != to and r.b != to) continue;
                const next = if (r.a == to) r.b else r.a;
                const angle = std.math.atan2(city.nodes[next].z - city.nodes[to].z, city.nodes[next].x - city.nodes[to].x);
                var turn = @mod(angle - back + std.math.pi * 2, std.math.pi * 2);
                if (turn < 0.0001) turn = std.math.pi * 2;
                if (turn < best) {
                    best = turn;
                    next_key = j * 2 + (if (r.a == to) @as(usize, 0) else 1);
                }
            }
            key = next_key;
        }
        if (closed and area < -40) blocks += 1;
    };
    return blocks;
}

pub fn main() !void {
    const out = std.io.getStdOut().writer();
    city.init();

    try out.print("nodes={d}/{d} roads={d}/{d} spans={d} blocks={d}\n", .{ city.node_count, city.max_nodes, city.road_count, city.max_roads, city.span_count, countBlocks() });

    var class_len = [_]f32{ 0, 0, 0 };
    var class_n = [_]usize{ 0, 0, 0 };
    for (city.roads) |r| {
        const a = city.nodes[r.a];
        const b = city.nodes[r.b];
        class_len[r.class] += city.hypot(b.x - a.x, b.z - a.z);
        class_n[r.class] += 1;
    }
    try out.print("lane: {d} segs {d:.0} m | street: {d} segs {d:.0} m | avenue: {d} segs {d:.0} m\n", .{ class_n[0], class_len[0], class_n[1], class_len[1], class_n[2], class_len[2] });

    var degree_hist = [_]usize{0} ** 9;
    for (0..city.node_count) |n| degree_hist[@min(city.degree(n), 8)] += 1;
    try out.print("degree histogram 0..8+: ", .{});
    for (degree_hist, 0..) |c, d| try out.print("{d}={d} ", .{ d, c });
    try out.print("\n", .{});

    var covered: usize = 0;
    var samples: usize = 0;
    var z: f32 = 10;
    while (z < city.size_z) : (z += 20) {
        var x: f32 = 10;
        while (x < city.size_x) : (x += 20) {
            samples += 1;
            if (nearRoad(x, z) < 60) covered += 1;
            x += 20;
        }
    }
    try out.print("lattice within 60 m of a road: {d}/{d} = {d:.1}%\n", .{ covered, samples, 100.0 * @as(f32, @floatFromInt(covered)) / @as(f32, @floatFromInt(samples)) });

    var wet: usize = 0;
    var overlap: usize = 0;
    for (&city.buildings, 0..) |b, i| {
        if (b.kind == .vacant) continue;
        if (footprintInWater(b)) {
            wet += 1;
            try out.print("  wet id={d} kind={s} at ({d:.0},{d:.0}) size {d:.1}x{d:.1}\n", .{ i, @tagName(b.kind), b.x, b.z, b.width, b.depth });
        }
        const centre = nearRoad(b.x + b.width / 2, b.z + b.depth / 2);
        const edge = @min(@min(nearRoad(b.x, b.z), nearRoad(b.x + b.width, b.z)), @min(nearRoad(b.x, b.z + b.depth), nearRoad(b.x + b.width, b.z + b.depth)));
        if (@min(centre, edge) < 2.75) {
            overlap += 1;
            var nearest: usize = 0;
            var nearest_d: f32 = 1e9;
            var corners: [5]city.Vec = undefined;
            corners[0] = .{ .x = b.x, .z = b.z };
            corners[1] = .{ .x = b.x + b.width, .z = b.z };
            corners[2] = .{ .x = b.x, .z = b.z + b.depth };
            corners[3] = .{ .x = b.x + b.width, .z = b.z + b.depth };
            corners[4] = .{ .x = b.x + b.width / 2, .z = b.z + b.depth / 2 };
            for (city.roads, 0..) |r, rid| {
                const a = city.nodes[r.a];
                const c = city.nodes[r.b];
                for (corners) |sp| {
                    const u = city.projection(sp, a, c);
                    const qx = a.x + (c.x - a.x) * u;
                    const qz = a.z + (c.z - a.z) * u;
                    const d = city.hypot(qx - sp.x, qz - sp.z);
                    if (d < nearest_d) {
                        nearest_d = d;
                        nearest = rid;
                    }
                }
            }
            const facing = city.roads[nearest].a == b.node or city.roads[nearest].b == b.node;
            try out.print("  overlap id={d} kind={s} at ({d:.0},{d:.0}) nearest road={d} d={d:.2} faces_node={} street={d} node_degree={d}\n", .{ i, @tagName(b.kind), b.x, b.z, nearest, nearest_d, facing, city.roads[nearest].street, city.degree(b.node) });
        }
    }
    try out.print("buildings touching water: {d}\n", .{wet});
    try out.print("buildings within a road surface: {d}\n", .{overlap});

    // The building array is fixed at 288 slots. `undefined` storage is zeroed
    // in this build, so a slot that never received a placement still has a zero
    // width — that is how a silent shortfall shows up.
    var unplaced: usize = 0;
    var placed: usize = 0;
    for (&city.buildings) |b| {
        if (b.width == 0 or b.depth == 0) unplaced += 1 else placed += 1;
    }
    try out.print("building slots placed={d} unplaced={d}\n", .{ placed, unplaced });
}
