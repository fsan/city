const std = @import("std");
const city = @import("../scene/city.zig");
const calendar = @import("calendar.zig");

// Slice 11: signalised junctions.
//
// A junction is signalised as a whole. Every arm (the road segments meeting at
// the node) belongs to exactly one phase, and only one phase is green at a
// time, so a single branch moves while the others wait. Phases run in a fixed
// order with a green, a yellow and an all-red clearance per phase. All three
// are in simulation seconds and are editable per junction.
//
// Slice 12 adds the granular controls the player asked for:
//   * an all-red "off" time after each branch's yellow;
//   * a daily window where the junction flashes amber instead of cycling, so
//     drivers cross slowly when it is safe;
//   * a manual flash switch that puts one junction, a street or the whole town
//     on flashing amber and takes it off again;
//   * coordination groups: a link names a leader, a follower and the delay in
//     simulation seconds between their actions;
//   * alerts, so a police or firefighter dispatcher can one day ask a junction
//     to hold cross traffic or to fall back to flashing amber. Nothing calls
//     those yet except the player's own controls.
//
// Item 14 (crossings and junction behaviour) adds the three things the earlier
// signals deliberately left out:
//   * a pedestrian-only stage. After every vehicle branch has run its green,
//     amber and all-red clearance, the junction holds every vehicle arm red for
//     a bounded walk time so people cross on their own stage rather than only
//     beside a parallel green. A clearance interval follows, during which no
//     crossing is admitted, so the box empties before the next vehicle phase.
//   * turning geometry. Every movement between an approach arm and an exit arm
//     is classified straight/left/right/u-turn from the codebase's own
//     right-hand side rule, given a bounded radius, and given the lateral lane
//     position a driver should hold on the approach for that turn.
//   * yielding. Turning traffic yields to whoever is on the crosswalk it turns
//     into, and a left turn yields while another vehicle is still in the box.
pub const max_junctions = 64;
pub const max_arms = 4;
pub const max_links = 128;
pub const max_alerts = 32;
pub const max_groups = 32;
// Any value the player can type in the timing fields is accepted: one half of
// a simulation second is the floor, which is one and a half simulation minutes
// of city time. The old floors (green 2 s, amber 1 s) silently replaced smaller
// values the player typed.
pub const min_green: f32 = 0.5;
pub const max_green: f32 = 60;
pub const min_yellow: f32 = 0.5;
pub const max_yellow: f32 = 10;
pub const min_red: f32 = 0;
pub const max_red: f32 = 6;
pub const min_delay: f32 = 0;
pub const max_delay: f32 = 60;
pub const default_green: f32 = 8;
pub const default_yellow: f32 = 2;
pub const default_red: f32 = 1;
pub const default_delay: f32 = 0;
// Item 14: the pedestrian stage. Walk time zero disables the stage entirely, so
// a junction set that way keeps the exact pre-item-14 cycle.
pub const min_ped_walk: f32 = 0;
pub const max_ped_walk: f32 = 30;
pub const min_ped_clear: f32 = 0;
pub const max_ped_clear: f32 = 10;
pub const default_ped_walk: f32 = 4;
pub const default_ped_clear: f32 = 1.5;
// Turning geometry: the last stretch of approach where a driver moves into the
// lane their turn needs, and the bounds of a measured turning radius.
pub const turn_approach: f32 = 12;
pub const min_turn_radius: f32 = 3;
pub const max_turn_radius: f32 = 16;
// A signal head sits this far down its own arm, set back from the corner.
pub const head_setback: f32 = 3.4;
pub const head_offset: f32 = 2.6;
// Flashing amber: one half of the blink lasts this many simulation seconds.
pub const flash_period: f32 = 0.9;
// A preemption or alert keeps control for this long unless it is released.
pub const default_preempt_seconds: f32 = 30;

