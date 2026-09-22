const transport = @import("transport.zig");
const city = @import("../scene/city.zig");
const calendar = @import("calendar.zig");
const households = @import("households.zig");
pub const Person = struct { x: f32, z: f32, y: f32, phase: u8 = 0, mode: u8 = 0, wallet: f64 = 0, income: f64 = 0, owns_car: bool = false, owns_bike: bool = false, car_node: usize = 0, bike_node: usize = 0, scores: [4]f32 = @splat(-1), crew: bool = false, chosen: bool = false, bus_line: i32 = -1, bus: i32 = -1, boarding: usize = 0, exit_node: usize = 0, bus_version: u32 = 0, bus_wait: f32 = 0, bus_wait_start: f64 = -1, bus_full_mask: u8 = 0, bus_stage: u8 = 0, walk_side: f32 = 1, shift: u8 = 0, routine: u8 = 0, home: usize, current_building: usize = 0, destination_building: usize = 0, origin_building: usize = 0, employer: i32 = -1, origin: usize = 0, destination: usize, node: usize, next: usize, wait: f32, trips: u32 = 0, travel: f32 = 0, last_trip: f32 = 0, order: i32 = -1, arrived: bool = false };
pub const Company = struct { building: usize, employees: usize = 0, capacity: usize, cash: f64 = 45000, contractor: bool, crew: [4]usize = .{ 0, 0, 0, 0 }, crew_count: usize = 0, order: i32 = -1, margin: f64, labour: f64, costs: f64 = 0 };
pub const DistrictOutcome = struct {
    wait_starts: u32 = 0,
    completed: u32 = 0,
    wait_total: f64 = 0,
    capacity_denials: u32 = 0,
    abandoned: u32 = 0,
    abandoned_after_capacity: u32 = 0,
};
pub var people: [city.population]Person = undefined;
pub var companies: [city.buildings.len]Company = undefined;
pub var district_outcomes: [city.district_count]DistrictOutcome = @splat(.{});
pub var company_count: usize = 0;
pub var pedestrians: [city.max_roads]usize = @splat(0);
pub var walking: usize = 0;
pub var employed: usize = 0;
pub fn init() void {
    company_count = 0;
    employed = 0;
    walking = 0;
    district_outcomes = @splat(.{});
    var homes: [city.buildings.len * 6]usize = undefined;
    var home_count: usize = 0;
    for (&city.buildings, 0..) |*b, i| {
        if (b.kind == .home) {
            const weight: usize = @intFromFloat(@max(1, b.height - 2));
            for (0..@min(6, weight)) |_| {
                homes[home_count] = i;
                home_count += 1;
            }
        }
        if (b.capacity == 0) continue;
        b.employer = @intCast(company_count);
        companies[company_count] = .{ .building = i, .capacity = b.capacity, .contractor = b.kind == .depot, .margin = 1.15 + @as(f64, @floatFromInt(company_count % 3)) * 0.12, .labour = 14 + @as(f64, @floatFromInt(company_count % 3)) * 3 };
        company_count += 1;
    }
    // Fill actual employer capacities round-robin; remaining residents are jobseekers.
    for (&people, 0..) |*p, i| {
        const home = homes[i % home_count];
        var employer: i32 = -1;
        for (0..company_count) |offset| {
            const c = (i + offset) % company_count;
            if (companies[c].employees >= companies[c].capacity) continue;
            employer = @intCast(c);
            companies[c].employees += 1;
            employed += 1;
            if (companies[c].contractor and companies[c].crew_count < 4) {
                companies[c].crew[companies[c].crew_count] = i;
                companies[c].crew_count += 1;
            }
            break;
        }
        const node = city.buildings[home].node;
        const b = city.buildings[home];
        p.* = .{ .x = b.entry_x, .z = b.entry_z, .y = b.ground + 0.35, .wallet = @as(f64, @floatFromInt(100 + i % 9000)), .income = @as(f64, @floatFromInt(30 + i % 170)), .owns_bike = i % 3 != 0, .car_node = node, .bike_node = node, .shift = @intCast(@intFromEnum(calendar.shiftFor(i))), .routine = 0, .home = home, .current_building = home, .origin_building = home, .destination_building = if (employer >= 0) companies[@intCast(employer)].building else home, .origin = node, .employer = employer, .destination = if (employer >= 0) city.buildings[companies[@intCast(employer)].building].node else node, .node = node, .next = node, .wait = @as(f32, @floatFromInt(i % 100)) * 0.14 };
        considerCar(p);
        city.buildings[home].occupants += 1;
    }
    households.init();
    for (companies[0..company_count]) |c| {
        for (c.crew[0..c.crew_count]) |id| people[id].crew = true;
    }
}
pub fn send(id: usize, target: usize, order: i32) void {
    const p = &people[id];
    p.origin = p.node;
    p.origin_building = p.current_building;
    p.destination = target;
    p.order = order;
    p.arrived = false;
    p.wait = 0;
    p.mode = 0;
    p.chosen = true;
    if (p.phase == 2 or p.phase == 3) p.phase = 0;
    // Finish the current segment before taking the new route; never teleport a crew.
}
pub fn release(company: usize) void {
    const c = &companies[company];
    for (c.crew[0..c.crew_count]) |id| {
        send(id, city.buildings[c.building].node, -1);
        people[id].destination_building = c.building;
    }
    c.order = -1;
}

