const std = @import("std");
pub const River = @import("river.zig");

// Slice 13: the seeded town is modelled on the attached Trastevere/Testaccio
// slice of Rome. It is six times the area of the old 520 x 440 lattice, so an
// outer home-to-centre trip is 600-1,000 m rather than 150-300 m, and a river
// with four bridges splits the two banks.
pub const cols = 33;
pub const rows = 26;
pub const spacing: f32 = 40;
pub const size_x: f32 = 1320;
pub const size_z: f32 = 1040;
pub const population = 3840;
pub const district_count = 12;
pub const max_nodes = 640;
pub const max_roads = 1200;
pub const street_count_default: usize = 14;
// Street 12 is reserved for the bridges, which are the only spans that may
// cross the water. Nothing is built on them.
pub const bridge_street: usize = 12;
pub const max_spans = 16;
pub const Kind = enum(u32) { home, shop, office, clinic, hall, park, depot, vacant, bike_park, car_park };
pub const Building = struct { x: f32, z: f32, width: f32, depth: f32, height: f32, ground: f32, kind: Kind, district: usize, node: usize, value: f64, capacity: usize, slots: usize = 0, sun: f32 = 1, occupants: usize = 0, employer: i32 = -1, entry_x: f32 = 0, entry_z: f32 = 0, street: usize = 0, number: usize = 0 };
pub const Node = struct { x: f32, z: f32, y: f32, street: usize = 0, number: usize = 0 };
pub const Road = struct { a: usize, b: usize, length: f32, slope: f32, district: usize, condition: f32, street: usize = 0, class: u8 = 1, pedestrians: bool = true, vehicles: bool = true, crosswalk: bool = false, works: bool = false };
pub const Vec = struct { x: f32, z: f32 };
pub var buildings: [288]Building = undefined;
var node_storage: [max_nodes]Node = undefined;
var road_storage: [max_roads]Road = undefined;
pub var nodes: []Node = node_storage[0..0];
pub var roads: []Road = road_storage[0..0];
pub var building_at_node: [max_nodes]i32 = undefined;
pub var road_between: [max_nodes][max_nodes]i16 = undefined;
pub var walk_next: [max_nodes][max_nodes]u16 = undefined;
var walk_distance: [max_nodes][max_nodes]f32 = undefined;
pub var next_node: [max_nodes][max_nodes]u16 = undefined;
pub var distance: [max_nodes][max_nodes]f32 = undefined;
pub var street_count: usize = street_count_default;
pub const district_names = [_][]const u8{ "Westbank", "Station Quarter", "East Rise", "Foundry Ward", "Civic Centre", "Orchard Hill", "Millfield", "Market Ward", "Highgate", "Southbank", "Garden Ward", "Upper Bellwether" };

// Bridge decks. A span is a road on the bridge street; `elevation` returns its
// level inside the corridor so walkers, vehicles and the renderer all cross at
// the deck height instead of dropping into the carved channel.
pub const Span = struct { ax: f32, az: f32, bx: f32, bz: f32, level: f32 };
pub var spans: [max_spans]Span = undefined;
pub var span_count: usize = 0;
pub var node_count: usize = 0;
pub var road_count: usize = 0;
pub var revision: u32 = 0;

fn ramp(value: f32, start: f32, end: f32) f32 {
    return std.math.clamp((value - start) / (end - start), 0, 1);
}

// The river bounding box, so the carve costs nothing away from the water.
var river_min_x: f32 = 0;
var river_max_x: f32 = 0;
var river_min_z: f32 = 0;
var river_max_z: f32 = 0;

// Raw ground before the river is carved. A hill on the west bank (the
// Janiculum side), a lower ridge in the east, and a gentle rise to the south.
pub fn terrain(x: f32, z: f32) f32 {
    return 7 + ramp(x, 30, 210) * 10 + ramp(x, 1140, 1300) * 7 + ramp(z, 830, 1020) * 5 + ramp(z, 0, 130) * 3;
}

// Walkable surface: the raw terrain with the channel carved into it, plus the
// bridge decks. Called for every vertex, vehicle corner and resident, so the
// river test is guarded by the bounding box computed in `init`.
pub fn elevation(x: f32, z: f32) f32 {
    if (deckAt(x, z)) |level| return level;
    const ground = terrain(x, z);
    if (River.count == 0) return ground;
    if (x < river_min_x or x > river_max_x or z < river_min_z or z > river_max_z) return ground;
    const s = River.nearest(x, z);
    if (s.distance >= s.half_width + River.bank_width) return ground;
    const bed = s.level - River.depth;
    if (s.distance <= s.half_width) return @min(ground, bed);
    const t = (s.distance - s.half_width) / River.bank_width;
    return @min(ground, bed + (s.level + River.bank_height - bed) * t);
}

fn deckAt(x: f32, z: f32) ?f32 {
    for (spans[0..span_count]) |s| {
        const dx = s.bx - s.ax;
        const dz = s.bz - s.az;
        const squared = dx * dx + dz * dz;
        if (squared < 0.01) continue;
        const t = ((x - s.ax) * dx + (z - s.az) * dz) / squared;
        if (t < -0.02 or t > 1.02) continue;
        if (hypot(x - (s.ax + dx * t), z - (s.az + dz * t)) > 3.2) continue;
        return s.level;
    }
    return null;
}

// True inside the water itself, and true a little way up the bank, which is
// what the road tool, the parcel seeder and the building seeder all want.
pub fn inWater(x: f32, z: f32) bool {
    if (River.count == 0) return false;
    const s = River.nearest(x, z);
    return s.distance < s.half_width + 3;
}

pub fn isBridge(road: usize) bool {
    return road < road_count and road_storage[road].street == bridge_street;
}

