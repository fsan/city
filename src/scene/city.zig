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
// Slice 16 lifted the ceiling that used to cap this. `rebuildRoutes` is no
// longer O(nodes^3) (it is one Dijkstra per source over an adjacency list), and
// the snapshot no longer carries the all-pairs tables, so neither the frame
// budget nor the 16 MiB save buffer is set by the node count any more. The
// plan can therefore afford an access street off every avenue instead of a
// handful of long ribbons with empty blocks between them.
pub const max_nodes = 1600;
pub const max_roads = 3200;
pub const street_count_default: usize = 14;
// Street 12 is reserved for the bridges, which are the only spans that may
// cross the water. Nothing is built on them.
pub const bridge_street: usize = 12;
pub const max_spans = 16;
// Slice 15 appended the downtown and green-space kinds. Existing values are
// retained so saved towns, `web/data.js` and the reports keep their meaning.
pub const Kind = enum(u32) { home, shop, office, clinic, hall, park, depot, vacant, bike_park, car_park, apartment, market, playground, plaza };
// Slice 15: the authored population grew from 288 lots to a dense street wall
// of mixed housing, business and public space, so the fixed lot array grew with
// it. The count is capped by the node ceiling above, not by this array.
pub const max_buildings = 900;
pub const Building = struct { x: f32, z: f32, width: f32, depth: f32, height: f32, ground: f32, kind: Kind, district: usize, node: usize, value: f64, capacity: usize, slots: usize = 0, sun: f32 = 1, occupants: usize = 0, employer: i32 = -1, entry_x: f32 = 0, entry_z: f32 = 0, street: usize = 0, number: usize = 0 };
pub const Node = struct { x: f32, z: f32, y: f32, street: usize = 0, number: usize = 0 };
pub const Road = struct { a: usize, b: usize, length: f32, slope: f32, district: usize, condition: f32, street: usize = 0, class: u8 = 1, pedestrians: bool = true, vehicles: bool = true, crosswalk: bool = false, works: bool = false };
pub const Vec = struct { x: f32, z: f32 };
pub var buildings: [max_buildings]Building = undefined;
// Slice 15: `buildings.len` is the array bound (900), not the number of lots the
// street wall actually placed. Everything that walks the town - the scalar ABI,
// the parcel list, the assessment roll, the snapshot validator and the browser -
// must use this count instead, otherwise the unused tail is read as a row of
// zero-sized homes standing on the origin.
pub var lot_count: usize = 0;

// The placed lots, as opposed to the fixed storage the array reserves. Every
// walk of the town uses this slice so the unused tail can never be read as a
// building standing on the origin.
pub fn lots() []Building {
    return buildings[0..lot_count];
}
// Slice 15: how many lots the street wall aims to fill. `max_buildings` is the
// hard array bound; this is the authored density target, so the sweep leaves
// room at the end of the array for the fallback sites.
pub const building_target: usize = 820;
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