pub const State = enum(u8) { red = 0, yellow = 1, green = 2, flash = 3 };
// Which part of the cycle is running. The vehicle stage walks the arms in
// order; the pedestrian stage holds every arm red; clearance then empties the
// box before the next vehicle arm is released.
pub const Stage = enum(u8) { vehicle = 0, pedestrian = 1, clearance = 2 };
// The movement from one arm of a junction to another, from the codebase's own
// right-hand side rule: rotate the direction of travel by +90 degrees and the
// exit lies on the driver's right when the exit direction has a positive
// component along it.
pub const Turn = enum(u8) { straight = 0, left = 1, right = 2, uturn = 3 };
pub const FlashMode = enum(i8) { off = -1, auto = 0, on = 1 };
pub const Preempt = enum(u8) { none = 0, closed = 1, open = 2 };
pub const AlertKind = enum(u8) { hold = 1, open = 2, release = 3 };
pub const BulkScope = enum(u8) { all = 0, street = 1, junction = 2 };
pub const BulkField = enum(u8) {
    green = 0,
    yellow = 1,
    red = 2,
    flash_start = 3,
    flash_end = 4,
    flash_enabled = 5,
    flash_mode = 6,
    // Item 14 append-only bulk targets for the pedestrian stage.
    ped_walk = 7,
    ped_clear = 8,
    ped_enabled = 9,
};

pub const Junction = struct {
    node: usize = 0,
    arms: [max_arms]i32 = @splat(-1),
    arm_count: usize = 0,
    green: f32 = default_green,
    yellow: f32 = default_yellow,
    red: f32 = default_red,
    // Stagger so neighbouring junctions do not all turn green together.
    offset: f32 = 0,
    // Coordination: a follower runs the same cycle as its group leader, held
    // back by this many simulation seconds.
    delay: f32 = default_delay,
    group: i8 = -1,
    flash: FlashMode = .auto,
    flash_enabled: bool = false,
    // Hours of the simulation day covered by the automatic flash window. A
    // window whose start is later than its end runs overnight.
    flash_start: f32 = 22,
    flash_end: f32 = 6,
    preempt: Preempt = .none,
    preempt_until: f64 = 0,
    // Item 14: the pedestrian-only walk time and the all-red clearance that
    // follows it. `ped_enabled` false removes both from the cycle, so an older
    // junction keeps its original timing.
    ped_walk: f32 = default_ped_walk,
    ped_clear: f32 = default_ped_clear,
    ped_enabled: bool = true,
    active: bool = false,
};

pub const Link = struct {
    from: usize = 0,
    to: usize = 0,
    delay: f32 = default_delay,
    active: bool = false,
};

pub const Alert = struct {
    node: usize = 0,
    kind: AlertKind = .hold,
    until: f64 = 0,
};

pub var junctions: [max_junctions]Junction = @splat(.{});
pub var count: usize = 0;
pub var placed_total: u32 = 0;
pub var removed_total: u32 = 0;
pub var links: [max_links]Link = @splat(.{});
pub var link_count: usize = 0;
pub var link_total: u32 = 0;
pub var alerts: [max_alerts]Alert = @splat(.{});
pub var alert_count: usize = 0;
pub var alerts_handled: u64 = 0;
pub var alerts_dropped: u64 = 0;
pub var alerts_pushed: u64 = 0;

pub fn reset() void {
    junctions = @splat(.{});
    count = 0;
    placed_total = 0;
    removed_total = 0;
    links = @splat(.{});
    link_count = 0;
    link_total = 0;
    alerts = @splat(.{});
    alert_count = 0;
    alerts_handled = 0;
    alerts_dropped = 0;
    alerts_pushed = 0;
}

pub fn find(node: usize) ?usize {
    for (junctions[0..count], 0..) |j, index| {
        if (j.active and j.node == node) return index;
    }
    return null;
}

fn spanSeconds(j: *const Junction) f32 {
    return @max(0.5, j.green + j.yellow + j.red);
}

fn vehicleSeconds(j: *const Junction) f32 {
    return spanSeconds(j) * @as(f32, @floatFromInt(@max(1, j.arm_count)));
}

fn pedWalkSeconds(j: *const Junction) f32 {
    return if (j.ped_enabled) @max(0, j.ped_walk) else 0;
}

fn pedClearSeconds(j: *const Junction) f32 {
    return if (j.ped_enabled) @max(0, j.ped_clear) else 0;
}

fn totalSeconds(j: *const Junction) f32 {
    return @max(0.5, vehicleSeconds(j) + pedWalkSeconds(j) + pedClearSeconds(j));
}

