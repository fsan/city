const std = @import("std");
const transport = @import("transport.zig");
const city = @import("../scene/city.zig");
const calendar = @import("calendar.zig");
const households = @import("households.zig");
const parking = @import("parking.zig");
const travel = @import("travel.zig");
// Slice 10: every resident also carries a deliberately tiny learned model of
// trip time and parking availability, the plan for the current journey, and the
// parking space their bicycle or car currently occupies. Nothing allocates.
pub const Person = struct { x: f32, z: f32, y: f32, phase: u8 = 0, mode: u8 = 0, wallet: f64 = 0, income: f64 = 0, owns_car: bool = false, owns_bike: bool = false, car_node: usize = 0, bike_node: usize = 0, scores: [4]f32 = @splat(-1), crew: bool = false, chosen: bool = false, bus_line: i32 = -1, bus: i32 = -1, boarding: usize = 0, exit_node: usize = 0, bus_version: u32 = 0, bus_wait: f32 = 0, bus_wait_start: f64 = -1, bus_full_mask: u8 = 0, bus_stage: u8 = 0, walk_side: f32 = 1, shift: u8 = 0, routine: u8 = 0, skill: u8 = 0, home: usize, current_building: usize = 0, destination_building: usize = 0, origin_building: usize = 0, employer: i32 = -1, origin: usize = 0, destination: usize, node: usize, next: usize, wait: f32, trips: u32 = 0, travel: f32 = 0, last_trip: f32 = 0, order: i32 = -1, arrived: bool = false, prefers_car: bool = false, plan_mode: u8 = 0, access: bool = false, via: usize = 0, leg_target: usize = 0, plan_facility: i32 = -1, park_facility: i32 = -1, parked_vehicle: u8 = 0, back: usize = 0, crossing: bool = false, cross_wait: f32 = 0, cross_waits: u32 = 0, crossings: u32 = 0, park_tries: u32 = 0, park_taken: u32 = 0, park_searched: u32 = 0, park_refused: u32 = 0, depart_bucket: u8 = 0, last_facility: u16 = travel.no_facility, last_outcome: u8 = 0, model: travel.Model = .{} };
// Slice 10: private car ownership is a household purchase with a posted price
// and a running cost, so the mode choice compares real money against time.
pub const car_price: f64 = 1800;
pub const car_reserve: f64 = 2400;
// Slice 13: the per-trip motoring cost and the daily ownership charge. The old
// per-metre rate (0.014) grew faster than the time a car could save, so no
// distance could ever pay for a car; the town is now large enough that the
// rate has to be the realistic one for the comparison to mean anything.
pub const fuel_per_metre: f64 = 0.002;
pub const fuel_base: f64 = 0.20;
pub const car_daily_cost: f64 = 12;
pub const Company = struct { building: usize, employees: usize = 0, capacity: usize, cash: f64 = 45000, contractor: bool, crew: [4]usize = .{ 0, 0, 0, 0 }, crew_count: usize = 0, order: i32 = -1, margin: f64, labour: f64, costs: f64 = 0, wage: f64 = 40, skill_required: u8 = 0, wage_arrears: f64 = 0, staffing_pressure: f64 = 0 };
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
        companies[company_count] = .{ .building = i, .capacity = b.capacity, .contractor = b.kind == .depot, .margin = 1.15 + @as(f64, @floatFromInt(company_count % 3)) * 0.12, .labour = 14 + @as(f64, @floatFromInt(company_count % 3)) * 3, .wage = 40 + @as(f64, @floatFromInt(company_count % 3)) * 15, .skill_required = switch (b.kind) {
            .office, .hall => 1,
            .clinic => 2,
            else => 0,
        } };
        company_count += 1;
    }
    // Slice 8: employment starts from an explicit inherited position. Post
    // requirements are read across employers by post slot so the skill mix
    // follows the city's real vacancy mix, one adult in eight starts out of
    // work, and the daily hiring step fills open posts only from qualified
    // jobseekers. A skill mismatch is therefore a real, inspectable refusal.
    var post_plan: [city.population]u8 = undefined;
    for (0..post_plan.len) |k| {
        const company = k % company_count;
        const slot = k / company_count;
        post_plan[k] = if (slot < companies[company].capacity) companies[company].skill_required else 0;
    }
    for (&people, 0..) |*p, i| {
        const home = homes[i % home_count];
        const skill: u8 = post_plan[i];
        var employer: i32 = -1;
        if (i % 8 != 0) {
            for (0..company_count) |offset| {
                const c = (i + offset) % company_count;
                if (companies[c].employees >= companies[c].capacity or companies[c].skill_required > skill) continue;
                employer = @intCast(c);
                companies[c].employees += 1;
                employed += 1;
                if (companies[c].contractor and companies[c].crew_count < 4) {
                    companies[c].crew[companies[c].crew_count] = i;
                    companies[c].crew_count += 1;
                }
                break;
            }
        }
        const node = city.buildings[home].node;
        const b = city.buildings[home];
        p.* = .{ .x = b.entry_x, .z = b.entry_z, .y = b.ground + 0.35, .wallet = @as(f64, @floatFromInt(100 + i % 9000)), .income = if (employer >= 0) companies[@intCast(employer)].wage else 0, .owns_bike = i % 3 != 0, .car_node = node, .bike_node = node, .shift = @intCast(@intFromEnum(calendar.shiftFor(i))), .routine = 0, .skill = skill, .home = home, .current_building = home, .origin_building = home, .destination_building = if (employer >= 0) companies[@intCast(employer)].building else home, .origin = node, .employer = employer, .destination = if (employer >= 0) city.buildings[companies[@intCast(employer)].building].node else node, .node = node, .next = node, .back = node, .wait = @as(f32, @floatFromInt(i % 100)) * 0.14 };
        city.buildings[home].occupants += 1;
    }
    households.init();
    for (companies[0..company_count]) |c| {
        for (c.crew[0..c.crew_count]) |id| people[id].crew = true;
    }
    // Car ownership is a household purchase, so it can only be decided once the
    // shared household ledger exists and the crew rosters are known. Running it
    // inside the creation loop left every household invalid, so no resident ever
    // bought a car and the city started with no private traffic at all.
    for (&people) |*p| considerCar(p);
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
// Slice 13: working hours belong to the place people work.
fn facilityOf(kind: city.Kind) calendar.Facility {
    return switch (kind) {
        .office => .office,
        .shop => .shop,
        .clinic => .clinic,
        .hall => .hall,
        .depot => .depot,
        else => .other,
    };
}

