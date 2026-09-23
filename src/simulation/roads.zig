const std = @import("std");
const city = @import("../scene/city.zig");
const River = city.River;
const parcels = @import("../scene/parcels.zig");
const transport = @import("transport.zig");
const residents = @import("residents.zig");
const finance = @import("finance.zig");
const contracts = @import("contracts.zig");
pub var points: [65]city.Vec = undefined;
pub var count: usize = 0;
pub var cost: f64 = 0;
pub var length: f32 = 0;
pub var error_code: u32 = 0;
pub var active = false;
pub var curved = false;
pub var knots: [3]city.Vec = @splat(.{ .x = 0, .z = 0 });
pub var knot_count: usize = 0;
// Slice 10: the road tool chooses a street class (0 lane, 1 street, 2 avenue).
pub var class: u8 = 1;
// 0 valid, 1 bounds/length, 2 occupied parcel, 3 grade, 4 funds,
// 5 network capacity, 6 reserved works, 7 overlap/shallow junction, 8 disconnected.
pub fn reset() void {
    count = 0;
    knot_count = 0;
    active = false;
    cost = 0;
    error_code = 0;
}
pub fn snap(p: city.Vec) city.Vec {
    var best: f32 = 5;
    var result = p;
    for (city.nodes) |n| {
        const d = city.hypot(p.x - n.x, p.z - n.z);
        if (d < best) {
            best = d;
            result = .{ .x = n.x, .z = n.z };
        }
    }
    if (best < 5) return result;
    best = 3;
    for (city.roads) |r| {
        const a = city.nodes[r.a];
        const b = city.nodes[r.b];
        const t = city.projection(p, a, b);
        const q = city.Vec{ .x = a.x + (b.x - a.x) * t, .z = a.z + (b.z - a.z) * t };
        const d = city.hypot(q.x - p.x, q.z - p.z);
        if (d < best) {
            best = d;
            result = q;
        }
    }
    return result;
}
fn cross(a: city.Vec, b: city.Vec) f32 {
    return a.x * b.z - a.z * b.x;
}
fn sub(a: city.Vec, b: city.Vec) city.Vec {
    return .{ .x = a.x - b.x, .z = a.z - b.z };
}
const Hit = struct { t: f32, u: f32 };
fn intersection(a: city.Vec, b: city.Vec, c: city.Vec, d: city.Vec) ?Hit {
    const ab = sub(b, a);
    const cd = sub(d, c);
    const denominator = cross(ab, cd);
    if (@abs(denominator) < 0.0001) return null;
    const t = cross(sub(c, a), cd) / denominator;
    const u = cross(sub(c, a), ab) / denominator;
    if (t < -0.0001 or t > 1.0001 or u < -0.0001 or u > 1.0001) return null;
    return .{ .t = std.math.clamp(t, 0, 1), .u = std.math.clamp(u, 0, 1) };
}
fn hitsBuilding(a: city.Vec, b: city.Vec, building: city.Building) bool {
    var low: f32 = 0;
    var high: f32 = 1;
    for (0..2) |axis| {
        const p = if (axis == 0) a.x else a.z;
        const delta = if (axis == 0) b.x - a.x else b.z - a.z;
        const minimum = (if (axis == 0) building.x else building.z) - 3;
        const maximum = (if (axis == 0) building.x + building.width else building.z + building.depth) + 3;
        if (@abs(delta) < 0.00001) {
            if (p < minimum or p > maximum) return false;
        } else {
            const t1 = (minimum - p) / delta;
            const t2 = (maximum - p) / delta;
            low = @max(low, @min(t1, t2));
            high = @min(high, @max(t1, t2));
        }
    }
    return high >= low;
}
pub fn preview() void {
    count = 0;
    cost = 0;
    length = 0;
    error_code = 0;
    if (knot_count < 2) return;
    const start = snap(knots[0]);
    const end = snap(knots[if (curved and knot_count == 3) @as(usize, 2) else 1]);
    const control = knots[1];
    const estimate = if (curved and knot_count == 3) city.hypot(control.x - start.x, control.z - start.z) + city.hypot(end.x - control.x, end.z - control.z) else city.hypot(end.x - start.x, end.z - start.z);
    if (!std.math.isFinite(estimate) or estimate < 6 or estimate > 500) {
        error_code = 1;
        return;
    }
    const pieces: usize = @intFromFloat(@ceil(estimate / 10));
    count = pieces + 1;
    for (points[0..count], 0..) |*p, i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(pieces));
        p.* = if (curved and knot_count == 3) .{ .x = (1 - t) * (1 - t) * start.x + 2 * (1 - t) * t * control.x + t * t * end.x, .z = (1 - t) * (1 - t) * start.z + 2 * (1 - t) * t * control.z + t * t * end.z } else .{ .x = start.x + (end.x - start.x) * t, .z = start.z + (end.z - start.z) * t };
    }
    var cuts: usize = 0;
    var connected = false;
    for (points[0 .. count - 1], 0..) |a, i| {
        const b = points[i + 1];
        const len = city.hypot(b.x - a.x, b.z - a.z);
        length += len;
        if (a.x < 3 or a.z < 3 or a.x > city.size_x - 3 or a.z > city.size_z - 3 or b.x < 3 or b.z < 3 or b.x > city.size_x - 3 or b.z > city.size_z - 3) {
            error_code = 1;
            return;
        }
        // Slice 13: the river is an obstacle. Only the seeded bridges cross it;
        // the road tool refuses a span that would run over the water.
        if (River.crosses(a.x, a.z, b.x, b.z)) {
            error_code = 9;
            return;
        }
        for (&city.buildings) |building| {
            if (building.kind != .vacant and hitsBuilding(a, b, building)) {
                error_code = 2;
                return;
            }
        }
        var last = city.elevation(a.x, a.z);
        for (1..11) |sample| {
            const t = @as(f32, @floatFromInt(sample)) / 10;
            const y = city.elevation(a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t);
            if (@abs(y - last) / (len / 10) > 0.5) {
                error_code = 3;
                return;
            }
            last = y;
        }
        for (city.roads, 0..) |r, rid| {
            const c = city.Vec{ .x = city.nodes[r.a].x, .z = city.nodes[r.a].z };
            const d = city.Vec{ .x = city.nodes[r.b].x, .z = city.nodes[r.b].z };
            if (intersection(a, b, c, d)) |hit| {
                _ = hit;
                cuts += 1;
                connected = true;
                if (contracts.siteBusy(rid)) {
                    error_code = 6;
                    return;
                }
                const sine = @abs(cross(sub(b, a), sub(d, c))) / (len * city.hypot(d.x - c.x, d.z - c.z));
                if (sine < 0.25) {
                    error_code = 7;
                    return;
                }
            } else {
                const ab = sub(b, a);
                const cd = sub(d, c);
                if (@abs(cross(ab, cd)) / (len * city.hypot(cd.x, cd.z)) < 0.1 and @abs(cross(sub(c, a), ab)) / len < 2.8) {
                    const u = ((c.x - a.x) * ab.x + (c.z - a.z) * ab.z) / (len * len);
                    const v = ((d.x - a.x) * ab.x + (d.z - a.z) * ab.z) / (len * len);
                    if (@min(1, @max(u, v)) - @max(0, @min(u, v)) > 0.05) {
                        error_code = 7;
                        return;
                    }
                    if (city.hypot(a.x - c.x, a.z - c.z) < 0.1 or city.hypot(a.x - d.x, a.z - d.z) < 0.1 or city.hypot(b.x - c.x, b.z - c.z) < 0.1 or city.hypot(b.x - d.x, b.z - d.z) < 0.1) connected = true;
                }
            }
        }
    }
    if (!connected) {
        error_code = 8;
        return;
    }
    if (city.node_count + count + cuts > city.max_nodes or city.road_count + count + cuts * 2 > city.max_roads) {
        error_code = 5;
        return;
    }
    const per_metre = if (class == 2) @as(f64, 40) else if (class == 0) @as(f64, 18) else @as(f64, 25);
    cost = finance.cents(@as(f64, length) * per_metre);
    if (cost > finance.available()) error_code = 4;
}
fn nodeAt(p: city.Vec, street: usize) usize {
    for (city.nodes, 0..) |n, id| {
        if (city.hypot(p.x - n.x, p.z - n.z) < 2.5) return id;
    }
    const before = city.road_count;
    for (0..before) |id| {
        const r = city.roads[id];
        const t = city.projection(p, city.nodes[r.a], city.nodes[r.b]);
        const x = city.nodes[r.a].x + (city.nodes[r.b].x - city.nodes[r.a].x) * t;
        const z = city.nodes[r.a].z + (city.nodes[r.b].z - city.nodes[r.a].z) * t;
        if (city.hypot(p.x - x, p.z - z) < 0.15) {
            const n = city.splitRoad(id, x, z);
            if (city.road_count > before) transport.lanes[city.road_count - 1] = transport.lanes[id];
            return n;
        }
    }
    return city.addNode(p.x, p.z, street);
}
const Link = struct { a: usize, b: usize, t: f32 };
fn reconnect(old: city.Road, x: f32, z: f32, forward: bool) Link {
    var best: f32 = 1e9;
    var result: Link = .{ .a = old.a, .b = old.b, .t = 0 };
    for (city.roads) |r| {
        if (r.street != old.street) continue;
        const a = city.nodes[r.a];
        const b = city.nodes[r.b];
        const t = city.projection(.{ .x = x, .z = z }, a, b);
        const d = city.hypot(a.x + (b.x - a.x) * t - x, a.z + (b.z - a.z) * t - z);
        if (d < best) {
            best = d;
            const dot = (b.x - a.x) * (city.nodes[old.b].x - city.nodes[old.a].x) + (b.z - a.z) * (city.nodes[old.b].z - city.nodes[old.a].z);
            const same = (dot >= 0) == forward;
            result = .{ .a = if (same) r.a else r.b, .b = if (same) r.b else r.a, .t = if (same) t else 1 - t };
        }
    }
    return result;
}
pub fn build(time: f64) bool {
    preview();
    if (count < 2 or error_code != 0) return false;
    var old_roads: [city.max_roads]city.Road = undefined;
    const old_count = city.road_count;
    @memcpy(old_roads[0..old_count], city.roads);
    var vehicle_road: [transport.vehicles.len]i16 = undefined;
    for (&transport.vehicles, 0..) |v, i| vehicle_road[i] = if (v.active and v.node != v.next) city.road_between[v.node][v.next] else -1;
    var person_road: [city.population]i16 = undefined;
    for (&residents.people, 0..) |p, i| person_road[i] = if (p.phase == 1 and p.node != p.next) city.road_between[p.node][p.next] else -1;
    const street = city.street_count;
    city.street_count += 1;
    for (points[0 .. count - 1], 0..) |a, i| {
        const b = points[i + 1];
        var values: [city.max_roads + 2]f32 = undefined;
        var used: usize = 2;
        values[0] = 0;
        values[1] = 1;
        for (city.roads) |r| {
            if (intersection(a, b, .{ .x = city.nodes[r.a].x, .z = city.nodes[r.a].z }, .{ .x = city.nodes[r.b].x, .z = city.nodes[r.b].z })) |hit| {
                values[used] = hit.t;
                used += 1;
            }
        }
        std.mem.sort(f32, values[0..used], {}, std.sort.asc(f32));
        var previous = nodeAt(a, street);
        for (values[1..used]) |t| {
            const n = nodeAt(.{ .x = a.x + (b.x - a.x) * t, .z = a.z + (b.z - a.z) * t }, street);
            if (n == previous) continue;
            var exists = false;
            for (city.roads) |r| {
                if ((r.a == previous and r.b == n) or (r.a == n and r.b == previous)) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                const rid = city.addRoadClass(previous, n, street, class);
                city.roads[rid].condition = 100;
            }
            previous = n;
        }
    }
    city.rebuildRoutes();
    city.revision += 1;
    for (&transport.vehicles, 0..) |*v, i| {
        if (vehicle_road[i] < 0 or city.road_between[v.node][v.next] >= 0) continue;
        const old = old_roads[@intCast(vehicle_road[i])];
        const link = reconnect(old, v.x, v.z, v.node == old.a);
        v.node = link.a;
        v.next = link.b;
        v.progress = link.t * city.roads[@intCast(city.road_between[v.node][v.next])].length;
    }
    for (&residents.people, 0..) |*p, i| {
        if (person_road[i] < 0 or city.road_between[p.node][p.next] >= 0) continue;
        const old = old_roads[@intCast(person_road[i])];
        const link = reconnect(old, p.x, p.z, p.node == old.a);
        p.node = link.a;
        p.next = link.b;
    }
    parcels.addFrontages(old_count);
    finance.record(time, -cost, 9, @intCast(street), -1);
    reset();
    return true;
}
