const city = @import("../scene/city.zig");
pub const Person = struct { x: f32, z: f32, y: f32, phase: u8 = 1, home: usize, employer: i32 = -1, destination: usize, node: usize, next: usize, wait: f32, trips: u32 = 0, travel: f32 = 0, last_trip: f32 = 0, order: i32 = -1, arrived: bool = false };
pub const Company = struct { building: usize, employees: usize = 0, capacity: usize, cash: f64 = 45000, contractor: bool, crew: [4]usize = .{ 0, 0, 0, 0 }, crew_count: usize = 0, order: i32 = -1, margin: f64, labour: f64, costs: f64 = 0 };
pub var people: [city.population]Person = undefined;
pub var companies: [city.buildings.len]Company = undefined;
pub var company_count: usize = 0;
pub var walking: usize = 0;
pub var employed: usize = 0;
pub fn init() void {
    company_count = 0;
    employed = 0;
    walking = 0;
    var homes: [city.buildings.len]usize = undefined;
    var home_count: usize = 0;
    for (&city.buildings, 0..) |*b, i| {
        if (b.kind == .home) {
            homes[home_count] = i;
            home_count += 1;
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
        const n = city.nodes[node];
        p.* = .{ .x = n.x + 1.65, .z = n.z + 1.65, .y = city.elevation(n.x + 1.65, n.z + 1.65) + 0.15, .home = home, .employer = employer, .destination = if (employer >= 0) city.buildings[companies[@intCast(employer)].building].node else node, .node = node, .next = node, .wait = @as(f32, @floatFromInt(i % 100)) * 0.14 };
        city.buildings[home].occupants += 1;
    }
}
pub fn send(id: usize, target: usize, order: i32) void {
    const p = &people[id];
    p.destination = target;
    p.order = order;
    p.arrived = false;
    p.wait = 0;
    if (p.phase == 2 or p.phase == 3) p.phase = 0;
    // Finish the current segment before taking the new route; never teleport a crew.
}
pub fn release(company: usize) void {
    const c = &companies[company];
    for (c.crew[0..c.crew_count]) |id| send(id, city.buildings[c.building].node, -1);
    c.order = -1;
}
fn destinationBuilding(node: usize) usize {
    return @intCast(city.building_at_node[node]);
}
fn moveTo(p: *Person, x: f32, y: f32, z: f32, speed: f32, dt: f32) bool {
    const dx = x - p.x;
    const dy = y - p.y;
    const dz = z - p.z;
    const distance = @sqrt(dx * dx + dy * dy + dz * dz);
    const step = speed * dt;
    p.travel += dt;
    walking += 1;
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
        const lane = 1.45 + @as(f32, @floatFromInt(i % 5)) * 0.09;
        if (p.phase == 3) {
            const home = city.buildings[p.home].node;
            const work = if (p.employer >= 0) city.buildings[companies[@intCast(p.employer)].building].node else home;
            const hour = @mod(elapsed / 20, 24);
            p.destination = if (hour < 7 or hour > 19 or p.destination == work) home else work;
            if (p.destination == p.node) {
                p.wait = 10;
                continue;
            }
            p.phase = 0;
        }
        if (p.phase == 0) {
            const node = city.nodes[p.node];
            if (moveTo(p, node.x + lane, city.elevation(node.x + lane, node.z + lane) + 0.15, node.z + lane, 1.1, dt)) p.phase = 1;
            continue;
        }
        if (p.phase == 2) {
            const b = city.buildings[destinationBuilding(p.destination)];
            if (moveTo(p, b.x + b.width / 2, b.ground + 0.35, b.z - 0.4, 1.1, dt)) {
                p.phase = 3;
                p.wait = 18 + @as(f32, @floatFromInt(i % 50));
                p.last_trip = p.travel;
                p.travel = 0;
                p.trips += 1;
            }
            continue;
        }
        if (p.node == p.next) {
            if (p.node == p.destination) {
                if (p.order >= 0) {
                    p.arrived = true;
                    p.last_trip = p.travel;
                    p.travel = 0;
                    p.trips += 1;
                } else p.phase = 2;
                continue;
            }
            if (city.distance[p.node][p.destination] >= 1e8) continue;
            p.next = city.next_node[p.node][p.destination];
        }
        const road_id = city.road_between[p.node][p.next];
        if (road_id < 0) continue;
        const road = city.roads[@intCast(road_id)];
        const target = city.nodes[p.next];
        const speed = (0.7 + road.condition / 100) / (1 + road.slope * 3) * (if (road.works) @as(f32, 0.65) else 1);
        if (moveTo(p, target.x + lane, city.elevation(target.x + lane, target.z + lane) + 0.15, target.z + lane, speed, dt)) p.node = p.next;
        // Road surfaces follow authored terrain; do not interpolate through grade changes.
        p.y = city.elevation(p.x, p.z) + 0.15;
    }
}

// Travel estimate includes the unfinished segment or frontage connector.
pub fn remaining(id: usize) f32 {
    const p = people[id];
    if (p.arrived or p.wait > 0 or p.phase == 3) return 0;
    var target = city.nodes[p.next];
    var speed: f32 = 1.1;
    var rest = city.distance[p.next][p.destination];
    if (p.phase == 2) {
        const b = city.buildings[destinationBuilding(p.destination)];
        target = .{ .x = b.x + b.width / 2, .z = b.z - 0.4, .y = b.ground + 0.35 };
        rest = 0;
    } else {
        const lane = 1.45 + @as(f32, @floatFromInt(id % 5)) * 0.09;
        target.x += lane;
        target.z += lane;
        target.y = city.elevation(target.x, target.z) + 0.15;
        if (p.next != p.node) {
            const road = city.roads[@intCast(city.road_between[p.node][p.next])];
            speed = (0.7 + road.condition / 100) / (1 + road.slope * 3) * (if (road.works) @as(f32, 0.65) else 1);
        }
    }
    const dx = target.x - p.x;
    const dy = target.y - p.y;
    const dz = target.z - p.z;
    return rest + @sqrt(dx * dx + dy * dy + dz * dz) / speed;
}