// Slice 6: bounded routine destination from the shared civic calendar. Slice 13
// reads the employer's own working window instead of a global shift rotation, so
// offices run 9-5 while shops, clinics and depots cover their own patterns.
fn routineDestination(p: *const Person, index: usize, routine: calendar.Phase, time: f64) usize {
    if (p.crew or p.order >= 0 or p.employer < 0) return p.home;
    const work = companies[@intCast(p.employer)].building;
    const facility = facilityOf(city.buildings[work].kind);
    if (calendar.onFacilityShift(facility, p.shift, time)) return work;
    if (calendar.isWeekend(time)) {
        if ((routine == .morning or routine == .leisure) and index % 8 == 0) return errandTarget(p);
        return p.home;
    }
    // A short errand window keeps weekday demand on the network outside work.
    if (routine == .evening and index % 7 == 0) return errandTarget(p);
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
    // Crosswalk yielding reads the previous step's crossings; refill it now.
    transport.crossing_active = @splat(0);
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
            // Slice 10: a resident leaving home plans the departure time from
            // their own learned trip time rather than an arbitrary delay.
            if (!p.crew and p.order < 0 and p.current_building == p.home and p.destination_building != p.home) {
                const lead = departureLead(p, elapsed);
                if (lead > 0) {
                    p.wait = lead;
                    continue;
                }
            }
            p.phase = 0;
            p.chosen = false;
        }
        if (!p.chosen) choose(p, elapsed);
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
                v.active = false;
                settleParking(p, .car, elapsed);
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
            if (moveTo(p, node.x, city.elevation(node.x, node.z) + 0.25, node.z, travel.walk_speed, dt)) p.phase = 1;
            p.y = @max(city.elevation(p.x, p.z) + 0.25, p.y);
            continue;
        }
        if (p.phase == 2) {
            const b = city.buildings[p.destination_building];
            if (moveTo(p, b.entry_x, b.ground + 0.35, b.entry_z, travel.walk_speed, dt)) {
                p.current_building = p.destination_building;
                p.phase = 3;
                p.wait = 18 + @as(f32, @floatFromInt(i % 50));
                p.last_trip = p.travel;
                recordTrip(p, i, elapsed);
                p.travel = 0;
                p.trips += 1;
            }
            p.y = @max(city.elevation(p.x, p.z) + 0.25, p.y);
            continue;
        }
        // Slice 10: the access walk to the parked bicycle or car comes first.
        if (p.access and p.node == p.via) {
            p.access = false;
            p.mode = p.plan_mode;
            p.destination = p.leg_target;
            p.next = p.node;
            p.back = p.node;
        }
        const walking_leg = p.access or p.mode == 0 or p.mode == 3;
        const target_node = if (p.mode == 3 and p.bus_stage == 0) p.boarding else p.destination;
        if (p.node == p.next) {
            if (p.node == target_node) {
                if (p.access) continue;
                if (p.mode == 1) {
                    settleParking(p, .bike, elapsed);
                    p.phase = 2;
                    continue;
                }
                if (p.order >= 0) {
                    p.arrived = true;
                    p.last_trip = p.travel;
                    recordTrip(p, i, elapsed);
                    p.travel = 0;
                    p.trips += 1;
                } else p.phase = 2;
                continue;
            }
            if (city.distance[p.node][target_node] >= 1e8) continue;
            p.next = if (walking_leg and i % 5 != 0) city.walk_next[p.node][target_node] else city.next_node[p.node][target_node];
            const a = city.nodes[p.node];
            const b = city.nodes[p.next];
            const destination = city.buildings[p.destination_building];
            const side = (b.x - a.x) * (destination.entry_z - a.z) - (b.z - a.z) * (destination.entry_x - a.x);
            p.walk_side = if (i % 3 == 0) (if (i % 2 == 0) @as(f32, 1) else -1) else if (side >= 0) 1 else -1;
        }
        // Turning at a junction crosses an arm of the junction, so walkers and
        // cyclists obey the marked crossing's pedestrian phase or wait for a gap.
        if (!p.access and p.mode != 2 and crossingWait(p, elapsed, dt)) continue;
        const road_id = city.road_between[p.node][p.next];
        if (road_id < 0) continue;
        const road = city.roads[@intCast(road_id)];
        const a = city.nodes[p.node];
        const b = city.nodes[p.next];
        const span = city.hypot(b.x - a.x, b.z - a.z);
        // Pedestrians keep to the pavement. Cyclists ride the kerb-side lane on
        // the side of the street for their own direction of travel.
        const lateral: f32 = if (p.mode == 1) -1.35 else 2.3 * p.walk_side;
        const target = city.Vec{ .x = b.x - (b.z - a.z) / span * lateral, .z = b.z + (b.x - a.x) / span * lateral };
        const speed = if (p.mode == 1) travel.bikeRide(road.condition, road.slope, road.works, transport.lanes[@intCast(road_id)] == 2) else travel.walkRide(road.condition, road.slope, road.works);
        if (moveTo(p, target.x, city.elevation(target.x, target.z) + 0.15, target.z, speed, dt)) {
            p.back = p.node;
            p.node = p.next;
            p.crossing = false;
        }
        if (p.crossing and p.back < city.max_nodes) transport.crossing_active[p.back] +|= 1;
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
    return if (p.mode == 1) estimate * (travel.walk_speed / travel.bike_speed) else estimate;
}

