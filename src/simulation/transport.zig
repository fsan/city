const std = @import("std");
const city = @import("../scene/city.zig");
const travel = @import("travel.zig");
pub const operators = @import("operators.zig");
pub const signals = @import("signals.zig");
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
    // Owned fleet unit currently occupied by this bus; -1 for cars and idle slots.
    unit: i32 = -1,
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
// At most one approach completion per vehicle per fixed step.
pub const Arrival = struct { line: usize, node: usize, version: u32, company: usize, time: f64 };
pub var arrivals: [max_lines * buses_per_line]Arrival = undefined;
pub var arrival_count: usize = 0;
pub const StopObservation = struct {
    visits: u32 = 0,
    latest: f64 = -1,
    intervals: u32 = 0,
    last_interval: f64 = -1,
    total: f64 = 0,
    minimum: f64 = -1,
    maximum: f64 = -1,
    // Passenger outcomes are tied to this route version and stop index.
    wait_starts: u32 = 0,
    completed: u32 = 0,
    wait_total: f64 = 0,
    wait_min: f64 = -1,
    wait_max: f64 = -1,
    capacity_denials: u32 = 0,
    abandoned_timeout: u32 = 0,
    abandoned_offhours: u32 = 0,
    abandoned_fare: u32 = 0,
    abandoned_service: u32 = 0,
    abandoned_after_capacity: u32 = 0,
};
pub const Observation = struct {
    version: u32 = 0,
    window: u32 = 1,
    count: usize = 0,
    nodes: [max_stops]usize = @splat(0),
    stops: [max_stops]StopObservation = @splat(.{}),
};
pub var observations: [max_lines]Observation = @splat(.{});
pub var previous_observations: [max_lines]Observation = @splat(.{});
pub fn syncObservation(id: usize) void {
    const l = &lines[id];
    const o = &observations[id];
    if (o.version == l.version and o.window == l.window) return;
    if (o.count > 0) previous_observations[id] = o.*;
    o.* = .{ .version = l.version, .window = l.window };
    if (l.active) {
        o.count = l.count;
        @memcpy(o.nodes[0..l.count], l.stops[0..l.count]);
    }
}
fn recordArrival(v: *const Vehicle, elapsed: f64) void {
    const id: usize = @intCast(v.line);
    const l = &lines[id];
    if (v.retiring or !l.active or v.version != l.version or v.company != l.company or
        !operators.scheduled(l.window, elapsed) or v.node != l.stops[v.stop]) return;
    const o = &observations[id];
    const s = &o.stops[v.stop];
    // Omit any interval crossing a daytime closure, including whole skipped days.
    if (s.visits > 0 and (o.window == 0 or @floor((s.latest - 120) / 480) == @floor((elapsed - 120) / 480))) {
        const interval = elapsed - s.latest;
        s.intervals += 1;
        s.last_interval = interval;
        s.total += interval;
        s.minimum = if (s.minimum < 0) interval else @min(s.minimum, interval);
        s.maximum = @max(s.maximum, interval);
    }
    s.visits += 1;
    s.latest = elapsed;
    arrivals[arrival_count] = .{ .line = id, .node = v.node, .version = v.version, .company = v.company, .time = elapsed };
    arrival_count += 1;
}
pub var vehicles: [car_count + max_lines * buses_per_line]Vehicle = @splat(.{});
pub var lines: [max_lines]Line = @splat(.{});
// 0 mixed traffic, 1 dedicated bus lane, 2 protected cycle lane (both directions).
pub var lanes: [city.max_roads]u8 = @splat(0);
pub var occupancy: [city.max_roads]usize = @splat(0);
pub var queues: [city.max_roads]usize = @splat(0);
pub var congestion: [city.max_roads]f32 = @splat(0);
// Slice 10: smoothed traffic movement per segment drives kerbside parking
// prices; junction counts support gap acceptance and crosswalk yielding.
pub var movement: [city.max_roads]f32 = @splat(0);
var flow: [city.max_roads]f32 = @splat(0);
var baseline: [city.max_roads]f32 = @splat(0);
pub var junction_traffic: [city.max_nodes]u16 = @splat(0);
// Slice 12: vehicles whose *node* is the junction, which is to say the ones that
// have already committed and are on their way out of the box. Flashing amber
// admits a driver only when this is zero, so a queue on the approach can never
// block itself.
pub var junction_entered: [city.max_nodes]u16 = @splat(0);
pub var crossing_active: [city.max_nodes]u16 = @splat(0);
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
// Slice 11: cars obey the junction's own signal, which greens one branch at a
// time. An unsignalised junction stays uncontrolled.
pub fn green(node: usize, road: usize, elapsed: f64) bool {
    return signals.green(node, road, elapsed);
}
pub fn init() void {
    operators.init();
    clock = 160;
    arrival_count = 0;
    vehicles = @splat(.{});
    lines = @splat(.{});
    observations = @splat(.{});
    previous_observations = @splat(.{});
    lanes = @splat(0);
    occupancy = @splat(0);
    queues = @splat(0);
    congestion = @splat(0);
    junction_traffic = @splat(0);
    junction_entered = @splat(0);
    crossing_active = @splat(0);
    signals.seed();
    seedMovement();
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

// Background movement by class plus the measured flow on top. Rebuilt with the
// graph so a new street starts with its class baseline and then learns.
pub fn seedMovement() void {
    for (city.roads, 0..) |*r, i| {
        baseline[i] = switch (r.class) {
            2 => 2.2,
            1 => 0.8,
            else => 0.15,
        };
        flow[i] = 0;
        movement[i] = baseline[i];
    }
}

pub fn classOf(road: usize) u8 {
    return if (road < city.road_count) city.roads[road].class else 1;
}
pub fn apply(id: usize) bool {
    if (id >= max_lines or draft_count < 2 or draft_count > max_stops) return false;
    for (draft[0..draft_count], 0..) |n, i| {
        if (!city.validStop(n)) return false;
        for (draft[0..i]) |old| if (old == n) return false;
    }
    const line = &lines[id];
    line.active = true;
    line.version += 1;
    line.count = draft_count;
    @memcpy(line.stops[0..draft_count], draft[0..draft_count]);
    syncObservation(id);
    // Existing buses finish their segment and unload before joining the new service.
    return true;
}
pub fn remove(id: usize) void {
    if (id >= max_lines) return;
    lines[id].active = false;
    lines[id].version += 1;
    syncObservation(id);
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
    arrival_count = 0;
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
    // Junction pressure for pedestrian gap acceptance, and the measured movement
    // that bands kerbside parking prices.
    junction_traffic = @splat(0);
    junction_entered = @splat(0);
    for (vehicles[0..]) |v| {
        if (!v.active or v.node == v.next) continue;
        const a = city.nodes[v.node];
        const b = city.nodes[v.next];
        const da = (v.x - a.x) * (v.x - a.x) + (v.z - a.z) * (v.z - a.z);
        const db = (v.x - b.x) * (v.x - b.x) + (v.z - b.z) * (v.z - b.z);
        if (da < 196) {
            junction_traffic[v.node] +|= 1;
            junction_entered[v.node] +|= 1;
        }
        if (db < 196) junction_traffic[v.next] +|= 1;
    }
    for (0..city.road_count) |r| {
        flow[r] += (@as(f32, @floatFromInt(occupancy[r])) - flow[r]) * @min(1, dt / 45);
        movement[r] = baseline[r] + flow[r];
    }
    for (&lines, 0..) |*l, id| {
        syncObservation(id);
        for (0..buses_per_line) |slot| {
            const index = car_count + id * buses_per_line + slot;
            const v = &vehicles[index];
            if (!v.active and l.active and slot < l.fleet and blocker(id) == 0) {
                // A live commitment occupies a specific owned unit. Clearing
                // buses keep theirs until their passengers have left.
                const unit = operators.takeUnit(l.company, index);
                if (unit >= 0) {
                    if (operators.expense(l.company, 2, 0)) {
                        l.costs += 2;
                        const stop = slot * l.count / l.fleet;
                        const n = l.stops[stop];
                        v.* = .{ .active = true, .shift_day = operators.daytime(elapsed), .company = l.company, .line = @intCast(id), .node = n, .next = n, .target = n, .stop = stop, .dwell = 5, .version = l.version, .unit = unit, .x = city.nodes[n].x, .z = city.nodes[n].z };
                    } else operators.releaseUnit(l.company, unit);
                }
            }
            if (v.active and !v.retiring) {
                v.retiring = slot >= l.fleet or !l.active or v.version != l.version or v.company != l.company or !operators.scheduled(l.window, elapsed) or operators.unitUnavailable(v.company, v.unit);
                if (!v.retiring) {
                    if (operators.expense(v.company, @as(f64, dt) * 0.06, @as(f64, dt) * 0.12)) {
                        l.costs += @as(f64, dt) * 0.18;
                        operators.wear(v.company, index, @as(f64, dt) * operators.wear_rate);
                        if (operators.unitUnavailable(v.company, v.unit)) v.retiring = true;
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
                    if (v.passengers == 0) {
                        v.active = false;
                        operators.releaseUnit(v.company, v.unit);
                        v.unit = -1;
                    }
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
        const bus = v.line >= 0;
        const at_target = bus and v.next == v.target;
        const leaving = bus and (!lines[@intCast(v.line)].active or v.version != lines[@intCast(v.line)].version or v.retiring or v.shift_day != operators.daytime(elapsed));
        // Service and retirement stops reach the node itself so departure does
        // not jump from a pre-stop clearance point onto the next segment.
        // Cars yield at a crosswalk while somebody is actually crossing it.
        const cross_yield = !bus and !at_target and !leaving and crossing_active[@min(v.next, city.max_nodes - 1)] > 0;
        const stop_point = if (at_target or leaving) road.length else if (cross_yield) @max(road.length * 0.35, road.length - 2.6) else @max(road.length * 0.6, road.length - (if (bus) @as(f32, 1.6) else 1.0));
        const next_after = city.next_node[v.next][v.target];
        var lookahead = v.*;
        lookahead.node = v.next;
        lookahead.next = if (next_after == v.next) v.next else next_after;
        lookahead.lane = if (bus and next_after != v.next and lanes[@intCast(city.road_between[v.next][next_after])] == 1) 1 else 0;
        const blocked = next_after == v.next or !entryAllowed(lookahead, next_after, elapsed);
        // Only segment ends that actually stop the vehicle receive braking. Ordinary
        // short street segments keep their speed and hand momentum to the next one.
        const must_stop = v.retiring or leaving or at_target or cross_yield or (v.next != v.target and blocked);
        const stop_at = if (must_stop) stop_point else road.length;
        var free = @max(0, stop_at - v.progress);
        var following = false;
        var link = heads[laneKey(v.*, r)];
        while (link >= 0) {
            const other = vehicles[@intCast(link)];
            if (@as(usize, @intCast(link)) != i and other.active and other.node == v.node and other.next == v.next and other.progress >= v.progress) {
                const gap = @max(0, other.progress - v.progress - spacing(v.*, other));
                if (gap < free) {
                    free = gap;
                    following = true;
                }
            }
            link = links[@intCast(link)];
        }
        // Slice 12: a flashing-amber junction is a caution, not a green, so
        // approaching drivers slow to about half speed and yield.
        const caution: f32 = if (city.degree(v.next) >= 3 and signals.flashingAt(v.next, elapsed)) 0.5 else 1;
        const limit: f32 = (if (bus) travel.bus_limit else travel.classSpeed(road.class, road.condition, road.slope, road.works)) * (if (lanes[r] != 0 and !bus) @as(f32, 0.8) else 1) * caution;
        var target = limit;
        if (must_stop or following) target = @min(target, @sqrt(6 * free));
        if (v.speed < target) v.speed = @min(target, v.speed + dt * 2) else v.speed = @max(target, v.speed - dt * 3);
        const step = @min(free, v.speed * dt);
        v.progress += step;
        if (bus and !v.retiring and step > 0 and v.version == lines[@intCast(v.line)].version) lines[@intCast(v.line)].delivered += dt;
        const a = city.nodes[v.node];
        const b = city.nodes[v.next];
        const fraction = @min(1, v.progress / road.length);
        const lane: f32 = if (v.lane == 1) 1.25 else 0.55;
        v.x = a.x + (b.x - a.x) * fraction - (b.z - a.z) / road.length * lane;
        v.z = a.z + (b.z - a.z) * fraction + (b.x - a.x) / road.length * lane;
        if (v.progress >= stop_at - 0.01) {
            if (must_stop) v.speed = 0;
            if (v.next == v.target or leaving) {
                v.node = v.next;
                if (bus) {
                    v.dwell = if (v.node == v.target or v.retiring) 5 else 0;
                    if (v.node == v.target) recordArrival(v, elapsed);
                }
            } else {
                // Keep the vehicle's footprint on the approach until its exit has room.
                var candidate = v.*;
                candidate.node = v.next;
                const next = city.next_node[candidate.node][v.target];
                const carried = v.speed;
                if (next != candidate.node and enter(candidate, next, elapsed)) {
                    v.node = candidate.node;
                    v.next = next;
                    v.lane = if (bus and lanes[@intCast(city.road_between[v.node][next])] == 1) 1 else 0;
                    v.progress = 0;
                    v.speed = carried;
                } else v.speed = 0;
            }
        }
    }
}
// Ask a bus occupying an owned unit to retire safely at its next stop.
pub fn retire(bus: i32) void {
    if (bus < 0 or bus >= vehicles.len) return;
    const v = &vehicles[@intCast(bus)];
    if (v.active) v.retiring = true;
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
// 0 ready, 1 off hours, 2 no cash, 3 no free unit, 4 no on-duty driver,
// 5 depot capacity (never blocks dispatch directly), 6 all units in
// maintenance, 7 every serviceable unit is committed to a running/clearing bus.
pub fn blocker(line: usize) u32 {
    const l = &lines[line];
    if (!operators.scheduled(l.window, clock)) return 1;
    if (operators.accounts[l.company].cash < 2.18) return 2;
    if (operators.freeUnits(l.company) == 0) return if (operators.available(l.company) == 0) 6 else 7;
    if (occupied(l.company) >= operators.drivers(l.company, clock)) return 4;
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

fn entryAllowed(v: Vehicle, next: usize, elapsed: f64) bool {
    const road_id = city.road_between[v.node][next];
    if (road_id < 0 or !city.roads[@intCast(road_id)].vehicles) return false;
    if (city.degree(v.node) >= 3) {
        // Slice 12: an emergency hold stops cross traffic outright, and a
        // flashing-amber junction lets drivers cross slowly when it is safe, so
        // they only commit when nothing is already inside the junction box.
        if (signals.heldForEmergency(v.node)) return false;
        if (signals.flashingAt(v.node, elapsed)) {
            // Cross slowly, and only once the box is clear of whoever went in
            // ahead of this driver.
            if (junction_entered[v.node] > 0) return false;
        } else if (!green(v.node, @intCast(road_id), elapsed)) return false;
    }
    if (!room(v, next)) return false;
    var candidate = v;
    candidate.lane = if (v.line >= 0 and lanes[@intCast(road_id)] == 1) 1 else 0;
    return !entries[laneKey(candidate, @intCast(road_id))];
}

fn enter(v: Vehicle, next: usize, elapsed: f64) bool {
    if (!entryAllowed(v, next, elapsed)) return false;
    const road_id = city.road_between[v.node][next];
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