// The carved ground: the raw terrain with the channel cut into it and nothing
// else. This is what the renderer draws for the ground surface, so a bridge
// crossing stays open water underneath rather than a causeway damming the
// river. The river test is guarded by the bounding box computed in `init`.
pub fn carved(x: f32, z: f32) f32 {
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

// Walkable surface: the carved ground plus the bridge decks, so walkers,
// vehicles and picking all cross at the deck height instead of dropping into
// the channel. Called for every vertex, vehicle corner and resident.
pub fn elevation(x: f32, z: f32) f32 {
    if (deckAt(x, z)) |level| return level;
    return carved(x, z);
}

fn deckAt(x: f32, z: f32) ?f32 {
    for (spans[0..span_count]) |s| {
        const dx = s.bx - s.ax;
        const dz = s.bz - s.az;
        const squared = dx * dx + dz * dz;
        if (squared < 0.01) continue;
        const t = ((x - s.ax) * dx + (z - s.az) * dz) / squared;
        const along = t * @sqrt(squared);
        const span = @sqrt(squared);
        if (along < -8 or along > span + 8) continue;
        if (hypot(x - (s.ax + dx * t), z - (s.az + dz * t)) > 4.3) continue;
        return s.level;
    }
    return null;
}

// True inside the water itself, and true a little way up the bank. The road
// tool and the parcel seeder only need the carriageway clear of the waterline,
// so three metres of bank is enough; a building needs its whole wall on dry
// ground, which is what `inWaterForBuilding` adds.
pub fn inWater(x: f32, z: f32) bool {
    if (River.count == 0) return false;
    const s = River.nearest(x, z);
    return s.distance < s.half_width + 3;
}

// Water test for anything with a footprint. A frontage is eleven metres back
// from its node, so the corner of a wall can still stand in the channel even
// when the centre passes the closer test above. Nine metres of bank clearance
// keeps a 6.2 x 7 m footprint on the dry side of the waterline.
pub fn inWaterForBuilding(x: f32, z: f32) bool {
    if (River.count == 0) return false;
    const s = River.nearest(x, z);
    return s.distance < s.half_width + 9;
}

pub fn isBridge(road: usize) bool {
    return road < road_count and road_storage[road].street == bridge_street;
}

pub fn districtAt(x: f32, z: f32) usize {
    return @as(usize, @intFromFloat(std.math.clamp(z / (size_z / 4), 0, 3))) * 3 + @as(usize, @intFromFloat(std.math.clamp(x / (size_x / 3), 0, 2)));
}

pub fn hash01(value: u32) f32 {
    var v = value *% 2654435761;
    v ^= v >> 15;
    v *%= 2246822519;
    v ^= v >> 13;
    return @as(f32, @floatFromInt(v & 0xffff)) / 65535.0;
}

fn jitter(seed: u32, amount: f32) f32 {
    return (hash01(seed) - 0.5) * 2 * amount;
}

// Slice 15: the two questions the rest of the game keeps asking about a lot.
// `isHome` is what makes an apartment a permanent dwelling in the housing,
// household, tax and residence-counting code; `isGreen` is what makes a park,
// playground or plaza a place a family can spend an afternoon.
pub fn isHome(kind: Kind) bool {
    return kind == .home or kind == .apartment;
}

pub fn isGreen(kind: Kind) bool {
    return kind == .park or kind == .playground or kind == .plaza;
}

// Slice 15: the downtown quarter. It is the east-bank commercial core around
// the central avenue, bounded by the local mesh to the west, the east rise to
// the north-east and the southern arterials. Every frontage inside it is built
// up, taller and more commercial than the surrounding neighbourhoods, and it
// holds the market hall, the plazas and the office towers.
pub const downtown_x0: f32 = 830;
pub const downtown_z0: f32 = 330;
pub const downtown_x1: f32 = 1150;
pub const downtown_z1: f32 = 700;
pub const downtown_name = "Market Ward core";

pub fn inDowntown(x: f32, z: f32) bool {
    return x >= downtown_x0 and x <= downtown_x1 and z >= downtown_z0 and z <= downtown_z1;
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

// Slice 17: a split must never leave two roads joining the same pair of nodes.
// The tighter street mesh puts junctions close enough together that a split
// point can coincide with a link that already exists, and the snapshot
// validator rejects a duplicate edge outright, so the town would build but
// never reload.
pub fn duplicates(a: usize, b: usize) bool {
    return a != b and road_between[a][b] >= 0;
}

fn repoint(id: usize, a: usize, b: usize) void {
    const old = roads[id];
    if (road_between[old.a][old.b] == @as(i16, @intCast(id))) road_between[old.a][old.b] = -1;
    if (road_between[old.b][old.a] == @as(i16, @intCast(id))) road_between[old.b][old.a] = -1;
    const planar = hypot(nodes[b].x - nodes[a].x, nodes[b].z - nodes[a].z);
    const dy = nodes[b].y - nodes[a].y;
    roads[id].a = a;
    roads[id].b = b;
    roads[id].length = @sqrt(planar * planar + dy * dy);
    roads[id].slope = @abs(dy) / @max(0.01, planar);
    road_between[a][b] = @intCast(id);
    road_between[b][a] = @intCast(id);
}

pub fn splitRoad(id: usize, x: f32, z: f32) usize {
    const old = roads[id];
    if (hypot(x - nodes[old.a].x, z - nodes[old.a].z) < 2.5) return old.a;
    if (hypot(x - nodes[old.b].x, z - nodes[old.b].z) < 2.5) return old.b;
    if (node_count + 1 >= max_nodes) return old.a;
    // Reuse the nearer end when the split point already has a link to it; that
    // keeps the graph simple instead of adding a parallel edge.
    const n = addNode(x, z, old.street);
    const first_exists = duplicates(old.a, n);
    const second_exists = duplicates(n, old.b);
    if (first_exists and second_exists) return n;
    if (second_exists) {
        repoint(id, old.a, n);
        return n;
    }
    if (first_exists) {
        repoint(id, n, old.b);
        return n;
    }
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

// Node incidence: the roads meeting each node, in road-creation order, as one
// CSR pair of arrays. The renderer's join pass needs every node's own roads and
// used to scan the whole road list once per node per layer, which is about
// 2.2 M comparisons a layer on the authored town. One bucket pass rebuilds this
// in O(nodes + roads), so a frame pays that once instead. It is rebuilt rather
// than cached because `build` in `roads.zig` adds and splits roads mid-session
// and a restored snapshot can carry a revision number the renderer has already
// seen.
pub var incidence_start: [max_nodes + 1]usize = undefined;
pub var incidence_road: [max_roads * 2]usize = undefined;

pub fn buildIncidence() void {
    @memset(incidence_start[0 .. node_count + 1], 0);
    for (roads[0..road_count]) |r| {
        incidence_start[r.a + 1] += 1;
        incidence_start[r.b + 1] += 1;
    }
    for (0..node_count) |n| incidence_start[n + 1] += incidence_start[n];
    var cursor: [max_nodes]usize = undefined;
    @memcpy(cursor[0..node_count], incidence_start[0..node_count]);
    for (roads[0..road_count], 0..) |r, id| {
        incidence_road[cursor[r.a]] = id;
        cursor[r.a] += 1;
        incidence_road[cursor[r.b]] = id;
        cursor[r.b] += 1;
    }
}

pub fn incident(node: usize) []const usize {
    return incidence_road[incidence_start[node]..incidence_start[node + 1]];
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
    chainJitter(street, class, from, to, step, seed, @min(9, step * 0.22));
}

// The mesh wants to read as a street grid rather than as a bundle of wandering
// ribbons, so its runs carry a small wobble: enough that the plan is not a
// printed lattice, but small enough that a run still meets the cross street it
// was aimed at and closes a face. Wide jitter only ever produced dead ends.
fn chainJitter(street: usize, class: u8, from: Vec, to: Vec, step: f32, seed: u32, wobble: f32) void {
    const span = hypot(to.x - from.x, to.z - from.z);
    const pieces: usize = @max(1, @as(usize, @intFromFloat(@round(span / step))));
    var previous: ?usize = null;
    for (0..pieces + 1) |k| {
        if (node_count + 4 >= max_nodes or road_count + 4 >= max_roads) return;
        const t = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(pieces));
        const edge = k == 0 or k == pieces;
        const amount: f32 = if (edge) 0 else wobble;
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
    // The two halves have to be measured the same way `addRoadClass` measures a
    // span: the three-dimensional length, with the slope taken over the planar
    // run. Using the flat distance here left a junction-split road a few
    // centimetres short of the distance the snapshot validator recomputes from
    // its endpoints, so a town that crossed a junction could never be reloaded.
    // Never add a second road between a pair that is already joined; the
    // crossing just moves onto the existing link instead.
    const first_exists = duplicates(old.a, n);
    const second_exists = duplicates(n, old.b);
    if (first_exists and second_exists) return;
    if (second_exists) {
        repoint(id, old.a, n);
        return;
    }
    if (first_exists) {
        repoint(id, n, old.b);
        return;
    }
    const added = addRoadClass(n, old.b, old.street, old.class);
    roads[added].a = n;
    roads[added].b = old.b;
    const added_planar = hypot(nodes[n].x - nodes[old.b].x, nodes[n].z - nodes[old.b].z);
    const added_dy = nodes[n].y - nodes[old.b].y;
    roads[added].length = @sqrt(added_planar * added_planar + added_dy * added_dy);
    roads[added].slope = @abs(added_dy) / @max(0.01, added_planar);
    roads[id].b = n;
    const first_planar = hypot(nodes[n].x - nodes[old.a].x, nodes[n].z - nodes[old.a].z);
    const first_dy = nodes[n].y - nodes[old.a].y;
    roads[id].length = @sqrt(first_planar * first_planar + first_dy * first_dy);
    roads[id].slope = @abs(first_dy) / @max(0.01, first_planar);
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

// True when the whole footprint of a building is far enough from every road
// surface to be built on. Testing the centre alone let an 11 m frontage offset
// push a wall over a carriageway, so the corners and the middle are all
// measured against the ribbon the renderer actually draws (half-width 2.7 plus
// a metre of kerb).
fn clearOfRoads(x: f32, z: f32, width: f32, depth: f32, ignore: usize) bool {
    // Every footprint sample has to clear every carriageway. The street the
    // building is meant to face is not skipped outright — it is only held to
    // the shoulder edge (the ribbon the renderer draws at 2.7 m), because a
    // frontage that is skipped entirely is exactly how a wall ended up standing
    // on the road it was supposed to address.
    const margin: f32 = 3.7;
    const own_margin: f32 = 2.9;
    const samples = [_]Vec{
        .{ .x = x, .z = z },
        .{ .x = x + width, .z = z },
        .{ .x = x, .z = z + depth },
        .{ .x = x + width, .z = z + depth },
        .{ .x = x + width / 2, .z = z + depth / 2 },
    };
    for (samples) |p| {
        for (roads[0..road_count], 0..) |r, i| {
            const a = nodes[r.a];
            const b = nodes[r.b];
            const u = projection(p, a, b);
            const px = a.x + (b.x - a.x) * u;
            const pz = a.z + (b.z - a.z) * u;
            const limit: f32 = if (i == ignore) own_margin else margin;
            if (hypot(px - p.x, pz - p.z) < limit) return false;
        }
    }
    return true;
}

// Slice 17: node heights and road lengths are derived, so they have to be
// rebuilt once every span exists. A node created before its bridge deck was
// registered kept the carved river-bed height, and any node inside a deck
// corridor kept the height it had before the deck arrived. The snapshot
// validator compares a saved height against `elevation`, so a town that had
// either kind of node could never be reloaded.
pub fn refreshElevations() void {
    for (nodes[0..node_count]) |*n| n.y = elevation(n.x, n.z);
    for (roads[0..road_count]) |*r| {
        const dy = nodes[r.b].y - nodes[r.a].y;
        const planar = hypot(nodes[r.b].x - nodes[r.a].x, nodes[r.b].z - nodes[r.a].z);
        r.length = @sqrt(planar * planar + dy * dy);
        r.slope = @abs(dy) / @max(0.01, planar);
    }
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
    // Slice 15: the large authored parks claim their block interiors before the
    // street wall is laid out, so a terrace never grows through a park.
    // The parks claim their block interiors first and the street wall starts
    // from the first free lot, so a terrace can never be written over a park.
    const park_lots = seedParks();
    lot_count = seedBuildings(park_lots);
    @memset(buildings[lot_count..], std.mem.zeroes(Building));
    for (roads, 0..) |*r, i| {
        r.condition = if (r.district == 0 or r.district == 3) 34 + @as(f32, @floatFromInt(i % 15)) else 62 + @as(f32, @floatFromInt(i % 25));
        r.crosswalk = (degree(r.a) >= 3 or degree(r.b) >= 3) and i % 3 == 0;
    }
    seedParking();
    for (lots()) |*b| {
        for (lots()) |other| {
            if (other.z > b.z and other.z - b.z < 35 and @abs(other.x - b.x) < 9) b.sun = @max(0.35, b.sun - @max(0, other.height - b.height * 0.5) / 45);
        }
        b.value *= 0.9 + @as(f64, b.sun) * 0.2;
    }
    refreshElevations();
    rebuildRoutes();
}

// The street plan, modelled on the attached slice of Rome: a riverside road on
// each bank, two long bank arterials, a hill road and a south-eastern arterial,
// an irregular local mesh that stops at the water, and an outer ring.
fn seedStreets() void {
    // A riverside road on each bank, then the two long bank arterials set back
    // behind them: Viale di Trastevere in the west, Viale Aventino in the east.
    // The setback clears the waterline, which sits at 0.6875 of the bank ramp
    // past the channel, so the carriageway never overlaps the water surface.
    riverside(2, 1, -1, 17, 55);
    riverside(4, 1, 1, 17, 55);
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
    // The local mesh. Slice 16 tightened the spacing so the blocks are the size
    // of a real block rather than a field: at 130/140 m the arterials crossed
    // vast empty ground with a couple of isolated houses on each face, which is
    // the sparse look the plan was reported for.
    var seed: u32 = 100;
    for (0..11) |k| {
        const z = 90 + @as(f32, @floatFromInt(k)) * 86 + jitter(seed +% @as(u32, @intCast(k)) * 31, 9);
        chainJitter(7, 0, .{ .x = 60, .z = z }, .{ .x = size_x - 60, .z = z }, 74, seed +% @as(u32, @intCast(k)) * 3, 2.5);
        seed +%= 7;
    }
    for (0..14) |k| {
        const x = 90 + @as(f32, @floatFromInt(k)) * 88 + jitter(seed +% @as(u32, @intCast(k)) * 17, 10);
        chainJitter(8, 0, .{ .x = x, .z = 50 }, .{ .x = x + jitter(seed +% @as(u32, @intCast(k)), 24), .z = size_z - 50 }, 78, seed +% @as(u32, @intCast(k)) * 5, 2.5);
        seed +%= 11;
    }
    // A couple of long diagonals for variety, and the outer ring.
    chain(13, 0, .{ .x = 220, .z = 60 }, .{ .x = 520, .z = 560 }, 90, 21);
    chain(13, 0, .{ .x = 900, .z = 120 }, .{ .x = 1250, .z = 620 }, 90, 22);
    ring(11, 0, 55);
    // Slice 16: access streets. Every avenue and arterial gets short side lanes
    // off both faces at a walking interval, which is what turns a ribbon with a
    // vast empty block behind it into a built-up street. Each lane joins the
    // avenue at a node that is either already there or a short split of it, so
    // the cost is one node per lane rather than a node per metre.
    accessStreets();
}

// The interval between access lanes along a big street, and how far each one
// reaches back from the kerb before it stops inside the block.
const access_step: f32 = 34;
const access_depth: f32 = 26;

fn accessStreets() void {
    var seed: u32 = 9001;
    var rid: usize = 0;
    while (rid < road_count) : (rid += 1) {
        if (node_count + 6 >= max_nodes or road_count + 6 >= max_roads) return;
        const r = roads[rid];
        // Only the big streets carry frontage lanes; the local mesh is already
        // the access layer.
        if (r.street == bridge_street or r.class < 1) continue;
        const a = nodes[r.a];
        const b = nodes[r.b];
        const span = hypot(b.x - a.x, b.z - a.z);
        if (span < access_step * 2) continue;
        const ux = (b.x - a.x) / span;
        const uz = (b.z - a.z) / span;
        const nx = -uz;
        const nz = ux;
        var along: f32 = access_step * 0.5;
        while (along < span - 1.0) : (along += access_step) {
            if (node_count + 3 >= max_nodes or road_count + 3 >= max_roads) return;
            const jx = a.x + ux * along;
            const jz = a.z + uz * along;
            if (inWater(jx, jz)) continue;
            for ([_]f32{ 1, -1 }) |side| {
                if (node_count + 3 >= max_nodes or road_count + 3 >= max_roads) return;
                seed +%= 17;
                const depth = access_depth * (0.75 + hash01(seed) * 0.5);
                const ex = jx + nx * side * depth;
                const ez = jz + nz * side * depth;
                if (ex < 8 or ez < 8 or ex > size_x - 8 or ez > size_z - 8) continue;
                if (inWater(ex, ez) or inWater((jx + ex) / 2, (jz + ez) / 2)) continue;
                // Reuse the avenue node if the lane happens to start on one,
                // otherwise split the avenue so the lane has a junction.
                const junction = nodeAt(jx, jz, r.street, 6);
                const start = if (junction < node_count) junction else splitRoad(rid, jx, jz);
                const end = addNode(ex, ez, 8);
                if (start == end or road_between[start][end] >= 0) continue;
                const lane = addRoadClass(start, end, 8, 0);
                road_between[start][end] = @intCast(lane);
                road_between[end][start] = @intCast(lane);
            }
        }
    }
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
        const level = @max(terrain(west.x, west.z), terrain(east.x, east.z));
        // Slice 17: register the deck before its own nodes exist. A node takes
        // its height from `elevation`, and `elevation` only knows about spans
        // that are already in the list, so creating the nodes first left them
        // standing in the carved river bed at 16.7 m while the deck they belong
        // to sat at 20 m. A reload then compared the saved height against the
        // live deck and refused the file.
        spans[span_count] = .{ .ax = west.x, .az = west.z, .bx = east.x, .bz = east.z, .level = level };
        span_count += 1;
        const west_node = addNode(west.x, west.z, bridge_street);
        const east_node = addNode(east.x, east.z, bridge_street);
        _ = addRoadClass(west_node, east_node, bridge_street, 2);
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

// Slice 15: the mix a frontage gets. The downtown core is almost all business,
// services and apartments with public space between them; the inner
// neighbourhoods are a dense mixed wall; the outer suburbs stay low and green.
fn kindFor(index: usize, core: f32, downtown: bool) Kind {
    const roll = hash01(@as(u32, @intCast(index)) * 31 + 7);
    if (index % 47 == 0 and !downtown) return .depot;
    if (downtown) {
        if (roll < 0.30) return .office;
        if (roll < 0.52) return .shop;
        if (roll < 0.66) return .apartment;
        if (roll < 0.72) return .market;
        if (roll < 0.78) return .hall;
        if (roll < 0.84) return .plaza;
        if (roll < 0.89) return .playground;
        return .park;
    }
    if (core > 0.45) {
        if (roll < 0.22) return .home;
        if (roll < 0.34) return .apartment;
        if (roll < 0.52) return .shop;
        if (roll < 0.66) return .office;
        if (roll < 0.72) return .clinic;
        if (roll < 0.78) return .hall;
        if (roll < 0.83) return .playground;
        if (roll < 0.93) return .park;
        return .vacant;
    }
    if (roll < 0.56) return .home;
    if (roll < 0.66) return .apartment;
    if (roll < 0.75) return .shop;
    if (roll < 0.79) return .office;
    if (roll < 0.85) return .playground;
    if (roll < 0.93) return .park;
    if (roll < 0.97) return .vacant;
    return .home;
}

fn heightFor(kind: Kind, index: usize, core: f32, downtown: bool) f32 {
    return switch (kind) {
        .home => if (core > 0.5) 5 + @as(f32, @floatFromInt(index % 5)) * 1.7 else 3,
        .apartment => (if (downtown) @as(f32, 13) else 8) + @as(f32, @floatFromInt(index % 4)) * 3,
        .office => if (downtown) 15 + @as(f32, @floatFromInt(index % 6)) * 3.6 else 7 + @as(f32, @floatFromInt(index % 6)) * 2.4,
        .shop => if (downtown) 4.5 else 3,
        .market => 6,
        .clinic => 5,
        .hall => if (downtown) 12 else 9,
        .depot => 3.5,
        else => 0.1,
    };
}

// Footprints are authored per use so a downtown block reads as offices and
// apartments around a market, and the suburbs stay small and cottage-like.
fn footprintFor(kind: Kind, downtown: bool) [2]f32 {
    return switch (kind) {
        .apartment => if (downtown) .{ 9.5, 10 } else .{ 7.4, 8 },
        .office => if (downtown) .{ 10.5, 11 } else .{ 7, 8 },
        .market => .{ 13, 15 },
        .hall => .{ 10, 10 },
        .clinic => .{ 8, 8 },
        .depot => .{ 9, 9 },
        .shop => if (downtown) .{ 7.5, 8 } else .{ 6.2, 7 },
        else => .{ 6.2, 7 },
    };
}

// Slice 15: a street wall instead of a scattering of lots. Every road is
// walked end to end and built up at a fixed frontage interval, on both sides,
// so a block face reads as a terrace of homes, shops and offices rather than
// two isolated buildings per junction. The downtown core is built almost
// solidly, the inner neighbourhoods densely, and the outer suburbs sparsely.
//
// The node ceiling, not this loop, is what bounds the result: `attach` snaps a
// frontage onto a node the plan already has whenever one is close, so a long
// terrace shares a handful of routing nodes.
// How heavy a frontage slot's claim on the town's building budget is. Weight is
// relative, so the sweep is normalised against the plan's own total rather than
// filled front-to-back: every district gets its share, and downtown gets most.
fn frontageWeight(x: f32, z: f32) f32 {
    if (inDowntown(x, z)) return 3.4;
    return 0.28 + coreFactor(x, z) * 1.15;
}

// The step a frontage is sampled at, in metres: denser downtown, longer in the
// suburbs, so a terrace is fine-grained where it is busiest.
fn frontageStep(x: f32, z: f32) f32 {
    return if (inDowntown(x, z)) 10 else 12.5;
}

// Slice 17: the street wall is swept twice, not once. A single draw against
// the target cannot know how many of its own candidates the geometry will
// reject, and on the dense plan that was the difference between the 820 lots
// the plan asks for and the 391 it actually placed. The first sweep measures
// the yield; the second spends the corrected share; the loop repeats while it
// is short. Two or three passes is enough and the result is deterministic.
fn frontageSweep(first_free: usize, share: f64) usize {
    var placed: usize = first_free;
    var index: usize = 0;
    @memset(&building_at_node, -1);
    for (buildings[0..first_free], 0..) |b, i| {
        if (building_at_node[b.node] < 0) building_at_node[b.node] = @intCast(i);
    }
    for (0..road_count) |rid| {
        if (placed >= building_target) break;
        const r = roads[rid];
        if (r.street == bridge_street) continue;
        const a = nodes[r.a];
        const b = nodes[r.b];
        const span = hypot(b.x - a.x, b.z - a.z);
        if (span < 7) continue;
        const ux = (b.x - a.x) / span;
        const uz = (b.z - a.z) / span;
        const nx = -uz;
        const nz = ux;
        const step = frontageStep((a.x + b.x) / 2, (a.z + b.z) / 2);
        var along: f32 = step * 0.5;
        while (along < span - 1.5) : (along += step) {
            if (placed >= building_target) break;
            for ([_]f32{ 1, -1 }) |side| {
                if (placed >= building_target) break;
                index += 1;
                const here_x = a.x + ux * along;
                const here_z = a.z + uz * along;
                const here_down = inDowntown(here_x, here_z);
                const here_core = coreFactor(here_x, here_z);
                const here_chance: f32 = @floatCast(@min(0.98, frontageWeight(here_x, here_z) * share));
                if (hash01(@as(u32, @intCast(index)) * 13 + 5) > here_chance) continue;
                const kind = kindFor(index, here_core, here_down);
                const size = footprintFor(kind, here_down);
                const width = size[0];
                const depth = size[1];
                const back = 8 + depth * 0.5 + jitter(@as(u32, @intCast(index)) * 7 + 3, 2.0);
                const cx = here_x + nx * side * back;
                const cz = here_z + nz * side * back;
                const x = cx - width / 2;
                const z = cz - depth / 2;
                if (x < 3 or z < 3 or x + width > size_x - 3 or z + depth > size_z - 3) continue;
                if (inWaterForBuilding(x, z) or inWaterForBuilding(x + width, z + depth)) continue;
                if (!clearOfBuildings(x, z, width, depth, placed)) continue;
                if (!clearOfRoads(x, z, width, depth, rid)) continue;
                const height = heightFor(kind, index, here_core, here_down);
                // The door faces the road the building stands on.
                const entry_x = cx;
                const entry_z = cz + (if (side * nz >= 0) -depth / 2 else depth / 2);
                buildings[placed] = .{
                    .x = x,
                    .z = z,
                    .width = width,
                    .depth = depth,
                    .height = height,
                    .ground = elevation(x + width, z + depth),
                    .kind = kind,
                    .district = districtAt(x, z),
                    .node = 0,
                    .street = r.street,
                    .number = @intFromFloat(@max(1, @round(@max(x, z)))),
                    .value = valueFor(kind),
                    .capacity = capacityFor(kind),
                    .entry_x = entry_x,
                    .entry_z = entry_z,
                };
                buildings[placed].node = attach(placed, rid);
                if (building_at_node[buildings[placed].node] < 0) building_at_node[buildings[placed].node] = @intCast(placed);
                placed += 1;
            }
        }
    }
    return placed;
}

fn seedBuildings(first_free: usize) usize {
    var placed: usize = first_free;
    // Weighted sweep: the plan is measured first, then each slot takes a
    // deterministic draw against its own share of the target. This is what
    // keeps the density spread over the whole town instead of stopping when the
    // lot array runs out somewhere near the first streets.
    var total_weight: f64 = 0;
    for (roads) |r| {
        if (r.street == bridge_street) continue;
        const a = nodes[r.a];
        const b = nodes[r.b];
        const span = hypot(b.x - a.x, b.z - a.z);
        if (span < 7) continue;
        const step = frontageStep((a.x + b.x) / 2, (a.z + b.z) / 2);
        var along: f32 = step * 0.5;
        while (along < span - 1.5) : (along += step) {
            total_weight += 2 * frontageWeight(a.x + (b.x - a.x) * along / span, a.z + (b.z - a.z) * along / span);
        }
    }
    // The budget is the whole town's lots; the parks already hold their share.
    const remaining: usize = if (building_target > first_free) building_target - first_free else 0;
    const target: f64 = @floatFromInt(remaining);
    var share: f64 = if (total_weight > 0) target / total_weight else 0;
    placed = frontageSweep(first_free, share);
    // Slice 17: geometry, not the draw, decides how many candidates survive, so
    // the share is corrected against the yield the last pass actually placed.
    var pass: usize = 0;
    while (pass < 5 and placed < building_target and placed > first_free) : (pass += 1) {
        const yielded = @as(f64, @floatFromInt(placed - first_free));
        share = share * (@as(f64, @floatFromInt(remaining)) * 1.02) / yielded;
        placed = frontageSweep(first_free, share);
    }
    // The map must never be left without homes or without an employer. Every
    // fallback site is checked exactly like the ones above: an unchecked
    // placement here is what used to drop frontages into the river and push
    // slabs across a carriageway.
    if (placed < 140 + first_free) {
        const floor = 140 + first_free;
        var attempt: usize = 0;
        while (placed < floor and attempt < 4) : (attempt += 1) {
            for (0..node_count) |n| {
                if (placed >= floor) break;
                if (degree(n) == 0) continue;
                if (nodes[n].street == bridge_street) continue;
                if (building_at_node[n] >= 0) continue;
                const road = firstRoad(n) orelse continue;
                for ([_]f32{ 1, -1 }) |side| {
                    if (placed >= floor) break;
                    const a = nodes[roads[road].a];
                    const b = nodes[roads[road].b];
                    const span = @max(0.001, hypot(b.x - a.x, b.z - a.z));
                    const offset = 11 + jitter(@as(u32, @intCast(placed + attempt * 613)) * 3 + 1, 2.4);
                    const x = nodes[n].x - (b.z - a.z) / span * offset * side - 3.1;
                    const z = nodes[n].z + (b.x - a.x) / span * offset * side + 3.1;
                    const width: f32 = 6.2;
                    const depth: f32 = 7;
                    if (x < 3 or z < 3 or x + width > size_x - 3 or z + depth > size_z - 3) continue;
                    if (inWaterForBuilding(x, z) or inWaterForBuilding(x + width, z + depth)) continue;
                    if (!clearOfBuildings(x, z, width, depth, placed)) continue;
                    if (!clearOfRoads(x, z, width, depth, road)) continue;
                    buildings[placed] = .{ .x = x, .z = z, .width = width, .depth = depth, .height = 3, .ground = elevation(x + width, z + depth), .kind = .home, .district = districtAt(x, z), .node = 0, .street = nodes[n].street, .number = nodes[n].number + @as(usize, if (side > 0) 1 else 0), .value = 1800000, .capacity = 0, .entry_x = x + width / 2, .entry_z = if (side > 0) z else z + depth };
                    buildings[placed].node = attach(placed, road);
                    if (building_at_node[buildings[placed].node] < 0) building_at_node[buildings[placed].node] = @intCast(placed);
                    placed += 1;
                }
            }
        }
    }
    return placed;
}

// Slice 15: assessed value and employment by use. Apartments and homes are
// residential property; shops, offices, markets and depots are commercial;
// public open space carries no assessment.
fn valueFor(kind: Kind) f64 {
    return switch (kind) {
        .home => 1800000,
        .apartment => 2600000,
        .shop, .office, .market, .depot => 2400000,
        else => 0,
    };
}

fn capacityFor(kind: Kind) usize {
    return switch (kind) {
        .office => 95,
        .shop => 40,
        .market => 70,
        .clinic => 80,
        .hall => 90,
        .depot => 24,
        else => 0,
    };
}

// Slice 18 (numbered list item 10): private development reuses the authored
// numbers above rather than inventing a second set, so a proposal and the
// seeded plan agree on what a home, a shop or a depot is worth. These are the
// only public doors into those tables.
pub fn lotValue(kind: Kind) f64 {
    return valueFor(kind);
}

pub fn lotCapacity(kind: Kind) usize {
    return capacityFor(kind);
}

// Where a proposed use would be allowed to build: the plan's own height rule,
// read at the site's real position so a downtown proposal is downtown tall.
pub fn proposalHeight(kind: Kind, index: usize, x: f32, z: f32) f32 {
    return heightFor(kind, index, coreFactor(x, z), inDowntown(x, z));
}

pub fn proposalFootprint(kind: Kind, x: f32, z: f32) [2]f32 {
    return footprintFor(kind, inDowntown(x, z));
}

// Slice 15: the authored green spaces. Each site is a candidate rectangle; the
// largest size that clears every carriageway and every lot already placed wins,
// so a park lands in the middle of a block instead of on a street. Trees and
// bushes inside them are drawn from the lot's own identity by the renderer.
// The parks are found rather than pinned: each anchor is scanned for the
// largest axis-aligned rectangle that clears every carriageway, so a park lands
// in the middle of a block instead of across a street. Trees and bushes inside
// them are drawn from the lot's own identity by the renderer, so the green
// space survives a save without carrying a second list of positions.
// Slice 17: one candidate per district, plus second tries where the blocks are
// tight, so the authored green space is spread over the whole map instead of
// clustering on the two banks. Each anchor is a search box: `seedParks` looks
// for the largest clear rectangle inside it, stepping inward from the nominal
// centre before it shrinks.
const park_anchors = [_]LandSite{
    .{ .x = 150, .z = 130, .w = 120, .d = 96 },
    .{ .x = 120, .z = 520, .w = 110, .d = 118 },
    .{ .x = 400, .z = 320, .w = 116, .d = 96 },
    .{ .x = 300, .z = 800, .w = 118, .d = 96 },
    .{ .x = 980, .z = 860, .w = 128, .d = 96 },
    .{ .x = 1140, .z = 160, .w = 110, .d = 124 },
    .{ .x = 540, .z = 920, .w = 104, .d = 84 },
    .{ .x = 1080, .z = 400, .w = 92, .d = 88 },
    .{ .x = 340, .z = 580, .w = 96, .d = 84 },
    .{ .x = 730, .z = 250, .w = 92, .d = 88 },
    .{ .x = 900, .z = 980, .w = 96, .d = 80 },
    .{ .x = 420, .z = 120, .w = 88, .d = 84 },
    // District coverage: Civic Centre, Market Ward, Highgate and a second
    // Southbank candidate. Without these the mesh's tighter blocks left four
    // districts with no authored green space at all.
    .{ .x = 660, .z = 470, .w = 86, .d = 78 },
    .{ .x = 520, .z = 660, .w = 84, .d = 76 },
    .{ .x = 980, .z = 640, .w = 84, .d = 76 },
    .{ .x = 620, .z = 900, .w = 84, .d = 74 },
};
const LandSite = struct { x: f32, z: f32, w: f32, d: f32 };

// How much clear ground a park lot needs from a carriageway.
const park_clearance: f32 = 5.5;

fn parkClear(x: f32, z: f32, w: f32, d: f32) bool {
    if (x < 4 or z < 4 or x + w > size_x - 4 or z + d > size_z - 4) return false;
    if (inWaterForBuilding(x, z) or inWaterForBuilding(x + w, z) or inWaterForBuilding(x, z + d) or
        inWaterForBuilding(x + w, z + d) or inWaterForBuilding(x + w / 2, z + d / 2)) return false;
    const samples = [_]Vec{
        .{ .x = x, .z = z },
        .{ .x = x + w, .z = z },
        .{ .x = x, .z = z + d },
        .{ .x = x + w, .z = z + d },
        .{ .x = x + w / 2, .z = z + d / 2 },
        .{ .x = x + w / 2, .z = z },
        .{ .x = x + w / 2, .z = z + d },
        .{ .x = x, .z = z + d / 2 },
        .{ .x = x + w, .z = z + d / 2 },
    };
    for (samples) |p| {
        for (roads[0..road_count]) |r| {
            const a = nodes[r.a];
            const b = nodes[r.b];
            const u = projection(p, a, b);
            const px = a.x + (b.x - a.x) * u;
            const pz = a.z + (b.z - a.z) * u;
            if (hypot(px - p.x, pz - p.z) < park_clearance) return false;
        }
    }
    return true;
}

// Slice 17: search one anchor. The nominal rectangle is tried first, then the
// same rectangle nudged around its box, then progressively smaller versions of
// each. A bounded search rather than a single fixed rectangle is what lets a
// park fit a block that the tighter mesh made narrower than the authored site.
fn placePark(anchor: LandSite, placed: usize) ?LandSite {
    const offsets = [_][2]f32{
        .{ 0, 0 },      .{ -0.3, 0 },  .{ 0.3, 0 },
        .{ 0, -0.3 },   .{ 0, 0.3 },   .{ -0.3, -0.3 },
        .{ 0.3, -0.3 }, .{ -0.3, 0.3 }, .{ 0.3, 0.3 },
    };
    var scale: f32 = 1;
    while (scale > 0.14) : (scale -= 0.08) {
        for (offsets) |offset| {
            const w = anchor.w * scale;
            const d = anchor.d * scale;
            const x = anchor.x + (anchor.w - w) / 2 + anchor.w * offset[0];
            const z = anchor.z + (anchor.d - d) / 2 + anchor.d * offset[1];
            if (!parkClear(x, z, w, d)) continue;
            if (!clearOfBuildings(x, z, w, d, placed)) continue;
            return .{ .x = x, .z = z, .w = w, .d = d };
        }
    }
    return null;
}

fn seedParks() usize {
    var placed: usize = 0;
    for (park_anchors) |anchor| {
        if (placed >= buildings.len) return placed;
        const site = placePark(anchor, placed) orelse continue;
        const road = nearestRoadAt(site.x + site.w / 2, site.z + site.d);
        buildings[placed] = .{
            .x = site.x,
            .z = site.z,
            .width = site.w,
            .depth = site.d,
            .height = 0.1,
            .ground = elevation(site.x + site.w / 2, site.z + site.d / 2),
            .kind = .park,
            .district = districtAt(site.x + site.w / 2, site.z + site.d / 2),
            .node = 0,
            .street = roads[road].street,
            .number = @intFromFloat(@max(1, @round(site.x))),
            .value = 0,
            .capacity = 0,
            .entry_x = site.x + site.w / 2,
            .entry_z = site.z + site.d,
        };
        buildings[placed].node = attach(placed, road);
        if (building_at_node[buildings[placed].node] < 0) building_at_node[buildings[placed].node] = @intCast(placed);
        placed += 1;
    }
    return placed;
}

// Nearest road to a point, used to give a park an address on the street it
// fronts. Returns 0 when the plan is empty.
fn nearestRoadAt(x: f32, z: f32) usize {
    var best: usize = 0;
    var best_distance: f32 = 1e9;
    for (roads, 0..) |r, rid| {
        if (r.street == bridge_street) continue;
        const u = projection(.{ .x = x, .z = z }, nodes[r.a], nodes[r.b]);
        const px = nodes[r.a].x + (nodes[r.b].x - nodes[r.a].x) * u;
        const pz = nodes[r.a].z + (nodes[r.b].z - nodes[r.a].z) * u;
        const d = hypot(px - x, pz - z);
        if (d < best_distance) {
            best_distance = d;
            best = rid;
        }
    }
    return best;
}

fn firstRoad(node: usize) ?usize {
    for (roads, 0..) |r, i| {
        if (r.a == node or r.b == node) return i;
    }
    return null;
}

// A building's frontage node. Slice 15: a dense street wall has far more doors
// than the routing graph can afford nodes, so the door snaps onto a node the
// plan already has whenever one is within reach, and only splits the street
// when it is not. This is what keeps a built-up frontage from growing the
// quadratic routing tables one shop at a time.
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
    var nearest: ?usize = null;
    var nearest_distance: f32 = building_snap;
    for (nodes, 0..) |n, i| {
        if (n.street != b.street) continue;
        const d = hypot(n.x - point.x, n.z - point.z);
        if (d < nearest_distance) {
            nearest_distance = d;
            nearest = i;
        }
    }
    if (nearest) |n| return n;
    return splitRoad(road_id, point.x, point.z);
}

// How far a frontage will walk to share a routing node, in metres.
pub const building_snap: f32 = 26;

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
    for (lots()) |*b| {
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
        for (lots(), 0..) |*b, index| {
            if (b.district != district) continue;
            if (b.kind != .park and b.kind != .vacant) continue;
            // Slice 15: a large park is public open space, not a car park site.
            if (b.width > 22 or b.depth > 22) continue;
            // Slice 18: vacant land is also the site pool private development
            // draws on, so the parking pass must never take all of it. A
            // deterministic share of each district's vacant lots stays vacant
            // and can be zoned and built on later. Park lots are unaffected.
            if (b.kind == .vacant and hash01(@as(u32, @intCast(index)) * 13 + 5) < 0.6) continue;
            // A parking slab is a drawn surface, not a wall, but the player still
            // reads a tan rectangle over the carriageway as a glitch, so the
            // conversion is held to the same footprint clearance as a frontage.
            if (!clearOfRoads(b.x, b.z, b.width, b.depth, max_roads)) continue;
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

// Slice 16: the all-pairs tables are filled by one Dijkstra per source over an
// adjacency list. The triple loop this replaced was O(nodes^3); at the 1,500
// nodes the dense plan needs that is 3.4 billion relaxations per rebuild, and
// `rebuildRoutes` runs every 60 simulation seconds. Per-source Dijkstra is
// O(nodes * edges * log nodes), roughly fifty million, and it is what lets the
// town carry enough streets to be built up instead of a handful of long,
// empty ribbons.
const max_directed = max_roads * 2;
var adj_head: [max_nodes]i32 = undefined;
var adj_link: [max_directed]i32 = undefined;
var adj_to: [max_directed]u16 = undefined;
var adj_drive: [max_directed]f32 = undefined;
var adj_walk: [max_directed]f32 = undefined;
var heap_at: [max_directed]u16 = undefined;
var heap_key: [max_directed]f32 = undefined;

fn heapPush(count: *usize, node: usize, key: f32) void {
    if (count.* >= heap_at.len) return;
    var i = count.*;
    count.* += 1;
    heap_at[i] = @intCast(node);
    heap_key[i] = key;
    while (i > 0) {
        const parent = (i - 1) / 2;
        if (heap_key[parent] <= heap_key[i]) break;
        const tn = heap_at[parent];
        const tk = heap_key[parent];
        heap_at[parent] = heap_at[i];
        heap_key[parent] = heap_key[i];
        heap_at[i] = tn;
        heap_key[i] = tk;
        i = parent;
    }
}

fn heapPop(count: *usize) struct { node: usize, key: f32 } {
    const top_node: usize = heap_at[0];
    const top_key = heap_key[0];
    count.* -= 1;
    heap_at[0] = heap_at[count.*];
    heap_key[0] = heap_key[count.*];
    var i: usize = 0;
    while (true) {
        const left = i * 2 + 1;
        const right = left + 1;
        var best = i;
        if (left < count.* and heap_key[left] < heap_key[best]) best = left;
        if (right < count.* and heap_key[right] < heap_key[best]) best = right;
        if (best == i) break;
        const tn = heap_at[best];
        const tk = heap_key[best];
        heap_at[best] = heap_at[i];
        heap_key[best] = heap_key[i];
        heap_at[i] = tn;
        heap_key[i] = tk;
        i = best;
    }
    return .{ .node = top_node, .key = top_key };
}

fn addDirected(used: usize, from: usize, to: usize, drive: f32, walk: f32) usize {
    if (used >= max_directed) return used;
    adj_to[used] = @intCast(to);
    adj_drive[used] = drive;
    adj_walk[used] = walk;
    adj_link[used] = adj_head[from];
    adj_head[from] = @intCast(used);
    return used + 1;
}

// One source's shortest paths. `next_out[to]` is the first hop out of `source`
// towards `to`, which is the shape `next_node` has always had.
fn search(source: usize, weights: *const [max_directed]f32, dist_out: *[max_nodes]f32, next_out: *[max_nodes]u16) void {
    for (0..node_count) |i| {
        dist_out[i] = if (i == source) 0 else 1e9;
        next_out[i] = @intCast(i);
    }
    var count: usize = 0;
    heapPush(&count, source, 0);
    while (count > 0) {
        const top = heapPop(&count);
        if (top.key > dist_out[top.node]) continue;
        var edge = adj_head[top.node];
        while (edge >= 0) {
            const id: usize = @intCast(edge);
            const to: usize = adj_to[id];
            const candidate = top.key + weights[id];
            if (candidate < dist_out[to]) {
                dist_out[to] = candidate;
                next_out[to] = if (top.node == source) @intCast(to) else next_out[top.node];
                heapPush(&count, to, candidate);
            }
            edge = adj_link[id];
        }
    }
}

pub fn rebuildRoutes() void {
    for (0..max_nodes) |i| adj_head[i] = -1;
    for (0..node_count) |a| for (0..node_count) |b| {
        road_between[a][b] = if (road_between[a][b] > 0) road_between[a][b] else -1;
    };
    var used: usize = 0;
    for (roads, 0..) |r, i| {
        road_between[r.a][r.b] = @intCast(i);
        road_between[r.b][r.a] = @intCast(i);
    }
    for (roads) |r| {
        if (!r.pedestrians) continue;
        const cost = r.length * (1 + r.slope * 3) / (0.7 + r.condition / 100);
        used = addDirected(used, r.a, r.b, cost, cost + (if (markedCrossing(r.b, true)) @as(f32, 0) else 7));
        used = addDirected(used, r.b, r.a, cost, cost + (if (markedCrossing(r.a, true)) @as(f32, 0) else 7));
    }
    for (0..node_count) |source| {
        search(source, &adj_drive, &distance[source], &next_node[source]);
        search(source, &adj_walk, &walk_distance[source], &walk_next[source]);
    }
    // An unreachable pair keeps the identity hop, so a route walker can never
    // read a hop left over from an earlier rebuild.
    for (0..node_count) |a| for (0..node_count) |b| {
        if (distance[a][b] >= 1e9) next_node[a][b] = @intCast(b);
        if (walk_distance[a][b] >= 1e9) walk_next[a][b] = @intCast(b);
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
    // Slice 15: several doors can share one frontage node, so the walk starts at
    // the kerb outside this building's own door and only then joins the street
    // the shared node belongs to.
    var point: Vec = .{ .x = b.entry_x, .z = b.entry_z };
    var best: f32 = 1e9;
    for (roads, 0..) |r, rid| {
        if (r.street != b.street and roads[rid].a != b.node and roads[rid].b != b.node) continue;
        const a = nodes[r.a];
        const c = nodes[r.b];
        const u = projection(.{ .x = b.entry_x, .z = b.entry_z }, a, c);
        const px = a.x + (c.x - a.x) * u;
        const pz = a.z + (c.z - a.z) * u;
        const d = hypot(px - b.entry_x, pz - b.entry_z);
        if (d < best and d < 60) {
            best = d;
            point = .{ .x = px, .z = pz };
        }
    }
    const span = hypot(point.x - n.x, point.z - n.z);
    if (best >= 60 or span < 0.001) return sidewalk(b.node);
    const p = Vec{ .x = point.x - (point.z - n.z) / span * 2.3, .z = point.z + (point.x - n.x) / span * 2.3 };
    if (insideBuilding(p.x, p.z, b)) return point;
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
    for (lots(), 0..) |b, i| {
        if (building_at_node[b.node] < 0) building_at_node[b.node] = @intCast(i);
    }
    rebuildSpans();
    refreshElevations();
}