pub fn districtAt(x: f32, z: f32) usize {
    return @as(usize, @intFromFloat(std.math.clamp(z / (size_z / 4), 0, 3))) * 3 + @as(usize, @intFromFloat(std.math.clamp(x / (size_x / 3), 0, 2)));
}

fn hash01(value: u32) f32 {
    var v = value *% 2654435761;
    v ^= v >> 15;
    v *%= 2246822519;
    v ^= v >> 13;
    return @as(f32, @floatFromInt(v & 0xffff)) / 65535.0;
}

fn jitter(seed: u32, amount: f32) f32 {
    return (hash01(seed) - 0.5) * 2 * amount;
}

// 0 at the centre of the plan, 1 in the outer suburbs. Drives how dense the
// local streets and the buildings are.
fn coreFactor(x: f32, z: f32) f32 {
    const dx = (x - size_x * 0.5) / (size_x * 0.5);
    const dz = (z - size_z * 0.5) / (size_z * 0.5);
    return std.math.clamp(1 - @sqrt(dx * dx + dz * dz) / 1.05, 0, 1);
}

pub fn addNode(x: f32, z: f32, street: usize) usize {
    const id = node_count;
    if (id >= max_nodes) return if (node_count == 0) 0 else node_count - 1;
    const px = std.math.clamp(x, 2, size_x - 2);
    const pz = std.math.clamp(z, 2, size_z - 2);
    var number: usize = 1;
    if (street < street_count_default) {
        number = @intFromFloat(@max(1, @round(if (street % 2 == 0) x else z)));
    } else {
        for (nodes) |n| {
            if (n.street == street) number = @max(number, n.number + 2);
        }
    }
    node_storage[id] = .{ .x = px, .z = pz, .y = elevation(px, pz), .street = street, .number = number };
    node_count += 1;
    nodes = node_storage[0..node_count];
    return id;
}

pub fn addRoad(a: usize, b: usize, street: usize) usize {
    return addRoadClass(a, b, street, classForStreet(street));
}

pub fn addRoadClass(a: usize, b: usize, street: usize, class: u8) usize {
    if (road_count >= max_roads or a == b or a >= node_count or b >= node_count) return if (road_count == 0) 0 else road_count - 1;
    const dx = nodes[b].x - nodes[a].x;
    const dz = nodes[b].z - nodes[a].z;
    const dy = nodes[b].y - nodes[a].y;
    const planar = @sqrt(dx * dx + dz * dz);
    const district = districtAt((nodes[a].x + nodes[b].x) / 2, (nodes[a].z + nodes[b].z) / 2);
    const id = road_count;
    road_storage[id] = .{ .a = a, .b = b, .length = @sqrt(planar * planar + dy * dy), .slope = @abs(dy) / @max(0.01, planar), .district = district, .condition = 70, .street = street, .class = @min(class, 2) };
    road_count += 1;
    roads = road_storage[0..road_count];
    return id;
}

// Seeded street types: the two bank arterials and the central avenue are
// avenues, the local mesh and the ring are lanes, and everything else is an
// ordinary street. Player-built roads carry the class chosen in the road tool.
pub fn classForStreet(street: usize) u8 {
    if (street == 0 or street == 3 or street == 5 or street == 10) return 2;
    if (street == 6 or street == 7 or street == 8 or street == 11 or street == 13) return 0;
    return 1;
}

pub fn splitRoad(id: usize, x: f32, z: f32) usize {
    const old = roads[id];
    if (hypot(x - nodes[old.a].x, z - nodes[old.a].z) < 2.5) return old.a;
    if (hypot(x - nodes[old.b].x, z - nodes[old.b].z) < 2.5) return old.b;
    if (node_count + 1 >= max_nodes) return old.a;
    const n = addNode(x, z, old.street);
    const added = addRoadClass(n, old.b, old.street, old.class);
    const saved = roads[added];
    roads[added] = old;
    roads[added].a = n;
    roads[added].length = saved.length;
    roads[added].slope = saved.slope;
    roads[id].b = n;
    const dy = nodes[n].y - nodes[old.a].y;
    const planar = hypot(x - nodes[old.a].x, z - nodes[old.a].z);
    roads[id].length = @sqrt(planar * planar + dy * dy);
    roads[id].slope = @abs(dy) / @max(0.01, planar);
    return n;
}

pub fn hypot(x: f32, z: f32) f32 {
    return @sqrt(x * x + z * z);
}

pub fn projection(p: Vec, a: Node, b: Node) f32 {
    const dx = b.x - a.x;
    const dz = b.z - a.z;
    const squared = dx * dx + dz * dz;
    if (squared < 0.0001) return 0;
    return std.math.clamp(((p.x - a.x) * dx + (p.z - a.z) * dz) / squared, 0, 1);
}

pub fn degree(n: usize) usize {
    var total: usize = 0;
    for (roads) |r| {
        if (r.a == n or r.b == n) total += 1;
    }
    return total;
}

pub fn horizontal(a: usize, b: usize) bool {
    return @abs(nodes[a].x - nodes[b].x) >= @abs(nodes[a].z - nodes[b].z);
}

pub fn sidewalk(n: usize) Vec {
    var dx: f32 = 1;
    var dz: f32 = 0;
    for (roads) |r| {
        if (r.a == n or r.b == n) {
            dx = nodes[r.b].x - nodes[r.a].x;
            dz = nodes[r.b].z - nodes[r.a].z;
            break;
        }
    }
    const len = hypot(dx, dz);
    if (len < 0.001) return .{ .x = nodes[n].x, .z = nodes[n].z };
    return .{ .x = nodes[n].x - dz / len * 2.3, .z = nodes[n].z + dx / len * 2.3 };
}

fn insideBuilding(x: f32, z: f32, b: Building) bool {
    return x >= b.x and x <= b.x + b.width and z >= b.z and z <= b.z + b.depth;
}

