const std = @import("std");
pub const cols = 26;
pub const rows = 22;
pub const spacing: f32 = 20;
pub const size_x: f32 = 520;
pub const size_z: f32 = 440;
pub const population = 3840;
pub const district_count = 12;
pub const max_nodes = 640;
pub const max_roads = 1200;
pub var node_count: usize = 0;
pub var road_count: usize = 0;
pub var revision: u32 = 0;
pub const Kind = enum(u32) { home, shop, office, clinic, hall, park, depot, vacant };
pub const Building = struct { x: f32, z: f32, width: f32, depth: f32, height: f32, ground: f32, kind: Kind, district: usize, node: usize, value: f64, capacity: usize, sun: f32 = 1, occupants: usize = 0, employer: i32 = -1, entry_x: f32 = 0, entry_z: f32 = 0, street: usize = 0, number: usize = 0 };
pub const Node = struct { x: f32, z: f32, y: f32, street: usize = 0, number: usize = 0 };
pub const Road = struct { a: usize, b: usize, length: f32, slope: f32, district: usize, condition: f32, street: usize = 0, pedestrians: bool = true, vehicles: bool = true, crosswalk: bool = false, works: bool = false };
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
pub var street_count: usize = 14;
pub const district_names = [_][]const u8{ "Westbank", "Station Quarter", "East Rise", "Foundry Ward", "Civic Centre", "Orchard Hill", "Millfield", "Market Ward", "Highgate", "Southbank", "Garden Ward", "Upper Bellwether" };
const plan = [_][]const u8{
    "HHHSHHHHSHHHOOOSHH", "HHHHHHHHOHHHOOOHHH", "HHDHHSHHCHHHOOSHHP", "HHHHPHHHHHHHOHHHHH",
    "SHHHHHOOSHHHHHSHHH", "HHCHHHOOOHHHHHHHHH", "HHHHHHHHOHHPHHHHDH", "HHSHHPHHHHHHOOSHHC",
    "HHHHHHOOTOOHHHHHHH", "HHOHHHOOPOOHHSHPHH", "HHDHHSHHOHHHHHHHHH", "HHHHHHHHCHHHOHHSHH",
    "HHSHHHOOSHHHHHHHHH", "HHHHHHOHHHHPHHHSHH", "HHCHHHHHSHHHHHHHHH", "HHHHPHHHOHHHHHSHHH",
};

