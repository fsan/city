const std = @import("std");
pub const cols = 18;
pub const rows = 16;
pub const spacing: f32 = 14;
pub const size_x: f32 = cols * spacing;
pub const size_z: f32 = rows * spacing;
pub const population = 3840;
pub const district_count = 12;
pub const node_count = (cols + 1) * (rows + 1);
pub const road_count = cols * (rows + 1) + rows * (cols + 1);
pub const Kind = enum(u32) { home, shop, office, clinic, hall, park, depot };
pub const Building = struct { x: f32, z: f32, width: f32, depth: f32, height: f32, ground: f32, kind: Kind, district: usize, node: usize, value: f64, capacity: usize, occupants: usize = 0, employer: i32 = -1 };
pub const Node = struct { x: f32, z: f32, y: f32 };
pub const Road = struct { a: usize, b: usize, length: f32, slope: f32, district: usize, condition: f32, pedestrians: bool = true, vehicles: bool = true, works: bool = false };
// Fixed plan: H housing, S shops, O offices, C clinic, T town hall, P park, D contractor depot.
const plan = [_][]const u8{
    "HHHSHHHHSHHHOOOSHH", "HHHHHHHHOHHHOOOHHH", "HHDHHSHHCHHHOOSHHP", "HHHHPHHHHHHHOHHHHH",
    "SHHHHHOOSHHHHHSHHH", "HHCHHHOOOHHHHHHHHH", "HHHHHHHHOHHPHHHHDH", "HHSHHPHHHHHHOOSHHC",
    "HHHHHHOOTOOHHHHHHH", "HHOHHHOOPOOHHSHPHH", "HHDHHSHHOHHHHHHHHH", "HHHHHHHHCHHHOHHSHH",
    "HHSHHHOOSHHHHHHHHH", "HHHHHHOHHHHPHHHSHH", "HHCHHHHHSHHHHHHHHH", "HHHHPHHHOHHHHHSHHH",
};
pub var buildings: [cols * rows]Building = undefined;
pub var nodes: [node_count]Node = undefined;
pub var building_at_node: [node_count]i32 = undefined;
pub var roads: [road_count]Road = undefined;
pub var road_between: [node_count][node_count]i16 = undefined;
pub var next_node: [node_count][node_count]u16 = undefined;
pub var distance: [node_count][node_count]f32 = undefined;
pub const district_names = [_][]const u8{ "Westbank", "Station Quarter", "East Rise", "Foundry Ward", "Civic Centre", "Orchard Hill", "Millfield", "Market Ward", "Highgate", "Southbank", "Garden Ward", "Upper Bellwether" };
fn ramp(value: f32, start: f32, end: f32) f32 {
    return std.math.clamp((value - start) / (end - start), 0, 1);
}
pub fn elevation(x: f32, z: f32) f32 {
    return ramp(x, 70, 98) * 8 + ramp(x, 154, 182) * 11 + ramp(z, 98, 126) * 5;
}
pub fn districtAt(x: f32, z: f32) usize {
    return @as(usize, @intFromFloat(std.math.clamp(z / 56, 0, 3))) * 3 + @as(usize, @intFromFloat(std.math.clamp(x / 84, 0, 2)));
}
pub fn init() void {
    @memset(&building_at_node, -1);
    for (&nodes, 0..) |*n, i| {
        const x = @as(f32, @floatFromInt(i % (cols + 1))) * spacing;
        const z = @as(f32, @floatFromInt(i / (cols + 1))) * spacing;
        n.* = .{ .x = x, .z = z, .y = elevation(x, z) };
    }
    for (&buildings, 0..) |*b, i| {
        const col = i % cols;
        const row = i / cols;
        const kind: Kind = switch (plan[row][col]) {
            'H' => .home,
            'S' => .shop,
            'O' => .office,
            'C' => .clinic,
            'T' => .hall,
            'D' => .depot,
            else => .park,
        };
        const x = @as(f32, @floatFromInt(col)) * spacing + 3;
        const z = @as(f32, @floatFromInt(row)) * spacing + 3;
        const width: f32 = if (kind == .office or kind == .depot) 8 else 6 + @as(f32, @floatFromInt(i % 3));
        const height: f32 = switch (kind) {
            .home => 3 + @as(f32, @floatFromInt(i % 4)) * 1.6,
            .office => 8 + @as(f32, @floatFromInt(i % 5)) * 2,
            .shop => 3,
            .clinic => 5,
            .hall => 9,
            .depot => 3.5,
            .park => 0.1,
        };
        b.* = .{ .x = x, .z = z, .width = width, .depth = 7, .height = height, .ground = elevation(x + width, z + 7), .kind = kind, .district = districtAt(x, z), .node = row * (cols + 1) + col, .value = if (kind == .home) 1800000 + @as(f64, @floatFromInt(i % 4)) * 300000 else if (kind == .shop or kind == .office or kind == .depot) 2400000 + @as(f64, @floatFromInt(i % 5)) * 500000 else 0, .capacity = switch (kind) {
            .home, .park => 0,
            .office => 95,
            .shop => 40,
            .clinic => 80,
            .hall => 90,
            .depot => 24,
        } };
    }
    for (buildings, 0..) |b, id| building_at_node[b.node] = @intCast(id);
    var index: usize = 0;
    for (0..node_count) |a| {
        if (a % (cols + 1) < cols) {
            addRoad(index, a, a + 1);
            index += 1;
        }
        if (a / (cols + 1) < rows) {
            addRoad(index, a, a + cols + 1);
            index += 1;
        }
    }
    rebuildRoutes();
}
fn addRoad(index: usize, a: usize, b: usize) void {
    const dy = nodes[b].y - nodes[a].y;
    const district = districtAt((nodes[a].x + nodes[b].x) / 2, (nodes[a].z + nodes[b].z) / 2);
    roads[index] = .{ .a = a, .b = b, .length = @sqrt(spacing * spacing + dy * dy), .slope = @abs(dy) / spacing, .district = district, .condition = if (district == 0 or district == 3) 28 + @as(f32, @floatFromInt(index % 15)) else 58 + @as(f32, @floatFromInt(index % 30)) };
}
pub fn rebuildRoutes() void {
    for (0..node_count) |a| for (0..node_count) |b| {
        road_between[a][b] = -1;
        next_node[a][b] = @intCast(b);
        distance[a][b] = if (a == b) 0 else 1e9;
    };
    for (roads, 0..) |r, i| {
        road_between[r.a][r.b] = @intCast(i);
        road_between[r.b][r.a] = @intCast(i);
        if (!r.pedestrians) continue;
        const cost = r.length * (1 + r.slope * 3) / (0.7 + r.condition / 100);
        distance[r.a][r.b] = cost;
        distance[r.b][r.a] = cost;
    }
    // All-pairs next hops: shared by every resident; no per-frame path allocations.
    for (0..node_count) |k| for (0..node_count) |a| for (0..node_count) |b| {
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