pub fn stopPoint(n: usize) Vec {
    var p = sidewalk(n);
    var flipped = false;
    for (buildings) |b| {
        if (insideBuilding(p.x, p.z, b)) {
            flipped = true;
            break;
        }
    }
    if (flipped) p = .{ .x = 2 * nodes[n].x - p.x, .z = 2 * nodes[n].z - p.z };
    return p;
}

pub fn validStop(n: usize) bool {
    if (n >= node_count or degree(n) == 0) return false;
    const p = stopPoint(n);
    if (p.x < 0 or p.x > size_x or p.z < 0 or p.z > size_z) return false;
    if (inWater(p.x, p.z)) return false;
    for (buildings) |b| if (insideBuilding(p.x, p.z, b)) return false;
    for (roads) |r| if ((r.a == n or r.b == n) and r.pedestrians) return true;
    return false;
}

// Nearest node to a world point, used to lay the seeded bus services on the
// authored map without hard-coded node ids.
pub fn nearestNode(x: f32, z: f32) usize {
    var best: usize = 0;
    var best_distance: f32 = 1e9;
    for (nodes, 0..) |n, i| {
        const d = hypot(n.x - x, n.z - z);
        if (d < best_distance) {
            best_distance = d;
            best = i;
        }
    }
    return best;
}

// The river point at a fraction of the total length, with a perpendicular
// offset in metres. Negative is the west bank, positive the east.
fn riverPoint(chainage: f32, lateral: f32) Vec {
    const s = River.atChainage(chainage);
    const len = @max(0.001, hypot(s.dx, s.dz));
    return .{ .x = s.x - s.dz / len * lateral, .z = s.z + s.dx / len * lateral };
}

// One straight run of a street. Interior points are jittered deterministically
// and any point inside the water is dropped, which splits the run into a
// west-bank piece and an east-bank piece and leaves the bridges to reconnect
// them.
fn chain(street: usize, class: u8, from: Vec, to: Vec, step: f32, seed: u32) void {
    const span = hypot(to.x - from.x, to.z - from.z);
    const pieces: usize = @max(1, @as(usize, @intFromFloat(@round(span / step))));
    var previous: ?usize = null;
    for (0..pieces + 1) |k| {
        if (node_count + 4 >= max_nodes or road_count + 4 >= max_roads) return;
        const t = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(pieces));
        const edge = k == 0 or k == pieces;
        const amount: f32 = if (edge) 0 else @min(9, step * 0.22);
        const x = from.x + (to.x - from.x) * t + jitter(seed +% @as(u32, @intCast(k)) * 7, amount);
        const z = from.z + (to.z - from.z) * t + jitter(seed +% @as(u32, @intCast(k)) * 13 + 5, amount);
        if (x < 8 or z < 8 or x > size_x - 8 or z > size_z - 8 or inWater(x, z)) {
            previous = null;
            continue;
        }
        const node = nodeAt(x, z, street, 9);
        if (previous) |p| {
            if (p != node and road_between[p][node] < 0 and hypot(nodes[p].x - nodes[node].x, nodes[p].z - nodes[node].z) < 140) {
                _ = addRoadClass(p, node, street, class);
                road_between[p][node] = @intCast(road_count - 1);
                road_between[node][p] = @intCast(road_count - 1);
            }
        }
        previous = node;
    }
}

fn nodeAt(x: f32, z: f32, street: usize, tolerance: f32) usize {
    for (nodes, 0..) |n, i| {
        if (hypot(n.x - x, n.z - z) < tolerance) return i;
    }
    return addNode(x, z, street);
}

fn connect(node: usize, street: usize, class: u8, limit: f32) void {
    if (node >= node_count or road_count + 2 >= max_roads) return;
    var best: usize = node;
    var best_distance: f32 = limit;
    for (nodes, 0..) |n, i| {
        if (i == node) continue;
        const d = hypot(n.x - nodes[node].x, n.z - nodes[node].z);
        if (d < best_distance and !inWater((n.x + nodes[node].x) / 2, (n.z + nodes[node].z) / 2)) {
            best_distance = d;
            best = i;
        }
    }
    if (best == node) return;
    if (road_between[node][best] >= 0) return;
    _ = addRoadClass(node, best, street, class);
    road_between[node][best] = @intCast(road_count - 1);
    road_between[best][node] = @intCast(road_count - 1);
}

// Two straight spans cross at a point that is not shared by both, which is
// what leaves a seeded plan full of streets that pass over each other without a
// junction. Returns the crossing point when the two spans properly intersect.
fn crossing(a: Vec, b: Vec, c: Vec, d: Vec) ?Vec {
    const r_x = b.x - a.x;
    const r_z = b.z - a.z;
    const s_x = d.x - c.x;
    const s_z = d.z - c.z;
    const denom = r_x * s_z - r_z * s_x;
    if (@abs(denom) < 1e-4) return null;
    const q_x = c.x - a.x;
    const q_z = c.z - a.z;
    const t = (q_x * s_z - q_z * s_x) / denom;
    const u = (q_x * r_z - q_z * r_x) / denom;
    if (t <= 0.02 or t >= 0.98 or u <= 0.02 or u >= 0.98) return null;
    return .{ .x = a.x + r_x * t, .z = a.z + r_z * t };
}