fn ramp(value: f32, start: f32, end: f32) f32 {
    return std.math.clamp((value - start) / (end - start), 0, 1);
}
pub fn elevation(x: f32, z: f32) f32 {
    return ramp(x, 70, 98) * 8 + ramp(x, 154, 182) * 11 + ramp(z, 98, 126) * 5;
}
pub fn districtAt(x: f32, z: f32) usize {
    return @as(usize, @intFromFloat(std.math.clamp(z / (size_z / 4), 0, 3))) * 3 + @as(usize, @intFromFloat(std.math.clamp(x / (size_x / 3), 0, 2)));
}
pub fn addNode(x: f32, z: f32, street: usize) usize {
    const id = node_count;
    var number: usize = if (street < 14) @intFromFloat(@max(1, @round(if (street < 7) x else z))) else 1;
    if (street >= 14) for (nodes) |n| {
        if (n.street == street) number = @max(number, n.number + 2);
    };
    node_storage[id] = .{ .x = x, .z = z, .y = elevation(x, z), .street = street, .number = number };
    node_count += 1;
    nodes = node_storage[0..node_count];
    return id;
}
pub fn addRoad(a: usize, b: usize, street: usize) usize {
    const dx = nodes[b].x - nodes[a].x;
    const dz = nodes[b].z - nodes[a].z;
    const dy = nodes[b].y - nodes[a].y;
    const planar = @sqrt(dx * dx + dz * dz);
    const district = districtAt((nodes[a].x + nodes[b].x) / 2, (nodes[a].z + nodes[b].z) / 2);
    const id = road_count;
    road_storage[id] = .{ .a = a, .b = b, .length = @sqrt(planar * planar + dy * dy), .slope = @abs(dy) / @max(0.01, planar), .district = district, .condition = 70, .street = street };
    road_count += 1;
    roads = road_storage[0..road_count];
    return id;
}
pub fn splitRoad(id: usize, x: f32, z: f32) usize {
    const old = roads[id];
    if (hypot(x - nodes[old.a].x, z - nodes[old.a].z) < 2.5) return old.a;
    if (hypot(x - nodes[old.b].x, z - nodes[old.b].z) < 2.5) return old.b;
    const n = addNode(x, z, old.street);
    const added = addRoad(n, old.b, old.street);
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
    return std.math.clamp(((p.x - a.x) * dx + (p.z - a.z) * dz) / (dx * dx + dz * dz), 0, 1);
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
    return .{ .x = nodes[n].x - dz / len * 2.3, .z = nodes[n].z + dx / len * 2.3 };
}
pub fn init() void {
    node_count = 0;
    road_count = 0;
    street_count = 14;
    revision += 1;
    @memset(&building_at_node, -1);
    // An authored network independent of the parcel layout: skewed blocks,
    // winding cross streets, and an undeveloped eastern/southern reserve.
    for (0..7) |row| for (0..7) |col| {
        const x = 45 + @as(f32, @floatFromInt(col)) * 52 + @as(f32, @floatFromInt((row * 7 + col * 3) % 11)) - 5;
        const z = 45 + @as(f32, @floatFromInt(row)) * 44 + @as(f32, @floatFromInt((col * 9 + row * 2) % 13)) - 6;
        _ = addNode(x, z, row);
    };
    for (0..49) |a| {
        if (a % 7 < 6) seedStreet(a, a + 1, a / 7);
        if (a / 7 < 6 and !(a % 7 == 2 and a / 7 == 2) and !(a % 7 == 4 and a / 7 == 3)) seedStreet(a, a + 7, 7 + a % 7);
    }
    for (&buildings, 0..) |*b, i| {
        const block = i / 8;
        const row = block / 6;
        const col = block % 6;
        const slot = i % 8;
        const suburban = col == 0 or col == 5 or row == 0 or row == 5;
        const code = plan[i / 18][i % 18];
        const kind: Kind = if (suburban and code == 'H' and i % 4 == 0) .vacant else switch (code) {
            'H' => .home,
            'S' => .shop,
            'O' => .office,
            'C' => .clinic,
            'T' => .hall,
            'D' => .depot,
            else => .park,
        };
        const north = slot < 4;
        const left = nodes[row * 7 + col + (if (north) @as(usize, 0) else 7)];
        const right = nodes[row * 7 + col + 1 + (if (north) @as(usize, 0) else 7)];
        const t = 0.15 + @as(f32, @floatFromInt(slot % 4)) * 0.225;
        const seed_street = if (north) row else row + 1;
        const bend = streetBend(seed_street);
        const arc = @sin(t * std.math.pi) * bend;
        const span = hypot(right.x - left.x, right.z - left.z);
        const x = left.x + (right.x - left.x) * t - (right.z - left.z) / span * arc - 3.1;
        const z = left.z + (right.z - left.z) * t + (right.x - left.x) / span * arc + (if (north) @as(f32, 7) else -14);
        const width: f32 = 6.2;
        const height: f32 = switch (kind) {
            .home => if (suburban) 3 else 4 + @as(f32, @floatFromInt(i % 4)) * 1.6,
            .office => 8 + @as(f32, @floatFromInt(i % 5)) * 2,
            .shop => 3,
            .clinic => 5,
            .hall => 9,
            .depot => 3.5,
            .park, .vacant => 0.1,
        };
        b.* = .{ .x = x, .z = z, .width = width, .depth = 7, .height = height, .ground = elevation(x + width, z + 7), .kind = kind, .district = districtAt(x, z), .node = 0, .street = if (north) row else row + 1, .number = col * 8 + (slot % 4) * 2 + (if (north) @as(usize, 1) else 2), .value = if (kind == .home) 1800000 else if (kind == .shop or kind == .office or kind == .depot) 2400000 else 0, .capacity = switch (kind) {
            .home, .park, .vacant => 0,
            .office => 95,
            .shop => 40,
            .clinic => 80,
            .hall => 90,
            .depot => 24,
        }, .entry_x = x + width / 2, .entry_z = if (north) z else z + 7 };
        // Attach each frontage to the street, sharing an access node when close.
        var best: f32 = 1e9;
        var road_id: usize = 0;
        var point: Vec = undefined;
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
        b.node = splitRoad(road_id, point.x, point.z);
        if (building_at_node[b.node] < 0) building_at_node[b.node] = @intCast(i);
    }
    for (roads, 0..) |*r, i| {
        r.condition = if (r.district == 0 or r.district == 3) 30 + @as(f32, @floatFromInt(i % 15)) else 65 + @as(f32, @floatFromInt(i % 25));
        r.crosswalk = (degree(r.a) >= 3 or degree(r.b) >= 3) and i % 3 == 0;
    }
    for (&buildings) |*b| {
        for (&buildings) |other| {
            if (other.z > b.z and other.z - b.z < 35 and @abs(other.x - b.x) < 9) b.sun = @max(0.35, b.sun - @max(0, other.height - b.height * 0.5) / 45);
        }
        b.value *= 0.9 + @as(f64, b.sun) * 0.2;
    }
    rebuildRoutes();
}
fn streetBend(street: usize) f32 {
    return if (street == 0 or street == 6) 4 else if (street == 9) -4 else if (street == 3) 2.5 else 0;
}
fn seedStreet(a: usize, b: usize, street: usize) void {
    var previous = a;
    const dx = nodes[b].x - nodes[a].x;
    const dz = nodes[b].z - nodes[a].z;
    const length = hypot(dx, dz);
    const bend = streetBend(street);
    for (1..4) |step| {
        const t = @as(f32, @floatFromInt(step)) / 4;
        const arc = @sin(t * std.math.pi) * bend;
        const n = addNode(nodes[a].x + dx * t - dz / length * arc, nodes[a].z + dz * t + dx / length * arc, street);
        _ = addRoad(previous, n, street);
        previous = n;
    }
    _ = addRoad(previous, b, street);
}
pub fn rebuildRoutes() void {
    for (0..node_count) |a| for (0..node_count) |b| {
        road_between[a][b] = -1;
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
}