// Slice 10: the mode decision uses the resident's own learned trip time where
// they have one, the analytic estimate otherwise, plus the money cost, the
// expected parking search and the learned chance of finding a space. A
// car-owning household that already chose a car uses it unless another mode is
// clearly better for that particular trip.
fn choose(p: *Person, elapsed: f64) void {
    p.origin = p.node;
    p.origin_building = p.current_building;
    p.chosen = true;
    p.mode = 0;
    p.plan_mode = 0;
    p.access = false;
    p.leg_target = p.destination;
    p.plan_facility = -1;
    p.back = p.node;
    p.bus = -1;
    p.bus_wait = 0;
    p.bus_wait_start = -1;
    p.bus_full_mask = 0;
    p.bus_stage = 0;
    p.scores = @splat(-1);
    p.depart_bucket = @intCast(travel.bucket(elapsed));
    if (p.crew or p.order >= 0) return;
    const destination = p.destination;
    const slot = travel.bucket(elapsed);
    // Slice 8: an unemployed resident has no wage of their own, so the value of
    // time falls back to the household's posted employment income, bounded below
    // so out-of-pocket costs still dominate and walking stays the safe fallback.
    const own: f64 = if (p.income > 0) p.income else households.homes[p.home].income;
    const value: f32 = @floatCast(600 / @max(8, own));
    var best: f32 = 1e9;
    var best_mode: u8 = 0;
    var best_facility: i32 = -1;
    var best_access: usize = p.node;
    var best_target: usize = destination;

    // Walking is always available and is the safe fallback.
    const walk_time = walkSeconds(p.node, destination) + 6;
    p.scores[0] = walk_time;
    best = walk_time;

    if (p.owns_bike) {
        const plan = parkChoice(p, .bike, destination, slot);
        if (plan.facility >= 0) {
            const park_node = parking.facilities[@intCast(plan.facility)].node;
            const access = walkSeconds(p.node, p.bike_node);
            const ride = rideSeconds(p.bike_node, park_node);
            const time = access + ride + plan.walk + 4;
            const score = learnedOr(p, 1, slot, time);
            p.scores[1] = score;
            if (score < best) {
                best = score;
                best_mode = 1;
                best_facility = plan.facility;
                best_access = p.bike_node;
                best_target = park_node;
            }
        }
    }

    if (p.owns_car) {
        const plan = parkChoice(p, .car, destination, slot);
        if (plan.facility >= 0) {
            const park_node = parking.facilities[@intCast(plan.facility)].node;
            const access = walkSeconds(p.node, p.car_node);
            const drive = driveSeconds(p.car_node, park_node);
            const fuel = @as(f64, city.distance[p.car_node][park_node]) * fuel_per_metre + fuel_base;
            const cost = fuel + plan.price;
            if (households.canAfford(p.home, cost)) {
                const time = access + drive + plan.walk + 8;
                var score = learnedOr(p, 2, slot, time) + @as(f32, @floatCast(cost)) * value;
                // A car-owning household keeps a small tie-break rather than a
                // blanket discount: with a town this large, an 18% bonus made
                // every owner drive even the shortest errand. 0.94 is inside
                // the noise of the learned times, so a genuinely faster
                // bicycle or bus still wins its trip.
                const bias: f32 = if (p.prefers_car) 0.94 else 1;
                score *= bias;
                p.scores[2] = score;
                if (score < best) {
                    best = score;
                    best_mode = 2;
                    best_facility = plan.facility;
                    best_access = p.car_node;
                    best_target = park_node;
                }
            }
        }
    }

    const trip = transport.journey(p.node, destination);
    if (trip.line >= 0 and households.canAfford(p.home, transport.fare())) {
        const score = learnedOr(p, 3, slot, trip.time) + @as(f32, @floatCast(transport.fare())) * value;
        p.scores[3] = score;
        if (score < best) {
            best = score;
            best_mode = 3;
        }
    }

    p.mode = best_mode;
    p.plan_mode = best_mode;
    if (best_mode == 3) {
        p.bus_line = trip.line;
        p.boarding = trip.board_node;
        p.exit_node = trip.exit_node;
        p.bus_version = transport.lines[@intCast(trip.line)].version;
        return;
    }
    if (best_mode == 1 or best_mode == 2) {
        p.plan_facility = best_facility;
        p.leg_target = best_target;
        // The vehicle leaves the space where it was parked.
        releaseParking(p);
        if (p.parked_vehicle == 0) p.parked_vehicle = if (best_mode == 1) 1 else 2;
        if (best_access != p.node) {
            // Walk to the bicycle or car first; the access leg is a normal walk.
            p.access = true;
            p.via = best_access;
            p.destination = best_access;
            p.mode = 0;
        } else {
            p.destination = best_target;
        }
        if (best_mode == 2) {
            const fuel = @as(f64, city.distance[best_access][best_target]) * fuel_per_metre + fuel_base;
            _ = households.spend(p.home, fuel);
        }
    }
}

