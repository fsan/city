const std = @import("std");
const city = @import("../scene/city.zig");
const game = @import("../simulation/game.zig");
// Slice 15: the dense town needs rather more geometry than the slice-14
// lattice did. The buffer is sized for the authored street wall plus the
// downtown towers, the parks and their trees with room left for the selection
// highlights and route ribbons drawn on top.
pub var vertices: [1400000 * 6]f32 = undefined;
pub var count: usize = 0;
pub var camera_x: f32 = 24;
pub var camera_z: f32 = 24;
pub var zoom: f32 = 1;
pub var angle: f32 = std.math.pi / 4.0;
pub var width: f32 = 1200;
pub var height: f32 = 800;
pub var selected: i32 = -1;
pub var selected_person: i32 = -1;
pub var selected_signal: i32 = -1;
pub var overlay: u32 = 0;
const transport = game.transport;
const Color = [3]f32;
const Point = [3]f32;

// Pavement lift. `city.elevation` is the surface the simulation walks on - the
// carved ground, or a bridge deck inside its corridor - and it stays that. Every
// layer the player reads as the street steps up from it by one of these
// offsets, and the value is the layer's own: the pavement has to clear the
// coarse ground mesh's chord error, which is 40 m away from the river and 4 m
// beside it, or the carved bank rises through the road between samples. The
// list is the stacking order, lowest first.
//
//   kerb     0.22  the outer band, and anything standing on the verge
//   surface  0.26  the carriageway itself, and every actor standing on it
//   lane     0.30  bus- and cycle-lane paint
//   dash     0.31  the centre line
//   crossing 0.34  zebra bars, paint on the carriageway
//   works    0.38  an active or drafted work order, over all road paint
//   ribbon   0.40  selection ribbons: routes, stops and a drafted crew
const pavement_kerb: f32 = 0.22;
const pavement_surface: f32 = 0.26;
const pavement_lane: f32 = 0.30;
const pavement_dash: f32 = 0.31;
const pavement_crossing: f32 = 0.34;
const pavement_works: f32 = 0.38;
const pavement_ribbon: f32 = 0.40;
// Street widths: the kerb band is the full carriageway, the surface is the dark
// strip inside it.
const kerb_half: f32 = 2.7;
const surface_half: f32 = 1.75;
const kerb_color: Color = .{ 0.49, 0.49, 0.45 };
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

// The carriageway surface a street takes: an active work order's orange wins
// over the overlays, then the condition, traffic and pedestrian views, then the
// base pavement. The junction join paints itself with the same function, so a
// junction can never keep a colour the streets around it have left.
fn surfaceColor(r: city.Road, id: usize) Color {
    if (r.works) return .{ 0.66, 0.46, 0.18 };
    if (overlay == 2) return streetColor(100 * (1 - transport.congestion[id]));
    if (overlay == 3) return streetColor(100 * (1 - @min(1, @as(f32, @floatFromInt(game.residents.pedestrians[id])) / @max(1, r.length * 0.15))));
    if (overlay == 1) return streetColor(r.condition);
    return .{ 0.23, 0.25, 0.25 };
}

// A work order replaces the carriageway, so its surface is drawn over the lane,
// dash and crossing paint rather than under it.
fn surfaceOffset(r: city.Road) f32 {
    return if (r.works) pavement_works else pavement_surface;
}

// The pavement plane an actor stands on. The simulation keeps its own height
// (`p.y`, `city.elevation`); the drawn body never starts below the carriageway
// it stands on, on land or on a bridge deck.
fn actorPlane(x: f32, z: f32, standing: f32) f32 {
    return @max(standing, city.elevation(x, z) + pavement_surface);
}
// The terrain's own creases: the ends of the ramps authored in `city.terrain`.
// A triangle that spans one is drawn as a straight edge across a corner the
// ground actually turns at, so the drawn surface stops agreeing with the
// surface the simulation walks on and can rise through a road laid over it.
const crease_x = [_]f32{ 30, 210, 1140, 1300 };
const crease_z = [_]f32{ 130, 830, 1020 };

// Sample positions across one axis of a tile. No gap is wider than `step` and
// none straddles a crease, so every quad built from two neighbours lies on a
// single affine piece of the terrain and reproduces it exactly.
fn sampleAxis(out: *[24]f32, start: f32, end: f32, step: f32, creases: []const f32) usize {
    out[0] = start;
    var n: usize = 1;
    var cursor = start;
    while (cursor < end - 0.0001 and n < out.len) {
        var next = @min(end, cursor + step);
        for (creases) |c| {
            if (c > cursor + 0.0001 and c < next) next = c;
        }
        cursor = next;
        out[n] = cursor;
        n += 1;
    }
    return n;
}

// Slice 13: the ground is sampled finely wherever the river could carve it, so
// the channel and its banks are drawn instead of being averaged away between
// two tile corners. Away from the water one quad per tile is enough.
fn groundQuad(x: f32, z: f32, w: f32, d: f32, offset: f32, color: Color) void {
    const step: f32 = if (nearRiver(x, z, w, d)) 4 else 40;
    var xs: [24]f32 = undefined;
    var zs: [24]f32 = undefined;
    const nx = sampleAxis(&xs, x, x + w, step, &crease_x);
    const nz = sampleAxis(&zs, z, z + d, step, &crease_z);
    for (0..nx - 1) |i| {
        for (0..nz - 1) |j| {
            const x0 = xs[i];
            const x1 = xs[i + 1];
            const z0 = zs[j];
            const z1 = zs[j + 1];
            quad(.{ x0, city.carved(x0, z0) + offset, z0 }, .{ x1, city.carved(x1, z0) + offset, z0 }, .{ x1, city.carved(x1, z1) + offset, z1 }, .{ x0, city.carved(x0, z1) + offset, z1 }, color);
        }
    }
}