// Split a road at an already-created junction node, keeping the two halves as
// the same street and class. Mirrors `splitRoad` but reuses a node so both
// crossing streets meet at exactly one junction.
fn splitAtNode(id: usize, n: usize) void {
    if (id >= road_count or n >= node_count) return;
    const old = roads[id];
    if (old.a == n or old.b == n) return;
    if (node_count + 1 >= max_nodes or road_count + 1 >= max_roads) return;
    const added = addRoadClass(n, old.b, old.street, old.class);
    roads[added].a = n;
    roads[added].b = old.b;
    roads[added].length = hypot(nodes[n].x - nodes[old.b].x, nodes[n].z - nodes[old.b].z);
    const dy = nodes[n].y - nodes[old.b].y;
    roads[added].slope = @abs(dy) / @max(0.01, roads[added].length);
    roads[id].b = n;
    roads[id].length = hypot(nodes[n].x - nodes[old.a].x, nodes[n].z - nodes[old.a].z);
    const first_dy = nodes[n].y - nodes[old.a].y;
    roads[id].slope = @abs(first_dy) / @max(0.01, roads[id].length);
    road_between[n][old.b] = @intCast(added);
    road_between[old.b][n] = @intCast(added);
    road_between[old.a][n] = @intCast(id);
    road_between[n][old.a] = @intCast(id);
}

// Turn every true crossing into a junction. Without this the seeded plan is a
// pile of ribbons that pass over each other, so most node pairs have no route
// and nobody can drive or ride anywhere.
fn resolveJunctions() void {
    var i: usize = 0;
    while (i < road_count) : (i += 1) {
        var j: usize = i + 1;
        while (j < road_count) : (j += 1) {
            if (node_count + 3 >= max_nodes or road_count + 3 >= max_roads) return;
            const a = roads[i];
            const b = roads[j];
            if (a.a == b.a or a.a == b.b or a.b == b.a or a.b == b.b) continue;
            const p = crossing(.{ .x = nodes[a.a].x, .z = nodes[a.a].z }, .{ .x = nodes[a.b].x, .z = nodes[a.b].z }, .{ .x = nodes[b.a].x, .z = nodes[b.a].z }, .{ .x = nodes[b.b].x, .z = nodes[b.b].z }) orelse continue;
            if (inWater(p.x, p.z)) continue;
            const n = nodeAt(p.x, p.z, roads[i].street, 3);
            splitAtNode(i, n);
            splitAtNode(j, n);
        }
    }
}

// Any fragment left over gets one bounded link to the rest of the network, so
// the authored plan is always a single walkable, drivable component.
fn linkFragments() void {
    var round: usize = 0;
    while (round < 24) : (round += 1) {
        if (node_count + 2 >= max_nodes or road_count + 2 >= max_roads) return;
        var cid: [max_nodes]i32 = @splat(-1);
        var comps: usize = 0;
        var sizes: [max_nodes]usize = @splat(0);
        for (0..node_count) |start| {
            if (cid[start] >= 0) continue;
            cid[start] = @intCast(comps);
            var stack: [max_nodes]usize = undefined;
            var sp: usize = 0;
            stack[sp] = start;
            sp += 1;
            while (sp > 0) {
                sp -= 1;
                const here = stack[sp];
                for (roads) |r| {
                    const other: usize = if (r.a == here) r.b else if (r.b == here) r.a else continue;
                    if (cid[other] < 0) {
                        cid[other] = @intCast(comps);
                        stack[sp] = other;
                        sp += 1;
                    }
                }
            }
            comps += 1;
        }
        if (comps <= 1) return;
        for (0..node_count) |c| sizes[@intCast(cid[c])] += 1;
        var main: usize = 0;
        for (0..comps) |c| if (sizes[c] > sizes[main]) {
            main = c;
        };
        var attached: usize = 0;
        for (0..node_count) |orphan| {
            if (cid[orphan] == @as(i32, @intCast(main)) or degree(orphan) == 0) continue;
            if (attached >= comps) break;
            var best: usize = orphan;
            var best_distance: f32 = 320;
            for (0..node_count) |host| {
                if (cid[host] != @as(i32, @intCast(main))) continue;
                const d = hypot(nodes[host].x - nodes[orphan].x, nodes[host].z - nodes[orphan].z);
                if (d >= best_distance) continue;
                if (inWater((nodes[host].x + nodes[orphan].x) / 2, (nodes[host].z + nodes[orphan].z) / 2)) continue;
                best_distance = d;
                best = host;
            }
            if (best == orphan or road_between[orphan][best] >= 0) continue;
            _ = addRoadClass(orphan, best, roads[0].street, 1);
            road_between[orphan][best] = @intCast(road_count - 1);
            road_between[best][orphan] = @intCast(road_count - 1);
            attached += 1;
        }
        if (attached == 0) return;
    }
}

fn clearOfBuildings(x: f32, z: f32, width: f32, depth: f32, placed: usize) bool {
    for (buildings[0..placed]) |b| {
        if (x < b.x + b.width + 1.2 and x + width + 1.2 > b.x and z < b.z + b.depth + 1.2 and z + depth + 1.2 > b.z) return false;
    }
    return true;
}

fn clearOfRoads(x: f32, z: f32, ignore: usize) bool {
    for (roads[0..road_count], 0..) |r, i| {
        if (i == ignore) continue;
        const a = nodes[r.a];
        const b = nodes[r.b];
        const u = projection(.{ .x = x, .z = z }, a, b);
        const px = a.x + (b.x - a.x) * u;
        const pz = a.z + (b.z - a.z) * u;
        if (hypot(px - x, pz - z) < 6.4) return false;
    }
    return true;
}

