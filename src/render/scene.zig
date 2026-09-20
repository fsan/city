const std = @import("std");
const city = @import("../scene/city.zig");
const game = @import("../simulation/game.zig");
pub var vertices: [300000 * 6]f32 = undefined;
pub var count: usize = 0;
pub var camera_x: f32 = 24;
pub var camera_z: f32 = 24;
pub var zoom: f32 = 1;
pub var angle: f32 = std.math.pi / 4.0;
pub var width: f32 = 1200;
pub var height: f32 = 800;
pub var selected: i32 = -1;
pub var selected_person: i32 = -1;
pub var overlay = false;
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
    quad(a, b, bt, at, shade(color, 0.68));
    quad(b, c, ct, bt, shade(color, 0.82));
    quad(c, e, et, ct, shade(color, 0.72));
    quad(e, a, at, et, shade(color, 0.88));
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
    quad(.{ x, city.elevation(x, z) + offset, z }, .{ x + w, city.elevation(x + w, z) + offset, z }, .{ x + w, city.elevation(x + w, z + d) + offset, z + d }, .{ x, city.elevation(x, z + d) + offset, z + d }, color);
}
pub fn focus(x: f32, z: f32) void {
    camera_x = x;
    camera_z = z;
    zoom = 3;
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
    for (city.roads) |r| {
        const a = city.nodes[r.a];
        const b = city.nodes[r.b];
        const horizontal = a.z == b.z;
        groundQuad(a.x - 2, a.z - 2, if (horizontal) city.spacing + 4 else 4, if (horizontal) 4 else city.spacing + 4, 0.04, .{ 0.49, 0.49, 0.45 });
        const color: Color = if (r.works) .{ 0.66, 0.46, 0.18 } else if (overlay) streetColor(r.condition) else .{ 0.23, 0.25, 0.25 };
        groundQuad(a.x - 1.05, a.z - 1.05, if (horizontal) city.spacing + 2.1 else 2.1, if (horizontal) 2.1 else city.spacing + 2.1, 0.09, color);
        for (0..4) |j| {
            const offset = @as(f32, @floatFromInt(j)) * 3.2 + 1;
            groundQuad(a.x + (if (horizontal) offset else -0.05), a.z + (if (horizontal) -0.05 else offset), if (horizontal) 1.1 else 0.1, if (horizontal) 0.1 else 1.1, 0.12, .{ 0.65, 0.63, 0.51 });
        }
    }
    for (city.buildings, 0..) |b, i| {
        const materials = [_]Color{ .{ 0.57, 0.52, 0.43 }, .{ 0.62, 0.60, 0.53 }, .{ 0.47, 0.42, 0.36 }, .{ 0.66, 0.65, 0.60 }, .{ 0.48, 0.50, 0.48 } };
        const color: Color = if (b.kind == .office) .{ 0.43, 0.48, 0.48 } else if (b.kind == .park) .{ 0.33, 0.43, 0.31 } else materials[i % materials.len];
        const entry = city.nodes[b.node];
        quad(.{ entry.x + 1.35, city.elevation(entry.x + 1.35, entry.z + 1.65) + 0.13, entry.z + 1.65 }, .{ entry.x + 1.95, city.elevation(entry.x + 1.95, entry.z + 1.65) + 0.13, entry.z + 1.65 }, .{ b.x + b.width / 2 + 0.3, b.ground + 0.35, b.z - 0.4 }, .{ b.x + b.width / 2 - 0.3, b.ground + 0.35, b.z - 0.4 }, .{ 0.55, 0.53, 0.47 });
        const low = city.elevation(b.x, b.z);
        box(b.x, b.z, b.width, b.depth, b.ground - low + 0.2, low, .{ 0.41, 0.41, 0.37 });
        if (selected == @as(i32, @intCast(i))) box(b.x - 0.25, b.z - 0.25, b.width + 0.5, b.depth + 0.5, 0.08, b.ground + 0.21, .{ 0.94, 0.76, 0.32 });
        box(b.x, b.z, b.width, b.depth, b.height, b.ground + 0.3, color);
        if (b.kind == .park) {
            for (0..3) |t| {
                const x = b.x + 1 + @as(f32, @floatFromInt(t)) * 2;
                box(x, b.z + 3, 0.25, 0.25, 1.8, b.ground + 0.4, .{ 0.33, 0.28, 0.21 });
                box(x - 0.6, b.z + 2.4, 1.6, 1.6, 2, b.ground + 1.6, .{ 0.25, 0.35, 0.24 });
            }
        } else {
            box(b.x + 0.3, b.z + 0.3, b.width - 0.6, b.depth - 0.6, 0.2, b.ground + b.height + 0.3, shade(color, 0.78));
            if (b.kind == .home and i % 3 == 0) box(b.x + 1, b.z + 1, b.width - 2, b.depth - 2, 0.9, b.ground + b.height + 0.5, .{ 0.36, 0.34, 0.31 });
            if (b.kind == .depot) box(b.x + 0.5, b.z + b.depth, 5, 0.05, 2.5, b.ground + 0.3, .{ 0.25, 0.27, 0.26 });
            var floor: f32 = 1.5;
            while (floor < b.height) : (floor += 2) {
                for (0..3) |j| {
                    const offset = @as(f32, @floatFromInt(j)) * 1.8 + 0.8;
                    box(b.x + offset, b.z + b.depth, 0.8, 0.035, 0.75, b.ground + floor, .{ 0.26, 0.31, 0.31 });
                    box(b.x + b.width, b.z + offset, 0.035, 0.8, 0.75, b.ground + floor, .{ 0.29, 0.34, 0.34 });
                }
            }
        }
    }
    if (selected_person >= 0) {
        const p = game.residents.people[@intCast(selected_person)];
        var node = p.next;
        var steps: usize = 0;
        while (node != p.destination and steps < city.node_count) : (steps += 1) {
            const next = city.next_node[node][p.destination];
            const a = city.nodes[node];
            const b = city.nodes[next];
            const x = @min(a.x, b.x) + 1.5;
            const z = @min(a.z, b.z) + 1.5;
            groundQuad(x, z, if (a.x == b.x) 0.3 else city.spacing, if (a.z == b.z) 0.3 else city.spacing, 0.18, .{ 0.95, 0.76, 0.3 });
            node = next;
        }
        const y = p.y;
        box(p.x - 0.3, p.z - 0.3, 0.6, 0.6, 0.12, y + 0.2, .{ 1, 0.82, 0.25 });
    }
    for (game.residents.people, 0..) |p, i| {
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
    for (city.buildings, 0..) |b, i| {
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