// The bridge decks. A span is drawn as its own slab over the water with a
// parapet on either side and nothing beneath it, so the channel keeps its full
// width and the river reads as continuous under the bridge instead of being
// dammed by a causeway.
fn bridgeDecks() void {
    const deck = Color{ 0.42, 0.42, 0.39 };
    const parapet = Color{ 0.52, 0.51, 0.47 };
    const half: f32 = 4.2;
    const thickness: f32 = 1.1;
    for (city.spans[0..city.span_count]) |s| {
        const dx = s.bx - s.ax;
        const dz = s.bz - s.az;
        const length = city.hypot(dx, dz);
        if (length < 0.001) continue;
        const ux = dx / length;
        const uz = dz / length;
        const nx = -uz;
        const nz = ux;
        const cx = (s.ax + s.bx) / 2;
        const cz = (s.az + s.bz) / 2;
        // The slab itself, hanging below the deck level the traffic walks on.
        vehicleBox(cx, cz, length, half * 2, thickness, s.level - thickness, ux, uz, deck);
        // Parapets along both edges, so the span reads as a bridge.
        for ([_]f32{ -1, 1 }) |side| {
            vehicleBox(cx + nx * side * (half - 0.25), cz + nz * side * (half - 0.25), length, 0.5, 0.55, s.level, ux, uz, parapet);
        }
    }
}

// The bank strip either side of the water. The waterline is a curve, but the
// ground tiles that carry it are chords of an axis-aligned grid, so the edge
// they present to the river is ragged. This strip is built from the river's own
// centreline, so the water reads against the authored curve instead of the grid,
// and it laps a little way up the bank where the ground is already above the
// water plane.
fn riverBank() void {
    const r = city.River;
    if (r.count < 2) return;
    const inner = r.bank_width * 0.6875;
    const outer = inner + 7;
    const color = Color{ 0.36, 0.40, 0.32 };
    var have = false;
    var in_left: Point = undefined;
    var in_right: Point = undefined;
    var out_left: Point = undefined;
    var out_right: Point = undefined;
    for (0..r.count) |i| {
        const ei = bankEdge(i, inner);
        const eo = bankEdge(i, outer);
        const i_left = Point{ ei[0][0], city.carved(ei[0][0], ei[0][2]) + 0.04, ei[0][2] };
        const i_right = Point{ ei[1][0], city.carved(ei[1][0], ei[1][2]) + 0.04, ei[1][2] };
        const o_left = Point{ eo[0][0], city.carved(eo[0][0], eo[0][2]) + 0.04, eo[0][2] };
        const o_right = Point{ eo[1][0], city.carved(eo[1][0], eo[1][2]) + 0.04, eo[1][2] };
        if (have) {
            quad(in_left, i_left, o_left, out_left, color);
            quad(out_right, o_right, i_right, in_right, color);
        }
        in_left = i_left;
        in_right = i_right;
        out_left = o_left;
        out_right = o_right;
        have = true;
    }
}

// True when a tile could contain or touch the water, tested through the river's
// own centreline distance so the renderer never duplicates its shape.
fn nearRiver(x: f32, z: f32, w: f32, d: f32) bool {
    const c = city.River.nearest(x + w * 0.5, z + d * 0.5);
    return c.distance < c.half_width + city.River.bank_width + @max(w, d) * 0.75;
}

// The water surface. Every centreline point contributes one shared edge, laid
// on the bisector of the two spans that meet there, so consecutive spans meet
// exactly and a bend no longer leaves a wedge of bank showing through the
// water. The surface also reaches well past the waterline, which is where the
// carved bank rises through the water plane: its own boundary is then buried
// under the bank, and the water simply ends wherever the ground crosses it.
fn riverSurface() void {
    const r = city.River;
    if (r.count < 2) return;
    const reach = r.bank_width + 4;
    var have_previous = false;
    var left_previous: Point = undefined;
    var right_previous: Point = undefined;
    for (0..r.count) |i| {
        const edge = bankEdge(i, reach);
        if (have_previous) quad(left_previous, edge[0], edge[1], right_previous, .{ 0.17, 0.33, 0.44 });
        left_previous = edge[0];
        right_previous = edge[1];
        have_previous = true;
    }
}