fn bump(counter: *u32) void {
    if (counter.* < 1_000_000_000) counter.* += 1;
}

fn outcomeStop(line: usize, version: u32, node: usize) ?*transport.StopObservation {
    if (line >= transport.max_lines) return null;
    const current = &transport.observations[line];
    if (current.version == version) {
        for (current.nodes[0..current.count], 0..) |candidate, i| if (candidate == node) return &current.stops[i];
    }
    const previous = &transport.previous_observations[line];
    if (previous.version == version) {
        for (previous.nodes[0..previous.count], 0..) |candidate, i| if (candidate == node) return &previous.stops[i];
    }
    return null;
}

fn outcomeDistrict(p: *const Person) *DistrictOutcome {
    const district = @min(city.buildings[p.home].district, city.district_count - 1);
    return &district_outcomes[district];
}

pub const AbandonCause = enum { timeout, offhours, fare, service };

pub fn beginWait(p: *Person, time: f64) void {
    p.bus_wait_start = time;
    p.bus_full_mask = 0;
    if (p.bus_line >= 0 and p.bus_line < transport.max_lines) {
        if (outcomeStop(@intCast(p.bus_line), p.bus_version, p.boarding)) |stop| bump(&stop.wait_starts);
    }
    bump(&outcomeDistrict(p).wait_starts);
}

pub fn completeWait(p: *Person, time: f64) void {
    if (p.bus_wait_start < 0) return;
    const duration = @max(0, time - p.bus_wait_start);
    if (p.bus_line >= 0 and p.bus_line < transport.max_lines) {
        if (outcomeStop(@intCast(p.bus_line), p.bus_version, p.boarding)) |stop| {
            bump(&stop.completed);
            stop.wait_total += duration;
            if (stop.completed == 1) {
                stop.wait_min = duration;
                stop.wait_max = duration;
            } else {
                stop.wait_min = @min(stop.wait_min, duration);
                stop.wait_max = @max(stop.wait_max, duration);
            }
        }
    }
    const district = outcomeDistrict(p);
    bump(&district.completed);
    district.wait_total += duration;
    p.bus_wait_start = -1;
    p.bus_full_mask = 0;
}

pub fn recordFullBuses(p: *Person, count: usize) void {
    if (count == 0) return;
    if (p.bus_line >= 0 and p.bus_line < transport.max_lines) {
        if (outcomeStop(@intCast(p.bus_line), p.bus_version, p.boarding)) |stop| {
            for (0..count) |_| bump(&stop.capacity_denials);
        }
    }
    const district = outcomeDistrict(p);
    for (0..count) |_| bump(&district.capacity_denials);
}