pub fn init() void {
    node_count = 0;
    road_count = 0;
    street_count = street_count_default;
    span_count = 0;
    revision += 1;
    @memset(&building_at_node, -1);
    for (&road_between) |*row| @memset(row, -1);
    River.init();
    var min_x: f32 = 1e9;
    var max_x: f32 = -1e9;
    var min_z: f32 = 1e9;
    var max_z: f32 = -1e9;
    for (River.points[0..River.count]) |p| {
        min_x = @min(min_x, p.x);
        max_x = @max(max_x, p.x);
        min_z = @min(min_z, p.z);
        max_z = @max(max_z, p.z);
    }
    river_min_x = min_x - 70;
    river_max_x = max_x + 70;
    river_min_z = min_z - 70;
    river_max_z = max_z + 70;
    // The water surface sits a fixed bank height below the raw ground at the
    // centreline, so the authored terrain and the river cannot disagree.
    for (0..River.count) |i| {
        River.levels[i] = terrain(River.points[i].x, River.points[i].z) - River.bank_height;
    }
    seedStreets();
    seedBridges();
    resolveJunctions();
    linkFragments();
    seedBuildings();
    for (roads, 0..) |*r, i| {
        r.condition = if (r.district == 0 or r.district == 3) 34 + @as(f32, @floatFromInt(i % 15)) else 62 + @as(f32, @floatFromInt(i % 25));
        r.crosswalk = (degree(r.a) >= 3 or degree(r.b) >= 3) and i % 3 == 0;
    }
    seedParking();
    for (&buildings) |*b| {
        for (&buildings) |other| {
            if (other.z > b.z and other.z - b.z < 35 and @abs(other.x - b.x) < 9) b.sun = @max(0.35, b.sun - @max(0, other.height - b.height * 0.5) / 45);
        }
        b.value *= 0.9 + @as(f64, b.sun) * 0.2;
    }
    rebuildRoutes();
}

// The street plan, modelled on the attached slice of Rome: a riverside road on
// each bank, two long bank arterials, a hill road and a south-eastern arterial,
// an irregular local mesh that stops at the water, and an outer ring.
fn seedStreets() void {
    // A riverside road on each bank, then the two long bank arterials set back
    // behind them: Viale di Trastevere in the west, Viale Aventino in the east.
    riverside(2, 1, -1, 13, 55);
    riverside(4, 1, 1, 13, 55);
    riverside(0, 2, -1, 62, 95);
    riverside(3, 2, 1, 78, 95);
    // The hill road on the west, and the two south-western arterials.
    chain(1, 1, .{ .x = 90, .z = 40 }, .{ .x = 160, .z = 470 }, 70, 11);
    chain(1, 1, .{ .x = 160, .z = 470 }, .{ .x = 250, .z = 1010 }, 70, 12);
    chain(9, 1, .{ .x = 235, .z = 520 }, .{ .x = 430, .z = 700 }, 70, 13);
    chain(9, 1, .{ .x = 430, .z = 700 }, .{ .x = 470, .z = 1010 }, 70, 14);
    // Via Ostiense and Viale Marco Polo in the south east.
    chain(5, 2, .{ .x = 900, .z = 560 }, .{ .x = 1080, .z = 790 }, 70, 15);
    chain(5, 2, .{ .x = 1080, .z = 790 }, .{ .x = 1270, .z = 1010 }, 70, 16);
    chain(6, 0, .{ .x = 1180, .z = 880 }, .{ .x = 800, .z = 1015 }, 80, 17);
    // The central avenue east of the river.
    chain(10, 2, .{ .x = 980, .z = 60 }, .{ .x = 1060, .z = 480 }, 75, 18);
    chain(10, 2, .{ .x = 1060, .z = 480 }, .{ .x = 1080, .z = 900 }, 75, 19);
    // The irregular local mesh. Each run spans the whole plan and is trimmed at
    // the water, so the west and east banks get their own street pattern.
    var seed: u32 = 100;
    for (0..6) |k| {
        const z = 130 + @as(f32, @floatFromInt(k)) * 155 + jitter(seed +% @as(u32, @intCast(k)) * 31, 30);
        chain(7, 0, .{ .x = 60, .z = z }, .{ .x = size_x - 60, .z = z }, 78, seed +% @as(u32, @intCast(k)) * 3);
        seed +%= 7;
    }
    for (0..4) |k| {
        const x = 130 + @as(f32, @floatFromInt(k)) * 300 + jitter(seed +% @as(u32, @intCast(k)) * 17, 40);
        chain(8, 0, .{ .x = x, .z = 50 }, .{ .x = x + jitter(seed +% @as(u32, @intCast(k)), 60), .z = size_z - 50 }, 82, seed +% @as(u32, @intCast(k)) * 5);
        seed +%= 11;
    }
    // A couple of long diagonals for variety, and the outer ring.
    chain(13, 0, .{ .x = 220, .z = 60 }, .{ .x = 520, .z = 560 }, 90, 21);
    chain(13, 0, .{ .x = 900, .z = 120 }, .{ .x = 1250, .z = 620 }, 90, 22);
    ring(11, 0, 55);
}

// A road that follows the water at a fixed setback from the bank. Sampled by
// chainage so it bends with the river, and split into pieces if the trim ever
// drops a sample.
fn riverside(street: usize, class: u8, side: f32, setback: f32, step: f32) void {
    if (River.count == 0 or River.length < 1) return;
    const pieces: usize = @max(1, @as(usize, @intFromFloat(@round(River.length / step))));
    var previous: ?usize = null;
    const seed: u32 = @as(u32, @intCast(street)) * 97 + @as(u32, @intFromFloat(@max(0, side))) * 131;
    for (0..pieces + 1) |k| {
        if (node_count + 4 >= max_nodes or road_count + 4 >= max_roads) return;
        const t = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(pieces));
        const s = River.atChainage(t * River.length);
        const length = @max(0.001, hypot(s.dx, s.dz));
        const lateral = side * (s.half_width + setback);
        const x = s.x - s.dz / length * lateral + jitter(seed +% @as(u32, @intCast(k)) * 3, 4);
        const z = s.z + s.dx / length * lateral + jitter(seed +% @as(u32, @intCast(k)) * 11 + 2, 4);
        if (x < 8 or z < 8 or x > size_x - 8 or z > size_z - 8 or inWater(x, z)) {
            previous = null;
            continue;
        }
        const node = nodeAt(x, z, street, 12);
        if (previous) |q| {
            if (q != node and road_between[q][node] < 0) {
                _ = addRoadClass(q, node, street, class);
                road_between[q][node] = @intCast(road_count - 1);
                road_between[node][q] = @intCast(road_count - 1);
            }
        }
        previous = node;
    }
}

