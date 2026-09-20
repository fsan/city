const std = @import("std");
const city = @import("city.zig");
pub const max_parcels = 1024;
pub const Parcel = struct { x: f32, z: f32, width: f32 = 7, depth: f32 = 8, zone: u32 = 0, building: i32 = -1, block: i32 = -1, node: usize = 0, street: usize = 0, number: usize = 0 };
// 0 unzoned, 1 residential, 2 commercial, 3 industrial, 4 mixed, 5 civic/park reserve.
pub var storage: [max_parcels]Parcel = undefined;
pub var count: usize = 0;
pub var selected: i32 = -1;
pub var visible = false;
pub const Block = struct { nodes: [128]usize = undefined, count: usize = 0, area: f32 = 0 };
pub var blocks: [128]Block = undefined;
pub var block_count: usize = 0;
pub fn init() void {
    count = city.buildings.len;
    selected = -1;
    visible = false;
    for (&city.buildings, 0..) |b, i| storage[i] = .{ .x = b.x, .z = b.z, .width = b.width, .depth = b.depth, .zone = switch (b.kind) {
        .home => 1,
        .shop, .office => 2,
        .depot => 3,
        .vacant => 0,
        else => 5,
    }, .building = if (b.kind == .vacant) -1 else @intCast(i), .node = b.node, .street = b.street, .number = b.number };
    rebuildBlocks();
}
fn inside(block: Block, x: f32, z: f32) bool {
    var result = false;
    for (block.nodes[0..block.count], 0..) |id, i| {
        const a = city.nodes[id];
        const b = city.nodes[block.nodes[(i + 1) % block.count]];
        if ((a.z > z) != (b.z > z) and x < (b.x - a.x) * (z - a.z) / (b.z - a.z) + a.x) result = !result;
    }
    return result;
}
pub fn rebuildBlocks() void {
    block_count = 0;
    var visited: [city.max_roads * 2]bool = @splat(false);
    for (city.roads, 0..) |road, rid| for (0..2) |direction| {
        const initial = rid * 2 + direction;
        if (visited[initial]) continue;
        var key = initial;
        var face: Block = .{};
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
            if (face.count == face.nodes.len) break;
            face.nodes[face.count] = from;
            face.count += 1;
            face.area += city.nodes[from].x * city.nodes[to].z - city.nodes[to].x * city.nodes[from].z;
            const back = std.math.atan2(city.nodes[from].z - city.nodes[to].z, city.nodes[from].x - city.nodes[to].x);
            var best: f32 = 10;
            var next_key = key ^ 1;
            for (city.roads, 0..) |r, j| {
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
        _ = road;
        if (closed and face.area < -40 and block_count < blocks.len) {
            face.area = -face.area / 2;
            blocks[block_count] = face;
            block_count += 1;
        }
    };
    for (storage[0..count]) |*p| {
        p.block = -1;
        for (blocks[0..block_count], 0..) |b, i| {
            if (inside(b, p.x + p.width / 2, p.z + p.depth / 2)) {
                p.block = @intCast(i);
                break;
            }
        }
    }
}
pub fn paint(id: usize, zone: u32, whole_block: bool) bool {
    if (id >= count or zone > 5) return false;
    const block = storage[id].block;
    for (storage[0..count], 0..) |*p, i| if (i == id or (whole_block and block >= 0 and p.block == block)) {
        p.zone = zone;
    };
    return true;
}
pub fn pick(x: f32, z: f32) i32 {
    for (storage[0..count], 0..) |p, i| {
        if (x >= p.x and x <= p.x + p.width and z >= p.z and z <= p.z + p.depth) return @intCast(i);
    }
    return -1;
}
pub fn addFrontages(first_road: usize) void {
    for (city.roads[first_road..]) |r| {
        const a = city.nodes[r.a];
        const b = city.nodes[r.b];
        const length = city.hypot(b.x - a.x, b.z - a.z);
        const dx = (b.x - a.x) / length;
        const dz = (b.z - a.z) / length;
        var at: f32 = 5;
        while (at < length - 3 and count < storage.len) : (at += 10) {
            for ([_]f32{ -1, 1 }) |side| {
                const x = a.x + dx * at - dz * side * 8.5 - 3.5;
                const z = a.z + dz * at + dx * side * 8.5 - 4;
                if (x < 3 or z < 3 or x + 7 > city.size_x - 3 or z + 8 > city.size_z - 3) continue;
                var clear = true;
                for (storage[0..count]) |p| {
                    if (x < p.x + p.width + 1 and x + 8 > p.x and z < p.z + p.depth + 1 and z + 9 > p.z) {
                        clear = false;
                        break;
                    }
                }
                for (city.roads) |other| {
                    const u = city.projection(.{ .x = x + 3.5, .z = z + 4 }, city.nodes[other.a], city.nodes[other.b]);
                    const ox = city.nodes[other.a].x + (city.nodes[other.b].x - city.nodes[other.a].x) * u;
                    const oz = city.nodes[other.a].z + (city.nodes[other.b].z - city.nodes[other.a].z) * u;
                    if (city.hypot(ox - x - 3.5, oz - z - 4) < 7.8) {
                        clear = false;
                        break;
                    }
                }
                if (clear) {
                    var number: usize = if (side > 0) 1 else 2;
                    for (storage[0..count]) |p| {
                        if (p.street == r.street and p.number % 2 == number % 2) number = @max(number, p.number + 2);
                    }
                    storage[count] = .{ .x = x, .z = z, .node = r.a, .street = r.street, .number = number };
                    count += 1;
                }
            }
        }
    }
    rebuildBlocks();
}
