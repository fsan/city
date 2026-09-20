const transport = @import("transport.zig");
const city = @import("../scene/city.zig");
pub const Person = struct { x: f32, z: f32, y: f32, phase: u8 = 0, mode: u8 = 0, wallet: f64 = 0, income: f64 = 0, owns_car: bool = false, owns_bike: bool = false, car_node: usize = 0, bike_node: usize = 0, scores: [4]f32 = @splat(-1), crew: bool = false, chosen: bool = false, bus_line: i32 = -1, bus: i32 = -1, boarding: usize = 0, exit_node: usize = 0, bus_version: u32 = 0, bus_wait: f32 = 0, bus_stage: u8 = 0, walk_side: f32 = 1, home: usize, current_building: usize = 0, destination_building: usize = 0, origin_building: usize = 0, employer: i32 = -1, origin: usize = 0, destination: usize, node: usize, next: usize, wait: f32, trips: u32 = 0, travel: f32 = 0, last_trip: f32 = 0, order: i32 = -1, arrived: bool = false };
pub const Company = struct { building: usize, employees: usize = 0, capacity: usize, cash: f64 = 45000, contractor: bool, crew: [4]usize = .{ 0, 0, 0, 0 }, crew_count: usize = 0, order: i32 = -1, margin: f64, labour: f64, costs: f64 = 0 };
pub var people: [city.population]Person = undefined;
pub var companies: [city.buildings.len]Company = undefined;
pub var company_count: usize = 0;
pub var pedestrians: [city.max_roads]usize = @splat(0);
pub var walking: usize = 0;
pub var employed: usize = 0;
pub fn init() void {
    company_count = 0;
    employed = 0;
    walking = 0;
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
        p.* = .{ .x = b.entry_x, .z = b.entry_z, .y = b.ground + 0.35, .wallet = @as(f64, @floatFromInt(100 + i % 9000)), .income = @as(f64, @floatFromInt(30 + i % 170)), .owns_bike = i % 3 != 0, .car_node = node, .bike_node = node, .home = home, .current_building = home, .origin_building = home, .destination_building = if (employer >= 0) companies[@intCast(employer)].building else home, .origin = node, .employer = employer, .destination = if (employer >= 0) city.buildings[companies[@intCast(employer)].building].node else node, .node = node, .next = node, .wait = @as(f32, @floatFromInt(i % 100)) * 0.14 };
        considerCar(p);
        city.buildings[home].occupants += 1;
    }
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
pub fn update(dt: f32, elapsed: f64) void {
    walking = 0;
    for (&people, 0..) |*p, i| {
        if (p.arrived and p.order >= 0) continue;
        if (p.wait > 0) {
            p.wait -= dt;
            continue;
        }

        if (p.phase == 3) {
            const home = city.buildings[p.home].node;
            const work = if (p.employer >= 0) city.buildings[companies[@intCast(p.employer)].building].node else home;
            const hour = @mod(elapsed / 20, 24);
            p.destination = if (hour < 7 or hour > 19 or p.destination == work) home else work;
            p.destination_building = if (p.destination == home) p.home else companies[@intCast(p.employer)].building;
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
                if (v.node == v.next and ((v.node == p.exit_node and v.dwell > 0) or v.retiring or !line.active or line.version != p.bus_version or line.cash <= 0)) {
                    v.passengers -= 1;
                    p.node = v.node;
                    p.next = v.node;
                    p.bus = -1;
                    p.bus_stage = 2;
                }
                continue;
            }
            if (!line.active or line.version != p.bus_version) {
                p.mode = 0;
                p.bus_stage = 2;
            }
            if (p.bus_stage == 0 and p.node == p.boarding and p.node == p.next) {
                p.bus_wait += dt;
                p.travel += dt;
                for (0..transport.buses_per_line) |slot| {
                    const bus = transport.car_count + @as(usize, @intCast(p.bus_line)) * transport.buses_per_line + slot;
                    const v = transport.vehicles[bus];
                    if (v.active and v.node == p.node and v.node == v.next and p.wallet >= transport.fare() and transport.board(bus)) {
                        p.wallet -= transport.fare();
                        p.bus = @intCast(bus);
                        p.bus_stage = 1;
                        break;
                    }
                }
                if (p.bus_wait > 180 or p.wallet < transport.fare()) {
                    p.mode = 0;
                    p.bus_stage = 2;
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
        if (p.wallet >= cost) p.scores[2] = score;
        if (p.wallet >= cost and score < best) {
            best = score;
            p.mode = 2;
        }
    }
    const trip = transport.journey(p.node, p.destination);
    if (trip.line >= 0 and p.wallet >= transport.fare()) p.scores[3] = trip.time + @as(f32, @floatCast(transport.fare())) * value;
    if (trip.line >= 0 and p.wallet >= transport.fare() and trip.time + @as(f32, @floatCast(transport.fare())) * value < best) {
        p.mode = 3;
        p.bus_line = trip.line;
        p.boarding = trip.board_node;
        p.exit_node = trip.exit_node;
        p.bus_version = transport.lines[@intCast(trip.line)].version;
    }
    if (p.mode == 2) p.wallet -= @as(f64, distance) * 0.014 + 0.3;
}
pub fn daily() void {
    for (&people) |*p| {
        p.wallet += p.income * 0.25; // Income remaining after simplified living expenses.
        if (p.owns_car) p.wallet = @max(0, p.wallet - 8);
        if (p.phase == 3 and p.node == city.buildings[p.home].node) considerCar(p);
    }
}

fn considerCar(p: *Person) void {
    if (p.owns_car or p.wallet < 2400 or p.employer < 0 or p.crew) return;
    const home = city.buildings[p.home].node;
    const work = city.buildings[companies[@intCast(p.employer)].building].node;
    const distance = city.distance[home][work];
    // Buy only when estimated daily time savings justify running cost; retain a cash buffer.
    const saved = distance * (if (p.owns_bike) @as(f32, 0.15) else 0.55);
    const benefit = @as(f64, saved) * p.income / 600;
    if (benefit <= 8 + @as(f64, distance) * 0.028) return;
    p.wallet -= 1800;
    p.owns_car = true;
    p.car_node = home;
}