pub fn abandonWait(p: *Person, time: f64, cause: AbandonCause) void {
    _ = time;
    if (p.bus_wait_start < 0) return;
    const had_capacity = p.bus_full_mask != 0;
    if (p.bus_line >= 0 and p.bus_line < transport.max_lines) {
        if (outcomeStop(@intCast(p.bus_line), p.bus_version, p.boarding)) |stop| {
            switch (cause) {
                .timeout => bump(&stop.abandoned_timeout),
                .offhours => bump(&stop.abandoned_offhours),
                .fare => bump(&stop.abandoned_fare),
                .service => bump(&stop.abandoned_service),
            }
            if (had_capacity) bump(&stop.abandoned_after_capacity);
        }
    }
    const district = outcomeDistrict(p);
    bump(&district.abandoned);
    if (had_capacity) bump(&district.abandoned_after_capacity);
    p.bus_wait_start = -1;
    p.bus_full_mask = 0;
}

// Route edits/withdrawal invalidate waiting service immediately. Attribute the
// abandonment to the old observation record before transport archives it.
pub fn closeLineWaits(line: usize, time: f64) void {
    if (line >= transport.max_lines) return;
    for (&people) |*p| {
        if (p.bus_line != @as(i32, @intCast(line)) or p.mode != 3 or p.phase != 1 or p.bus >= 0) continue;
        abandonWait(p, time, .service);
        p.mode = 0;
        p.bus_stage = 2;
    }
}
fn moveTo(p: *Person, x: f32, y: f32, z: f32, speed: f32, dt: f32) bool {
    const dx = x - p.x;
    const dy = y - p.y;
    const dz = z - p.z;
    const distance = @sqrt(dx * dx + dy * dy + dz * dz);
    const step = speed * dt;
    p.travel += dt;
    if (p.mode == 0 or p.mode == 3) walking += 1;
    if (distance <= step) {
        p.x = x;
        p.y = y;
        p.z = z;
        return true;
    }
    p.x += dx / distance * step;
    p.y += dy / distance * step;
    p.z += dz / distance * step;
    return false;
}
// Slice 6: bounded routine destination from the shared civic calendar.
fn routineDestination(p: *const Person, index: usize, routine: calendar.Phase, time: f64) usize {
    const weekend = calendar.isWeekend(time);
    if (p.crew or p.order >= 0 or p.employer < 0) return p.home;
    const work = companies[@intCast(p.employer)].building;
    if (!weekend) {
        const shift: calendar.Shift = @enumFromInt(p.shift);
        if (calendar.onShift(shift, time)) return work;
        // A short errand window keeps weekday demand on the network outside work.
        if (routine == .evening and index % 7 == 0) return errandTarget(p);
        return p.home;
    }
    if ((routine == .morning or routine == .leisure) and index % 8 == 0) return errandTarget(p);
    return p.home;
}

fn errandTarget(p: *const Person) usize {
    const district = city.buildings[p.home].district;
    for (&city.buildings, 0..) |*b, i| {
        if (b.district != district or b.kind == .home or b.kind == .vacant) continue;
        if (b.kind == .park or b.kind == .hall or b.kind == .shop) return i;
    }
    return p.home;
}