// Learned mean for this mode and departure bucket, or the analytic estimate.
fn learnedOr(p: *const Person, mode: u8, slot: usize, analytic: f32) f32 {
    if (travel.observed(&p.model, mode, slot)) |known| return @max(known, analytic * 0.4);
    return analytic;
}

fn predictedSeconds(p: *const Person, mode: u8, slot: usize) f32 {
    if (travel.observed(&p.model, mode, slot)) |known| return known;
    return switch (mode) {
        1 => 90,
        2 => 60,
        3 => 80,
        else => 120,
    };
}

// A resident leaving home plans the departure from their own learned commute.
// The day is compressed into 480 seconds, so the learned door-to-door time is
// scaled into a bounded pre-shift window instead of leaving at a fixed moment.
fn departureLead(p: *const Person, elapsed: f64) f32 {
    const work: usize = if (p.employer >= 0) companies[@intCast(p.employer)].building else p.destination_building;
    if (p.destination_building != work) return 0;
    const facility = facilityOf(city.buildings[work].kind);
    const window = calendar.facilityWindow(facility, p.shift);
    const day = @floor(elapsed / calendar.seconds_per_day);
    // Slice 13: aim for the window that is running now, or the next one when the
    // resident is still early. The old code always stepped to tomorrow, so
    // anybody at home during their own shift waited a whole day and never went
    // back to work; that is what emptied the streets after the first day.
    var target = day * calendar.seconds_per_day + @as(f64, window.start) * calendar.seconds_per_hour;
    if (!calendar.inSchedule(window, @floatCast(calendar.hour(elapsed)))) {
        while (target <= elapsed + 2) target += calendar.seconds_per_day;
    }
    // The lead uses the fastest mode this resident could actually take, so the
    // departure reflects the commute they are about to make rather than a
    // single assumed mode. Walking is always available.
    const slot = travel.bucket(target);
    var predicted = predictedSeconds(p, 0, slot);
    if (p.owns_bike) predicted = @min(predicted, predictedSeconds(p, 1, slot));
    if (p.owns_car) predicted = @min(predicted, predictedSeconds(p, 2, slot));
    // A compressed day cannot hold a real-time commute, so the learned time is
    // scaled into a bounded pre-shift window; the ordering by mode and by
    // learned duration is preserved.
    const lead = std.math.clamp(predicted * 0.2, 2, 45);
    const leave = target - lead;
    if (elapsed >= leave) return 0;
    return @floatCast(@min(leave - elapsed, 60));
}

