const std = @import("std");
const city = @import("../scene/city.zig");

// Slice 11: signalised junctions.
//
// A junction is signalised as a whole. Every arm (the road segments meeting at
// the node) belongs to exactly one phase, and only one phase is green at a
// time, so a single branch moves while the others wait. Phases run in a fixed
// order with a green then a yellow per phase. Green and yellow are in
// simulation seconds and are editable per junction.
pub const max_junctions = 64;
pub const max_arms = 4;
pub const min_green: f32 = 2;
pub const max_green: f32 = 60;
pub const min_yellow: f32 = 1;
pub const max_yellow: f32 = 10;
pub const default_green: f32 = 8;
pub const default_yellow: f32 = 2;
// A signal head sits this far down its own arm, set back from the corner.
pub const head_setback: f32 = 3.4;
pub const head_offset: f32 = 2.6;

pub const State = enum(u8) { red = 0, yellow = 1, green = 2 };

pub const Junction = struct {
    node: usize = 0,
    arms: [max_arms]i32 = @splat(-1),
    arm_count: usize = 0,
    green: f32 = default_green,
    yellow: f32 = default_yellow,
    // Stagger so neighbouring junctions do not all turn green together.
    offset: f32 = 0,
    active: bool = false,
};

pub var junctions: [max_junctions]Junction = @splat(.{});
pub var count: usize = 0;
pub var placed_total: u32 = 0;
pub var removed_total: u32 = 0;

pub fn reset() void {
    junctions = @splat(.{});
    count = 0;
    placed_total = 0;
    removed_total = 0;
}

pub fn find(node: usize) ?usize {
    for (junctions[0..count], 0..) |j, index| {
        if (j.active and j.node == node) return index;
    }
    return null;
}

pub fn cycleSeconds(j: *const Junction) f32 {
    const phases: f32 = @floatFromInt(@max(1, j.arm_count));
    return phases * (j.green + j.yellow);
}

// Which phase is running, and how far into it, for a junction at this instant.
pub fn phaseAt(j: *const Junction, elapsed: f64) usize {
    const span = @max(0.5, j.green + j.yellow);
    const total = span * @as(f32, @floatFromInt(@max(1, j.arm_count)));
    const clock = @mod(@as(f32, @floatCast(elapsed)) + j.offset, total);
    return @intFromFloat(@min(@as(f32, @floatFromInt(j.arm_count - 1)), @floor(clock / span)));
}

pub fn armState(j: *const Junction, arm: usize, elapsed: f64) State {
    if (arm >= j.arm_count) return .red;
    const span = @max(0.5, j.green + j.yellow);
    const total = span * @as(f32, @floatFromInt(@max(1, j.arm_count)));
    const clock = @mod(@as(f32, @floatCast(elapsed)) + j.offset, total);
    const phase: usize = @intFromFloat(@min(@as(f32, @floatFromInt(j.arm_count - 1)), @floor(clock / span)));
    if (phase != arm) return .red;
    const into = clock - @as(f32, @floatFromInt(phase)) * span;
    return if (into < j.green) .green else .yellow;
}

// Seconds until this arm changes state, for the inspector.
pub fn secondsLeft(j: *const Junction, arm: usize, elapsed: f64) f32 {
    const span = @max(0.5, j.green + j.yellow);
    const total = span * @as(f32, @floatFromInt(@max(1, j.arm_count)));
    const clock = @mod(@as(f32, @floatCast(elapsed)) + j.offset, total);
    const phase: usize = @intFromFloat(@min(@as(f32, @floatFromInt(j.arm_count - 1)), @floor(clock / span)));
    if (phase == arm) {
        const into = clock - @as(f32, @floatFromInt(phase)) * span;
        return if (into < j.green) j.green - into else j.green + j.yellow - into;
    }
    var left = total - clock;
    var step = phase;
    while (step != arm) {
        left += span;
        step = (step + 1) % j.arm_count;
    }
    return left;
}

pub fn armCount(node: usize) usize {
    var total: usize = 0;
    for (city.roads) |r| {
        if (r.a == node or r.b == node) total += 1;
    }
    return @min(total, max_arms);
}