pub fn update(dt: f32, elapsed: f64) void {
    walking = 0;
    for (&people, 0..) |*p, i| {
        if (p.arrived and p.order >= 0) continue;
        if (p.wait > 0) {
            p.wait -= dt;
            continue;
        }

        if (p.phase == 3) {
            const routine = calendar.phase(elapsed);
            p.routine = @intCast(@intFromEnum(routine));
            p.destination_building = routineDestination(p, i, routine, elapsed);
            p.destination = city.buildings[p.destination_building].node;
            if (p.destination == p.node and p.destination_building == p.current_building) {
                p.wait = 10;
                continue;
            }
            p.phase = 0;
            p.chosen = false;
        }
        if (!p.chosen) choose(p);
        if (p.phase == 1 and p.mode == 2) {
            const v = &transport.vehicles[i];
            if (!v.active) transport.startCar(i, p.node, p.destination);
            p.node = v.node;
            p.next = v.next;
            p.x = v.x;
            p.z = v.z;
            p.y = city.elevation(p.x, p.z) + 0.2;
            p.travel += dt;
            if (v.arrived) {
                p.node = v.node;
                p.next = v.node;
                p.car_node = v.node;
                v.active = false;
                p.phase = 2;
            }
            continue;
        }
        if (p.mode == 3 and p.phase == 1) {
            const line = &transport.lines[@intCast(p.bus_line)];
            if (p.bus >= 0) {
                const v = &transport.vehicles[@intCast(p.bus)];
                p.node = v.node;
                p.next = v.next;
                p.x = v.x;
                p.z = v.z;
                p.y = city.elevation(p.x, p.z) + 0.2;
                p.travel += dt;
                if (v.node == v.next and ((v.node == p.exit_node and v.dwell > 0) or v.retiring or !line.active or line.version != p.bus_version)) {
                    v.passengers -= 1;
                    p.node = v.node;
                    p.next = v.node;
                    p.bus = -1;
                    p.bus_stage = 2;
                }
                continue;
            }
            if (!line.active or line.version != p.bus_version) {
                abandonWait(p, elapsed, .service);
                p.mode = 0;
                p.bus_stage = 2;
            }
            if (p.bus_stage == 0 and p.node == p.boarding and p.node == p.next) {
                if (p.bus_wait_start < 0) beginWait(p, elapsed);
                p.bus_wait += dt;
                p.travel += dt;
                if (households.canAfford(p.home, transport.fare())) {
                    var mask: u8 = 0;
                    for (0..transport.buses_per_line) |slot| {
                        const bus = transport.car_count + @as(usize, @intCast(p.bus_line)) * transport.buses_per_line + slot;
                        const v = transport.vehicles[bus];
                        if (v.active and !v.retiring and v.line == p.bus_line and v.version == p.bus_version and v.company == line.company and v.node == p.node and v.node == v.next and v.dwell > 0 and v.passengers >= 24)
                            mask |= @as(u8, 1) << @intCast(slot);
                    }
                    const fresh = mask & ~p.bus_full_mask;
                    if (fresh != 0) recordFullBuses(p, @popCount(fresh));
                    p.bus_full_mask = mask;
                } else p.bus_full_mask = 0;
                var boarded = false;
                for (0..transport.buses_per_line) |slot| {
                    const bus = transport.car_count + @as(usize, @intCast(p.bus_line)) * transport.buses_per_line + slot;
                    const v = transport.vehicles[bus];
                    if (v.active and v.node == p.node and v.node == v.next and households.canAfford(p.home, transport.fare()) and transport.board(bus)) {
                        _ = households.spend(p.home, transport.fare());
                        p.bus = @intCast(bus);
                        p.bus_stage = 1;
                        boarded = true;
                        completeWait(p, elapsed);
                        break;
                    }
                }
                if (!boarded) {
                    if (!households.canAfford(p.home, transport.fare())) {
                        abandonWait(p, elapsed, .fare);
                        p.mode = 0;
                        p.bus_stage = 2;
                    } else if (p.bus_wait > 180) {
                        abandonWait(p, elapsed, if (transport.operators.scheduled(line.window, elapsed)) .timeout else .offhours);
                        p.mode = 0;
                        p.bus_stage = 2;
                    }
                }
                continue;
            }
        }
        if (p.phase == 0) {
            const node = city.frontage(city.buildings[p.current_building]);
            if (moveTo(p, node.x, city.elevation(node.x, node.z) + 0.25, node.z, 1.1, dt)) p.phase = 1;
            p.y = @max(city.elevation(p.x, p.z) + 0.25, p.y);
            continue;
        }
        if (p.phase == 2) {
            const b = city.buildings[p.destination_building];
            if (moveTo(p, b.entry_x, b.ground + 0.35, b.entry_z, 1.1, dt)) {
                if (p.mode == 1) p.bike_node = p.node;
                p.current_building = p.destination_building;
                p.phase = 3;
                p.wait = 18 + @as(f32, @floatFromInt(i % 50));
                p.last_trip = p.travel;
                p.travel = 0;
                p.trips += 1;
            }
            p.y = @max(city.elevation(p.x, p.z) + 0.25, p.y);
            continue;
        }
        const target_node = if (p.mode == 3 and p.bus_stage == 0) p.boarding else p.destination;
        if (p.node == p.next) {
            if (p.node == target_node) {
                if (p.order >= 0) {
                    p.arrived = true;
                    p.last_trip = p.travel;
                    p.travel = 0;
                    p.trips += 1;
                } else p.phase = 2;
                continue;
            }
            if (city.distance[p.node][target_node] >= 1e8) continue;
            p.next = if ((p.mode == 0 or p.mode == 3) and i % 5 != 0) city.walk_next[p.node][target_node] else city.next_node[p.node][target_node];
            const a = city.nodes[p.node];
            const b = city.nodes[p.next];
            const destination = city.buildings[p.destination_building];
            const side = (b.x - a.x) * (destination.entry_z - a.z) - (b.z - a.z) * (destination.entry_x - a.x);
            p.walk_side = if (i % 3 == 0) (if (i % 2 == 0) @as(f32, 1) else -1) else if (side >= 0) 1 else -1;
        }
        const road_id = city.road_between[p.node][p.next];
        if (road_id < 0) continue;
        const road = city.roads[@intCast(road_id)];
        const a = city.nodes[p.node];
        const b = city.nodes[p.next];
        const span = city.hypot(b.x - a.x, b.z - a.z);
        const target = city.Vec{ .x = b.x - (b.z - a.z) / span * 2.3 * p.walk_side, .z = b.z + (b.x - a.x) / span * 2.3 * p.walk_side };
        const speed = (if (p.mode == 1) (if (transport.lanes[@intCast(road_id)] == 2) @as(f32, 4.5) else 3.0) else @as(f32, 1)) * (0.7 + road.condition / 100) / (1 + road.slope * 3) * (if (road.works) @as(f32, 0.65) else 1);
        if (moveTo(p, target.x, city.elevation(target.x, target.z) + 0.15, target.z, speed, dt)) {
            p.node = p.next;
        }
        // Road surfaces follow authored terrain; do not interpolate through grade changes.
        p.y = city.elevation(p.x, p.z) + 0.15;
    }
    pedestrians = @splat(0);
    for (&people) |p| {
        if (p.phase == 3 or p.bus >= 0 or p.mode == 1 or (p.mode == 2 and p.phase == 1) or (p.wait > 0 and p.phase == 0)) continue;
        var road: i16 = if (p.node != p.next) city.road_between[p.node][p.next] else -1;
        if (road < 0) {
            for (city.roads, 0..) |r, id| {
                if (r.a == p.node or r.b == p.node) {
                    road = @intCast(id);
                    break;
                }
            }
        }
        if (road >= 0) pedestrians[@intCast(road)] += 1;
    }
}