fn ring(street: usize, class: u8, inset: f32) void {
    const corners = [_]Vec{
        .{ .x = inset, .z = inset },
        .{ .x = size_x - inset, .z = inset },
        .{ .x = size_x - inset, .z = size_z - inset },
        .{ .x = inset, .z = size_z - inset },
    };
    for (0..4) |i| chain(street, class, corners[i], corners[(i + 1) % 4], 95, 300 +% @as(u32, @intCast(i)));
}

// Four seeded crossings. Each is a span between the two riverside roads, with a
// short approach to whatever street is nearest so the bridge is never isolated.
fn seedBridges() void {
    if (River.count == 0) return;
    const at = [_]f32{ 0.16, 0.36, 0.62, 0.87 };
    for (at, 0..) |fraction, index| {
        const chainage = River.length * fraction;
        if (node_count + 4 >= max_nodes or road_count + 6 >= max_roads) return;
        const west = riverPoint(chainage, -(River.half_width[0] + 13));
        const east = riverPoint(chainage, River.half_width[0] + 13);
        const west_node = addNode(west.x, west.z, bridge_street);
        const east_node = addNode(east.x, east.z, bridge_street);
        const level = @max(terrain(west.x, west.z), terrain(east.x, east.z));
        _ = addRoadClass(west_node, east_node, bridge_street, 2);
        spans[span_count] = .{ .ax = west.x, .az = west.z, .bx = east.x, .bz = east.z, .level = level };
        span_count += 1;
        // Approaches first, so the bridge itself is the direct span. The
        // approach is skipped when the deck already touches a junction.
        var west_link: ?usize = null;
        var east_link: ?usize = null;
        for (nodes, 0..) |n, i| {
            if (i == west_node or i == east_node or n.street == bridge_street) continue;
            if (degree(i) == 0) continue;
            const d = hypot(n.x - west.x, n.z - west.z);
            if (d < 70 and !inWater(n.x, n.z) and (west_link == null or d < hypot(nodes[west_link.?].x - west.x, nodes[west_link.?].z - west.z))) west_link = i;
            const e = hypot(n.x - east.x, n.z - east.z);
            if (e < 70 and !inWater(n.x, n.z) and (east_link == null or e < hypot(nodes[east_link.?].x - east.x, nodes[east_link.?].z - east.z))) east_link = i;
        }
        if (west_link) |link| if (hypot(nodes[link].x - west.x, nodes[link].z - west.z) > 6 and road_between[link][west_node] < 0) {
            _ = addRoadClass(link, west_node, bridge_street, 2);
            road_between[link][west_node] = @intCast(road_count - 1);
            road_between[west_node][link] = @intCast(road_count - 1);
        };
        if (east_link) |link| if (hypot(nodes[link].x - east.x, nodes[link].z - east.z) > 6 and road_between[link][east_node] < 0) {
            _ = addRoadClass(link, east_node, bridge_street, 2);
            road_between[link][east_node] = @intCast(road_count - 1);
            road_between[east_node][link] = @intCast(road_count - 1);
        };
        _ = index;
    }
    // Anything the trimming left stranded gets one bounded lifeline.
    for (0..node_count) |i| {
        if (degree(i) == 0) connect(i, 8, 0, 160);
    }
}

fn kindFor(index: usize, core: f32) Kind {
    const roll = hash01(@as(u32, @intCast(index)) * 31 + 7);
    if (index % 47 == 0) return .depot;
    if (core > 0.45) {
        if (roll < 0.24) return .home;
        if (roll < 0.44) return .shop;
        if (roll < 0.62) return .office;
        if (roll < 0.70) return .clinic;
        if (roll < 0.76) return .hall;
        if (roll < 0.86) return .park;
        return .vacant;
    }
    if (roll < 0.62) return .home;
    if (roll < 0.70) return .shop;
    if (roll < 0.75) return .office;
    if (roll < 0.84) return .park;
    if (roll < 0.94) return .vacant;
    return .home;
}

fn heightFor(kind: Kind, index: usize, core: f32) f32 {
    return switch (kind) {
        .home => if (core > 0.5) 5 + @as(f32, @floatFromInt(index % 5)) * 1.7 else 3,
        .office => 7 + @as(f32, @floatFromInt(index % 6)) * 2.4,
        .shop => 3,
        .clinic => 5,
        .hall => 9,
        .depot => 3.5,
        else => 0.1,
    };
}

