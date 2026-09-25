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
const calendar = game.calendar;
const households = game.households;
const housing = game.housing;
const parking = game.parking;
const travel = game.travel;
const signals = game.transport.signals;
const development = game.development;

// JSON fields, not native struct bytes. Bump version/rules when changing this contract.
pub const capacity = 16 * 1024 * 1024;
pub var buffer: [capacity]u8 = undefined;
var parse_memory: [64 * 1024 * 1024]u8 = undefined;
pub var restored_speed: f32 = 1;
pub var restored_resume: f32 = 1;
pub var restored_accumulator: f32 = 0;
const Clock = struct { elapsed: f64, speed: f32, resume_speed: f32, accumulator: f32, next_sample: f64, next_routes: f64, next_operating: f64, next_week: f64 };
const Camera = struct { x: f32, z: f32, zoom: f32, angle: f32 };
const Town = struct {
    revision: u32,
    street_count: usize,
    nodes: []const city.Node,
    roads: []const city.Road,
    buildings: []const city.Building,
    parcels: []const parcels.Parcel,
};
const Citizens = struct {
    people: []const residents.Person,
    companies: []const residents.Company,
    walking: usize,
    employed: usize,
    pedestrians: []const usize,
    district_outcomes: []const residents.DistrictOutcome,
};
const Parking = struct {
    facilities: []const parking.Facility,
    attempts: u32,
    successes: u32,
    fallbacks: u32,
    refusals: u32,
    revenue_today: f64,
    revenue_total: f64,
    kerbside_used: usize,
    batches_applied: u64,
    batches_dropped: u64,
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
    movement: []const f32,
    fare_cap: f64,
    subsidy: f64,
    subsidy_total: f64,
    // Slice 11: signalised junctions, their per-arm phases and timings.
    junctions: []const signals.Junction,
    placed_total: u32,
    removed_total: u32,
};
const Parked = struct {
    facilities: []const parking.Facility,
    attempts: u32,
    successes: u32,
    fallbacks: u32,
    refusals: u32,
    revenue_today: f64,
    revenue_total: f64,
    kerbside_used: usize,
    batches_applied: u64,
    batches_dropped: u64,
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
    periods: []const finance.Period,
    period_count: u32,
    period_opening: f64,
    period_receipts: f64,
    period_expenses: f64,
    period_entries: u32,
    period_week: u32,
};
const Services = struct {
    orders: []const contracts.Order,
    next_review: f64,
    current: []const agreements.Agreement,
    history: []const agreements.Agreement,
    history_count: usize,
    next_number: usize,
};
// Slice 18: the bounded private-development queue. The proposals are stored as
// their own JSON records and validated field by field, exactly like the
// agreement rings; `demand` is derived and therefore never saved.
const Development = struct {
    proposals: []const development.Proposal,
    count: u32,
    next_number: u32,
    lodged_total: u32,
    approved_total: u32,
    refused_total: u32,
    lapsed_total: u32,
    built_total: u32,
    levies_collected: f64,
    lodged_today: u32,
    building: usize,
    cursor: u8,
};
const State = struct {
    format: []const u8,
    version: u32,
    rules: []const u8,
    clock: Clock,
    camera: Camera,
    town: Town,
    citizens: Citizens,
    homes: []const households.Household,
    housing: []const housing.Unit,
    housing_moves_today: u32,
    housing_displacements_today: u32,
    housing_applications_today: u32,
    housing_failed_moves_today: u32,
    housing_rent_collected_today: f64,
    housing_ownership_collected_today: f64,
    housing_rent_collected_total: f64,
    housing_ownership_collected_total: f64,
    mobility: Mobility,
    parked: Parked,
    treasury: Treasury,
    services: Services,
    development: Development,
    trust: []const f32,
    history: []const game.Sample,
    history_count: usize,
};
var lane_values: [city.max_roads]u32 = undefined;
fn capture(speed: f32, resume_speed: f32, accumulator: f32) State {
    for (transport.lanes[0..city.road_count], 0..) |lane, i| lane_values[i] = lane;
    return .{
        .format = "Common Ground town",
        .version = 13,
        .rules = "bellwether-2027-11-v13",
        .clock = .{ .elapsed = game.elapsed, .speed = speed, .resume_speed = resume_speed, .accumulator = accumulator, .next_sample = game.next_sample, .next_routes = game.next_routes, .next_operating = game.next_operating, .next_week = game.next_week },
        .camera = .{ .x = scene.camera_x, .z = scene.camera_z, .zoom = scene.zoom, .angle = scene.angle },
        .town = .{ .revision = city.revision, .street_count = city.street_count, .nodes = city.nodes, .roads = city.roads, .buildings = city.lots(), .parcels = parcels.storage[0..parcels.count] },
        .parked = .{ .facilities = parking.facilities[0..parking.count], .attempts = parking.attempts, .successes = parking.successes, .fallbacks = parking.fallbacks, .refusals = parking.refusals, .revenue_today = parking.revenue_today, .revenue_total = parking.revenue_total, .kerbside_used = parking.kerbside_used, .batches_applied = residents.batches_applied, .batches_dropped = residents.batches_dropped },
        // Slice 15: the household and housing rolls are stored per placed lot,
        // matching `town.buildings`, so the unused tail of the lot array never
        // enters the snapshot.
        .homes = households.homes[0..city.lot_count],
        .housing = housing.units[0..city.lot_count],
        .housing_moves_today = housing.moves_today,
        .housing_displacements_today = housing.displacements_today,
        .housing_applications_today = housing.applications_today,
        .housing_failed_moves_today = housing.failed_moves_today,
        .housing_rent_collected_today = housing.rent_collected_today,
        .housing_ownership_collected_today = housing.ownership_collected_today,
        .housing_rent_collected_total = housing.rent_collected_total,
        .housing_ownership_collected_total = housing.ownership_collected_total,
        .citizens = .{ .people = &residents.people, .companies = residents.companies[0..residents.company_count], .walking = residents.walking, .employed = residents.employed, .pedestrians = residents.pedestrians[0..city.road_count], .district_outcomes = &residents.district_outcomes },
        .mobility = .{ .vehicles = &transport.vehicles, .lines = &transport.lines, .accounts = &operators.accounts, .observations = &transport.observations, .previous_observations = &transport.previous_observations, .lanes = lane_values[0..city.road_count], .occupancy = transport.occupancy[0..city.road_count], .queues = transport.queues[0..city.road_count], .congestion = transport.congestion[0..city.road_count], .movement = transport.movement[0..city.road_count], .fare_cap = transport.fare_cap, .subsidy = transport.subsidy, .subsidy_total = transport.subsidy_total, .junctions = signals.junctions[0..signals.count], .placed_total = signals.placed_total, .removed_total = signals.removed_total },
        .treasury = .{ .cash = finance.cash, .reserved = finance.reserved, .residential_rate = finance.residential_rate, .commercial_rate = finance.commercial_rate, .funding = finance.funding, .active_funding = finance.active_funding, .maintenance_paid = finance.maintenance_paid, .collected = finance.collected, .spent = finance.spent, .arrears = &finance.arrears, .entry_count = finance.entry_count, .entries = finance.entries[0..@min(finance.entry_count, finance.entries.len)], .periods = finance.periods[0..@min(finance.period_count, finance.periods.len)], .period_count = finance.period_count, .period_opening = finance.period_opening, .period_receipts = finance.period_receipts, .period_expenses = finance.period_expenses, .period_entries = finance.period_entries, .period_week = finance.period_week },
        .services = .{ .orders = contracts.orders[0..contracts.count], .next_review = contracts.next_review, .current = &agreements.agreements, .history = agreements.history[0..@min(agreements.history_count, agreements.history.len)], .history_count = agreements.history_count, .next_number = agreements.next_number },
        .development = .{ .proposals = development.storage[0..@min(@as(usize, development.count), development.storage.len)], .count = development.count, .next_number = development.next_number, .lodged_total = development.lodged_total, .approved_total = development.approved_total, .refused_total = development.refused_total, .lapsed_total = development.lapsed_total, .built_total = development.built_total, .levies_collected = development.levies_collected, .lodged_today = development.lodged_today, .building = development.building, .cursor = development.cursor },
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
        !agreements.validInterval(a.max_interval) or a.reason > 8 or a.route_version == 0 or
        !between(a.offered, 0, s.clock.elapsed) or !between(a.start, 0, s.clock.elapsed) or !between(a.ended, 0, s.clock.elapsed) or
        !between(a.updated, 0, s.clock.elapsed) or !between(a.regularity_updated, 0, s.clock.elapsed) or !between(a.regularity_time, 0, s.clock.elapsed) or
        a.delivered < 0 or a.expected < a.delivered or a.baseline < 0 or a.target < 0) return false;
    // Slice 5: cure-first service credit. Only delivered bus-seconds against the
    // windowed target integral can move money, and a waived balance is never debt.
    if (!between(a.breach_start, 0, s.clock.elapsed) or !between(a.cure_until, 0, s.clock.elapsed + agreements.cure_seconds + 0.001) or
        a.breach_days > 64 or a.credit_accrued < 0 or a.credit_paid < 0 or a.credit_waived < 0 or
        a.credit_accrued > agreements.creditCap(a) + 0.001 or a.credit_paid + a.credit_waived > a.credit_accrued + 0.011 or
        !between(a.settled_expected, 0, a.expected + 0.001) or !between(a.settled_delivered, 0, a.delivered + 0.001)) return false;
    if (a.breach_start == 0 and (a.cure_until != 0 or a.breach_days != 0)) return false;
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
        !between(c.next_week, c.elapsed, c.elapsed + calendar.seconds_per_week + 0.1) or
        !between(s.camera.zoom, 0.5, 12) or !between(s.camera.x, city.origin_x - 100, city.origin_x + city.size_x + 100) or !between(s.camera.z, city.origin_z - 100, city.origin_z + city.size_z + 100) or
        n < 2 or n > city.max_nodes or roads.len == 0 or roads.len > city.max_roads or town.street_count < 14 or town.street_count > city.max_roads + 14 or
        town.buildings.len != city.lot_count or town.parcels.len > parcels.max_parcels or town.parcels.len < city.lot_count or
        people.len != city.population or companies.len == 0 or companies.len > city.lot_count or
        m.vehicles.len != transport.vehicles.len or m.lines.len != transport.max_lines or m.accounts.len != 3 or
        m.observations.len != transport.max_lines or m.previous_observations.len != transport.max_lines or
        m.lanes.len != roads.len or m.occupancy.len != roads.len or m.queues.len != roads.len or m.congestion.len != roads.len or m.movement.len != roads.len or s.citizens.pedestrians.len != roads.len or s.citizens.district_outcomes.len != city.district_count or
        s.parked.facilities.len > parking.max_facilities or
        f.arrears.len != city.buildings.len or f.entries.len != @min(f.entry_count, 1024) or f.entry_count == 0 or
        s.trust.len != city.district_count or s.history.len != @min(s.history_count, 96) or
        services.orders.len > 64 or services.current.len != 8 or services.history.len != @min(services.history_count, 64) or services.next_number == 0) return false;
    if (!between(m.fare_cap, 0, 10) or !between(m.subsidy, 0, 10) or m.subsidy_total < 0 or
        f.cash < 0 or f.reserved < 0 or f.reserved > f.cash + 0.001 or f.funding > 2 or f.active_funding > 2 or
        !between(f.residential_rate, 0, 5) or !between(f.commercial_rate, 0, 5) or !between(f.maintenance_paid, 0, 1) or f.collected < 0 or f.spent < 0 or
        f.periods.len != @min(f.period_count, 12) or f.period_opening < 0 or f.period_receipts < 0 or f.period_expenses < 0 or f.period_week > 1000000000) return false;
    for (f.periods) |period| {
        if (period.week > 1000000000 or period.opening < 0 or period.receipts < 0 or period.expenses < 0 or period.closing < 0 or
            !near(period.closing, period.opening + period.receipts - period.expenses)) return false;
    }
    if (!near(f.period_opening + f.period_receipts - f.period_expenses, f.cash)) return false;
    for (f.arrears) |v| if (v < 0) return false;
    for (s.trust) |v| if (!between(v, 0, 100)) return false;
    for (s.citizens.district_outcomes) |d| {
        if (d.completed > d.wait_starts or d.abandoned > d.wait_starts - d.completed or d.abandoned_after_capacity > d.abandoned or d.wait_total < 0 or (d.completed == 0 and d.wait_total != 0)) return false;
    }
    for (&edges) |*row| @memset(row, -1);
    for (town.nodes) |node| if (!city.insideWindow(node.x, node.z, 0) or node.street >= town.street_count or !near(node.y, city.elevation(node.x, node.z))) return false;
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
    // The all-pairs routing tables are derived: `rebuildRoutes` reconstructs
    // them from the graph on load, so they are deliberately not part of the
    // snapshot. Writing them cost 53% of the file and made the node count the
    // thing that decided whether a town could be saved at all.
    for (town.buildings) |b| if (b.node >= n or b.district >= 12 or b.street >= town.street_count or !index(b.employer, companies.len) or b.width <= 0 or b.depth <= 0 or b.value < 0 or b.capacity > city.population or b.occupants > city.population or !between(b.sun, 0, 1)) return false;
    for (town.parcels) |p| if (p.node >= n or p.street >= town.street_count or p.zone > 5 or !index(p.building, town.buildings.len) or !index(p.block, 128) or p.width <= 0 or p.depth <= 0) return false;
    var riders: [transport.vehicles.len]usize = @splat(0);
    var employees: [city.buildings.len]usize = @splat(0);
    var occupants: [city.buildings.len]usize = @splat(0);
    for (people) |*p| {
        if (p.phase > 3 or p.mode > 3 or p.bus_stage > 2 or p.shift > 2 or p.routine > 5 or p.skill > 2 or p.node >= n or p.next >= n or p.destination >= n or p.origin >= n or p.car_node >= n or p.bike_node >= n or p.boarding >= n or p.exit_node >= n or
            p.home >= town.buildings.len or p.current_building >= town.buildings.len or p.origin_building >= town.buildings.len or p.destination_building >= town.buildings.len or
            !index(p.employer, companies.len) or !index(p.order, services.orders.len) or !index(p.bus_line, 8) or !index(p.bus, m.vehicles.len) or p.wallet < 0 or p.income < 0 or p.bus_wait < 0 or p.travel < 0 or p.last_trip < 0 or
            !between(p.bus_wait_start, -1, c.elapsed) or p.bus_full_mask > 7 or
            p.plan_mode > 3 or p.parked_vehicle > 2 or p.depart_bucket >= travel.bucket_count or
            p.plan_facility < -1 or p.park_facility < -1 or p.plan_facility >= @as(i32, @intCast(parking.max_facilities)) or p.park_facility >= @as(i32, @intCast(parking.max_facilities)) or
            p.via >= n or p.leg_target >= n or p.back >= n or p.last_outcome > 2 or
            p.last_facility != travel.no_facility and p.last_facility >= s.parked.facilities.len or
            !between(p.cross_wait, 0, 1e6) or p.cross_waits > 1000000000 or p.crossings > 1000000000 or
            p.park_tries > 1000000000 or p.park_taken > 1000000000 or p.park_searched > 1000000000 or p.park_refused > 1000000000) return false;
        if (p.park_facility >= 0 and @as(usize, @intCast(p.park_facility)) >= s.parked.facilities.len) return false;
        for (0..travel.memory_count) |memory| {
            if (p.model.facility[memory] != travel.no_facility and p.model.facility[memory] >= s.parked.facilities.len) return false;
        }
        const waiting = p.mode == 3 and p.phase == 1 and p.bus < 0 and p.bus_stage == 0 and p.node == p.next and p.node == p.boarding;
        // A resident can reach the stop one fixed step before beginWait records
        // the wait. An active timestamp must still belong to a waiting person.
        if (p.bus_wait_start >= 0 and !waiting) return false;
        if (p.mode == 3 and p.bus_line < 0) return false;
        if (p.node != p.next and edges[p.node][p.next] < 0) return false;
        if (p.bus_stage == 1 and p.bus < 0) return false;
        if (p.order >= 0 and (!p.crew or p.employer < 0 or companies[@intCast(p.employer)].order != p.order)) return false;
        // Slice 8: an employed resident's posted wage is exactly their employer's
        // posted wage; a jobseeker has no wage at all.
        if (p.employer >= 0) {
            employees[@intCast(p.employer)] += 1;
            if (!near(p.income, companies[@intCast(p.employer)].wage)) return false;
        } else if (p.income != 0) return false;
        occupants[p.home] += 1;
        if (p.bus >= 0) {
            const id: usize = @intCast(p.bus);
            if (id < city.population or p.mode != 3 or p.bus_stage != 1 or !m.vehicles[id].active or m.vehicles[id].line != p.bus_line) return false;
            riders[id] += 1;
        }
    }
    var employed: usize = 0;
    for (companies, 0..) |*company, i| {
        if (company.building >= town.buildings.len or company.cash < 0 or company.costs < 0 or company.margin < 1 or company.labour <= 0 or company.crew_count > 4 or company.employees != employees[i] or company.employees > company.capacity or !index(company.order, services.orders.len) or town.buildings[company.building].employer != @as(i32, @intCast(i)) or company.wage <= 0 or company.wage > 1000 or company.skill_required > 2 or company.wage_arrears < 0 or company.wage_arrears > @as(f64, @floatFromInt(company.employees)) * company.wage + 0.001 or !between(company.staffing_pressure, 0, 1)) return false;
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
    // Slice 7 household conservation: members and income must match the live
    // resident population, balances and arrears stay explicit and non-negative.
    if (s.homes.len != town.buildings.len) return false;
    var members_sum: usize = 0;
    for (s.homes, 0..) |*h, i| {
        if (!h.present) {
            if (h.members != 0 or h.balance != 0 or h.income != 0 or h.essential != 0 or h.arrears != 0 or h.paid != 0 or h.unpaid != 0) return false;
            continue;
        }
        if (h.members == 0 or h.members > city.population or h.balance < 0 or h.income < 0 or h.paid_wages < 0 or h.paid_wages > h.income + 0.011 or h.essential < 0 or h.arrears < 0 or h.paid < 0 or h.unpaid < 0) return false;
        if (!near(h.unpaid, h.arrears)) return false;
        if (occupants[i] != h.members) return false;
        var income: f64 = 0;
        for (people) |*p| if (p.home == i and p.employer >= 0) {
            income += p.income;
        };
        if (!near(h.income, income)) return false;
        members_sum += h.members;
    }
    if (members_sum != people.len) return false;
    // Slice 9 housing: units exist only on authored home buildings, occupancy
    // must match the live household member count, and all housing money stays
    // explicit and non-negative.
    if (s.housing.len != town.buildings.len) return false;
    if (s.housing_moves_today > 1000000000 or s.housing_displacements_today > s.housing_moves_today or
        s.housing_applications_today > 1000000000 or s.housing_failed_moves_today > s.housing_applications_today or
        s.housing_rent_collected_today < 0 or s.housing_ownership_collected_today < 0 or
        s.housing_rent_collected_total < 0 or s.housing_ownership_collected_total < 0 or
        s.housing_rent_collected_today > s.housing_rent_collected_total + 0.011 or
        s.housing_ownership_collected_today > s.housing_ownership_collected_total + 0.011) return false;
    for (s.housing, 0..) |*unit, i| {
        if (unit.application != -1 and !index(unit.application, town.buildings.len)) return false;
        if (unit.application >= 0 and !s.housing[@intCast(unit.application)].present) return false;
        if (!unit.present) {
            if (unit.tenure != .owned or unit.rent != 0 or unit.ownership_cost != 0 or unit.owner_cash != 0 or
                unit.arrears != 0 or unit.occupants != 0 or unit.application != -1 or unit.move_state != .idle or
                unit.paid_rent != 0 or unit.paid_ownership != 0) return false;
            continue;
        }
        // Slice 17: an apartment is a dwelling too. The housing, household and
        // finance modules all ask `city.isHome`, so the snapshot validator has
        // to ask the same question or a town with apartments can be written but
        // never read back.
        if (!city.isHome(town.buildings[i].kind) or unit.rent <= 0 or unit.ownership_cost <= 0 or
            unit.owner_cash < 0 or unit.arrears < 0 or unit.paid_rent < 0 or unit.paid_ownership < 0 or
            unit.owner_cash < unit.paid_rent + unit.paid_ownership - 0.011 or
            unit.occupants != town.buildings[i].occupants or unit.occupants > city.population or
            @intFromEnum(unit.move_state) > 4) return false;
        if (town.buildings[i].occupants == 0 and unit.application != -1) return false;
    }
    // Slice 18 development proposals: every applicant names a real authored
    // vacant lot, its numbers stay inside the rules, and the queue never
    // exceeds its own bounds. Nothing here creates money: the levy is only
    // ever the value that was recorded when the permit was granted.
    const d = &s.development;
    if (d.proposals.len != @min(@as(usize, d.count), development.max_proposals)) return false;
    if (d.next_number == 0 or d.next_number != d.count + 1 or d.lodged_total != d.count) return false;
    if (d.approved_total + d.refused_total + d.lapsed_total > d.count or d.built_total > d.approved_total) return false;
    if (d.building > d.approved_total - d.built_total or d.building > development.max_pending) return false;
    if (d.levies_collected < 0 or d.lodged_today > development.max_lodged_per_day or d.cursor >= city.district_count) return false;
    var open_applications: usize = 0;
    for (d.proposals) |*p| {
        if (p.number == 0 or p.number >= d.next_number) return false;
        if (p.parcel >= town.parcels.len or p.building >= town.buildings.len or p.parcel != p.building) return false;
        if (p.district >= city.district_count or p.zone < 1 or p.zone > 4) return false;
        if (@intFromEnum(p.decision) > 4 or @intFromEnum(p.reason) > 6) return false;
        if (p.kind > @intFromEnum(city.Kind.plaza)) return false;
        if (p.height < 0 or p.value < 0 or p.capacity > city.population) return false;
        if (p.levy < 0 or p.levy > p.value * development.levy_rate + 0.011) return false;
        if (!between(p.offered, 160, c.elapsed) or p.deadline < p.offered or p.decided < 0 or p.complete < 0) return false;
        if (p.decided > c.elapsed or p.complete > c.elapsed + 6 * development.days + 0.001) return false;
        if (!std.math.isFinite(p.pressure) or p.pressure < 0 or p.pressure > 1000) return false;
        if (p.decision == .offered) open_applications += 1;
    }
    if (open_applications > development.max_pending) return false;
    // Slice 10 parking: every facility is bounded, occupancy never exceeds the
    // slot count, and the aggregate counters stay ordered.
    if (s.parked.attempts > 1000000000 or s.parked.successes > s.parked.attempts or s.parked.fallbacks > s.parked.attempts or
        s.parked.refusals > s.parked.attempts or s.parked.revenue_today < 0 or s.parked.revenue_total < 0 or
        s.parked.revenue_today > s.parked.revenue_total + 0.011 or s.parked.kerbside_used > s.parked.facilities.len or
        s.parked.batches_applied > 1000000000000 or s.parked.batches_dropped > 1000000000000) return false;
    for (s.parked.facilities) |*facility| {
        if (facility.slots == 0 or facility.slots > 1000 or facility.occupied > facility.slots or facility.price < 0 or facility.price > parking.kerbside_price_cap + 0.001) return false;
        if (@intFromEnum(facility.kind) > 1) return false;
        if (facility.building >= 0) {
            if (!index(facility.building, town.buildings.len) or facility.road >= 0 or town.buildings[@intCast(facility.building)].kind != (if (facility.kind == .bike) city.Kind.bike_park else city.Kind.car_park)) return false;
        } else if (facility.road >= 0) {
            if (facility.road >= roads.len or facility.kind != .car or facility.node != roads[@intCast(facility.road)].a) return false;
        } else return false;
        if (facility.node >= n) return false;
    }
    for (m.movement) |value| if (!between(value, 0, 1e6)) return false;
    // Slice 11 signals: bounded junction count, valid node and arm roads, and
    // green/yellow inside the editor's own limits.
    if (m.junctions.len > signals.max_junctions or m.placed_total > 1000000 or m.removed_total > 1000000) return false;
    for (m.junctions) |junction| {
        if (junction.node >= n or junction.arm_count == 0 or junction.arm_count > signals.max_arms) return false;
        if (!between(junction.green, signals.min_green, signals.max_green) or
            !between(junction.yellow, signals.min_yellow, signals.max_yellow) or
            !between(junction.offset, 0, 60)) return false;
        // Slice 12: the granular properties and the coordination fields.
        if (!between(junction.red, signals.min_red, signals.max_red) or
            !between(junction.delay, signals.min_delay, signals.max_delay) or
            !between(junction.flash_start, 0, 24) or
            !between(junction.flash_end, 0, 24) or
            junction.group < -1 or junction.group >= signals.max_groups or
            junction.preempt_until < 0) return false;
        _ = @intFromEnum(junction.flash);
        _ = @intFromEnum(junction.preempt);
        for (junction.arms[0..junction.arm_count]) |arm| {
            if (arm < 0 or arm >= roads.len) return false;
            const road = roads[@intCast(arm)];
            if (road.a != junction.node and road.b != junction.node) return false;
        }
    }
    for (m.vehicles, 0..) |v, i| {
        if (v.node >= n or v.next >= n or v.target >= n or v.company >= 3 or v.lane > 1 or !index(v.line, 8) or v.stop >= 16 or !between(v.dwell, 0, 5) or v.speed < 0 or v.progress < 0 or v.passengers != riders[i] or v.passengers > 24 or (!v.active and v.passengers != 0)) return false;
        if (i < city.population) {
            // Parked personal cars never hold an owned bus unit.
            if (v.unit != -1) return false;
        } else {
            if (v.unit < -1 or v.unit >= operators.max_units) return false;
            if (v.active and v.unit < 0) return false;
            if (v.unit >= 0) {
                const owner = m.accounts[v.company].units[@intCast(v.unit)];
                if (!owner.present or owner.bus != @as(i32, @intCast(i))) return false;
            }
        }
        if (v.unit != -1) {
            if (i < city.population or v.unit >= operators.max_units) return false;
            const owner = m.accounts[v.company].units[@intCast(v.unit)];
            if (!owner.present or owner.bus != @as(i32, @intCast(i))) return false;
        } else if (i >= city.population and v.active) return false;
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
    const opening = [_]f64{ 600, 300, 5 };
    const depots = [_]usize{ 6, 5, 3 };
    for (m.accounts, 0..) |account, i| {
        if (account.opening != opening[i] or account.depot != depots[i] or
            account.day > 12 or account.night > account.day or account.cash < 0 or account.fares < 0 or account.subsidies < 0 or account.receipts < 0 or
            account.vehicle < 0 or account.labour < 0 or account.purchases < 0 or account.sales < 0 or account.recruitment < 0 or account.severance < 0 or account.maintenance < 0 or account.credits < 0) return false;
        const expected = account.opening + account.fares + account.subsidies + account.receipts + account.sales -
            account.purchases - account.recruitment - account.severance - account.maintenance - account.vehicle - account.labour - account.credits;
        if (!near(account.cash, expected)) return false;
        var present: usize = 0;
        for (account.units, 0..) |unit, slot| {
            if (!unit.present) {
                if (unit.bus != -1 or unit.service or unit.paid or unit.service_end != 0 or unit.condition != 100) return false;
                continue;
            }
            present += 1;
            if (!between(unit.condition, 0, 100) or !between(unit.service_end, 0, c.elapsed + operators.maintenance_seconds + 0.001) or !index(unit.bus, m.vehicles.len)) return false;
            if (unit.paid and !unit.service) return false;
            if (unit.service and unit.bus >= 0 and !m.vehicles[@intCast(unit.bus)].retiring) return false;
            if (unit.bus >= 0) {
                const bus: usize = @intCast(unit.bus);
                if (bus < city.population or m.vehicles[bus].unit != @as(i32, @intCast(slot)) or m.vehicles[bus].company != i) return false;
            }
        }
        if (present > account.depot) return false;
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
        // Money actually received must appear in the retained ledger; a credit
        // whose records have already rolled out is allowed to be unpaid here.
        var recorded: f64 = 0;
        const first_entry = f.entry_count - f.entries.len;
        for (first_entry..f.entry_count) |entry| {
            const e = f.entries[entry % 1024];
            if (e.kind == 10 and e.party == @as(i32, @intCast(a.company)) and e.order == @as(i32, @intCast(a.number))) recorded += e.amount;
        }
        if (recorded > a.credit_paid + 0.011) return false;
        if (recorded < a.credit_paid - 0.011 and f.entry_count - f.entries.len <= 0) return false;
        reserved += a.reserved;
    }
    for (services.history, 0..) |*a, i| {
        if (!validAgreement(a, s, true)) return false;
        const current = &services.current[a.line];
        if (current.number == a.number and !std.meta.eql(current.*, a.*)) return false;
        for (services.history[0..i]) |old| if (old.number == a.number) return false;
        var recorded: f64 = 0;
        const first_entry = f.entry_count - f.entries.len;
        for (first_entry..f.entry_count) |entry| {
            const e = f.entries[entry % 1024];
            if (e.kind == 10 and e.party == @as(i32, @intCast(a.company)) and e.order == @as(i32, @intCast(a.number))) recorded += e.amount;
        }
        if (recorded > a.credit_paid + 0.011) return false;
        if (recorded < a.credit_paid - 0.011 and f.entry_count - f.entries.len <= 0) return false;
    }
    if (!near(f.reserved, reserved) or !near(f.entries[(f.entry_count - 1) % 1024].balance, f.cash)) return false;
    const first = f.entry_count - f.entries.len;
    for (first..f.entry_count) |i| {
        const e = f.entries[i % 1024];
        if (!between(e.time, 0, c.elapsed) or e.kind > 12 or e.balance < 0) return false;
        switch (e.kind) {
            1, 2 => if (e.party < 0 or !index(e.party, town.buildings.len) or e.order != -1) return false,
            5, 6 => if (e.party < 0 or !index(e.party, companies.len) or e.order < 0 or !index(e.order, services.orders.len)) return false,
            8, 10 => if (e.party < 0 or !index(e.party, 3) or e.order < 1 or e.order >= services.next_number) return false,
            11 => if (e.party != -1 or e.order != -1 or e.amount < 0) return false,
            // Slice 18: the development levy names its own application number.
            12 => if (e.party != -1 or e.order < 1 or e.order >= @as(i32, @intCast(d.next_number)) or e.amount < 0) return false,
            9 => if (e.party < 0 or !index(e.party, town.street_count) or e.order != -1) return false,
            else => if (e.party != -1 or e.order != -1) return false,
        }
        if (i > first and (!near(e.balance, f.entries[(i - 1) % 1024].balance + e.amount) or e.time < f.entries[(i - 1) % 1024].time)) return false;
    }
    for (s.history) |sample| if (!between(sample.time, 0, c.elapsed) or sample.cash < 0 or sample.reserved < 0 or sample.reserved > sample.cash + 0.001 or sample.walking > people.len or !between(sample.condition, 0, 100)) return false;
    return true;
}
fn commit(s: *const State) void {
    @memcpy(city.buildings[0..s.town.buildings.len], s.town.buildings);
    @memset(city.buildings[s.town.buildings.len..], std.mem.zeroes(city.Building));
    city.lot_count = s.town.buildings.len;
    city.restoreGraph(s.town.nodes, s.town.roads);
    city.revision = s.town.revision;
    city.street_count = s.town.street_count;
    city.rebuildRoutes();
    parcels.count = s.town.parcels.len;
    @memcpy(parcels.storage[0..parcels.count], s.town.parcels);
    parcels.rebuildBlocks();
    parcels.selected = -1;
    parcels.visible = false;
    @memcpy(households.homes[0..s.homes.len], s.homes);
    @memset(households.homes[s.homes.len..], .{});
    @memcpy(housing.units[0..s.housing.len], s.housing);
    @memset(housing.units[s.housing.len..], .{});
    housing.moves_today = s.housing_moves_today;
    housing.displacements_today = s.housing_displacements_today;
    housing.applications_today = s.housing_applications_today;
    housing.failed_moves_today = s.housing_failed_moves_today;
    housing.rent_collected_today = s.housing_rent_collected_today;
    housing.ownership_collected_today = s.housing_ownership_collected_today;
    housing.rent_collected_total = s.housing_rent_collected_total;
    housing.ownership_collected_total = s.housing_ownership_collected_total;
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
    @memcpy(transport.movement[0..city.road_count], m.movement);
    parking.count = s.parked.facilities.len;
    @memcpy(parking.facilities[0..parking.count], s.parked.facilities);
    parking.attempts = s.parked.attempts;
    parking.successes = s.parked.successes;
    parking.fallbacks = s.parked.fallbacks;
    parking.refusals = s.parked.refusals;
    parking.revenue_today = s.parked.revenue_today;
    parking.revenue_total = s.parked.revenue_total;
    parking.kerbside_used = s.parked.kerbside_used;
    parking.dues = 0;
    residents.batches_applied = s.parked.batches_applied;
    residents.batches_dropped = s.parked.batches_dropped;
    transport.fare_cap = m.fare_cap;
    transport.subsidy = m.subsidy;
    transport.subsidy_total = m.subsidy_total;
    signals.count = m.junctions.len;
    @memcpy(signals.junctions[0..signals.count], m.junctions);
    signals.placed_total = m.placed_total;
    signals.removed_total = m.removed_total;
    scene.selected_signal = -1;
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
    finance.period_count = f.period_count;
    @memcpy(finance.periods[0..f.periods.len], f.periods);
    finance.period_opening = f.period_opening;
    finance.period_receipts = f.period_receipts;
    finance.period_expenses = f.period_expenses;
    finance.period_entries = f.period_entries;
    finance.period_week = f.period_week;
    contracts.count = s.services.orders.len;
    @memcpy(contracts.orders[0..contracts.count], s.services.orders);
    contracts.next_review = s.services.next_review;
    @memcpy(&agreements.agreements, s.services.current);
    agreements.history_count = s.services.history_count;
    @memcpy(agreements.history[0..s.services.history.len], s.services.history);
    agreements.next_number = s.services.next_number;
    const d = &s.development;
    development.storage = @splat(.{});
    @memcpy(development.storage[0..d.proposals.len], d.proposals);
    development.count = d.count;
    development.next_number = d.next_number;
    development.lodged_total = d.lodged_total;
    development.approved_total = d.approved_total;
    development.refused_total = d.refused_total;
    development.lapsed_total = d.lapsed_total;
    development.built_total = d.built_total;
    development.levies_collected = d.levies_collected;
    development.lodged_today = d.lodged_today;
    development.building = d.building;
    development.cursor = d.cursor;
    development.measure();
    game.elapsed = s.clock.elapsed;
    game.next_sample = s.clock.next_sample;
    game.next_routes = s.clock.next_routes;
    game.next_operating = s.clock.next_operating;
    game.next_week = s.clock.next_week;
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
const Header = struct { format: []const u8, version: u32, rules: []const u8 };
fn supported(version: u32, rules: []const u8) bool {
    return version == 13 and std.mem.eql(u8, rules, "bellwether-2027-11-v13");
}
// A file whose metadata already declares another schema is incompatible, not
// malformed. This second scan runs only after the strict parse has failed, so a
// genuine town still pays a single parse.
fn incompatibleHeader(length: usize) bool {
    var fixed = std.heap.FixedBufferAllocator.init(&parse_memory);
    const parsed = std.json.parseFromSlice(Header, fixed.allocator(), buffer[0..length], .{ .max_value_len = 1024, .allocate = .alloc_always, .ignore_unknown_fields = true }) catch return false;
    defer parsed.deinit();
    return !std.mem.eql(u8, parsed.value.format, "Common Ground town") or !supported(parsed.value.version, parsed.value.rules);
}
// 0 success, 1 size, 2 malformed/bounded-parser failure, 3 incompatible, 4 inconsistent.
pub fn load(length: usize) u32 {
    if (length == 0 or length > capacity) return 1;
    var fixed = std.heap.FixedBufferAllocator.init(&parse_memory);
    const parsed = std.json.parseFromSlice(State, fixed.allocator(), buffer[0..length], .{ .max_value_len = 1024, .allocate = .alloc_always }) catch return if (incompatibleHeader(length)) 3 else 2;
    defer parsed.deinit();
    const state = &parsed.value;
    if (!std.mem.eql(u8, state.format, "Common Ground town") or !supported(state.version, state.rules)) return 3;
    if (!validate(state)) return 4;
    commit(state);
    return 0;
}