// Travel estimate includes the unfinished segment or frontage connector.
pub fn remaining(id: usize) f32 {
    const p = &people[id];
    if (p.arrived or p.wait > 0 or p.phase == 3) return 0;
    if (p.mode == 2 or p.mode == 3) return -1; // Traffic and headways make a walking ETA misleading.
    var target = city.nodes[p.next];
    var speed: f32 = 1.1;
    var rest = city.distance[p.next][p.destination];
    if (p.phase == 2) {
        const b = city.buildings[p.destination_building];
        target = .{ .x = b.entry_x, .z = b.entry_z, .y = b.ground + 0.35 };
        rest = 0;
    } else {
        const walk = city.sidewalk(p.next);
        target.x = walk.x;
        target.z = walk.z;
        target.y = city.elevation(target.x, target.z) + 0.15;
        if (p.next != p.node) {
            const road = city.roads[@intCast(city.road_between[p.node][p.next])];
            speed = (0.7 + road.condition / 100) / (1 + road.slope * 3) * (if (road.works) @as(f32, 0.65) else 1);
        }
    }
    const dx = target.x - p.x;
    const dy = target.y - p.y;
    const dz = target.z - p.z;
    const estimate = rest + @sqrt(dx * dx + dy * dy + dz * dz) / speed;
    return if (p.mode == 1) estimate / 3 else estimate;
}