// Buildings stand beside the street nodes rather than mid-segment, so their
// frontage snaps to a node that already exists and the routing graph stays
// small: the whole plan costs roughly 400 nodes instead of 500.
fn seedBuildings() void {
    var placed: usize = 0;
    var index: usize = 0;
    const node_total = node_count;
    var pass: usize = 0;
    while (placed < buildings.len and pass < 6) : (pass += 1) {
        for (0..node_total) |n| {
            if (placed >= buildings.len) break;
            if (node_count + 2 >= max_nodes) break;
            if (degree(n) == 0) continue;
            if (nodes[n].street == bridge_street) continue;
            const core = coreFactor(nodes[n].x, nodes[n].z);
            if (hash01(@as(u32, @intCast(n)) * 13 + @as(u32, @intCast(pass * 977))) > 0.35 + core * 0.5) continue;
            for ([_]f32{ 1, -1 }) |side| {
                if (placed >= buildings.len) break;
                if (nodes[n].street == bridge_street) break;
                const road = firstRoad(n) orelse continue;
                const a = nodes[roads[road].a];
                const b = nodes[roads[road].b];
                const span = @max(0.001, hypot(b.x - a.x, b.z - a.z));
                const offset = 11 + jitter(@as(u32, @intCast(index)) * 3 + 1, 2.4);
                const x = nodes[n].x - (b.z - a.z) / span * offset * side - 3.1;
                const z = nodes[n].z + (b.x - a.x) / span * offset * side + 3.1;
                const width: f32 = 6.2;
                const depth: f32 = 7;
                if (x < 3 or z < 3 or x + width > size_x - 3 or z + depth > size_z - 3) continue;
                if (inWater(x, z) or inWater(x + width, z + depth)) continue;
                if (!clearOfBuildings(x, z, width, depth, placed)) continue;
                if (!clearOfRoads(x + width / 2, z + depth / 2, road)) continue;
                const kind = kindFor(index, core);
                const height = heightFor(kind, index, core);
                const entry_x = x + width / 2;
                const entry_z = if (side > 0) z else z + depth;
                buildings[placed] = .{ .x = x, .z = z, .width = width, .depth = depth, .height = height, .ground = elevation(x + width, z + depth), .kind = kind, .district = districtAt(x, z), .node = 0, .street = roads[road].street, .number = nodes[n].number + @as(usize, if (side > 0) @as(usize, 1) else 0) , .value = if (kind == .home) 1800000 else if (kind == .shop or kind == .office or kind == .depot) 2400000 else 0, .capacity = switch (kind) {
                    .home, .park, .vacant, .bike_park, .car_park => 0,
                    .office => 95,
                    .shop => 40,
                    .clinic => 80,
                    .hall => 90,
                    .depot => 24,
                }, .entry_x = entry_x, .entry_z = entry_z };
                buildings[placed].node = attach(placed, road);
                if (building_at_node[buildings[placed].node] < 0) building_at_node[buildings[placed].node] = @intCast(placed);
                placed += 1;
                index += 1;
            }
        }
    }
    // The map must never be left without homes or without an employer.
    if (placed < buildings.len) {
        // Fill any remainder with homes beside the first nodes, bounded.
        var n: usize = 0;
        while (placed < buildings.len and n < node_total) : (n += 1) {
            if (degree(n) == 0) continue;
            buildings[placed] = .{ .x = nodes[n].x + 6, .z = nodes[n].z + 6, .width = 6.2, .depth = 7, .height = 3, .ground = elevation(nodes[n].x + 12, nodes[n].z + 13), .kind = .home, .district = districtAt(nodes[n].x, nodes[n].z), .node = n, .street = nodes[n].street, .number = nodes[n].number + 1, .value = 1800000, .capacity = 0, .entry_x = nodes[n].x + 9, .entry_z = nodes[n].z + 6 };
            if (building_at_node[buildings[placed].node] < 0) building_at_node[buildings[placed].node] = @intCast(placed);
            placed += 1;
        }
    }
}

fn firstRoad(node: usize) ?usize {
    for (roads, 0..) |r, i| {
        if (r.a == node or r.b == node) return i;
    }
    return null;
}

// A building's frontage node: split the street it faces at the projection of
// its entrance, which snaps to an existing node whenever one is close.
fn attach(index: usize, road: usize) usize {
    const b = buildings[index];
    var best: f32 = 1e9;
    var road_id = road;
    var point: Vec = .{ .x = b.entry_x, .z = b.entry_z };
    for (roads, 0..) |r, rid| {
        if (r.street != b.street) continue;
        const u = projection(.{ .x = b.entry_x, .z = b.entry_z }, nodes[r.a], nodes[r.b]);
        const px = nodes[r.a].x + (nodes[r.b].x - nodes[r.a].x) * u;
        const pz = nodes[r.a].z + (nodes[r.b].z - nodes[r.a].z) * u;
        const d = hypot(px - b.entry_x, pz - b.entry_z);
        if (d < best) {
            best = d;
            road_id = rid;
            point = .{ .x = px, .z = pz };
        }
    }
    return splitRoad(road_id, point.x, point.z);
}

fn alreadyOrdered(prefix: []const usize, candidate: usize) bool {
    for (prefix) |value| if (value == candidate) return true;
    return false;
}

// Slice 13: the seeded town is six times the old area, so the bounded parking
// supply is scaled with it. Too few bicycle parks made the bicycle unavailable
// at most destinations and pushed riders onto foot.
const max_bike_parks = 132;
const max_car_parks = 40;