// The unit direction from a node along a road, or null when the road does not
// touch the node.
pub fn armDirection(node: usize, road: usize) ?city.Vec {
    if (road >= city.roads.len) return null;
    const r = city.roads[road];
    const a = city.nodes[r.a];
    const b = city.nodes[r.b];
    var dx: f32 = 0;
    var dz: f32 = 0;
    if (r.a == node) {
        dx = b.x - a.x;
        dz = b.z - a.z;
    } else if (r.b == node) {
        dx = a.x - b.x;
        dz = a.z - b.z;
    } else return null;
    const len = city.hypot(dx, dz);
    if (len < 0.01) return null;
    return .{ .x = dx / len, .z = dz / len };
}

// Where the head for this arm stands: back from the corner and just off the
// carriageway on the right-hand side of the approach.
pub fn headPosition(node: usize, road: usize) ?city.Vec {
    const dir = armDirection(node, road) orelse return null;
    const n = city.nodes[node];
    return .{
        .x = n.x + dir.x * head_setback - dir.z * head_offset,
        .z = n.z + dir.z * head_setback + dir.x * head_offset,
    };
}

// Signalise a junction, adding every arm it currently has. Returns the new or
// existing junction index.
pub fn signalise(node: usize) ?usize {
    if (node >= city.node_count or city.degree(node) < 3) return null;
    if (find(node)) |existing| return existing;
    if (count >= max_junctions) return null;
    var j = Junction{ .node = node, .active = true, .offset = @floatFromInt((node * 7) % 11) };
    for (city.roads, 0..) |r, id| {
        if (r.a != node and r.b != node) continue;
        if (j.arm_count >= max_arms) break;
        j.arms[j.arm_count] = @intCast(id);
        j.arm_count += 1;
    }
    if (j.arm_count < 2) return null;
    junctions[count] = j;
    count += 1;
    placed_total +|= 1;
    return count - 1;
}

pub fn remove(node: usize) bool {
    const index = find(node) orelse return false;
    junctions[index] = junctions[count - 1];
    count -= 1;
    removed_total +|= 1;
    return true;
}

pub fn armIndex(node: usize, road: usize) ?usize {
    const index = find(node) orelse return null;
    const j = &junctions[index];
    for (j.arms[0..j.arm_count], 0..) |arm, slot| {
        if (arm >= 0 and @as(usize, @intCast(arm)) == road) return slot;
    }
    return null;
}

// Cars turning into an arm may only do so while that arm's phase is green.
pub fn green(node: usize, road: usize, elapsed: f64) bool {
    const index = find(node) orelse return true; // Unsignalised junctions stay uncontrolled.
    const arm = armIndex(node, road) orelse return true;
    return armState(&junctions[index], arm, elapsed) == .green;
}

// Pedestrians and cyclists cross an arm while it is stopped for traffic, which
// is when the movement parallel to them holds green.
pub fn crossingAllowed(node: usize, movement: city.Vec, elapsed: f64) bool {
    const index = find(node) orelse return true;
    const j = &junctions[index];
    var parallel_green = false;
    for (j.arms[0..j.arm_count], 0..) |arm, slot| {
        if (arm < 0) continue;
        const dir = armDirection(node, @intCast(arm)) orelse continue;
        const dot = dir.x * movement.x + dir.z * movement.z;
        if (@abs(dot) < 0.7) continue; // Perpendicular arms are not this crossing's control.
        if (armState(j, slot, elapsed) == .green) parallel_green = true;
    }
    return parallel_green;
}

pub fn setGreen(node: usize, seconds: f32) bool {
    const index = find(node) orelse return false;
    junctions[index].green = std.math.clamp(seconds, min_green, max_green);
    return true;
}

pub fn setYellow(node: usize, seconds: f32) bool {
    const index = find(node) orelse return false;
    junctions[index].yellow = std.math.clamp(seconds, min_yellow, max_yellow);
    return true;
}

pub fn signalisedCount() usize {
    return count;
}

pub fn armStateAt(node: usize, road: usize, elapsed: f64) State {
    const index = find(node) orelse return .green;
    const arm = armIndex(node, road) orelse return .green;
    return armState(&junctions[index], arm, elapsed);
}

// Seed signals where the authored plan already crosses a busy corner, so the
// opening town behaves as before and the player can add or remove from there.
pub fn seed() void {
    reset();
    for (city.roads, 0..) |r, id| {
        if (!r.crosswalk) continue;
        if (city.degree(r.a) >= 3) _ = signalise(r.a);
        if (city.degree(r.b) >= 3) _ = signalise(r.b);
        _ = id;
        if (count >= max_junctions) break;
    }
}
