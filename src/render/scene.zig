const std = @import("std");
const city = @import("../scene/city.zig");
const game = @import("../simulation/game.zig");
pub var vertices: [600000 * 6]f32 = undefined;
pub var count: usize = 0;
pub var camera_x: f32 = 24;
pub var camera_z: f32 = 24;
pub var zoom: f32 = 1;
pub var angle: f32 = std.math.pi / 4.0;
pub var width: f32 = 1200;
pub var height: f32 = 800;
pub var selected: i32 = -1;
pub var selected_person: i32 = -1;
pub var overlay: u32 = 0;
const transport = game.transport;
const Color = [3]f32;
const Point = [3]f32;
pub fn reset() void {
    camera_x = city.size_x / 2;
    camera_z = city.size_z / 2;
    zoom = 1;
    angle = std.math.pi / 4.0;
}
fn scale() f32 {
    return @min(width / (city.size_x * 1.6), height / (city.size_z * 1.1)) * zoom;
}
fn vertex(p: Point, color: Color) void {
    const x = p[0] - camera_x;
    const z = p[2] - camera_z;
    const across = x * @cos(angle) - z * @sin(angle);
    const back = x * @sin(angle) + z * @cos(angle);
    if (count >= vertices.len / 6) return;
    const values = [6]f32{ across * scale() * 2 / width, (p[1] * 0.8164966 - back * 0.5773503) * scale() * 2 / height, -(back * 0.8164966 + p[1] * 0.5773503) / (city.size_x * 4), color[0], color[1], color[2] };
    @memcpy(vertices[count * 6 ..][0..6], &values);
    count += 1;
}
fn quad(a: Point, b: Point, c: Point, d: Point, color: Color) void {
    vertex(a, color);
    vertex(b, color);
    vertex(c, color);
    vertex(a, color);
    vertex(c, color);
    vertex(d, color);
}
fn shade(c: Color, amount: f32) Color {
    return .{ c[0] * amount, c[1] * amount, c[2] * amount };
}
fn box(x: f32, z: f32, w: f32, d: f32, h: f32, base: f32, color: Color) void {
    const a = Point{ x, base, z };
    const b = Point{ x + w, base, z };
    const c = Point{ x + w, base, z + d };
    const e = Point{ x, base, z + d };
    const at = Point{ x, base + h, z };
    const bt = Point{ x + w, base + h, z };
    const ct = Point{ x + w, base + h, z + d };
    const et = Point{ x, base + h, z + d };
    quad(at, bt, ct, et, color);
    const sun = @as(f32, @floatCast(@mod(game.elapsed / 480, 1))) * 2 * std.math.pi;
    quad(a, b, bt, at, shade(color, 0.65 + 0.25 * @max(0, -@cos(sun))));
    quad(b, c, ct, bt, shade(color, 0.65 + 0.25 * @max(0, @sin(sun))));
    quad(c, e, et, ct, shade(color, 0.65 + 0.25 * @max(0, @cos(sun))));
    quad(e, a, at, et, shade(color, 0.65 + 0.25 * @max(0, -@sin(sun))));
}
pub fn pan(dx: f32, dy: f32) void {
    camera_x = std.math.clamp(camera_x + (dx * @cos(angle) + dy * @sin(angle) / 0.5773503) / scale(), -20, city.size_x + 20);
    camera_z = std.math.clamp(camera_z + (-dx * @sin(angle) + dy * @cos(angle) / 0.5773503) / scale(), -20, city.size_z + 20);
}
fn streetColor(condition: f32) Color {
    const amount = condition / 100;
    return .{ 0.8 - amount * 0.6, 0.25 + amount * 0.4, 0.2 + amount * 0.25 };
}
fn groundQuad(x: f32, z: f32, w: f32, d: f32, offset: f32, color: Color) void {
    var xx = x;
    while (xx < x + w - 0.0001) {
        var nx = x + w;
        for ([_]f32{ 70, 98, 154, 182 }) |cut| if (cut > xx + 0.0001 and cut < nx) {
            nx = cut;
        };
        var zz = z;
        while (zz < z + d - 0.0001) {
            var nz = z + d;
            for ([_]f32{ 98, 126 }) |cut| if (cut > zz + 0.0001 and cut < nz) {
                nz = cut;
            };
            quad(.{ xx, city.elevation(xx, zz) + offset, zz }, .{ nx, city.elevation(nx, zz) + offset, zz }, .{ nx, city.elevation(nx, nz) + offset, nz }, .{ xx, city.elevation(xx, nz) + offset, nz }, color);
            zz = nz;
        }
        xx = nx;
    }
}
// Clip ribbons at each analytical terrain crease before triangulating.
fn terrainFace(points: []const city.Vec, offset: f32, color: Color) void {
    const cuts = [_]f32{ 70, 98, 154, 182, 98, 126 };
    for (cuts, 0..) |cut, axis| {
        var lo: f32 = 1e9;
        var hi: f32 = -1e9;
        for (points) |p| {
            const value = if (axis < 4) p.x else p.z;
            lo = @min(lo, value);
            hi = @max(hi, value);
        }
        if (lo >= cut - 0.001 or hi <= cut + 0.001) continue;
        var left: [12]city.Vec = undefined;
        var right: [12]city.Vec = undefined;
        var lc: usize = 0;
        var rc: usize = 0;
        for (points, 0..) |p, i| {
            const q = points[(i + 1) % points.len];
            const pv = (if (axis < 4) p.x else p.z) - cut;
            const qv = (if (axis < 4) q.x else q.z) - cut;
            if (pv <= 0) {
                left[lc] = p;
                lc += 1;
            }
            if (pv >= 0) {
                right[rc] = p;
                rc += 1;
            }
            if ((pv < 0 and qv > 0) or (pv > 0 and qv < 0)) {
                const t = pv / (pv - qv);
                const v = city.Vec{ .x = p.x + (q.x - p.x) * t, .z = p.z + (q.z - p.z) * t };
                left[lc] = v;
                lc += 1;
                right[rc] = v;
                rc += 1;
            }
        }
        if (lc >= 3) terrainFace(left[0..lc], offset, color);
        if (rc >= 3) terrainFace(right[0..rc], offset, color);
        return;
    }
    for (1..points.len - 1) |i| {
        for ([_]usize{ 0, i, i + 1 }) |j| {
            const p = points[j];
            vertex(.{ p.x, city.elevation(p.x, p.z) + offset, p.z }, color);
        }
    }
}
pub fn ribbon(a: city.Vec, b: city.Vec, half: f32, lateral: f32, offset: f32, color: Color) void {
    const length = city.hypot(b.x - a.x, b.z - a.z);
    if (length < 0.001) return;
    const nx = -(b.z - a.z) / length;
    const nz = (b.x - a.x) / length;
    const points = [_]city.Vec{ .{ .x = a.x + nx * (lateral - half), .z = a.z + nz * (lateral - half) }, .{ .x = b.x + nx * (lateral - half), .z = b.z + nz * (lateral - half) }, .{ .x = b.x + nx * (lateral + half), .z = b.z + nz * (lateral + half) }, .{ .x = a.x + nx * (lateral + half), .z = a.z + nz * (lateral + half) } };
    terrainFace(&points, offset, color);
}
fn vehicleBox(x: f32, z: f32, length: f32, wide: f32, h: f32, base: f32, ux: f32, uz: f32, color: Color) void {
    var p: [8]Point = undefined;
    for (0..8) |i| {
        const along: f32 = if (i % 4 == 0 or i % 4 == 3) -length / 2 else length / 2;
        const across: f32 = if (i % 4 < 2) -wide / 2 else wide / 2;
        p[i] = .{ x + ux * along - uz * across, base + (if (i < 4) @as(f32, 0) else h), z + uz * along + ux * across };
    }
    quad(p[4], p[5], p[6], p[7], color);
    for (0..4) |i| quad(p[i], p[(i + 1) % 4], p[(i + 1) % 4 + 4], p[i + 4], shade(color, 0.75));
}
pub fn groundPoint(sx: f32, sy: f32) city.Vec {
    const across = (sx - width / 2) / scale();
    const back = (sy - height / 2) / scale() / 0.5773503;
    const ox = camera_x + across * @cos(angle) + back * @sin(angle);
    const oz = camera_z - across * @sin(angle) + back * @cos(angle);
    var low: f32 = 0;
    var high: f32 = 50;
    for (0..24) |_| {
        const y = (low + high) / 2;
        const x = ox + @sin(angle) * 1.41421356 * y;
        const z = oz + @cos(angle) * 1.41421356 * y;
        if (y < city.elevation(x, z)) low = y else high = y;
    }
    return .{ .x = ox + @sin(angle) * 1.41421356 * (low + high) / 2, .z = oz + @cos(angle) * 1.41421356 * (low + high) / 2 };
}
pub fn focus(x: f32, z: f32) void {
    camera_x = x;
    camera_z = z;
    zoom = 3;
}
fn carColor(id: usize) Color {
    const palette = [_]Color{ .{ 0.64, 0.27, 0.22 }, .{ 0.26, 0.38, 0.52 }, .{ 0.78, 0.76, 0.69 }, .{ 0.25, 0.29, 0.27 }, .{ 0.62, 0.52, 0.31 }, .{ 0.48, 0.51, 0.55 }, .{ 0.36, 0.45, 0.34 } };
    return palette[(id * 17 + id / 7) % palette.len];
}
pub fn draw(w: f32, h: f32) void {
    width = w;
    height = h;
    count = 0;
    for (0..city.rows) |row| for (0..city.cols) |col| {
        const x = @as(f32, @floatFromInt(col)) * city.spacing;
        const z = @as(f32, @floatFromInt(row)) * city.spacing;
        groundQuad(x, z, city.spacing, city.spacing, 0, .{ 0.36, 0.40, 0.32 });
    };
    // Visible edges communicate the plateau heights without a terrain art dependency.
    for (0..city.cols) |i| {
        const x = @as(f32, @floatFromInt(i)) * city.spacing;
        quad(.{ x, -2, 0 }, .{ x + city.spacing, -2, 0 }, .{ x + city.spacing, city.elevation(x + city.spacing, 0), 0 }, .{ x, city.elevation(x, 0), 0 }, .{ 0.32, 0.31, 0.27 });
        quad(.{ x, -2, city.size_z }, .{ x + city.spacing, -2, city.size_z }, .{ x + city.spacing, city.elevation(x + city.spacing, city.size_z), city.size_z }, .{ x, city.elevation(x, city.size_z), city.size_z }, .{ 0.32, 0.31, 0.27 });
    }
    for (0..city.rows) |i| {
        const z = @as(f32, @floatFromInt(i)) * city.spacing;
        quad(.{ 0, -2, z }, .{ 0, -2, z + city.spacing }, .{ 0, city.elevation(0, z + city.spacing), z + city.spacing }, .{ 0, city.elevation(0, z), z }, .{ 0.28, 0.28, 0.25 });
        quad(.{ city.size_x, -2, z }, .{ city.size_x, -2, z + city.spacing }, .{ city.size_x, city.elevation(city.size_x, z + city.spacing), z + city.spacing }, .{ city.size_x, city.elevation(city.size_x, z), z }, .{ 0.28, 0.28, 0.25 });
    }
    if (game.parcels.visible) for (game.parcels.storage[0..game.parcels.count], 0..) |p, id| {
        const colors = [_]Color{ .{ 0.54, 0.55, 0.48 }, .{ 0.3, 0.61, 0.39 }, .{ 0.3, 0.48, 0.78 }, .{ 0.76, 0.62, 0.29 }, .{ 0.61, 0.43, 0.68 }, .{ 0.31, 0.67, 0.66 } };
        groundQuad(p.x - 0.45, p.z - 0.45, p.width + 0.9, p.depth + 0.9, 0.07, if (game.parcels.selected == @as(i32, @intCast(id))) .{ 1, 0.85, 0.35 } else colors[p.zone]);
    };
    for (city.roads, 0..) |r, id| {
        const a = city.Vec{ .x = city.nodes[r.a].x, .z = city.nodes[r.a].z };
        const b = city.Vec{ .x = city.nodes[r.b].x, .z = city.nodes[r.b].z };
        ribbon(a, b, 2.7, 0, 0.08, .{ 0.49, 0.49, 0.45 });
        const color: Color = if (r.works) .{ 0.66, 0.46, 0.18 } else if (overlay == 2) streetColor(100 * (1 - transport.congestion[id])) else if (overlay == 3) streetColor(100 * (1 - @min(1, @as(f32, @floatFromInt(game.residents.pedestrians[id])) / @max(1, r.length * 0.15)))) else if (overlay == 1) streetColor(r.condition) else .{ 0.23, 0.25, 0.25 };
        ribbon(a, b, 1.75, 0, 0.12, color);
        if (transport.lanes[id] != 0) ribbon(a, b, 0.15, 1.4, 0.16, if (transport.lanes[id] == 1) .{ 0.3, 0.55, 0.8 } else .{ 0.35, 0.65, 0.35 });
        const length = city.hypot(b.x - a.x, b.z - a.z);
        const ux = (b.x - a.x) / length;
        const uz = (b.z - a.z) / length;
        var d: f32 = 1;
        while (d + 1 < length) : (d += 3.2) ribbon(.{ .x = a.x + ux * d, .z = a.z + uz * d }, .{ .x = a.x + ux * (d + 1), .z = a.z + uz * (d + 1) }, 0.05, 0, 0.17, .{ 0.65, 0.63, 0.51 });
        if (r.crosswalk and length > 5) for (0..2) |end| {
            const n = if (end == 0) r.a else r.b;
            if (city.degree(n) < 3) continue;
            const t: f32 = if (end == 0) 2.5 else length - 2.5;
            const c = city.Vec{ .x = a.x + ux * t, .z = a.z + uz * t };
            for (0..7) |stripe| {
                const off = -1.5 + @as(f32, @floatFromInt(stripe)) * 0.5;
                ribbon(.{ .x = c.x - ux * 0.5, .z = c.z - uz * 0.5 }, .{ .x = c.x + ux * 0.5, .z = c.z + uz * 0.5 }, 0.14, off, 0.2, .{ 0.88, 0.86, 0.74 });
            }
        };
    }
    for (city.nodes, 0..) |n, id| {
        if (city.degree(id) < 3) continue;
        for (0..2) |axis| {
            const x = n.x + (if (axis == 0) @as(f32, -2.3) else 2.3);
            const z = n.z - 2.3;
            const y = city.elevation(x, z);
            box(x - 0.07, z - 0.07, 0.14, 0.14, 1.7, y + 0.1, .{ 0.25, 0.27, 0.25 });
            box(x - 0.18, z - 0.18, 0.36, 0.36, 0.6, y + 1.7, .{ 0.12, 0.14, 0.13 });
            const green = transport.green(id, axis == 0, game.elapsed);
            box(x - 0.2, z - 0.2, 0.4, 0.4, 0.18, y + (if (green) @as(f32, 1.75) else 2.08), if (green) .{ 0.26, 0.9, 0.4 } else .{ 1, 0.24, 0.12 });
        }
    }
    // Ground-only projected shadows, clipped into small terrain-following cells.
    const hour: f32 = @floatCast(@mod(game.elapsed / 20, 24));
    if (hour > 6 and hour < 18) {
        const azimuth = (hour - 6) / 12 * std.math.pi;
        for (&city.buildings) |b| {
            if (b.kind == .park or b.kind == .vacant) continue;
            const reach = @min(16, b.height / @max(0.4, @sin(azimuth)));
            for (0..6) |step| {
                const t = @as(f32, @floatFromInt(step)) / 6;
                groundQuad(b.x - @cos(azimuth) * reach * t, b.z + reach * 0.45 * t, b.width, b.depth, 0.025, .{ 0.29, 0.33, 0.27 });
            }
        }
    }
    for (&city.buildings, 0..) |b, i| {
        const materials = [_]Color{ .{ 0.57, 0.52, 0.43 }, .{ 0.62, 0.60, 0.53 }, .{ 0.47, 0.42, 0.36 }, .{ 0.66, 0.65, 0.60 }, .{ 0.48, 0.50, 0.48 } };
        const color: Color = if (b.kind == .office) .{ 0.43, 0.48, 0.48 } else if (b.kind == .park) .{ 0.33, 0.43, 0.31 } else materials[i % materials.len];
        if (selected == @as(i32, @intCast(i)) and (b.kind == .vacant or b.kind == .park)) groundQuad(b.x - 0.25, b.z - 0.25, b.width + 0.5, b.depth + 0.5, 0.03, .{ 0.94, 0.76, 0.32 });
        if (b.kind == .vacant) {
            groundQuad(b.x, b.z, b.width, b.depth, 0.025, .{ 0.43, 0.46, 0.35 });
            continue;
        }
        if (b.kind == .park) {
            groundQuad(b.x, b.z, b.width, b.depth, 0.06, color);
            for (0..3) |t| {
                const x = b.x + 1 + @as(f32, @floatFromInt(t)) * 2;
                const y = city.elevation(x, b.z + 3);
                box(x, b.z + 3, 0.25, 0.25, 1.8, y, .{ 0.33, 0.28, 0.21 });
                box(x - 0.6, b.z + 2.4, 1.6, 1.6, 2, y + 1.4, .{ 0.25, 0.35, 0.24 });
            }
            continue;
        }
        const entry = city.frontage(b);
        ribbon(entry, .{ .x = b.entry_x, .z = b.entry_z }, 0.4, 0, 0.2, .{ 0.55, 0.53, 0.47 });
        const direction: f32 = if (b.entry_z == b.z) -1 else 1;
        const count_steps: usize = 6;
        for (0..count_steps) |step| {
            const t = @as(f32, @floatFromInt(step)) / @as(f32, @floatFromInt(count_steps));
            const z = b.entry_z + direction * (1.8 * (1 - t));
            const low = city.elevation(b.entry_x, z);
            box(b.entry_x - 0.45, z - 0.15, 0.9, 0.3, @max(0.08, (b.ground + 0.3 - low) * t), low, .{ 0.51, 0.50, 0.45 });
        }
        const low = city.elevation(b.x, b.z);
        box(b.x, b.z, b.width, b.depth, b.ground - low + 0.3, low, .{ 0.41, 0.41, 0.37 });
        if (selected == @as(i32, @intCast(i))) box(b.x - 0.25, b.z - 0.25, b.width + 0.5, b.depth + 0.5, 0.08, b.ground + 0.21, .{ 0.94, 0.76, 0.32 });
        box(b.x, b.z, b.width, b.depth, b.height, b.ground + 0.3, color);
        {
            box(b.x + 0.3, b.z + 0.3, b.width - 0.6, b.depth - 0.6, 0.2, b.ground + b.height + 0.3, shade(color, 0.78));
            if (b.kind == .home and i % 3 == 0) box(b.x + 1, b.z + 1, b.width - 2, b.depth - 2, 0.9, b.ground + b.height + 0.5, .{ 0.36, 0.34, 0.31 });
            if (b.kind == .depot) box(b.x + 0.5, b.z + b.depth, 5, 0.05, 2.5, b.ground + 0.3, .{ 0.25, 0.27, 0.26 });
            var floor: f32 = 1.5;
            while (floor + 0.75 <= b.height - 0.4) : (floor += 2) {
                for (0..3) |j| {
                    const offset = 0.8 + @as(f32, @floatFromInt(j)) * (@min(b.width, b.depth) - 2.4) / 2;
                    if (j != 1 or b.sun > 0.65) box(b.x + offset, b.z - 0.035, 0.8, 0.035, 0.75, b.ground + floor, .{ 0.27, 0.32, 0.33 });
                    box(b.x - 0.035, b.z + offset, 0.035, 0.8, 0.75, b.ground + floor, .{ 0.27, 0.32, 0.33 });
                    box(b.x + offset, b.z + b.depth, 0.8, 0.035, 0.75, b.ground + floor, .{ 0.26, 0.31, 0.31 });
                    box(b.x + b.width, b.z + offset, 0.035, 0.8, 0.75, b.ground + floor, .{ 0.29, 0.34, 0.34 });
                }
            }
        }
    }
    if (selected_person >= 0) {
        const p = game.residents.people[@intCast(selected_person)];
        for ([_]usize{ p.origin, p.destination }, 0..) |endpoint, k| {
            const building: i32 = if (p.order >= 0 and k == 1) -1 else @intCast(if (k == 0) p.origin_building else p.destination_building);
            const color: Color = if (k == 0) .{ 0.3, 0.75, 1 } else .{ 1, 0.64, 0.2 };
            if (building >= 0) {
                const b = city.buildings[@intCast(building)];
                box(b.x - 0.15, b.z - 0.15, b.width + 0.3, b.depth + 0.3, 0.18, b.ground + b.height + 0.6, color);
            } else {
                const n = city.nodes[endpoint];
                box(n.x - 0.5, n.z - 0.5, 1, 1, 3, n.y + 0.2, color);
            }
        }
        var node = p.next;
        var steps: usize = 0;
        while (node != p.destination and steps < city.node_count and p.bus < 0) : (steps += 1) {
            const next = if ((p.mode == 0 or p.mode == 3) and @mod(selected_person, 5) != 0) city.walk_next[node][p.destination] else city.next_node[node][p.destination];
            const a = city.nodes[node];
            const b = city.nodes[next];
            ribbon(.{ .x = a.x, .z = a.z }, .{ .x = b.x, .z = b.z }, 0.15, 2.3, 0.24, .{ 0.95, 0.76, 0.3 });
            node = next;
        }
        const y = p.y;
        box(p.x - 0.3, p.z - 0.3, 0.6, 0.6, 0.12, y + 0.2, .{ 1, 0.82, 0.25 });
    }
    if (transport.selected >= 0 or transport.editing) {
        const stops = if (transport.editing) transport.draft[0..transport.draft_count] else transport.lines[@intCast(transport.selected)].stops[0..transport.lines[@intCast(transport.selected)].count];
        for (stops, 0..) |stop, index| {
            const n = city.nodes[stop];
            box(n.x - 0.6, n.z - 0.6, 1.2, 1.2, 1, n.y + 0.2, .{ 0.95, 0.72, 0.23 });
            var node = stop;
            var steps: usize = 0;
            const destination = stops[(index + 1) % stops.len];
            while (node != destination and steps < city.node_count) : (steps += 1) {
                const next = city.next_node[node][destination];
                const a = city.nodes[node];
                const b = city.nodes[next];
                ribbon(.{ .x = a.x, .z = a.z }, .{ .x = b.x, .z = b.z }, 0.17, 0, 0.24, .{ 0.98, 0.72, 0.22 });
                node = next;
            }
        }
    }
    if (game.roadworks.active and game.roadworks.count > 1) {
        const color: Color = if (game.roadworks.error_code == 0) .{ 0.35, 0.8, 0.65 } else .{ 0.95, 0.28, 0.24 };
        for (game.roadworks.points[0 .. game.roadworks.count - 1], 0..) |a, i| ribbon(a, game.roadworks.points[i + 1], 2.7, 0, 0.3, color);
        for (game.roadworks.knots[0..game.roadworks.knot_count]) |p| box(p.x - 0.4, p.z - 0.4, 0.8, 0.8, 1.3, city.elevation(p.x, p.z) + 0.2, color);
    }
    for (&transport.vehicles, 0..) |v, vehicle_id| {
        if (!v.active) continue;
        const a = city.nodes[v.node];
        const b = city.nodes[v.next];
        const dist = city.hypot(b.x - a.x, b.z - a.z);
        const ux = if (dist > 0.001) (b.x - a.x) / dist else 1;
        const uz = if (dist > 0.001) (b.z - a.z) / dist else 0;
        const length: f32 = if (v.line >= 0) 2.7 else 1.5;
        const color: Color = if (v.line >= 0) .{ 0.78, 0.48, 0.17 } else carColor(vehicle_id);
        var y: f32 = -1e9;
        for ([_]f32{ -1, 1 }) |front| for ([_]f32{ -1, 1 }) |side| {
            y = @max(y, city.elevation(v.x + ux * length / 2 * front - uz * 0.325 * side, v.z + uz * length / 2 * front + ux * 0.325 * side) + 0.2);
        };
        const body: f32 = if (v.line >= 0) 0.95 else 0.55;
        vehicleBox(v.x, v.z, length, 0.65, body, y, ux, uz, color);
        vehicleBox(v.x, v.z, length * 0.56, 0.4, 0.16, y + body, ux, uz, .{ 0.2, 0.29, 0.32 });
    }
    for (&game.residents.people, 0..) |p, i| {
        if (p.phase == 3 or (p.mode == 2 and p.phase == 1) or p.bus >= 0) continue;
        if (p.mode == 1) box(p.x - 0.35, p.z - 0.15, 0.7, 0.3, 0.25, p.y, .{ 0.16, 0.20, 0.18 });
        const dx = @cos(angle) * 0.16;
        const dz = -@sin(angle) * 0.16;
        const y = p.y;
        const colors = [_]Color{ .{ 0.70, 0.62, 0.44 }, .{ 0.65, 0.68, 0.62 }, .{ 0.53, 0.38, 0.30 }, .{ 0.34, 0.44, 0.51 } };
        const color: Color = if (p.order >= 0) .{ 1, 0.66, 0.15 } else colors[i % 4];
        quad(.{ p.x - dx, y, p.z - dz }, .{ p.x + dx, y, p.z + dz }, .{ p.x + dx, y + 0.9, p.z + dz }, .{ p.x - dx, y + 0.9, p.z - dz }, color);
    }
}
pub fn pick(sx: f32, sy: f32) void {
    const across = (sx - width / 2) / scale();
    const back = (sy - height / 2) / scale() / 0.5773503;
    const origin = Point{ camera_x + across * @cos(angle) + back * @sin(angle), 0, camera_z - across * @sin(angle) + back * @cos(angle) };
    const direction = Point{ @sin(angle) * 0.8164966, 0.5773503, @cos(angle) * 0.8164966 };
    var nearest: f32 = -1e9;
    selected = -1;
    selected_person = -1;
    for (&city.buildings, 0..) |b, i| {
        const low = Point{ b.x, b.ground, b.z };
        const high = Point{ b.x + b.width, b.ground + b.height + 0.6, b.z + b.depth };
        var enter: f32 = -1e9;
        var leave: f32 = 1e9;
        for (0..3) |axis| {
            if (@abs(direction[axis]) < 0.00001) {
                if (origin[axis] < low[axis] or origin[axis] > high[axis]) {
                    leave = -1e9;
                }
            } else {
                const a = (low[axis] - origin[axis]) / direction[axis];
                const c = (high[axis] - origin[axis]) / direction[axis];
                enter = @max(enter, @min(a, c));
                leave = @min(leave, @max(a, c));
            }
        }
        if (leave >= enter and leave > nearest) {
            nearest = leave;
            selected = @intCast(i);
        }
    }
    var best_distance: f32 = 100;
    for (&game.residents.people, 0..) |p, id| {
        if (p.phase == 3 or p.bus >= 0) continue;
        const px = p.x - camera_x;
        const pz = p.z - camera_z;
        const py = p.y + 0.5;
        const screen_x = width / 2 + (px * @cos(angle) - pz * @sin(angle)) * scale();
        const screen_y = height / 2 - (py * 0.8164966 - (px * @sin(angle) + pz * @cos(angle)) * 0.5773503) * scale();
        const d = (screen_x - sx) * (screen_x - sx) + (screen_y - sy) * (screen_y - sy);
        const depth = py / direction[1];
        if (d < best_distance and (selected < 0 or depth > nearest - 0.5)) {
            best_distance = d;
            selected_person = @intCast(id);
        }
    }
    if (selected_person >= 0) selected = -1;
}

// Preserve the ground point under the cursor while changing magnification.
pub fn zoomAt(amount: f32, x: f32, y: f32) void {
    const old_scale = scale();
    zoom = std.math.clamp(zoom * amount, 0.5, 12);
    const change = 1 / old_scale - 1 / scale();
    const across = (x - width / 2) * change;
    const back = (y - height / 2) * change / 0.5773503;
    camera_x = std.math.clamp(camera_x + across * @cos(angle) + back * @sin(angle), -20, city.size_x + 20);
    camera_z = std.math.clamp(camera_z - across * @sin(angle) + back * @cos(angle), -20, city.size_z + 20);
}

pub fn project(node: usize, axis: u32) f32 {
    const n = city.nodes[node];
    const x = n.x - camera_x;
    const z = n.z - camera_z;
    return if (axis == 0) width / 2 + (x * @cos(angle) - z * @sin(angle)) * scale() else height / 2 - ((n.y + 0.3) * 0.8164966 - (x * @sin(angle) + z * @cos(angle)) * 0.5773503) * scale();
}