fn seedParking() void {
    var workplaces: [district_count]usize = @splat(0);
    var homes: [district_count]usize = @splat(0);
    for (&buildings) |*b| {
        const district = @min(b.district, district_count - 1);
        if (b.capacity > 0) workplaces[district] += 1;
        if (b.kind == .home) homes[district] += 1;
    }
    var order: [district_count]usize = undefined;
    // Busiest districts are served first so the bounded supply lands there.
    for (0..district_count) |i| {
        var best: usize = 0;
        var placed = false;
        for (0..district_count) |candidate| {
            if (alreadyOrdered(order[0..i], candidate)) continue;
            if (!placed or workplaces[candidate] > workplaces[best]) {
                best = candidate;
                placed = true;
            }
        }
        order[i] = best;
    }
    var bike_placed: usize = 0;
    var car_placed: usize = 0;
    for (order) |district| {
        const density: f32 = @as(f32, @floatFromInt(workplaces[district])) + @as(f32, @floatFromInt(homes[district])) / 8;
        const bike_target: usize = @intFromFloat(std.math.clamp(@round(density / 1.5), 4, 18));
        const car_target: usize = @intFromFloat(std.math.clamp(@round(@as(f32, @floatFromInt(workplaces[district])) / 2), 1, 8));
        const bike_slots: usize = @intFromFloat(std.math.clamp(10 + density * 2, 10, 48));
        const car_slots: usize = @intFromFloat(std.math.clamp(20 + @as(f32, @floatFromInt(workplaces[district])) * 6, 20, 80));
        var placed_bike: usize = 0;
        var placed_car: usize = 0;
        for (&buildings) |*b| {
            if (b.district != district) continue;
            if (b.kind != .park and b.kind != .vacant) continue;
            const kind: Kind = if (placed_bike < bike_target and bike_placed < max_bike_parks) .bike_park else if (placed_car < car_target and car_placed < max_car_parks) .car_park else continue;
            if (kind == .bike_park) {
                placed_bike += 1;
                bike_placed += 1;
            } else {
                placed_car += 1;
                car_placed += 1;
            }
            const slots: usize = if (kind == .bike_park) bike_slots else car_slots;
            b.* = .{ .x = b.x, .z = b.z, .width = b.width, .depth = b.depth, .height = 0.3, .ground = b.ground, .kind = kind, .district = b.district, .node = b.node, .value = 0, .capacity = 0, .slots = slots, .sun = b.sun, .occupants = 0, .employer = -1, .entry_x = b.entry_x, .entry_z = b.entry_z, .street = b.street, .number = b.number };
        }
    }
}

pub fn rebuildRoutes() void {
    for (0..node_count) |a| for (0..node_count) |b| {
        road_between[a][b] = if (road_between[a][b] > 0) road_between[a][b] else -1;
        next_node[a][b] = @intCast(b);
        walk_next[a][b] = @intCast(b);
        walk_distance[a][b] = if (a == b) 0 else 1e9;
        distance[a][b] = if (a == b) 0 else 1e9;
    };
    for (roads, 0..) |r, i| {
        road_between[r.a][r.b] = @intCast(i);
        road_between[r.b][r.a] = @intCast(i);
    }
    for (roads) |r| {
        if (!r.pedestrians) continue;
        const cost = r.length * (1 + r.slope * 3) / (0.7 + r.condition / 100);
        distance[r.a][r.b] = cost;
        distance[r.b][r.a] = cost;
        const aligned = horizontal(r.a, r.b);
        walk_distance[r.a][r.b] = cost + (if (markedCrossing(r.b, aligned)) @as(f32, 0) else 7);
        walk_distance[r.b][r.a] = cost + (if (markedCrossing(r.a, aligned)) @as(f32, 0) else 7);
    }
    // All-pairs next hops: shared by every resident; no per-frame path allocations.
    for (0..node_count) |k| for (0..node_count) |a| for (0..node_count) |b| {
        const walking_cost = walk_distance[a][k] + walk_distance[k][b];
        if (walking_cost < walk_distance[a][b]) {
            walk_distance[a][b] = walking_cost;
            walk_next[a][b] = walk_next[a][k];
        }
        const cost = distance[a][k] + distance[k][b];
        if (cost < distance[a][b]) {
            distance[a][b] = cost;
            next_node[a][b] = next_node[a][k];
        }
    };
}

// Slice 10: expose the walking route cost so simulation code can tell an
// unreachable pair (1e9) from a genuinely short walk.
pub fn walkCost(from: usize, to: usize) f32 {
    return walk_distance[from][to];
}

pub fn driveCost(from: usize, to: usize) f32 {
    return distance[from][to];
}

pub fn condition(district: usize) f32 {
    var total: f32 = 0;
    var count: f32 = 0;
    for (roads) |r| if (r.district == district) {
        total += r.condition;
        count += 1;
    };
    return total / @max(1, count);
}

pub fn markedCrossing(node: usize, _: bool) bool {
    if (degree(node) < 3) return true;
    for (roads) |r| {
        if ((r.a == node or r.b == node) and r.crosswalk) return true;
    }
    return false;
}

pub fn frontage(b: Building) Vec {
    const n = nodes[b.node];
    var p = sidewalk(b.node);
    if ((p.x - n.x) * (b.entry_x - n.x) + (p.z - n.z) * (b.entry_z - n.z) < 0) {
        p.x = 2 * n.x - p.x;
        p.z = 2 * n.z - p.z;
    }
    return p;
}

fn rebuildSpans() void {
    span_count = 0;
    for (roads) |r| {
        if (r.street != bridge_street or span_count >= max_spans) continue;
        const a = nodes[r.a];
        const b = nodes[r.b];
        if (!River.crosses(a.x, a.z, b.x, b.z)) continue;
        spans[span_count] = .{ .ax = a.x, .az = a.z, .bx = b.x, .bz = b.z, .level = @max(terrain(a.x, a.z), terrain(b.x, b.z)) };
        span_count += 1;
    }
}

// Called only after snapshot validation; array identities and node IDs stay stable.
pub fn restoreGraph(saved_nodes: []const Node, saved_roads: []const Road) void {
    node_count = saved_nodes.len;
    road_count = saved_roads.len;
    @memcpy(node_storage[0..node_count], saved_nodes);
    @memcpy(road_storage[0..road_count], saved_roads);
    nodes = node_storage[0..node_count];
    roads = road_storage[0..road_count];
    @memset(&building_at_node, -1);
    for (&road_between) |*row| @memset(row, -1);
    for (roads, 0..) |r, i| {
        road_between[r.a][r.b] = @intCast(i);
        road_between[r.b][r.a] = @intCast(i);
    }
    for (&buildings, 0..) |b, i| {
        if (building_at_node[b.node] < 0) building_at_node[b.node] = @intCast(i);
    }
    rebuildSpans();
}