// Which part of the cycle is running, which vehicle arm is in its green/amber
// if any, and how far into that part the junction is.
pub const StageInfo = struct { stage: Stage = .vehicle, arm: usize = 0, into: f32 = 0 };

pub fn stageAt(j: *const Junction, elapsed: f64) StageInfo {
    const clock = clockAt(j, elapsed);
    const vehicle = vehicleSeconds(j);
    if (clock < vehicle) {
        const span = spanSeconds(j);
        const limit: f32 = @floatFromInt(@max(0, j.arm_count -| 1));
        const arm_f = @min(limit, @floor(clock / span));
        return .{ .stage = .vehicle, .arm = @intFromFloat(arm_f), .into = clock - arm_f * span };
    }
    if (clock < vehicle + pedWalkSeconds(j)) {
        return .{ .stage = .pedestrian, .arm = @max(0, j.arm_count -| 1), .into = clock - vehicle };
    }
    const walk = pedWalkSeconds(j);
    return .{ .stage = .clearance, .arm = @max(0, j.arm_count -| 1), .into = clock - vehicle - walk };
}

fn clockAt(j: *const Junction, elapsed: f64) f32 {
    const raw = @as(f32, @floatCast(elapsed)) + j.offset + j.delay;
    return @mod(@max(0, raw), totalSeconds(j));
}

// Phase length, including the all-red clearance between branches and the
// pedestrian walk and clearance stages.
pub fn cycleSeconds(j: *const Junction) f32 {
    return totalSeconds(j);
}

// Item 14: the current pedestrian stage and how long it still has to run, both
// for the inspector and for the ABI. `secondsLeft` is zero during the vehicle
// stage and counts down through walk and clearance.
pub fn stage(j: *const Junction, elapsed: f64) Stage {
    return stageAt(j, elapsed).stage;
}

pub fn pedestrianWalk(j: *const Junction, elapsed: f64) bool {
    return stageAt(j, elapsed).stage == .pedestrian;
}

pub fn pedestrianClearance(j: *const Junction, elapsed: f64) bool {
    return stageAt(j, elapsed).stage == .clearance;
}

pub fn pedSecondsLeft(j: *const Junction, elapsed: f64) f32 {
    const info = stageAt(j, elapsed);
    return switch (info.stage) {
        .vehicle => 0,
        .pedestrian => pedWalkSeconds(j) - info.into,
        .clearance => pedClearSeconds(j) - info.into,
    };
}

// Is this junction showing flashing amber right now? A manual switch wins over
// the schedule, an alert-driven preemption wins over both.
pub fn flashing(j: *const Junction, elapsed: f64) bool {
    switch (j.flash) {
        .on => return true,
        .off => return false,
        .auto => {},
    }
    switch (j.preempt) {
        .open => return true,
        .closed => return false,
        .none => {},
    }
    if (!j.flash_enabled) return false;
    const hour: f32 = @floatCast(calendar.hour(elapsed));
    if (@abs(j.flash_start - j.flash_end) < 0.001) return false;
    if (j.flash_start < j.flash_end) return hour >= j.flash_start and hour < j.flash_end;
    return hour >= j.flash_start or hour < j.flash_end;
}

// The blink itself: amber lamps are lit for half of every flash period.
pub fn flashLit(j: *const Junction, elapsed: f64) bool {
    const clock = @as(f32, @floatCast(elapsed)) + j.offset + j.delay;
    return @mod(@max(0, clock), flash_period * 2) < flash_period;
}

// Which vehicle arm holds the running phase. During the pedestrian walk or the
// clearance that follows it every arm is red, so the last arm is reported and
// its state is red.
pub fn phaseAt(j: *const Junction, elapsed: f64) usize {
    return stageAt(j, elapsed).arm;
}

pub fn armState(j: *const Junction, arm: usize, elapsed: f64) State {
    if (arm >= j.arm_count) return .red;
    if (flashing(j, elapsed)) return .flash;
    const info = stageAt(j, elapsed);
    if (info.stage != .vehicle) return .red; // pedestrian walk and clearance hold every arm
    if (info.arm != arm) return .red;
    if (info.into < j.green) return .green;
    if (info.into < j.green + j.yellow) return .yellow;
    return .red;
}

