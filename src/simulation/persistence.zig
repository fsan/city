const std = @import("std");
const game = @import("game.zig");
const city = game.city;
const residents = game.residents;
const transport = game.transport;
const operators = transport.operators;
const finance = game.finance;
const contracts = game.contracts;
const agreements = game.agreements;
const parcels = game.parcels;
const scene = @import("../render/scene.zig");

// JSON fields, not native struct bytes. Bump version/rules when changing this contract.
pub const capacity = 16 * 1024 * 1024;
pub var buffer: [capacity]u8 = undefined;
var parse_memory: [64 * 1024 * 1024]u8 = undefined;
pub var restored_speed: f32 = 1;
pub var restored_resume: f32 = 1;
pub var restored_accumulator: f32 = 0;
const Clock = struct { elapsed: f64, speed: f32, resume_speed: f32, accumulator: f32, next_sample: f64, next_routes: f64, next_operating: f64 };
const Camera = struct { x: f32, z: f32, zoom: f32, angle: f32 };
const Town = struct {
    revision: u32,
    street_count: usize,
    nodes: []const city.Node,
    roads: []const city.Road,
    buildings: []const city.Building,
    parcels: []const parcels.Parcel,
    next_node: []const []const u16,
    walk_next: []const []const u16,
    distance: []const []const f32,
};
const Citizens = struct {
    people: []const residents.Person,
    companies: []const residents.Company,
    walking: usize,
    employed: usize,
    pedestrians: []const usize,
    district_outcomes: []const residents.DistrictOutcome,
};
const Mobility = struct {
    vehicles: []const transport.Vehicle,
    lines: []const transport.Line,
    accounts: []const operators.Account,
    observations: []const transport.Observation,
    previous_observations: []const transport.Observation,
    lanes: []const u32,
    occupancy: []const usize,
    queues: []const usize,
    congestion: []const f32,
    fare_cap: f64,
    subsidy: f64,
    subsidy_total: f64,
};
const Treasury = struct {
    cash: f64,
    reserved: f64,
    residential_rate: f64,
    commercial_rate: f64,
    funding: usize,
    active_funding: usize,
    maintenance_paid: f64,
    collected: f64,
    spent: f64,
    arrears: []const f64,
    entry_count: usize,
    entries: []const finance.Entry,
};
const Services = struct {
    orders: []const contracts.Order,
    next_review: f64,
    current: []const agreements.Agreement,
    history: []const agreements.Agreement,
    history_count: usize,
    next_number: usize,
};
const State = struct {
    format: []const u8,
    version: u32,
    rules: []const u8,
    clock: Clock,
    camera: Camera,
    town: Town,
    citizens: Citizens,
    mobility: Mobility,
    treasury: Treasury,
    services: Services,
    trust: []const f32,
    history: []const game.Sample,
    history_count: usize,
};
var lane_values: [city.max_roads]u32 = undefined;
var next_rows: [city.max_nodes][]const u16 = undefined;
var walk_rows: [city.max_nodes][]const u16 = undefined;
var distance_rows: [city.max_nodes][]const f32 = undefined;
fn capture(speed: f32, resume_speed: f32, accumulator: f32) State {
    for (0..city.node_count) |i| {
        next_rows[i] = city.next_node[i][0..city.node_count];
        walk_rows[i] = city.walk_next[i][0..city.node_count];
        distance_rows[i] = city.distance[i][0..city.node_count];
    }
    for (transport.lanes[0..city.road_count], 0..) |lane, i| lane_values[i] = lane;
    return .{
        .format = "Common Ground town",
        .version = 2,
        .rules = "bellwether-2026-09-v2",
        .clock = .{ .elapsed = game.elapsed, .speed = speed, .resume_speed = resume_speed, .accumulator = accumulator, .next_sample = game.next_sample, .next_routes = game.next_routes, .next_operating = game.next_operating },
        .camera = .{ .x = scene.camera_x, .z = scene.camera_z, .zoom = scene.zoom, .angle = scene.angle },
        .town = .{ .revision = city.revision, .street_count = city.street_count, .nodes = city.nodes, .roads = city.roads, .buildings = &city.buildings, .parcels = parcels.storage[0..parcels.count], .next_node = next_rows[0..city.node_count], .walk_next = walk_rows[0..city.node_count], .distance = distance_rows[0..city.node_count] },
        .citizens = .{ .people = &residents.people, .companies = residents.companies[0..residents.company_count], .walking = residents.walking, .employed = residents.employed, .pedestrians = residents.pedestrians[0..city.road_count], .district_outcomes = &residents.district_outcomes },
        .mobility = .{ .vehicles = &transport.vehicles, .lines = &transport.lines, .accounts = &operators.accounts, .observations = &transport.observations, .previous_observations = &transport.previous_observations, .lanes = lane_values[0..city.road_count], .occupancy = transport.occupancy[0..city.road_count], .queues = transport.queues[0..city.road_count], .congestion = transport.congestion[0..city.road_count], .fare_cap = transport.fare_cap, .subsidy = transport.subsidy, .subsidy_total = transport.subsidy_total },
        .treasury = .{ .cash = finance.cash, .reserved = finance.reserved, .residential_rate = finance.residential_rate, .commercial_rate = finance.commercial_rate, .funding = finance.funding, .active_funding = finance.active_funding, .maintenance_paid = finance.maintenance_paid, .collected = finance.collected, .spent = finance.spent, .arrears = &finance.arrears, .entry_count = finance.entry_count, .entries = finance.entries[0..@min(finance.entry_count, finance.entries.len)] },
        .services = .{ .orders = contracts.orders[0..contracts.count], .next_review = contracts.next_review, .current = &agreements.agreements, .history = agreements.history[0..@min(agreements.history_count, agreements.history.len)], .history_count = agreements.history_count, .next_number = agreements.next_number },
        .trust = &game.trust,
        .history = game.history[0..@min(game.history_count, game.history.len)],
        .history_count = game.history_count,
    };
}
pub fn write(speed: f32, resume_speed: f32, accumulator: f32) usize {
    const state = capture(speed, resume_speed, accumulator);
    var stream = std.io.fixedBufferStream(&buffer);
    std.json.stringify(state, .{}, stream.writer()) catch return 0;
    return stream.pos;
}
fn numbers(value: anytype) bool {
    switch (@typeInfo(@TypeOf(value.*))) {
        .float => if (!std.math.isFinite(value.*) or @abs(value.*) > 1e15) return false,
        .int => if (value.* > 1000000000 or value.* < -1000000000) return false,
        .@"struct" => |info| inline for (info.fields) |field| {
            if (!numbers(&@field(value.*, field.name))) return false;
        },
        .array => for (value) |*item| {
            if (!numbers(item)) return false;
        },
        .pointer => |info| {
            if (info.size != .slice) @compileError("Snapshot only supports slices");
            for (value.*) |*item| {
                if (!numbers(item)) return false;
            }
        },
        .bool, .@"enum" => {},
        else => @compileError("Unsupported snapshot type"),
    }
    return true;
}
fn index(id: i32, count: usize) bool {
    return id == -1 or (id >= 0 and @as(usize, @intCast(id)) < count);
}
fn near(a: f64, b: f64) bool {
    return @abs(a - b) < 0.011;
}
fn between(value: anytype, low: f64, high: f64) bool {
    return value >= low and value <= high;
}
var edges: [city.max_nodes][city.max_nodes]i16 = undefined;
fn routeTable(table: []const []const u16, n: usize) bool {
    if (table.len != n) return false;
    for (table, 0..) |row, from| {
        if (row.len != n) return false;
        for (row, 0..) |hop, to| {
            if (hop >= n or (from == to and hop != from) or (from != to and (hop == from or edges[from][hop] < 0))) return false;
        }
    }
    // Every next-hop chain must terminate at its destination (linear per column).
    for (0..n) |to| {
        var color: [city.max_nodes]u8 = @splat(0);
        color[to] = 2;
        for (0..n) |from| {
            var path: [city.max_nodes]usize = undefined;
            var count: usize = 0;
            var at = from;
            while (color[at] == 0) {
                color[at] = 1;
                path[count] = at;
                count += 1;
                at = table[at][to];
            }
            if (color[at] == 1) return false;
            for (path[0..count]) |id| color[id] = 2;
        }
    }
    return true;
}
fn validAgreement(a: *const agreements.Agreement, s: *const State, closed: bool) bool {
    if (a.status == 0) return !closed and a.number == 0;
    const n = s.town.nodes.len;
    if (a.status > 6 or a.line >= transport.max_lines or a.company >= 3 or a.fleet < 1 or a.fleet > 3 or a.window > 1 or
        a.number == 0 or a.number >= s.services.next_number or a.stop_count < 2 or a.stop_count > 16 or
        !between(a.duration, 480, 3360) or @mod(a.duration, 480) != 0 or !between(a.price, 0.01, 1e9) or
        !between(a.paid, 0, a.price) or !between(a.reserved, 0, a.price) or !between(a.released, 0, a.price) or
        !agreements.validInterval(a.max_interval) or a.reason > 5 or a.route_version == 0 or
        !between(a.offered, 0, s.clock.elapsed) or !between(a.start, 0, s.clock.elapsed) or !between(a.ended, 0, s.clock.elapsed) or
        !between(a.updated, 0, s.clock.elapsed) or !between(a.regularity_updated, 0, s.clock.elapsed) or !between(a.regularity_time, 0, s.clock.elapsed) or
        a.delivered < 0 or a.expected < a.delivered or a.baseline < 0 or a.target < 0) return false;
    if (closed and a.status < 3) return false;
    if (a.status >= 3) {
        if (a.reserved != 0 or !near(a.paid + a.released, a.price)) return false;
    } else if (!near(a.paid + a.reserved, a.price) or a.released != 0) return false;
    if (a.start > 0 and (!near(a.target, operators.hours(a.window, a.start, a.start + a.duration) * @as(f64, @floatFromInt(a.fleet))) or a.expected > a.target + 0.001)) return false;
    var pair_total: u64 = 0;
    for (a.stops[0..a.stop_count], 0..) |node, i| {
        if (node >= n) return false;
        for (a.stops[0..i]) |old| if (old == node) return false;
        const r = &a.regularity[i];
        pair_total += r.intervals;
        if (pair_total > 1000000000) return false;
        if (r.intervals > r.visits -| 1 or r.exceeded > r.intervals or !between(r.latest, -1, s.clock.elapsed)) return false;
        if ((r.visits == 0) != (r.latest == -1) or (r.intervals == 0) != (r.last == -1) or (r.intervals == 0) != (r.worst == -1) or r.worst < r.last) return false;
    }
    return true;
}
fn validate(s: *const State) bool {
    if (!numbers(s)) return false;
    const c = &s.clock;
    const town = &s.town;
    const people = s.citizens.people;
    const n = town.nodes.len;
    const roads = town.roads;
    const companies = s.citizens.companies;
    const m = &s.mobility;
    const f = &s.treasury;
    const services = &s.services;
    if (!between(c.elapsed, 160, 1e9) or !between(c.speed, 0, 16) or !between(c.resume_speed, 0.001, 16) or !between(c.accumulator, 0, @as(f32, 1.0 / 30.0)) or
        !between(c.next_sample, c.elapsed, c.elapsed + 30.1) or !between(c.next_routes, c.elapsed, c.elapsed + 60.1) or !between(c.next_operating, c.elapsed, c.elapsed + 30.1) or
        !between(s.camera.zoom, 0.5, 12) or !between(s.camera.x, -100, city.size_x + 100) or !between(s.camera.z, -100, city.size_z + 100) or
        n < 2 or n > city.max_nodes or roads.len == 0 or roads.len > city.max_roads or town.street_count < 14 or town.street_count > city.max_roads + 14 or
        town.buildings.len != city.buildings.len or town.parcels.len > parcels.max_parcels or town.parcels.len < city.buildings.len or
        people.len != city.population or companies.len == 0 or companies.len > city.buildings.len or
        m.vehicles.len != transport.vehicles.len or m.lines.len != transport.max_lines or m.accounts.len != 3 or
        m.observations.len != transport.max_lines or m.previous_observations.len != transport.max_lines or
        m.lanes.len != roads.len or m.occupancy.len != roads.len or m.queues.len != roads.len or m.congestion.len != roads.len or s.citizens.pedestrians.len != roads.len or s.citizens.district_outcomes.len != city.district_count or
        f.arrears.len != city.buildings.len or f.entries.len != @min(f.entry_count, 1024) or f.entry_count == 0 or
        s.trust.len != city.district_count or s.history.len != @min(s.history_count, 96) or
        services.orders.len > 64 or services.current.len != 8 or services.history.len != @min(services.history_count, 64) or services.next_number == 0) return false;
    if (!between(m.fare_cap, 0, 10) or !between(m.subsidy, 0, 10) or m.subsidy_total < 0 or
        f.cash < 0 or f.reserved < 0 or f.reserved > f.cash + 0.001 or f.funding > 2 or f.active_funding > 2 or
        !between(f.residential_rate, 0, 5) or !between(f.commercial_rate, 0, 5) or !between(f.maintenance_paid, 0, 1) or f.collected < 0 or f.spent < 0) return false;
    for (f.arrears) |v| if (v < 0) return false;
    for (s.trust) |v| if (!between(v, 0, 100)) return false;
    for (s.citizens.district_outcomes) |d| {
        if (d.completed > d.wait_starts or d.abandoned > d.wait_starts - d.completed or d.abandoned_after_capacity > d.abandoned or d.wait_total < 0 or (d.completed == 0 and d.wait_total != 0)) return false;
    }
    for (&edges) |*row| @memset(row, -1);
    for (town.nodes) |node| if (!between(node.x, 0, city.size_x) or !between(node.z, 0, city.size_z) or node.street >= town.street_count or !near(node.y, city.elevation(node.x, node.z))) return false;
    for (roads, 0..) |road, i| {
        if (road.a >= n or road.b >= n or road.a == road.b or road.district >= 12 or road.street >= town.street_count or !between(road.condition, 0, 100) or !between(road.length, 0.01, 1000) or !between(road.slope, 0, 10) or edges[road.a][road.b] >= 0 or m.lanes[i] > 2 or !between(m.congestion[i], 0, 1) or m.queues[i] > m.vehicles.len or m.occupancy[i] > m.vehicles.len) return false;
        const a = town.nodes[road.a];
        const b = town.nodes[road.b];
        const planar = city.hypot(b.x - a.x, b.z - a.z);
        const dy = b.y - a.y;
        if (!near(road.length, @sqrt(planar * planar + dy * dy)) or !near(road.slope, @abs(dy) / @max(0.01, planar))) return false;
        edges[road.a][road.b] = @intCast(i);
        edges[road.b][road.a] = @intCast(i);
    }
    if (town.distance.len != n or !routeTable(town.next_node, n) or !routeTable(town.walk_next, n)) return false;
    for (town.distance, 0..) |row, i| {
        if (row.len != n) return false;
        for (row, 0..) |value, j| if (!between(value, 0, 1e9) or (i == j and value != 0) or (i != j and value <= 0)) return false;
    }
    for (town.buildings) |b| if (b.node >= n or b.district >= 12 or b.street >= town.street_count or !index(b.employer, companies.len) or b.width <= 0 or b.depth <= 0 or b.value < 0 or b.capacity > city.population or b.occupants > city.population or !between(b.sun, 0, 1)) return false;
    for (town.parcels) |p| if (p.node >= n or p.street >= town.street_count or p.zone > 5 or !index(p.building, town.buildings.len) or !index(p.block, 128) or p.width <= 0 or p.depth <= 0) return false;
    var riders: [transport.vehicles.len]usize = @splat(0);
    var employees: [city.buildings.len]usize = @splat(0);
    var occupants: [city.buildings.len]usize = @splat(0);
    for (people) |*p| {
        if (p.phase > 3 or p.mode > 3 or p.bus_stage > 2 or p.node >= n or p.next >= n or p.destination >= n or p.origin >= n or p.car_node >= n or p.bike_node >= n or p.boarding >= n or p.exit_node >= n or
            p.home >= town.buildings.len or p.current_building >= town.buildings.len or p.origin_building >= town.buildings.len or p.destination_building >= town.buildings.len or
            !index(p.employer, companies.len) or !index(p.order, services.orders.len) or !index(p.bus_line, 8) or !index(p.bus, m.vehicles.len) or p.wallet < 0 or p.income <= 0 or p.bus_wait < 0 or p.travel < 0 or p.last_trip < 0 or
            !between(p.bus_wait_start, -1, c.elapsed) or p.bus_full_mask > 7) return false;
        const waiting = p.mode == 3 and p.phase == 1 and p.bus < 0 and p.bus_stage == 0 and p.node == p.next and p.node == p.boarding;
        // A resident can reach the stop one fixed step before beginWait records
        // the wait. An active timestamp must still belong to a waiting person.
        if (p.bus_wait_start >= 0 and !waiting) return false;
        if (p.mode == 3 and p.bus_line < 0) return false;
        if (p.node != p.next and edges[p.node][p.next] < 0) return false;
        if (p.bus_stage == 1 and p.bus < 0) return false;
        if (p.order >= 0 and (!p.crew or p.employer < 0 or companies[@intCast(p.employer)].order != p.order)) return false;
        if (p.employer >= 0) employees[@intCast(p.employer)] += 1;
        occupants[p.home] += 1;
        if (p.bus >= 0) {
            const id: usize = @intCast(p.bus);
            if (id < city.population or p.mode != 3 or p.bus_stage != 1 or !m.vehicles[id].active or m.vehicles[id].line != p.bus_line) return false;
            riders[id] += 1;
        }
    }
    var employed: usize = 0;
    for (companies, 0..) |*company, i| {
        if (company.building >= town.buildings.len or company.cash < 0 or company.costs < 0 or company.margin < 1 or company.labour <= 0 or company.crew_count > 4 or company.employees != employees[i] or company.employees > company.capacity or !index(company.order, services.orders.len) or town.buildings[company.building].employer != @as(i32, @intCast(i))) return false;
        if (company.capacity != town.buildings[company.building].capacity) return false;
        employed += employees[i];
        for (company.crew[0..company.crew_count], 0..) |id, k| {
            if (id >= people.len or !people[id].crew or people[id].employer != @as(i32, @intCast(i))) return false;
            for (company.crew[0..k]) |old| if (id == old) return false;
            if (company.order >= 0 and people[id].order != company.order) return false;
        }
    }
    if (s.citizens.employed != employed or s.citizens.walking > people.len) return false;
    for (town.buildings, 0..) |b, i| if (b.occupants != occupants[i]) return false;
    for (m.vehicles, 0..) |v, i| {
        if (v.node >= n or v.next >= n or v.target >= n or v.company >= 3 or v.lane > 1 or !index(v.line, 8) or v.stop >= 16 or !between(v.dwell, 0, 5) or v.speed < 0 or v.progress < 0 or v.passengers != riders[i] or v.passengers > 24 or (!v.active and v.passengers != 0)) return false;
        if (v.active) {
            if ((i < city.population and v.line != -1) or (i >= city.population and v.line != @as(i32, @intCast((i - city.population) / 3)))) return false;
            if (v.node != v.next and (edges[v.node][v.next] < 0 or v.progress > roads[@intCast(edges[v.node][v.next])].length + 0.1)) return false;
        }
    }
    var revenue: f64 = 0;
    var costs: f64 = 0;
    for (m.lines) |l| {
        if (l.company >= 3 or l.window > 1 or l.fleet < 1 or l.fleet > 3 or l.count > 16 or (l.active and (l.count < 2 or l.version == 0)) or l.revenue < 0 or l.costs < 0 or l.delivered < 0) return false;
        for (l.stops[0..l.count], 0..) |node, i| {
            if (node >= n) return false;
            for (l.stops[0..i]) |old| if (old == node) return false;
        }
        revenue += l.revenue;
        costs += l.costs;
    }
    var receipts: f64 = 0;
    var expenses: f64 = 0;
    var subsidy_sum: f64 = 0;
    const capacity_expected = [_]usize{ 4, 3, 2 };
    const day = [_]usize{ 4, 3, 2 };
    const night = [_]usize{ 2, 1, 0 };
    const opening = [_]f64{ 600, 300, 5 };
    for (m.accounts, 0..) |account, i| {
        if (account.capacity != capacity_expected[i] or account.day != day[i] or account.night != night[i] or account.opening != opening[i] or account.cash < 0 or account.fares < 0 or account.subsidies < 0 or account.receipts < 0 or account.vehicle < 0 or account.labour < 0 or !near(account.cash, account.opening + account.fares + account.subsidies + account.receipts - account.vehicle - account.labour)) return false;
        receipts += account.fares + account.subsidies + account.receipts;
        expenses += account.vehicle + account.labour;
        subsidy_sum += account.subsidies;
    }
    if (!near(revenue, receipts) or !near(costs, expenses) or !near(m.subsidy_total, subsidy_sum)) return false;
    for ([_][]const transport.Observation{ m.observations, m.previous_observations }) |records| for (records) |*o| {
        if (o.count > 16 or o.window > 1) return false;
        for (o.nodes[0..o.count], 0..) |node, i| {
            if (node >= n) return false;
            const r = &o.stops[i];
            const abandoned = @as(u64, r.abandoned_timeout) + r.abandoned_offhours + r.abandoned_fare + r.abandoned_service;
            if (r.intervals > r.visits -| 1 or !between(r.latest, -1, c.elapsed) or r.total < 0 or (r.visits == 0) != (r.latest == -1) or (r.intervals == 0) != (r.last_interval == -1) or (r.intervals == 0) != (r.minimum == -1) or (r.intervals == 0) != (r.maximum == -1) or r.minimum > r.maximum or
                r.completed > r.wait_starts or abandoned > r.wait_starts - r.completed or r.abandoned_after_capacity > abandoned or r.wait_total < 0 or (r.completed == 0) != (r.wait_min == -1) or (r.completed == 0) != (r.wait_max == -1) or r.wait_min > r.wait_max or (r.completed == 0 and r.wait_total != 0)) return false;
        }
    };
    var reserved: f64 = 0;
    for (services.orders, 0..) |o, i| {
        if (o.road >= roads.len or !index(o.company, companies.len) or !between(o.scope, 1, 60) or !between(o.progress, 0, 1) or !between(o.price, 100, 1e6) or !between(o.paid, 0, o.price) or o.costs < 0 or o.reason > 5 or !between(o.created, 0, c.elapsed) or !between(o.accepted, 0, c.elapsed) or !between(o.finished, 0, c.elapsed)) return false;
        if (contracts.active(o)) {
            reserved += o.price;
            for (services.orders[0..i]) |old| if (contracts.active(old) and old.road == o.road) return false;
            if (o.company >= 0 and companies[@intCast(o.company)].order != @as(i32, @intCast(i))) return false;
        }
        if ((o.status == .mobilising or o.status == .working or o.status == .blocked) and o.company < 0) return false;
    }
    for (roads, 0..) |road, i| {
        var working = false;
        for (services.orders) |order| if (order.road == i and order.status == .working) {
            working = true;
        };
        if (road.works != working) return false;
    }
    for (companies, 0..) |company, i| if (company.order >= 0) {
        const o = services.orders[@intCast(company.order)];
        if (!contracts.active(o) or o.company != @as(i32, @intCast(i))) return false;
    };
    for (services.current, 0..) |*a, i| {
        if (!validAgreement(a, s, false) or (a.status > 0 and a.line != i)) return false;
        if ((a.status == 1 or a.status == 2) and !m.lines[i].active) return false;
        if (a.status == 2 and (a.company != m.lines[i].company or a.window != m.lines[i].window or a.fleet != m.lines[i].fleet or !near(a.baseline, m.lines[i].delivered))) return false;
        for (services.current[0..i]) |other| if (a.number != 0 and a.number == other.number) return false;
        reserved += a.reserved;
    }
    for (services.history, 0..) |*a, i| {
        if (!validAgreement(a, s, true)) return false;
        const current = &services.current[a.line];
        if (current.number == a.number and !std.meta.eql(current.*, a.*)) return false;
        for (services.history[0..i]) |old| if (old.number == a.number) return false;
    }
    if (!near(f.reserved, reserved) or !near(f.entries[(f.entry_count - 1) % 1024].balance, f.cash)) return false;
    const first = f.entry_count - f.entries.len;
    for (first..f.entry_count) |i| {
        const e = f.entries[i % 1024];
        if (!between(e.time, 0, c.elapsed) or e.kind > 9 or e.balance < 0) return false;
        switch (e.kind) {
            1, 2 => if (e.party < 0 or !index(e.party, town.buildings.len) or e.order != -1) return false,
            5, 6 => if (e.party < 0 or !index(e.party, companies.len) or e.order < 0 or !index(e.order, services.orders.len)) return false,
            8 => if (e.party < 0 or !index(e.party, 3) or e.order < 1 or e.order >= services.next_number) return false,
            9 => if (e.party < 0 or !index(e.party, town.street_count) or e.order != -1) return false,
            else => if (e.party != -1 or e.order != -1) return false,
        }
        if (i > first and (!near(e.balance, f.entries[(i - 1) % 1024].balance + e.amount) or e.time < f.entries[(i - 1) % 1024].time)) return false;
    }
    for (s.history) |sample| if (!between(sample.time, 0, c.elapsed) or sample.cash < 0 or sample.reserved < 0 or sample.reserved > sample.cash + 0.001 or sample.walking > people.len or !between(sample.condition, 0, 100)) return false;
    return true;
}
fn commit(s: *const State) void {
    @memcpy(&city.buildings, s.town.buildings);
    city.restoreGraph(s.town.nodes, s.town.roads);
    city.revision = s.town.revision;
    city.street_count = s.town.street_count;
    for (0..city.node_count) |i| {
        @memcpy(city.next_node[i][0..city.node_count], s.town.next_node[i]);
        @memcpy(city.walk_next[i][0..city.node_count], s.town.walk_next[i]);
        @memcpy(city.distance[i][0..city.node_count], s.town.distance[i]);
    }
    parcels.count = s.town.parcels.len;
    @memcpy(parcels.storage[0..parcels.count], s.town.parcels);
    parcels.rebuildBlocks();
    parcels.selected = -1;
    parcels.visible = false;
    @memcpy(&residents.people, s.citizens.people);
    residents.company_count = s.citizens.companies.len;
    @memcpy(residents.companies[0..residents.company_count], s.citizens.companies);
    residents.walking = s.citizens.walking;
    residents.employed = s.citizens.employed;
    @memset(&residents.pedestrians, 0);
    @memcpy(residents.pedestrians[0..city.road_count], s.citizens.pedestrians);
    @memcpy(&residents.district_outcomes, s.citizens.district_outcomes);
    const m = &s.mobility;
    @memcpy(&transport.vehicles, m.vehicles);
    @memcpy(&transport.lines, m.lines);
    @memcpy(&operators.accounts, m.accounts);
    @memcpy(&transport.observations, m.observations);
    @memcpy(&transport.previous_observations, m.previous_observations);
    @memset(&transport.lanes, 0);
    @memset(&transport.occupancy, 0);
    @memset(&transport.queues, 0);
    @memset(&transport.congestion, 0);
    for (m.lanes, 0..) |lane, i| transport.lanes[i] = @intCast(lane);
    @memcpy(transport.occupancy[0..city.road_count], m.occupancy);
    @memcpy(transport.queues[0..city.road_count], m.queues);
    @memcpy(transport.congestion[0..city.road_count], m.congestion);
    transport.fare_cap = m.fare_cap;
    transport.subsidy = m.subsidy;
    transport.subsidy_total = m.subsidy_total;
    transport.subsidy_due = 0;
    transport.subsidy_available = 0;
    transport.arrival_count = 0;
    transport.clock = s.clock.elapsed;
    transport.selected = -1;
    transport.editing = false;
    transport.draft_count = 0;
    const f = &s.treasury;
    finance.cash = f.cash;
    finance.reserved = f.reserved;
    finance.residential_rate = f.residential_rate;
    finance.commercial_rate = f.commercial_rate;
    finance.funding = f.funding;
    finance.active_funding = f.active_funding;
    finance.maintenance_paid = f.maintenance_paid;
    finance.collected = f.collected;
    finance.spent = f.spent;
    @memcpy(&finance.arrears, f.arrears);
    finance.entry_count = f.entry_count;
    @memcpy(finance.entries[0..f.entries.len], f.entries);
    contracts.count = s.services.orders.len;
    @memcpy(contracts.orders[0..contracts.count], s.services.orders);
    contracts.next_review = s.services.next_review;
    @memcpy(&agreements.agreements, s.services.current);
    agreements.history_count = s.services.history_count;
    @memcpy(agreements.history[0..s.services.history.len], s.services.history);
    agreements.next_number = s.services.next_number;
    game.elapsed = s.clock.elapsed;
    game.next_sample = s.clock.next_sample;
    game.next_routes = s.clock.next_routes;
    game.next_operating = s.clock.next_operating;
    @memcpy(&game.trust, s.trust);
    game.history_count = s.history_count;
    @memcpy(game.history[0..s.history.len], s.history);
    game.roadworks.reset();
    scene.camera_x = s.camera.x;
    scene.camera_z = s.camera.z;
    scene.zoom = s.camera.zoom;
    scene.angle = s.camera.angle;
    scene.selected = -1;
    scene.selected_person = -1;
    scene.overlay = 0;
    scene.count = 0;
    restored_speed = s.clock.speed;
    restored_resume = s.clock.resume_speed;
    restored_accumulator = s.clock.accumulator;
}
// 0 success, 1 size, 2 malformed/bounded-parser failure, 3 incompatible, 4 inconsistent.
pub fn load(length: usize) u32 {
    if (length == 0 or length > capacity) return 1;
    var fixed = std.heap.FixedBufferAllocator.init(&parse_memory);
    const parsed = std.json.parseFromSlice(State, fixed.allocator(), buffer[0..length], .{ .max_value_len = 1024, .allocate = .alloc_always }) catch return 2;
    defer parsed.deinit();
    const state = &parsed.value;
    if (!std.mem.eql(u8, state.format, "Common Ground town") or state.version != 2 or !std.mem.eql(u8, state.rules, "bellwether-2026-09-v2")) return 3;
    if (!validate(state)) return 4;
    commit(state);
    return 0;
}