// Seconds to walk the resident's own walking route between two nodes.
const unreachable_cost: f32 = 1e8;

fn walkSeconds(from: usize, to: usize) f32 {
    if (from == to) return 0;
    if (city.walkCost(from, to) >= unreachable_cost) return unreachable_cost;
    var total: f32 = 0;
    var node = from;
    var steps: usize = 0;
    while (node != to and steps < city.node_count) : (steps += 1) {
        const next = city.walk_next[node][to];
        if (next == node) return unreachable_cost;
        const road_id = city.road_between[node][next];
        if (road_id < 0) return unreachable_cost;
        const road = city.roads[@intCast(road_id)];
        total += road.length / travel.walkRide(road.condition, road.slope, road.works);
        node = next;
    }
    if (node != to) return unreachable_cost;
    return total;
}

fn rideSeconds(from: usize, to: usize) f32 {
    if (from == to) return 0;
    if (city.driveCost(from, to) >= unreachable_cost) return unreachable_cost;
    var total: f32 = 0;
    var node = from;
    var steps: usize = 0;
    while (node != to and steps < city.node_count) : (steps += 1) {
        const next = city.next_node[node][to];
        if (next == node) return unreachable_cost;
        const road_id = city.road_between[node][next];
        if (road_id < 0) return unreachable_cost;
        const road = city.roads[@intCast(road_id)];
        total += road.length / travel.bikeRide(road.condition, road.slope, road.works, transport.lanes[@intCast(road_id)] == 2);
        node = next;
    }
    if (node != to) return unreachable_cost;
    return total;
}