// The two ends of the water surface's shared edge at one centreline point. The
// edge is pushed out along the bisector of the neighbouring spans by whatever
// it takes to stay `reach` past the channel from both of them.
fn bankEdge(index: usize, reach: f32) [2]Point {
    const r = city.River;
    const centre = r.points[index];
    const y = r.levelAt(index) + 0.35;
    var nx: f32 = 0;
    var nz: f32 = 0;
    var spans: f32 = 0;
    if (index > 0) {
        const a = r.points[index - 1];
        const len = city.hypot(centre.x - a.x, centre.z - a.z);
        if (len > 0.001) {
            nx += -(centre.z - a.z) / len;
            nz += (centre.x - a.x) / len;
            spans += 1;
        }
    }
    if (index + 1 < r.count) {
        const b = r.points[index + 1];
        const len = city.hypot(b.x - centre.x, b.z - centre.z);
        if (len > 0.001) {
            nx += -(b.z - centre.z) / len;
            nz += (b.x - centre.x) / len;
            spans += 1;
        }
    }
    const len = city.hypot(nx, nz);
    if (len < 0.001) return .{ .{ centre.x, y, centre.z }, .{ centre.x, y, centre.z } };
    nx /= len;
    nz /= len;
    // Two spans make a miter, one span needs no widening at all.
    const miter = if (spans < 2) 1 else @min(3, 2 / len);
    const edge = (r.half_width[index] + reach) * miter;
    return .{ .{ centre.x + nx * edge, y, centre.z + nz * edge }, .{ centre.x - nx * edge, y, centre.z - nz * edge } };
}

// Clip ribbons at each analytical terrain crease before triangulating.
fn terrainFace(points: []const city.Vec, offset: f32, color: Color) void {
    // Clip ribbons at the terrain's own ramps (west hill, east rise, southern
    // rise, northern shelf) before triangulating.
    const cuts = [_]f32{ 30, 210, 1140, 1300, 130, 830, 1020 };
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
    // A strip that runs beside the river is cut into short pieces so it follows
    // the carved bank rather than spanning the dip in one flat quad.
    const strips: usize = if (nearRiver(@min(a.x, b.x), @min(a.z, b.z), @abs(b.x - a.x), @abs(b.z - a.z))) @max(1, @as(usize, @intFromFloat(@ceil(length / 4)))) else 1;
    var i: usize = 0;
    while (i < strips) : (i += 1) {
        const t0 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(strips));
        const t1 = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(strips));
        const p = city.Vec{ .x = a.x + (b.x - a.x) * t0, .z = a.z + (b.z - a.z) * t0 };
        const q = city.Vec{ .x = a.x + (b.x - a.x) * t1, .z = a.z + (b.z - a.z) * t1 };
        const points = [_]city.Vec{ .{ .x = p.x + nx * (lateral - half), .z = p.z + nz * (lateral - half) }, .{ .x = q.x + nx * (lateral - half), .z = q.z + nz * (lateral - half) }, .{ .x = q.x + nx * (lateral + half), .z = q.z + nz * (lateral + half) }, .{ .x = p.x + nx * (lateral + half), .z = p.z + nz * (lateral + half) } };
        terrainFace(&points, offset, color);
    }
}
// Road joins. A road is a strip with a perpendicular end edge, so two roads
// meeting at a bend or junction leave a wedge between those end edges and the
// ground below shows through it. Each node therefore fills one triangle per
// neighbouring pair of roads, from those two roads' own edge corners and their
// bearings around the node, so the wedge is covered and nothing is painted
// outside the carriageway.
//
// The wedge belongs to both roads, so the triangle is split on the bisector of
// the pair and each half takes the colour and the layer of the road that
// borders it. That is what carries an overlay, and a work order's orange, right
// through a junction instead of stopping at the street. With `per_road` false
// the whole join is one colour and one layer, which is what the kerb band
// wants, and `uniform_offset`/`uniform_color` are what it uses then.
//
// The incident roads come from `city.incident`, built once a frame in
// `city.buildIncidence`: the pass used to scan every road for every node once
// per layer, which is about 2.2 M comparisons a layer on this town.
fn junctionFans(half: f32, uniform_offset: f32, uniform_color: Color, per_road: bool) void {
    var away: [24]f32 = undefined;
    var normal_x: [24]f32 = undefined;
    var normal_z: [24]f32 = undefined;
    var road_id: [24]usize = undefined;
    for (0..city.node_count) |node| {
        const node_x = city.nodes[node].x;
        const node_z = city.nodes[node].z;
        var arms: usize = 0;
        for (city.incident(node)) |road_index| {
            if (arms >= away.len) break;
            const r = city.roads[road_index];
            const other = if (r.a == node) r.b else r.a;
            const dx = city.nodes[other].x - node_x;
            const dz = city.nodes[other].z - node_z;
            const len = city.hypot(dx, dz);
            if (len < 0.001) continue;
            normal_x[arms] = -dz / len;
            normal_z[arms] = dx / len;
            away[arms] = std.math.atan2(dz, dx);
            road_id[arms] = road_index;
            arms += 1;
        }
        if (arms < 2) continue;
        // Order the roads by the bearing they leave the node at.
        var i: usize = 1;
        while (i < arms) : (i += 1) {
            const key_away = away[i];
            const key_x = normal_x[i];
            const key_z = normal_z[i];
            const key_id = road_id[i];
            var j: usize = i;
            while (j > 0 and away[j - 1] > key_away) : (j -= 1) {
                away[j] = away[j - 1];
                normal_x[j] = normal_x[j - 1];
                normal_z[j] = normal_z[j - 1];
                road_id[j] = road_id[j - 1];
            }
            away[j] = key_away;
            normal_x[j] = key_x;
            normal_z[j] = key_z;
            road_id[j] = key_id;
        }
        var k: usize = 0;
        while (k < arms) : (k += 1) {
            const next = (k + 1) % arms;
            const centre = city.Vec{ .x = node_x, .z = node_z };
            const corner = city.Vec{ .x = node_x + normal_x[k] * half, .z = node_z + normal_z[k] * half };
            const opposite = city.Vec{ .x = node_x - normal_x[next] * half, .z = node_z - normal_z[next] * half };
            if (!per_road) {
                terrainFace(&[_]city.Vec{ centre, corner, opposite }, uniform_offset, uniform_color);
                continue;
            }
            const mid = city.Vec{ .x = (corner.x + opposite.x) / 2, .z = (corner.z + opposite.z) / 2 };
            const left = city.roads[road_id[k]];
            const right = city.roads[road_id[next]];
            terrainFace(&[_]city.Vec{ centre, corner, mid }, surfaceOffset(left), surfaceColor(left, road_id[k]));
            terrainFace(&[_]city.Vec{ centre, mid, opposite }, surfaceOffset(right), surfaceColor(right, road_id[next]));
        }
    }
}

