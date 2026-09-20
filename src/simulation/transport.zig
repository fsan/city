const std = @import("std");
const city = @import("../scene/city.zig");
pub const operators = @import("operators.zig");
pub var clock: f64 = 160;
pub const max_lines = 8;
pub const max_stops = 16;
pub const buses_per_line = 3;
pub const car_count = city.population;
pub const Vehicle = struct {
    company: usize = 0,
    active: bool = false,
    retiring: bool = false,
    shift_day: bool = true,
    lane: u8 = 0,
    node: usize = 0,
    next: usize = 0,
    target: usize = 0,
    progress: f32 = 0,
    speed: f32 = 0,
    x: f32 = 0,
    z: f32 = 0,
    arrived: bool = false,
    line: i32 = -1,
    stop: usize = 0,
    dwell: f32 = 0,
    passengers: usize = 0,
    version: u32 = 0,
};
pub const Line = struct {
    active: bool = false,
    stops: [max_stops]usize = @splat(0),
    count: usize = 0,
    version: u32 = 0,
    boardings: usize = 0,
    revenue: f64 = 0,
    costs: f64 = 0,
    company: usize = 2,
    window: u32 = 1,
    fleet: usize = 2,
    delivered: f64 = 0,
};
pub var vehicles: [car_count + max_lines * buses_per_line]Vehicle = @splat(.{});
pub var lines: [max_lines]Line = @splat(.{});
// 0 mixed traffic, 1 dedicated bus lane, 2 protected cycle lane (both directions).
pub var lanes: [city.max_roads]u8 = @splat(0);
pub var occupancy: [city.max_roads]usize = @splat(0);
pub var queues: [city.max_roads]usize = @splat(0);
pub var congestion: [city.max_roads]f32 = @splat(0);
var heads: [city.max_roads * 4]i32 = @splat(-1);
var entries: [city.max_roads * 4]bool = @splat(false);
var links: [vehicles.len]i32 = @splat(-1);
pub var fare_cap: f64 = 2;
pub var subsidy: f64 = 1;
pub var subsidy_available: f64 = 0;
pub var subsidy_due: f64 = 0;
pub var subsidy_total: f64 = 0;
pub var selected: i32 = -1;
pub var draft: [max_stops]usize = @splat(0);
pub var draft_count: usize = 0;
pub var editing: bool = false;
pub fn green(node: usize, horizontal: bool, elapsed: f64) bool {
    const phase = @mod(elapsed + @as(f64, @floatFromInt(node % 3)), 12);
    return if (horizontal) phase < 5 else phase >= 6 and phase < 11;
}
pub fn init() void {
    operators.init();
    clock = 160;
    vehicles = @splat(.{});
    lines = @splat(.{});
    lanes = @splat(0);
    occupancy = @splat(0);
    queues = @splat(0);
    congestion = @splat(0);
    fare_cap = 2;
    subsidy = 1;
    subsidy_due = 0;
    subsidy_total = 0;
    selected = -1;
    editing = false;
    draft_count = 0;
    const first = [_]usize{ 8, 10, 12, 26, 40, 38, 36, 22 };
    const second = [_]usize{ 0, 3, 6, 27, 48, 45, 42, 21 };
    draft_count = first.len;
    @memcpy(draft[0..first.len], &first);
    _ = apply(0);
    draft_count = second.len;
    @memcpy(draft[0..second.len], &second);
    _ = apply(1);
    lines[0].company = 0;
    lines[1].company = 1;
    draft_count = 0;
}
pub fn fare() f64 {
    return @min(fare_cap, 3);
}
pub fn apply(id: usize) bool {
    if (id >= max_lines or draft_count < 2 or draft_count > max_stops) return false;
    for (draft[0..draft_count], 0..) |n, i| {
        if (n >= city.node_count) return false;
        for (draft[0..i]) |old| if (old == n) return false;
    }
    const line = &lines[id];
    line.active = true;
    line.version += 1;
    line.count = draft_count;
    @memcpy(line.stops[0..draft_count], draft[0..draft_count]);
    // Existing buses finish their segment and unload before joining the new service.
    return true;
}
pub fn remove(id: usize) void {
    if (id >= max_lines) return;
    lines[id].active = false;
    lines[id].version += 1;
}
fn laneKey(v: Vehicle, road: usize) usize {
    return road * 4 + (if (v.node == city.roads[road].a) @as(usize, 0) else 2) + @as(usize, v.lane);
}
fn room(v: Vehicle, next: usize) bool {
    const road: usize = @intCast(city.road_between[v.node][next]);
    var candidate = v;
    candidate.next = next;
    candidate.lane = if (v.line >= 0 and lanes[road] == 1) 1 else 0;
    const key = laneKey(candidate, road);
    if (entries[key]) return false;
    var link = heads[key];
    while (link >= 0) {
        const other = vehicles[@intCast(link)];
        if (other.active and other.node == candidate.node and other.next == candidate.next and other.progress < spacing(v, other)) return false;
        link = links[@intCast(link)];
    }
    return true;
}
pub fn startCar(id: usize, node: usize, target: usize) void {
    const n = city.nodes[node];
    vehicles[id] = .{ .active = true, .node = node, .next = node, .target = target, .x = n.x, .z = n.z };
}
pub fn board(bus: usize) bool {
    const v = &vehicles[bus];
    const l = &lines[@intCast(v.line)];
    if (v.retiring or !l.active or v.company != l.company or v.version != l.version or v.passengers >= 24 or v.dwell <= 0) return false;
    v.passengers += 1;
    l.boardings += 1;
    l.revenue += fare();
    operators.accounts[v.company].cash += fare();
    operators.accounts[v.company].fares += fare();
    const paid = @min(subsidy, @max(0, subsidy_available - subsidy_due));
    subsidy_due += paid;
    subsidy_total += paid;
    operators.accounts[v.company].cash += paid;
    operators.accounts[v.company].subsidies += paid;
    l.revenue += paid;
    return true;
}
pub fn update(dt: f32, elapsed: f64) void {
    clock = elapsed;
    entries = @splat(false);
    heads = @splat(-1);
    occupancy = @splat(0);
    queues = @splat(0);
    for (&vehicles, 0..) |*v, i| {
        if (!v.active or v.node == v.next) continue;
        const r: usize = @intCast(city.road_between[v.node][v.next]);
        const key = laneKey(v.*, r);
        links[i] = heads[key];
        heads[key] = @intCast(i);
        occupancy[r] += 1;
        if (v.speed < 0.6) queues[r] += 1;
    }
    for (&congestion, 0..) |*c, i| c.* += (@min(1, @as(f32, @floatFromInt(queues[i])) / 5) - c.*) * @min(1, dt / 3);
    for (&lines, 0..) |*l, id| {
        for (0..buses_per_line) |slot| {
            const v = &vehicles[car_count + id * buses_per_line + slot];
            if (!v.active and l.active and slot < l.fleet and blocker(id) == 0) {
                if (operators.expense(l.company, 2, 0)) {
                    l.costs += 2;
                    const stop = slot * l.count / l.fleet;
                    const n = l.stops[stop];
                    v.* = .{ .active = true, .shift_day = operators.daytime(elapsed), .company = l.company, .line = @intCast(id), .node = n, .next = n, .target = n, .stop = stop, .dwell = 5, .version = l.version, .x = city.nodes[n].x, .z = city.nodes[n].z };
                }
            }
            if (v.active and !v.retiring) {
                v.retiring = slot >= l.fleet or !l.active or v.version != l.version or v.company != l.company or !operators.scheduled(l.window, elapsed);
                if (!v.retiring) {
                    if (operators.expense(v.company, @as(f64, dt) * 0.06, @as(f64, dt) * 0.12)) {
                        l.costs += @as(f64, dt) * 0.18;
                    } else v.retiring = true;
                }
            }
        }
    }
    for (&vehicles, 0..) |*v, i| {
        if (!v.active or v.arrived) continue;
        if (v.node == v.next) {
            if (v.line >= 0) {
                const l = &lines[@intCast(v.line)];
                if (v.retiring or !l.active or v.version != l.version) {
                    // Residents leave a withdrawn/changed bus at this junction, never teleport.
                    v.dwell = 5;
                    if (v.passengers == 0) v.active = false;
                    continue;
                }
                // Relief happens at a junction. Aggregate labour is charged once;
                // the dispatch clearance fee covers outgoing cohort overtime.
                v.shift_day = operators.daytime(elapsed);
                if (v.dwell > 0) {
                    l.delivered += @min(v.dwell, dt);
                    v.dwell = @max(0, v.dwell - dt);
                    continue;
                }
                if (v.node == v.target) {
                    v.stop = (v.stop + 1) % l.count;
                    v.target = l.stops[v.stop];
                }
            } else if (v.node == v.target) {
                v.arrived = true;
                continue;
            }
            const next = city.next_node[v.node][v.target];
            if (next == v.node or city.road_between[v.node][next] < 0) continue;
            if (!enter(v.*, next, elapsed)) continue;
            v.next = next;
            v.lane = if (v.line >= 0 and lanes[@intCast(city.road_between[v.node][next])] == 1) 1 else 0;
            v.progress = 0;
        }
        const r: usize = @intCast(city.road_between[v.node][v.next]);
        const road = city.roads[r];
        const stop = @max(road.length * 0.6, road.length - (if (v.line >= 0) @as(f32, 1.6) else 1.0));
        var free = @max(0, stop - v.progress);
        var link = heads[laneKey(v.*, r)];
        while (link >= 0) {
            const other = vehicles[@intCast(link)];
            if (@as(usize, @intCast(link)) != i and other.active and other.node == v.node and other.next == v.next and other.progress >= v.progress)
                free = @min(free, @max(0, other.progress - v.progress - spacing(v.*, other)));
            link = links[@intCast(link)];
        }
        const limit: f32 = (if (v.line >= 0) @as(f32, 5.5) else 7) * (0.5 + road.condition / 200) / (1 + road.slope * 2) * (if (road.works) @as(f32, 0.45) else 1) * (if (lanes[r] != 0 and v.line < 0) @as(f32, 0.8) else 1);
        v.speed = @min(limit, @min(v.speed + dt * 2, @sqrt(6 * free)));
        const step = @min(free, v.speed * dt);
        v.progress += step;
        if (v.line >= 0 and !v.retiring and step > 0 and v.version == lines[@intCast(v.line)].version) lines[@intCast(v.line)].delivered += dt;
        const a = city.nodes[v.node];
        const b = city.nodes[v.next];
        const fraction = @min(1, v.progress / road.length);
        const lane: f32 = if (v.lane == 1) 1.25 else 0.55;
        v.x = a.x + (b.x - a.x) * fraction - (b.z - a.z) / road.length * lane;
        v.z = a.z + (b.z - a.z) * fraction + (b.x - a.x) / road.length * lane;
        if (v.progress >= stop - 0.01) {
            v.speed = 0;
            if (v.next == v.target or (v.line >= 0 and (!lines[@intCast(v.line)].active or v.version != lines[@intCast(v.line)].version or v.retiring or v.shift_day != operators.daytime(elapsed)))) {
                v.node = v.next;
                if (v.line >= 0) v.dwell = if (v.node == v.target or v.retiring) 5 else 0;
            } else {
                // Keep the vehicle's footprint on the approach until its exit has room.
                var candidate = v.*;
                candidate.node = v.next;
                const next = city.next_node[candidate.node][v.target];
                if (next != candidate.node and enter(candidate, next, elapsed)) {
                    v.node = candidate.node;
                    v.next = next;
                    v.lane = if (v.line >= 0 and lanes[@intCast(city.road_between[v.node][next])] == 1) 1 else 0;
                    v.progress = 0;
                }
            }
        }
    }
}
// Private services also reserve their nominal requirements; selected line is replaced by a quote.
pub fn committed(company: usize, night: bool, exclude: usize) usize {
    var n: usize = 0;
    for (&lines, 0..) |l, id| {
        if (id != exclude and l.active and l.company == company and (!night or l.window == 0)) n += l.fleet;
    }
    return n;
}
pub fn occupied(company: usize) usize {
    var n: usize = 0;
    for (vehicles[car_count..]) |v| {
        if (v.active and v.company == company) n += 1;
    }
    return n;
}
// 0 ready, 1 off hours, 2 no cash, 3 no vehicle, 4 no on-duty driver.
pub fn blocker(line: usize) u32 {
    const l = &lines[line];
    if (!operators.scheduled(l.window, clock)) return 1;
    if (operators.accounts[l.company].cash < 2.18) return 2;
    const used = occupied(l.company);
    if (used >= operators.accounts[l.company].capacity) return 3;
    if (used >= operators.drivers(l.company, clock)) return 4;
    return 0;
}
// Mutually exclusive live states for each requested fleet slot. Signals and
// downstream queues both count as held; this is not timetable compliance.
pub fn serviceCount(line: usize, state: u32) usize {
    const l = &lines[line];
    var count: usize = 0;
    for (vehicles[car_count + line * buses_per_line ..][0..l.fleet]) |v| {
        const current: u32 = if (!v.active or !l.active) 0 else if (v.retiring or v.version != l.version) 4 else if (v.node == v.next and v.dwell > 0) 2 else if (v.speed > 0 and v.node != v.next) 1 else 3;
        if (current == state) count += 1;
    }
    return count;
}
pub const Journey = struct { line: i32 = -1, board_node: usize = 0, exit_node: usize = 0, time: f32 = 1e9 };
pub fn journey(from: usize, to: usize) Journey {
    var best: Journey = .{};
    for (&lines, 0..) |l, id| {
        if (!l.active) continue;
        var loop: f32 = 0;
        for (l.stops[0..l.count], 0..) |n, s| loop += city.distance[n][l.stops[(s + 1) % l.count]] / 3 + 5;
        for (l.stops[0..l.count], 0..) |board_node, s| {
            const access = city.distance[from][board_node];
            if (access > 45) continue;
            var ride: f32 = 0;
            var prev = board_node;
            for (1..l.count) |offset| {
                const exit_node = l.stops[(s + offset) % l.count];
                ride += city.distance[prev][exit_node] / 3 + 5;
                prev = exit_node;
                const egress = city.distance[exit_node][to];
                if (egress > 45) continue;
                const estimate = access + egress + ride + loop / @as(f32, @floatFromInt(l.fleet)) / 2;
                if (estimate < best.time) best = .{ .line = @intCast(id), .board_node = board_node, .exit_node = exit_node, .time = estimate };
            }
        }
    }
    return best;
}

fn enter(v: Vehicle, next: usize, elapsed: f64) bool {
    const road_id = city.road_between[v.node][next];
    if (road_id < 0 or !city.roads[@intCast(road_id)].vehicles) return false;
    const horizontal = city.horizontal(v.node, next);
    if (city.degree(v.node) >= 3 and !green(v.node, horizontal, elapsed)) return false;
    if (!room(v, next)) return false;
    var candidate = v;
    candidate.lane = if (v.line >= 0 and lanes[@intCast(road_id)] == 1) 1 else 0;
    entries[laneKey(candidate, @intCast(road_id))] = true;
    return true;
}

fn spacing(a: Vehicle, b: Vehicle) f32 {
    const first: f32 = if (a.line >= 0) 2.7 else 1.5;
    const second: f32 = if (b.line >= 0) 2.7 else 1.5;
    return (first + second) / 2 + 0.5;
}