fn driveSeconds(from: usize, to: usize) f32 {
    if (from == to) return 0;
    if (city.driveCost(from, to) >= unreachable_cost) return unreachable_cost;
    var total: f32 = 0;
    var delay: f32 = 0;
    var node = from;
    var steps: usize = 0;
    while (node != to and steps < city.node_count) : (steps += 1) {
        const next = city.next_node[node][to];
        if (next == node) return unreachable_cost;
        const road_id = city.road_between[node][next];
        if (road_id < 0) return unreachable_cost;
        const road = city.roads[@intCast(road_id)];
        total += road.length / @max(1, travel.classSpeed(road.class, road.condition, road.slope, road.works));
        // A junction costs a little; heavy queueing costs more.
        delay += 1.5 + transport.congestion[@intCast(road_id)] * 18;
        node = next;
    }
    if (node != to) return unreachable_cost;
    return total + delay;
}

fn vehicleKind(mode: u8) parking.Kind {
    return if (mode == 1) .bike else .car;
}

// This resident's estimate for a place: their own remembered experience where
// they have one, otherwise the rate observed there by everybody.
fn chanceAt(p: *const Person, index: usize, slot: usize) u8 {
    if (index >= parking.count) return travel.default_chance;
    if (travel.remembered(&p.model, @intCast(index))) |memory| return p.model.chance[memory][slot];
    return parking.facilities[index].observed[slot];
}

const ParkPlan = struct { facility: i32 = -1, walk: f32 = 0, price: f64 = 0 };

// Pick the place a traveller aims for: nearest to the destination once the
// expected search caused by a low learned chance of a free slot is priced in.
fn parkChoice(p: *const Person, kind: parking.Kind, destination: usize, slot: usize) ParkPlan {
    var plan: ParkPlan = .{};
    var best: f32 = 1e9;
    for (parking.facilities[0..parking.count], 0..) |f, index| {
        if (f.kind != kind) continue;
        const walk = walkSeconds(f.node, destination);
        if (walk > 300) continue;
        const chance = travel.chanceValue(chanceAt(p, index, slot));
        const expected = walk + (1 - chance) * 90;
        const score = expected + @as(f32, @floatCast(f.price)) * 20;
        if (score < best) {
            best = score;
            plan = .{ .facility = @intCast(index), .walk = walk, .price = f.price };
        }
    }
    return plan;
}