// Where a ribbon chain turns at a node, its own two perpendicular end edges
// leave the wedge two roads leave. The quad between them is painted in the
// ribbon's colour and layer, so a selected route, a stop chain or a drafted
// work order reads around a junction instead of breaking at it.
fn ribbonJoin(from: city.Vec, node: city.Vec, to: city.Vec, half: f32, lateral: f32, offset: f32, color: Color) void {
    const in_len = city.hypot(node.x - from.x, node.z - from.z);
    const out_len = city.hypot(to.x - node.x, to.z - node.z);
    if (in_len < 0.001 or out_len < 0.001) return;
    const in_x = -(node.z - from.z) / in_len;
    const in_z = (node.x - from.x) / in_len;
    const out_x = -(to.z - node.z) / out_len;
    const out_z = (to.x - node.x) / out_len;
    terrainFace(&[_]city.Vec{
        .{ .x = node.x + in_x * (lateral + half), .z = node.z + in_z * (lateral + half) },
        .{ .x = node.x + in_x * (lateral - half), .z = node.z + in_z * (lateral - half) },
        .{ .x = node.x + out_x * (lateral - half), .z = node.z + out_z * (lateral - half) },
        .{ .x = node.x + out_x * (lateral + half), .z = node.z + out_z * (lateral + half) },
    }, offset, color);
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
// Slice 15: greenery. A green lot is planted from its own seed, so the same
// park always carries the same trees and bushes and nothing has to be saved
// beyond the lot itself. Trees stand on trunks with a rounded canopy of three
// slabs; bushes are low two-slab clumps.
fn tree(x: f32, z: f32, size: f32, i: usize) void {
    const y = city.elevation(x, z);
    box(x - size * 0.09, z - size * 0.09, size * 0.18, size * 0.18, size * 0.85, y, .{ 0.32, 0.26, 0.19 });
    const trunk = y + size * 0.85;
    box(x - size * 0.5, z - size * 0.5, size, size, size * 0.55, trunk, if (i % 3 == 0) .{ 0.22, 0.36, 0.21 } else .{ 0.25, 0.40, 0.23 });
    box(x - size * 0.34, z - size * 0.34, size * 0.68, size * 0.68, size * 0.5, trunk + size * 0.5, .{ 0.29, 0.44, 0.26 });
}

fn bush(x: f32, z: f32, size: f32, i: usize) void {
    const y = city.elevation(x, z);
    box(x - size * 0.5, z - size * 0.5, size, size, size * 0.5, y, if (i % 2 == 0) .{ 0.28, 0.40, 0.25 } else .{ 0.32, 0.43, 0.28 });
    box(x - size * 0.32, z - size * 0.32, size * 0.64, size * 0.64, size * 0.3, y + size * 0.4, .{ 0.34, 0.46, 0.29 });
}

// Plant one green lot. Density scales with the lot's own area, so the large
// authored parks read as woodland and a pocket playground gets a pair of trees.
fn vegetation(b: city.Building, i: usize) void {
    const area = b.width * b.depth;
    const plant_count: usize = @intFromFloat(std.math.clamp(area / 90, 2, 26));
    const seed: u32 = @as(u32, @intCast(i)) *% 2654435761;
    const margin: f32 = if (b.kind == .playground) 4.5 else 3.0;
    var k: usize = 0;
    while (k < plant_count) : (k += 1) {
        const ux = city.hash01(seed +% @as(u32, @intCast(k)) * 7 + 1);
        const uz = city.hash01(seed +% @as(u32, @intCast(k)) * 13 + 5);
        const roll = city.hash01(seed +% @as(u32, @intCast(k)) * 29 + 11);
        const x = b.x + margin + ux * @max(0.5, b.width - margin * 2);
        const z = b.z + margin + uz * @max(0.5, b.depth - margin * 2);
        if (roll < 0.68) {
            tree(x, z, 2.2 + roll * 2.4, i + k);
        } else {
            bush(x, z, 1.4 + roll * 1.2, i + k);
        }
    }
}

// Playground equipment: a slide, a swing frame and a climbing frame on the
// sand, so a family visit has something to walk to.
fn playground(b: city.Building) void {
    const cx = b.x + b.width * 0.5;
    const cz = b.z + b.depth * 0.5;
    const y = city.elevation(cx, cz);
    // Sand pit.
    groundQuad(cx - b.width * 0.42, cz - b.depth * 0.42, b.width * 0.84, b.depth * 0.84, 0.09, .{ 0.74, 0.68, 0.51 });
    // Slide: a ladder, a tall deck and a ramp down.
    box(cx - 2.2, cz - 0.7, 0.3, 0.3, 1.5, y, .{ 0.55, 0.30, 0.24 });
    box(cx - 1.0, cz - 0.9, 1.2, 1.8, 0.12, y + 1.4, .{ 0.62, 0.36, 0.28 });
    box(cx + 0.2, cz - 0.6, 2.1, 1.2, 0.12, y + 0.9, .{ 0.70, 0.48, 0.30 });
    // Swing frame with two seats.
    box(cx - 0.1, cz + 2.6, 0.18, 0.18, 2.2, y, .{ 0.42, 0.44, 0.46 });
    box(cx + 3.0, cz + 2.6, 0.18, 0.18, 2.2, y, .{ 0.42, 0.44, 0.46 });
    box(cx - 0.1, cz + 2.52, 3.2, 0.12, 0.14, y + 2.1, .{ 0.48, 0.50, 0.52 });
    box(cx + 0.5, cz + 2.5, 0.7, 0.10, 0.10, y + 1.2, .{ 0.30, 0.32, 0.34 });
    box(cx + 2.0, cz + 2.5, 0.7, 0.10, 0.10, y + 1.2, .{ 0.30, 0.32, 0.34 });
    // Climbing frame.
    box(cx - 3.6, cz + 2.2, 1.8, 1.8, 1.6, y, .{ 0.58, 0.49, 0.32 });
    box(cx - 3.5, cz + 2.3, 1.6, 1.6, 0.12, y + 1.6, .{ 0.66, 0.57, 0.38 });
}

// A downtown plaza: paving, a fountain and a pair of benches.
fn plaza(b: city.Building) void {
    const cx = b.x + b.width * 0.5;
    const cz = b.z + b.depth * 0.5;
    const y = city.elevation(cx, cz);
    groundQuad(b.x + 0.6, b.z + 0.6, @max(1, b.width - 1.2), @max(1, b.depth - 1.2), 0.08, .{ 0.58, 0.56, 0.51 });
    box(cx - 2.2, cz - 2.2, 4.4, 4.4, 0.45, y + 0.05, .{ 0.52, 0.51, 0.47 });
    box(cx - 1.5, cz - 1.5, 3.0, 3.0, 0.55, y + 0.1, .{ 0.40, 0.50, 0.55 });
    box(cx - 0.45, cz - 0.45, 0.9, 0.9, 1.5, y + 0.5, .{ 0.62, 0.62, 0.58 });
    for (0..2) |side| {
        const sx = cx + (if (side == 0) -@as(f32, 5.0) else 5.0);
        box(sx - 0.9, cz - 0.35, 1.8, 0.7, 0.12, y + 0.5, .{ 0.46, 0.36, 0.27 });
        box(sx - 0.9, cz - 0.35, 0.12, 0.7, 0.45, y + 0.05, .{ 0.40, 0.42, 0.44 });
        box(sx + 0.78, cz - 0.35, 0.12, 0.7, 0.45, y + 0.05, .{ 0.40, 0.42, 0.44 });
    }
}

fn carColor(id: usize) Color {
    const palette = [_]Color{ .{ 0.64, 0.27, 0.22 }, .{ 0.26, 0.38, 0.52 }, .{ 0.78, 0.76, 0.69 }, .{ 0.25, 0.29, 0.27 }, .{ 0.62, 0.52, 0.31 }, .{ 0.48, 0.51, 0.55 }, .{ 0.36, 0.45, 0.34 } };
    return palette[(id * 17 + id / 7) % palette.len];
}
pub fn draw(w: f32, h: f32) void {
    width = w;
    height = h;
    count = 0;
    // One bucket pass over the roads, so the joins below can walk each node's
    // own roads instead of rescanning the whole road list once per node.
    city.buildIncidence();
    for (0..city.rows) |row| for (0..city.cols) |col| {
        const x = @as(f32, @floatFromInt(col)) * city.spacing;
        const z = @as(f32, @floatFromInt(row)) * city.spacing;
        groundQuad(x, z, city.spacing, city.spacing, 0, .{ 0.36, 0.40, 0.32 });
    };
    riverSurface();
    riverBank();
    bridgeDecks();
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
    junctionFans(kerb_half, pavement_kerb, kerb_color, false);
    junctionFans(surface_half, pavement_surface, kerb_color, true);
    for (city.roads, 0..) |r, id| {
        const a = city.Vec{ .x = city.nodes[r.a].x, .z = city.nodes[r.a].z };
        const b = city.Vec{ .x = city.nodes[r.b].x, .z = city.nodes[r.b].z };
        ribbon(a, b, kerb_half, 0, pavement_kerb, kerb_color);
        ribbon(a, b, surface_half, 0, surfaceOffset(r), surfaceColor(r, id));
        if (transport.lanes[id] != 0) ribbon(a, b, 0.15, 1.4, pavement_lane, if (transport.lanes[id] == 1) .{ 0.3, 0.55, 0.8 } else .{ 0.35, 0.65, 0.35 });
        const length = city.hypot(b.x - a.x, b.z - a.z);
        const ux = (b.x - a.x) / length;
        const uz = (b.z - a.z) / length;
        var d: f32 = 1;
        while (d + 1 < length) : (d += 3.2) ribbon(.{ .x = a.x + ux * d, .z = a.z + uz * d }, .{ .x = a.x + ux * (d + 1), .z = a.z + uz * (d + 1) }, 0.05, 0, pavement_dash, .{ 0.65, 0.63, 0.51 });
        if (r.crosswalk and length > 5) for (0..2) |end| {
            const n = if (end == 0) r.a else r.b;
            if (city.degree(n) < 3) continue;
            const t: f32 = if (end == 0) 3.6 else length - 3.6;
            const c = city.Vec{ .x = a.x + ux * t, .z = a.z + uz * t };
            for (0..7) |stripe| {
                const off = -1.5 + @as(f32, @floatFromInt(stripe)) * 0.5;
                ribbon(.{ .x = c.x - ux * 0.5, .z = c.z - uz * 0.5 }, .{ .x = c.x + ux * 0.5, .z = c.z + uz * 0.5 }, 0.14, off, pavement_crossing, .{ 0.88, 0.86, 0.74 });
            }
        };
    }
    // Slice 11: signal heads stand back from the corner on their own arm, one
    // per branch, and only the branch holding green shows a green lamp.
    for (transport.signals.junctions[0..transport.signals.count], 0..) |junction, junction_index| {
        if (!junction.active) continue;
        for (junction.arms[0..junction.arm_count], 0..) |arm, slot| {
            if (arm < 0) continue;
            const road_id: usize = @intCast(arm);
            const p = transport.signals.headPosition(junction.node, road_id) orelse continue;
            const y = city.elevation(p.x, p.z) + pavement_kerb;
            const state = transport.signals.armState(&junction, slot, game.elapsed);
            const selected_head = selected_signal == @as(i32, @intCast(signal_index(junction_index, slot)));
            box(p.x - 0.08, p.z - 0.08, 0.16, 0.16, 1.7, y, .{ 0.25, 0.27, 0.25 });
            box(p.x - 0.19, p.z - 0.19, 0.38, 0.38, 0.66, y + 1.6, if (selected_head) .{ 0.95, 0.8, 0.35 } else .{ 0.12, 0.14, 0.13 });
            const lamp = switch (state) {
                .green => Color{ 0.26, 0.9, 0.4 },
                .yellow, .flash => Color{ 0.95, 0.78, 0.2 },
                .red => Color{ 1, 0.24, 0.12 },
            };
            // The pole now starts at the pavement, so the head keeps the
            // absolute height it had when its base was 0.12 m lower.
            const lit = switch (state) {
                .green => @as(f32, 1.66),
                .yellow, .flash => @as(f32, 1.82),
                .red => @as(f32, 1.98),
            };
            // Slice 12: a flashing head is lit for half of every blink, which is
            // what tells the player at a glance that the junction is on caution
            // rather than on a green.
            const shown = if (state == .flash and !transport.signals.flashLit(&junction, game.elapsed))
                Color{ 0.30, 0.26, 0.11 }
            else
                lamp;
            box(p.x - 0.21, p.z - 0.21, 0.42, 0.42, 0.16, y + lit, shown);
        }
    }
    // Ground-only projected shadows, clipped into small terrain-following cells.
    const hour: f32 = @floatCast(@mod(game.elapsed / 20, 24));
    if (hour > 6 and hour < 18) {
        const azimuth = (hour - 6) / 12 * std.math.pi;
        for (city.lots()) |b| {
            if (b.kind == .park or b.kind == .vacant) continue;
            const reach = @min(16, b.height / @max(0.4, @sin(azimuth)));
            for (0..6) |step| {
                const t = @as(f32, @floatFromInt(step)) / 6;
                groundQuad(b.x - @cos(azimuth) * reach * t, b.z + reach * 0.45 * t, b.width, b.depth, 0.025, .{ 0.29, 0.33, 0.27 });
            }
        }
    }
    for (city.lots(), 0..) |b, i| {
        const materials = [_]Color{ .{ 0.57, 0.52, 0.43 }, .{ 0.62, 0.60, 0.53 }, .{ 0.47, 0.42, 0.36 }, .{ 0.66, 0.65, 0.60 }, .{ 0.48, 0.50, 0.48 } };
        const color: Color = if (b.kind == .office) .{ 0.43, 0.48, 0.48 } else if (b.kind == .park) .{ 0.33, 0.43, 0.31 } else if (b.kind == .apartment) .{ 0.55, 0.45, 0.40 } else if (b.kind == .market) .{ 0.60, 0.48, 0.35 } else materials[i % materials.len];
        if (selected == @as(i32, @intCast(i)) and (b.kind == .vacant or b.kind == .park or b.kind == .plaza or b.kind == .playground)) groundQuad(b.x - 0.25, b.z - 0.25, b.width + 0.5, b.depth + 0.5, 0.03, .{ 0.94, 0.76, 0.32 });
        if (b.kind == .vacant) {
            groundQuad(b.x, b.z, b.width, b.depth, 0.025, .{ 0.43, 0.46, 0.35 });
            continue;
        }
        // Slice 15: green space. Every park, playground and plaza is planted
        // from its own identity, so a large park reads as trees and bushes in
        // grass without carrying a second list of positions in the save file.
        if (b.kind == .park or b.kind == .playground or b.kind == .plaza) {
            groundQuad(b.x, b.z, b.width, b.depth, 0.06, color);
            vegetation(b, i);
            if (b.kind == .playground) playground(b);
            if (b.kind == .plaza) plaza(b);
            continue;
        }
        const entry = city.frontage(b);
        ribbon(entry, .{ .x = b.entry_x, .z = b.entry_z }, 0.4, 0, pavement_kerb, .{ 0.55, 0.53, 0.47 });
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
            // Slice 15: only the two façades the camera can see carry window
            // boxes, and windows step every 2.6 m rather than every 2 m. The
            // dense town has three times the lots of the old lattice, so this
            // is what keeps a full street wall inside the vertex budget.
            const toward_x = @cos(angle) <= 0;
            const toward_z = @sin(angle) <= 0;
            var floor: f32 = 1.5;
            while (floor + 0.75 <= b.height - 0.4) : (floor += 2.6) {
                for (0..3) |j| {
                    const offset = 0.8 + @as(f32, @floatFromInt(j)) * (@min(b.width, b.depth) - 2.4) / 2;
                    if (toward_z) box(b.x + offset, b.z - 0.035, 0.8, 0.035, 0.75, b.ground + floor, .{ 0.27, 0.32, 0.33 });
                    if (toward_x) box(b.x - 0.035, b.z + offset, 0.035, 0.8, 0.75, b.ground + floor, .{ 0.27, 0.32, 0.33 });
                    if (!toward_z) box(b.x + offset, b.z + b.depth, 0.8, 0.035, 0.75, b.ground + floor, .{ 0.26, 0.31, 0.31 });
                    if (!toward_x) box(b.x + b.width, b.z + offset, 0.035, 0.8, 0.75, b.ground + floor, .{ 0.29, 0.34, 0.34 });
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
        var previous: city.Vec = undefined;
        while (node != p.destination and steps < city.node_count and p.bus < 0) : (steps += 1) {
            const next = if ((p.mode == 0 or p.mode == 3) and @mod(selected_person, 5) != 0) city.walk_next[node][p.destination] else city.next_node[node][p.destination];
            const a = city.nodes[node];
            const b = city.nodes[next];
            const from = city.Vec{ .x = a.x, .z = a.z };
            if (steps > 0) ribbonJoin(previous, from, .{ .x = b.x, .z = b.z }, 0.15, 2.3, pavement_ribbon, .{ 0.95, 0.76, 0.3 });
            ribbon(from, .{ .x = b.x, .z = b.z }, 0.15, 2.3, pavement_ribbon, .{ 0.95, 0.76, 0.3 });
            previous = from;
            node = next;
        }
        const y = actorPlane(p.x, p.z, p.y);
        box(p.x - 0.3, p.z - 0.3, 0.6, 0.6, 0.12, y + 0.2, .{ 1, 0.82, 0.25 });
    }
    // Every active line has visible kerbside stop markers, not only the selected line.
    for (&transport.lines, 0..) |line, line_id| {
        if (!line.active) continue;
        for (line.stops[0..line.count]) |stop| {
            if (!city.validStop(stop)) continue;
            const p = city.stopPoint(stop);
            const base = city.elevation(p.x, p.z) + pavement_kerb;
            const accent: Color = if (transport.selected == line_id) .{ 1, 0.78, 0.24 } else .{ 0.72, 0.5, 0.18 };
            box(p.x - 0.08, p.z - 0.08, 0.16, 0.16, 1.35, base, .{ 0.32, 0.36, 0.38 });
            box(p.x - 0.45, p.z - 0.12, 0.9, 0.24, 0.45, base + 1.35, accent);
        }
    }
    if (transport.selected >= 0 or transport.editing) {
        const stops = if (transport.editing) transport.draft[0..transport.draft_count] else transport.lines[@intCast(transport.selected)].stops[0..transport.lines[@intCast(transport.selected)].count];
        for (stops, 0..) |stop, index| {
            const p = city.stopPoint(stop);
            box(p.x - 0.7, p.z - 0.7, 1.4, 1.4, 0.25, city.elevation(p.x, p.z) + pavement_kerb, .{ 0.95, 0.72, 0.23 });
            var node = stop;
            var steps: usize = 0;
            var previous: city.Vec = undefined;
            const destination = stops[(index + 1) % stops.len];
            while (node != destination and steps < city.node_count) : (steps += 1) {
                const next = city.next_node[node][destination];
                const a = city.nodes[node];
                const b = city.nodes[next];
                const from = city.Vec{ .x = a.x, .z = a.z };
                if (steps > 0) ribbonJoin(previous, from, .{ .x = b.x, .z = b.z }, 0.17, 0, pavement_ribbon, .{ 0.98, 0.72, 0.22 });
                ribbon(from, .{ .x = b.x, .z = b.z }, 0.17, 0, pavement_ribbon, .{ 0.98, 0.72, 0.22 });
                previous = from;
                node = next;
            }
        }
    }
    if (game.roadworks.active and game.roadworks.count > 1) {
        const color: Color = if (game.roadworks.error_code == 0) .{ 0.35, 0.8, 0.65 } else .{ 0.95, 0.28, 0.24 };
        for (game.roadworks.points[0 .. game.roadworks.count - 1], 0..) |a, i| {
            const b = game.roadworks.points[i + 1];
            if (i > 0) ribbonJoin(game.roadworks.points[i - 1], a, b, kerb_half, 0, pavement_works, color);
            ribbon(a, b, kerb_half, 0, pavement_works, color);
        }
        for (game.roadworks.knots[0..game.roadworks.knot_count]) |p| box(p.x - 0.4, p.z - 0.4, 0.8, 0.8, 1.3, city.elevation(p.x, p.z) + pavement_works, color);
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
            y = @max(y, city.elevation(v.x + ux * length / 2 * front - uz * 0.325 * side, v.z + uz * length / 2 * front + ux * 0.325 * side) + pavement_surface);
        };
        const body: f32 = if (v.line >= 0) 0.95 else 0.55;
        vehicleBox(v.x, v.z, length, 0.65, body, y, ux, uz, color);
        vehicleBox(v.x, v.z, length * 0.56, 0.4, 0.16, y + body, ux, uz, .{ 0.2, 0.29, 0.32 });
    }
    for (&game.residents.people, 0..) |p, i| {
        if (p.phase == 3 or (p.mode == 2 and p.phase == 1) or p.bus >= 0) continue;
        const plane = actorPlane(p.x, p.z, p.y);
        if (p.mode == 1) box(p.x - 0.35, p.z - 0.15, 0.7, 0.3, 0.25, plane, .{ 0.16, 0.20, 0.18 });
        const dx = @cos(angle) * 0.16;
        const dz = -@sin(angle) * 0.16;
        const y = plane;
        const colors = [_]Color{ .{ 0.70, 0.62, 0.44 }, .{ 0.65, 0.68, 0.62 }, .{ 0.53, 0.38, 0.30 }, .{ 0.34, 0.44, 0.51 } };
        const color: Color = if (p.order >= 0) .{ 1, 0.66, 0.15 } else colors[i % 4];
        quad(.{ p.x - dx, y, p.z - dz }, .{ p.x + dx, y, p.z + dz }, .{ p.x + dx, y + 0.9, p.z + dz }, .{ p.x - dx, y + 0.9, p.z - dz }, color);
    }
}
// Heads are addressed by a flat index: junctions in order, then their arms.
pub fn signal_index(junction_index: usize, slot: usize) usize {
    var index: usize = 0;
    var j: usize = 0;
    while (j < junction_index and j < transport.signals.count) : (j += 1) index += transport.signals.junctions[j].arm_count;
    return index + slot;
}

// Slice 11: nearest signal head under the cursor, in screen pixels. Sets the
// renderer's own selection so the inspector and the highlight agree.
pub fn pickSignal(sx: f32, sy: f32, radius: f32) i32 {
    var best: i32 = -1;
    var best_distance: f32 = radius * radius;
    for (transport.signals.junctions[0..transport.signals.count], 0..) |junction, junction_index| {
        if (!junction.active) continue;
        for (junction.arms[0..junction.arm_count], 0..) |arm, slot| {
            if (arm < 0) continue;
            const p = transport.signals.headPosition(junction.node, @intCast(arm)) orelse continue;
            const py = city.elevation(p.x, p.z) + 2.0;
            const px = p.x - camera_x;
            const pz = p.z - camera_z;
            const screen_x = width / 2 + (px * @cos(angle) - pz * @sin(angle)) * scale();
            const screen_y = height / 2 - (py * 0.8164966 - (px * @sin(angle) + pz * @cos(angle)) * 0.5773503) * scale();
            const d = (screen_x - sx) * (screen_x - sx) + (screen_y - sy) * (screen_y - sy);
            if (d < best_distance) {
                best_distance = d;
                best = @intCast(signal_index(junction_index, slot));
            }
        }
    }
    selected_signal = best;
    return best;
}

pub fn pick(sx: f32, sy: f32) void {
    const across = (sx - width / 2) / scale();
    const back = (sy - height / 2) / scale() / 0.5773503;
    const origin = Point{ camera_x + across * @cos(angle) + back * @sin(angle), 0, camera_z - across * @sin(angle) + back * @cos(angle) };
    const direction = Point{ @sin(angle) * 0.8164966, 0.5773503, @cos(angle) * 0.8164966 };
    var nearest: f32 = -1e9;
    selected = -1;
    selected_person = -1;
    for (city.lots(), 0..) |b, i| {
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

pub fn projectWorld(x: f32, y: f32, z: f32, axis: u32) f32 {
    const dx = x - camera_x;
    const dz = z - camera_z;
    return if (axis == 0) width / 2 + (dx * @cos(angle) - dz * @sin(angle)) * scale() else height / 2 - ((y + 0.3) * 0.8164966 - (dx * @sin(angle) + dz * @cos(angle)) * 0.5773503) * scale();
}

pub fn project(node: usize, axis: u32) f32 {
    const n = city.nodes[node];
    return projectWorld(n.x, n.y, n.z, axis);
}