// Seconds until this arm changes state, for the inspector. Flashing amber has
// no upcoming change, so it reports zero. The pedestrian walk and clearance are
// part of the arm's wait, so the countdown is honest about the whole cycle.
pub fn secondsLeft(j: *const Junction, arm: usize, elapsed: f64) f32 {
    if (j.arm_count == 0 or arm >= j.arm_count) return 0;
    if (flashing(j, elapsed)) return 0;
    const span = spanSeconds(j);
    const total = totalSeconds(j);
    const clock = clockAt(j, elapsed);
    const info = stageAt(j, elapsed);
    if (info.stage == .vehicle and info.arm == arm) {
        if (info.into < j.green) return j.green - info.into;
        return j.green + j.yellow + j.red - info.into;
    }
    var left = total - clock;
    var step = info.arm;
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

// Item 14 turning geometry. The direction a driver travels *into* the node along
// this arm: the arm direction points out of the node, so travel is its negative.
pub fn travelDirection(node: usize, road: usize) ?city.Vec {
    const out = armDirection(node, road) orelse return null;
    return .{ .x = -out.x, .z = -out.z };
}

// The movement from one arm of a junction to another. The right-hand side of a
// driver travelling along `d` is `(-d.z, d.x)`, the rule this file already uses
// for the signal head. An exit with a positive component along that side is a
// right turn; a negative component is a left turn; and a near-reversal is a
// u-turn. A junction with two arms or an arm that does not touch the node has no
// movement to classify and reports straight, so nothing is gated on bad data.
pub fn turnKind(node: usize, approach_road: usize, exit_road: usize) Turn {
    if (approach_road == exit_road) return .uturn;
    const d = travelDirection(node, approach_road) orelse return .straight;
    const e = armDirection(node, exit_road) orelse return .straight;
    const dot = d.x * e.x + d.z * e.z;
    if (dot > 0.7) return .straight;
    if (dot < -0.7) return .uturn;
    const cross = d.x * e.z - d.z * e.x;
    return if (cross > 0) .right else .left;
}

// The measured radius of the arc joining this approach's lane to this exit's
// lane. The two signal-head points sit a setback down their own arms; a right
// angle between them makes that chord the hypotenuse of a square, so the radius
// is the chord over the square root of two. Straight and u-turn movements have
// no corner to round and report zero. The value is bounded so a very short or
// very long authored arm cannot report a radius the renderer would have to
// trust blindly.
pub fn turnRadius(node: usize, approach_road: usize, exit_road: usize) f32 {
    const kind = turnKind(node, approach_road, exit_road);
    if (kind == .straight or kind == .uturn) return 0;
    const a = headPosition(node, approach_road) orelse return 0;
    const b = headPosition(node, exit_road) orelse return 0;
    const chord = city.hypot(a.x - b.x, a.z - b.z);
    return std.math.clamp(chord / std.math.sqrt2, min_turn_radius, max_turn_radius);
}

// How far from the centre line a driver holds on the approach for each kind of
// turn. A right turn keeps to the kerb so it can swing wide; a left turn keeps
// close to the centre so it crosses the oncoming lane as briefly as possible;
// a straight movement keeps the ordinary lane offset.
pub fn turnOffset(kind: Turn) f32 {
    return switch (kind) {
        .straight => 0.55,
        .right => 1.9,
        .left => 0.2,
        .uturn => 0.2,
    };
}

// The lateral offset at a point on the approach. Far from the junction the
// driver keeps the ordinary lane; inside the turn approach they slide steadily
// into the offset their turn needs, which is the visible turning geometry.
pub fn approachLaneOffset(base: f32, kind: Turn, remaining: f32) f32 {
    if (kind == .straight) return base;
    const span = @max(0.1, turn_approach);
    const t = std.math.clamp(1 - remaining / span, 0, 1);
    return base + (turnOffset(kind) - base) * t;
}

pub fn turnName(kind: Turn) []const u8 {
    return switch (kind) {
        .straight => "straight",
        .left => "left",
        .right => "right",
        .uturn => "u-turn",
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
    const last = count - 1;
    if (index != last) {
        junctions[index] = junctions[last];
        // Links and groups address junctions by index, so re-point whatever
        // referred to the junction that just moved into the vacated slot.
        for (links[0..link_count]) |*l| {
            if (l.from == last) l.from = index else if (l.from > index and l.from <= last) l.from -= 1;
            if (l.to == last) l.to = index else if (l.to > index and l.to <= last) l.to -= 1;
        }
    }
    count -= 1;
    removed_total +|= 1;
    // Drop links whose junction no longer exists.
    var kept: usize = 0;
    for (links[0..link_count]) |l| {
        if (l.from >= count or l.to >= count) continue;
        links[kept] = l;
        kept += 1;
    }
    link_count = kept;
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
// While the junction flashes amber every approach may go, slowly and yielding.
pub fn green(node: usize, road: usize, elapsed: f64) bool {
    const index = find(node) orelse return true; // Unsignalised junctions stay uncontrolled.
    const j = &junctions[index];
    if (j.preempt == .closed) return false; // Emergency hold: cross traffic stops.
    if (flashing(j, elapsed)) return true;
    const arm = armIndex(node, road) orelse return true;
    return armState(j, arm, elapsed) == .green;
}

// The lamp that governs a driver is the one over the arm the driver is standing
// on, exactly like a real head. `approach` is the road the vehicle is arriving
// along; pass -1 when it is already inside the junction and has no approach, in
// which case the outgoing arm is used.
pub fn greenForApproach(node: usize, approach: i32, exit: usize, elapsed: f64) bool {
    const index = find(node) orelse return true; // Unsignalised junctions stay uncontrolled.
    const j = &junctions[index];
    if (j.preempt == .closed) return false;
    if (flashing(j, elapsed)) return true;
    const road: usize = if (approach >= 0) @intCast(approach) else exit;
    const arm = armIndex(node, road) orelse return true;
    return armState(j, arm, elapsed) == .green;
}

// True when this junction is on flashing amber, so drivers proceed with care.
pub fn flashingAt(node: usize, elapsed: f64) bool {
    const index = find(node) orelse return false;
    return flashing(&junctions[index], elapsed);
}

// True while an emergency hold keeps this junction's cross traffic stopped.
pub fn heldForEmergency(node: usize) bool {
    const index = find(node) orelse return false;
    return junctions[index].preempt == .closed;
}

// Pedestrians and cyclists cross an arm while it is stopped for traffic, which
// is when the movement parallel to them holds green. Item 14 adds the
// pedestrian-only walk stage, when every vehicle arm is red and every crossing
// is open; the clearance that follows admits nobody, so people who started
// walking have a bounded interval to finish before the vehicles move again.
// Flashing amber is a yielding junction, so people on foot keep priority.
pub fn crossingAllowed(node: usize, movement: city.Vec, elapsed: f64) bool {
    const index = find(node) orelse return true;
    const j = &junctions[index];
    if (j.preempt == .closed) return false;
    if (flashing(j, elapsed)) return true;
    const info = stageAt(j, elapsed);
    if (info.stage == .pedestrian) return true;
    if (info.stage == .clearance) return false;
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

// Item 14: the crossing painted on one arm of a junction. A walker using it
// travels across that road, which is perpendicular to the arm's own direction,
// so the movement vector is the arm direction rotated onto the driver's right.
pub fn crossingAcrossArm(node: usize, arm_road: usize, elapsed: f64) bool {
    const dir = armDirection(node, arm_road) orelse return true;
    const movement = city.Vec{ .x = -dir.z, .z = dir.x };
    return crossingAllowed(node, movement, elapsed);
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

// The all-red clearance after each branch, the "off" time in the inspector.
pub fn setRed(node: usize, seconds: f32) bool {
    const index = find(node) orelse return false;
    junctions[index].red = std.math.clamp(seconds, min_red, max_red);
    return true;
}

// Item 14: the pedestrian walk time. Zero disables the stage without touching
// the vehicle timings.
pub fn setPedWalk(node: usize, seconds: f32) bool {
    const index = find(node) orelse return false;
    junctions[index].ped_walk = std.math.clamp(seconds, min_ped_walk, max_ped_walk);
    return true;
}

// The all-red clearance between the pedestrian walk and the next vehicle arm.
pub fn setPedClear(node: usize, seconds: f32) bool {
    const index = find(node) orelse return false;
    junctions[index].ped_clear = std.math.clamp(seconds, min_ped_clear, max_ped_clear);
    return true;
}

pub fn setPedEnabled(node: usize, enabled: bool) bool {
    const index = find(node) orelse return false;
    junctions[index].ped_enabled = enabled;
    return true;
}

fn clampHour(value: f32) f32 {
    return std.math.clamp(value, 0, 24);
}

fn modeFromNumber(value: f32) FlashMode {
    if (value > 0.5) return .on;
    if (value < -0.5) return .off;
    return .auto;
}

// The daily flashing window, in hours of the simulation day.
pub fn setFlashSchedule(node: usize, start_hour: f32, end_hour: f32) bool {
    const index = find(node) orelse return false;
    junctions[index].flash_start = clampHour(start_hour);
    junctions[index].flash_end = clampHour(end_hour);
    junctions[index].flash_enabled = true;
    return true;
}

pub fn setFlashEnabled(node: usize, enabled: bool) bool {
    const index = find(node) orelse return false;
    junctions[index].flash_enabled = enabled;
    return true;
}

// The manual switch: .on forces flashing now, .off forces normal cycling, and
// .auto hands control back to the schedule.
pub fn setFlashMode(node: usize, mode: FlashMode) bool {
    const index = find(node) orelse return false;
    junctions[index].flash = mode;
    return true;
}

pub fn setFlashHours(node: usize, start_hour: f32, end_hour: f32, enabled: bool) bool {
    const index = find(node) orelse return false;
    junctions[index].flash_start = clampHour(start_hour);
    junctions[index].flash_end = clampHour(end_hour);
    junctions[index].flash_enabled = enabled;
    return true;
}

// Preemption: hold cross traffic for an emergency vehicle, open the junction to
// flashing amber, or hand it back to its normal cycle. `until` is an absolute
// simulation time; pass zero for no automatic expiry.
pub fn setPreempt(node: usize, mode: Preempt, until: f64) bool {
    const index = find(node) orelse return false;
    junctions[index].preempt = mode;
    junctions[index].preempt_until = if (mode == .none) 0 else until;
    return true;
}

// The hook a police or firefighter dispatcher will use. Alerts are queued and
// applied at the next update, so a caller can raise one from anywhere.
pub fn pushAlert(node: usize, kind: AlertKind, until: f64) bool {
    if (node >= city.node_count) return false;
    if (alert_count >= max_alerts) {
        alerts_dropped +|= 1;
        return false;
    }
    alerts[alert_count] = .{ .node = node, .kind = kind, .until = until };
    alert_count += 1;
    alerts_pushed +|= 1;
    return true;
}

fn applyAlert(alert: Alert) bool {
    const index = find(alert.node) orelse return false;
    switch (alert.kind) {
        .hold => junctions[index].preempt = .closed,
        .open => junctions[index].preempt = .open,
        .release => junctions[index].preempt = .none,
    }
    junctions[index].preempt_until = if (alert.kind == .release) 0 else alert.until;
    return true;
}

// Called once per simulation step: drains queued alerts and lets timed
// preemptions expire back to the normal cycle.
pub fn update(elapsed: f64) void {
    if (alert_count > 0) {
        for (alerts[0..alert_count]) |alert| {
            if (applyAlert(alert)) alerts_handled +|= 1 else alerts_dropped +|= 1;
        }
        alert_count = 0;
    }
    for (junctions[0..count]) |*j| {
        if (j.preempt != .none and j.preempt_until > 0 and elapsed >= j.preempt_until) {
            j.preempt = .none;
            j.preempt_until = 0;
        }
    }
}

// Coordination: the follower runs the leader's cycle, delayed by `delay`
// simulation seconds. Followers join the leader's group so the map can draw
// which lights act together.
fn groupOf(index: usize) i8 {
    if (junctions[index].group >= 0) return junctions[index].group;
    var candidate: i8 = 0;
    while (candidate < max_groups) : (candidate += 1) {
        var used = false;
        for (junctions[0..count]) |j| {
            if (j.group == candidate) {
                used = true;
                break;
            }
        }
        if (!used) break;
    }
    junctions[index].group = candidate;
    return candidate;
}

pub fn link(from_node: usize, to_node: usize, delay: f32) bool {
    const from = find(from_node) orelse return false;
    const to = find(to_node) orelse return false;
    if (from == to) return false;
    const held = std.math.clamp(delay, min_delay, max_delay);
    for (links[0..link_count]) |*l| {
        if (l.from == from and l.to == to) {
            l.delay = held;
            junctions[to].delay = held;
            junctions[to].group = groupOf(from);
            link_total +|= 1;
            return true;
        }
    }
    if (link_count >= max_links) return false;
    links[link_count] = .{ .from = from, .to = to, .delay = held, .active = true };
    link_count += 1;
    junctions[to].delay = held;
    junctions[to].group = groupOf(from);
    link_total +|= 1;
    return true;
}

pub fn unlink(from_node: usize, to_node: usize) bool {
    const from = find(from_node) orelse return false;
    const to = find(to_node) orelse return false;
    var found = false;
    var kept: usize = 0;
    for (links[0..link_count]) |l| {
        if (l.from == from and l.to == to) {
            found = true;
            continue;
        }
        links[kept] = l;
        kept += 1;
    }
    if (!found) return false;
    link_count = kept;
    junctions[to].delay = default_delay;
    junctions[to].group = -1;
    return true;
}

pub fn linkDelay(from_node: usize, to_node: usize) f32 {
    const from = find(from_node) orelse return -1;
    const to = find(to_node) orelse return -1;
    for (links[0..link_count]) |l| {
        if (l.from == from and l.to == to) return l.delay;
    }
    return -1;
}

// Set the coordination delay of an existing link without recreating it.
pub fn setDelay(target: usize, seconds: f32) bool {
    if (target >= count) return false;
    const held = std.math.clamp(seconds, min_delay, max_delay);
    junctions[target].delay = held;
    for (links[0..link_count]) |*l| {
        if (l.to == target) l.delay = held;
    }
    return true;
}

fn junctionOnRoad(j: *const Junction, road: usize) bool {
    if (road >= city.roads.len) return false;
    for (j.arms[0..j.arm_count]) |arm| {
        if (arm >= 0 and @as(usize, @intCast(arm)) == road) return true;
    }
    return false;
}

// Bulk editing: apply one property to every light, to every light on a street,
// or to one junction's lights. Returns how many junctions changed.
pub fn bulkApply(scope: u8, key: usize, field: u8, value: f32) u32 {
    var changed: u32 = 0;
    for (junctions[0..count]) |*j| {
        const applies = switch (scope) {
            0 => true,
            1 => junctionOnRoad(j, key),
            2 => j.node == key,
            else => false,
        };
        if (!applies) continue;
        switch (field) {
            0 => j.green = std.math.clamp(value, min_green, max_green),
            1 => j.yellow = std.math.clamp(value, min_yellow, max_yellow),
            2 => j.red = std.math.clamp(value, min_red, max_red),
            3 => j.flash_start = clampHour(value),
            4 => j.flash_end = clampHour(value),
            5 => j.flash_enabled = value != 0,
            6 => j.flash = modeFromNumber(value),
            7 => j.ped_walk = std.math.clamp(value, min_ped_walk, max_ped_walk),
            8 => j.ped_clear = std.math.clamp(value, min_ped_clear, max_ped_clear),
            9 => j.ped_enabled = value != 0,
            else => continue,
        }
        changed +|= 1;
    }
    return changed;
}

// The same bulk edit for the manual flash switch, which takes a FlashMode.
pub fn bulkFlash(scope: u8, key: usize, mode: FlashMode) u32 {
    var changed: u32 = 0;
    for (junctions[0..count]) |*j| {
        const applies = switch (scope) {
            0 => true,
            1 => junctionOnRoad(j, key),
            2 => j.node == key,
            else => false,
        };
        if (!applies) continue;
        j.flash = mode;
        changed +|= 1;
    }
    return changed;
}

pub fn signalisedCount() usize {
    return count;
}

pub fn armStateAt(node: usize, road: usize, elapsed: f64) State {
    const index = find(node) orelse return .green;
    const arm = armIndex(node, road) orelse return .green;
    return armState(&junctions[index], arm, elapsed);
}

// One arm's lamp by flat slot, for the traffic-lights list.
pub fn slotState(junction_index: usize, slot: usize, elapsed: f64) State {
    if (junction_index >= count) return .red;
    const j = &junctions[junction_index];
    if (slot >= j.arm_count) return .red;
    if (j.preempt == .closed) return .red;
    return armState(j, slot, elapsed);
}

pub fn junctionNode(junction_index: usize) usize {
    if (junction_index >= count) return 0;
    return junctions[junction_index].node;
}

pub fn junctionRoad(junction_index: usize, slot: usize) i32 {
    if (junction_index >= count) return -1;
    if (slot >= junctions[junction_index].arm_count) return -1;
    return junctions[junction_index].arms[slot];
}

// Item 14 ABI: the movement from one arm slot of a junction to another. These
// index the junction's own arm slots, so a caller reads the road ids first and
// then asks this group about any pair of them. A junction with no signal has no
// movements to report.
pub fn movementApproach(junction_index: usize, movement: usize) i32 {
    if (junction_index >= count) return -1;
    const j = &junctions[junction_index];
    const approach = movement / max_arms;
    if (approach >= j.arm_count) return -1;
    return j.arms[approach];
}

pub fn movementExit(junction_index: usize, movement: usize) i32 {
    if (junction_index >= count) return -1;
    const j = &junctions[junction_index];
    const exit = movement % max_arms;
    if (exit >= j.arm_count) return -1;
    return j.arms[exit];
}

pub fn movementTurn(junction_index: usize, movement: usize) Turn {
    if (junction_index >= count) return .straight;
    const j = &junctions[junction_index];
    const approach = movement / max_arms;
    const exit = movement % max_arms;
    if (approach >= j.arm_count or exit >= j.arm_count) return .straight;
    const a = j.arms[approach];
    const b = j.arms[exit];
    if (a < 0 or b < 0) return .straight;
    return turnKind(j.node, @intCast(a), @intCast(b));
}

pub fn movementRadius(junction_index: usize, movement: usize) f32 {
    if (junction_index >= count) return 0;
    const j = &junctions[junction_index];
    const approach = movement / max_arms;
    const exit = movement % max_arms;
    if (approach >= j.arm_count or exit >= j.arm_count) return 0;
    const a = j.arms[approach];
    const b = j.arms[exit];
    if (a < 0 or b < 0) return 0;
    return turnRadius(j.node, @intCast(a), @intCast(b));
}

// Is a driver turning into this exit arm held because somebody is on that
// crosswalk, or because a left turn must wait for the box to clear? Both are
// the yielding half of item 14 and both are reported so the panel can show why
// a movement is refused.
pub fn movementBlocked(junction_index: usize, movement: usize, elapsed: f64) bool {
    if (junction_index >= count) return false;
    const j = &junctions[junction_index];
    const approach = movement / max_arms;
    const exit = movement % max_arms;
    if (approach >= j.arm_count or exit >= j.arm_count) return false;
    if (approach == exit) return false;
    const kind = movementTurn(junction_index, movement);
    const exit_road = movementExit(junction_index, movement);
    if (exit_road >= 0 and kind != .straight and crossingAcrossArmBlocked(junction_index, @intCast(exit_road), elapsed)) return true;
    if (kind == .left and boxOccupied(j.node)) return true;
    return false;
}

// Small indirections so signals.zig does not need to import transport.zig (the
// dependency runs the other way). transport fills these each step.
pub var crossing_blocked_road: [city.max_roads]bool = @splat(false);
pub var box_busy: [city.max_nodes]bool = @splat(false);

fn crossingAcrossArmBlocked(junction_index: usize, road: usize, elapsed: f64) bool {
    _ = junction_index;
    _ = elapsed;
    if (road >= city.max_roads) return false;
    return crossing_blocked_road[road];
}

fn boxOccupied(node: usize) bool {
    if (node >= city.max_nodes) return false;
    return box_busy[node];
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