// The nearest place of the right kind that actually has a free slot.
fn nearestFree(kind: parking.Kind, from: usize, destination_building: usize) i32 {
    const destination = city.buildings[destination_building].node;
    var best: i32 = -1;
    var best_score: f32 = 1e9;
    for (parking.facilities[0..parking.count], 0..) |f, index| {
        if (f.kind != kind or parking.full(index)) continue;
        const score = walkSeconds(f.node, destination) + walkSeconds(from, f.node) * 0.2;
        if (score < best_score) {
            best_score = score;
            best = @intCast(index);
        }
    }
    return best;
}

fn releaseParking(p: *Person) void {
    if (p.park_facility < 0) return;
    parking.release(@intCast(p.park_facility));
    p.park_facility = -1;
}

// Park the bicycle or car at the destination. A full first choice falls back to
// the nearest place with a slot; if nothing is free the traveller keeps the
// vehicle and walks the rest, and the learned chance of a space falls.
fn settleParking(p: *Person, kind: parking.Kind, elapsed: f64) void {
    _ = elapsed;
    p.park_tries +|= 1;
    p.last_facility = travel.no_facility;
    p.last_outcome = 0;
    var chosen: i32 = -1;
    if (p.plan_facility >= 0) {
        const planned: usize = @intCast(p.plan_facility);
        if (planned < parking.count and parking.facilities[planned].kind == kind and parking.take(planned)) {
            chosen = p.plan_facility;
            p.last_facility = @intCast(planned);
            p.last_outcome = 1;
        } else {
            p.last_facility = @intCast(@min(planned, parking.max_facilities - 1));
            p.last_outcome = 2;
        }
    }
    if (chosen < 0) {
        p.park_searched +|= 1;
        parking.fallbacks +|= 1;
        const fallback = nearestFree(kind, p.node, p.destination_building);
        if (fallback >= 0 and parking.take(@intCast(fallback))) {
            chosen = fallback;
            p.last_facility = @intCast(fallback);
            p.last_outcome = 1;
        }
    }
    parking.attempts +|= 1;
    if (chosen >= 0) {
        const held: usize = @intCast(chosen);
        p.park_facility = chosen;
        p.parked_vehicle = if (kind == .bike) 1 else 2;
        if (kind == .bike) p.bike_node = parking.facilities[held].node else p.car_node = parking.facilities[held].node;
        p.park_taken +|= 1;
        parking.successes +|= 1;
        const price = parking.facilities[held].price;
        if (price > 0 and households.spend(p.home, price)) {
            parking.revenue_today += price;
            parking.revenue_total += price;
            parking.dues += price;
        }
    } else {
        // No space anywhere: keep the vehicle and walk the rest of the way.
        p.park_facility = -1;
        p.parked_vehicle = if (kind == .bike) 1 else 2;
        p.park_refused +|= 1;
        parking.refusals +|= 1;
        if (kind == .bike) p.bike_node = p.node else p.car_node = p.node;
    }
    p.leg_target = p.node;
    p.plan_facility = -1;
}

// Walkers and cyclists crossing an arm of a junction obey the marked crossing's
// pedestrian phase; without a marked crossing they wait for a gap in traffic.
// Bounded patience keeps anybody from being stuck forever.
fn crossingWait(p: *Person, elapsed: f64, dt: f32) bool {
    if (p.back == p.node or p.back >= city.node_count or p.node >= city.node_count) return false;
    if (city.degree(p.node) < 3) return false;
    const came = city.nodes[p.back];
    const here = city.nodes[p.node];
    const next = city.nodes[p.next];
    const in_len = city.hypot(here.x - came.x, here.z - came.z);
    const out_len = city.hypot(next.x - here.x, next.z - here.z);
    if (in_len < 0.01 or out_len < 0.01) return false;
    const dot = ((here.x - came.x) * (next.x - here.x) + (here.z - came.z) * (next.z - here.z)) / (in_len * out_len);
    if (dot >= 0.7) return false; // straight through the junction: no crossing
    const marked = city.markedCrossing(p.node, city.horizontal(p.back, p.node));
    // Slice 11: the parallel movement holds green while this crossing's own
    // traffic arm is stopped, so a signalised corner releases walkers with it.
    const movement = city.Vec{ .x = next.x - here.x, .z = next.z - here.z };
    const parallel = transport.signals.crossingAllowed(p.node, movement, elapsed);
    const gap = transport.junction_traffic[p.node] == 0;
    if (travel.crossingAdmitted(marked, parallel, gap, p.cross_wait)) {
        p.cross_wait = 0;
        p.crossing = true;
        p.crossings +|= 1;
        return false;
    }
    if (p.cross_wait == 0) p.cross_waits +|= 1;
    p.cross_wait += dt;
    return true;
}