// Generalised travel cost combines time with out-of-pocket cost and income.
fn choose(p: *Person) void {
    p.origin = p.node;
    p.origin_building = p.current_building;
    p.chosen = true;
    p.mode = 0;
    p.bus = -1;
    p.bus_wait = 0;
    p.bus_wait_start = -1;
    p.bus_full_mask = 0;
    p.bus_stage = 0;
    p.scores = @splat(-1);
    if (p.crew or p.order >= 0) return;
    const distance = city.distance[p.node][p.destination];
    const value: f32 = @floatCast(600 / p.income);
    var best = distance;
    p.scores[0] = distance;
    if (p.owns_bike and p.bike_node == p.node) {
        var cycle: f32 = 7;
        var node = p.node;
        var steps: usize = 0;
        while (node != p.destination and steps < city.node_count) : (steps += 1) {
            const next = city.next_node[node][p.destination];
            const road_id = city.road_between[node][next];
            if (road_id < 0) break;
            const road = city.roads[@intCast(road_id)];
            cycle += road.length * (1 + road.slope * 3) / ((0.7 + road.condition / 100) * (if (transport.lanes[@intCast(road_id)] == 2) @as(f32, 4.5) else 3.0));
            node = next;
        }
        p.scores[1] = cycle;
        if (cycle < best) {
            best = cycle;
            p.mode = 1;
        }
    }
    if (p.owns_car and p.car_node == p.node) {
        const cost: f64 = @as(f64, distance) * 0.014 + 0.3;
        var delay: f32 = 0;
        var node = p.node;
        var steps: usize = 0;
        while (node != p.destination and steps < city.node_count) : (steps += 1) {
            const next = city.next_node[node][p.destination];
            const road = city.road_between[node][next];
            if (road < 0) break;
            delay += 4 + transport.congestion[@intCast(road)] * 18;
            node = next;
        }
        const score = distance / 5 + delay + 8 + @as(f32, @floatCast(cost)) * value;
        if (households.canAfford(p.home, cost)) p.scores[2] = score;
        if (households.canAfford(p.home, cost) and score < best) {
            best = score;
            p.mode = 2;
        }
    }
    const trip = transport.journey(p.node, p.destination);
    if (trip.line >= 0 and households.canAfford(p.home, transport.fare())) p.scores[3] = trip.time + @as(f32, @floatCast(transport.fare())) * value;
    if (trip.line >= 0 and households.canAfford(p.home, transport.fare()) and trip.time + @as(f32, @floatCast(transport.fare())) * value < best) {
        p.mode = 3;
        p.bus_line = trip.line;
        p.boarding = trip.board_node;
        p.exit_node = trip.exit_node;
        p.bus_version = transport.lines[@intCast(trip.line)].version;
    }
    if (p.mode == 2) _ = households.spend(p.home, @as(f64, distance) * 0.014 + 0.3);
}
pub fn daily() void {
    // Income and essentials are handled once per household; this loop only
    // updates bounded car decisions and keeps the per-person wallet mirror for
    // the existing inspector/ABI.
    for (&people) |*p| {
        if (p.phase == 3 and p.node == city.buildings[p.home].node) considerCar(p);
        p.wallet = households.balance(p.home);
    }
}

fn considerCar(p: *Person) void {
    if (p.owns_car or !households.canAfford(p.home, 2400) or p.employer < 0 or p.crew) return;
    const home = city.buildings[p.home].node;
    const work = city.buildings[companies[@intCast(p.employer)].building].node;
    const distance = city.distance[home][work];
    // Buy only when estimated daily time savings justify running cost; retain a cash buffer.
    const saved = distance * (if (p.owns_bike) @as(f32, 0.15) else 0.55);
    const benefit = @as(f64, saved) * p.income / 600;
    if (benefit <= 8 + @as(f64, distance) * 0.028) return;
    _ = households.spend(p.home, 1800);
    p.owns_car = true;
    p.car_node = home;
}