// Slice 10: the learned models are updated in one bounded batch per step, as
// residents arrive at work or home, never inside the movement loop.
const Batch = struct { person: u16 = 0, mode: u8 = 0, bucket: u8 = 0, arrive_bucket: u8 = 0, seconds: f32 = 0, facility: u16 = travel.no_facility, outcome: u8 = 0 };
var batch: [128]Batch = @splat(.{});
var batch_count: usize = 0;
pub var batches_applied: u64 = 0;
pub var batches_dropped: u64 = 0;

fn recordTrip(p: *Person, index: usize, elapsed: f64) void {
    if (batch_count >= batch.len) {
        batches_dropped +|= 1;
        return;
    }
    // Trip time is learned against the departure bucket; the chance of finding
    // a parking space is learned against the bucket the traveller arrives in,
    // so availability reflects the time they are actually near the facility.
    batch[batch_count] = .{ .person = @intCast(index), .mode = p.plan_mode, .bucket = p.depart_bucket, .arrive_bucket = @intCast(travel.bucket(elapsed)), .seconds = p.travel, .facility = p.last_facility, .outcome = p.last_outcome };
    batch_count += 1;
}

pub fn flushBatch() void {
    for (batch[0..batch_count]) |entry| {
        if (entry.person >= people.len) continue;
        const p = &people[entry.person];
        travel.record(&p.model, entry.mode, entry.bucket, entry.seconds);
        if (entry.facility != travel.no_facility and entry.outcome != 0) {
            const free = entry.outcome == 1;
            travel.observeChance(&p.model, entry.facility, entry.arrive_bucket, free);
            parking.observe(entry.facility, entry.arrive_bucket, free);
        }
        batches_applied +|= 1;
    }
    batch_count = 0;
}

pub fn pendingBatch() usize {
    return batch_count;
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
    if (p.owns_car or !households.canAfford(p.home, car_reserve) or p.employer < 0 or p.crew) return;
    const home = city.buildings[p.home].node;
    const work = city.buildings[companies[@intCast(p.employer)].building].node;
    const distance = city.distance[home][work];
    // Slice 13: buy only when the time a car saves on this resident's own
    // commute is worth more than the money it costs to run. The alternative is
    // the resident's real one: cycling where they own a bicycle, walking where
    // they do not. Because the fuel rate is now realistic, distance decides:
    // a household on the edge of the plan can reach the point where a car pays,
    // and a household beside its work cannot.
    const alt_speed: f64 = if (p.owns_bike) travel.bike_speed * 0.8 else travel.walk_speed * 0.85;
    const drive_speed: f64 = travel.car_limit * 0.65; // junctions and parking included
    const saved_seconds = @as(f64, distance) * (1 / alt_speed - 1 / drive_speed) * 2; // both legs
    const daily_running = car_daily_cost + @as(f64, distance) * fuel_per_metre * 2 + fuel_base * 2;
    const wage = if (p.income > 0) p.income else households.homes[p.home].income;
    const value_of_time = wage / 480; // daily wage expressed per simulated second
    if (saved_seconds * value_of_time <= daily_running) return;
    _ = households.spend(p.home, car_price);
    p.owns_car = true;
    // Slice 10: a household that chose to buy a car prefers driving until a
    // learned trip shows another mode is clearly better.
    p.prefers_car = true;
    p.car_node = home;
}
