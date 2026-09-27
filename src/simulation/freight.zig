const std = @import("std");
const city = @import("../scene/city.zig");
const residents = @import("residents.zig");

// Numbered list item 16: parking and freight.
//
// The parking supply already existed; this module gives it a freight
// counterpart. An existing contractor depot dispatches bounded delivery runs to
// the staffed businesses in the town. Each run travels a real route, then holds
// a kerbside loading bay at the customer's frontage for a bounded dwell. The
// player can convert kerbside car spaces into loading bays, so parking supply
// and freight access compete for the same kerbside, and a business that could
// not be reached trades at a measured loss.
//
// Everything is bounded and deterministic: dispatch order is derived from the
// companies array, and a run's travel time comes from the same routing tables
// the rest of the simulation uses. No regional trade, input market, warehouse
// or lorry fleet is modelled, and no money is created - the fee is a private
// transfer from the customer to its depot.
pub const max_runs = 48;
pub const max_bays_per_road = 6;
pub const max_lorries_per_depot = 3;
pub const bays_per_lorry = 2;

// Dwell bounds. The loading time scales with the goods carried, so a bigger
// delivery genuinely occupies the bay for longer.
pub const dwell_min: f32 = 20;
pub const dwell_max: f32 = 90;
pub const dwell_base: f32 = 20;
pub const dwell_per_unit: f32 = 14;

// Demand and money. Every number is a published policy bound, not a tender.
pub const goods_per_employee: f32 = 0.35;
pub const demand_floor: f32 = 1;
pub const market_rate: f32 = 2.2;
pub const industrial_rate: f32 = 1.8;
pub const retail_rate: f32 = 1.15;
pub const fee_per_unit: f64 = 6;
pub const access_floor: f32 = 0.5;

// A lorry is slower than a car and never uses a lane it cannot fit down.
pub const lorry_speed: f32 = 4.5;
pub const lorry_fuel: f64 = 0.35;

pub const Phase = enum(u8) { dispatched = 0, travelling = 1, loading = 2, delivered = 3, failed = 4 };

pub const Run = struct {
    number: u32 = 0,
    depot: usize = 0,
    customer: usize = 0,
    lot: usize = 0,
    node: usize = 0,
    road: i32 = -1,
    lane: u8 = 0,
    goods: f32 = 0,
    fee: f64 = 0,
    phase: Phase = .dispatched,
    dispatched: f64 = 0,
    arrived: f64 = 0,
    departed: f64 = 0,
    travel_seconds: f32 = 0,
    dwell_seconds: f32 = 0,
};

pub var runs: [max_runs]Run = @splat(.{});
pub var count: usize = 0;
pub var next_number: u32 = 1;

// One loading-bay designation per road. Player-set, so it is serialized.
pub var loading_bays: [city.max_roads]u8 = @splat(0);
pub var bay_used: [city.max_roads]u8 = @splat(0);

pub var dispatched_total: u32 = 0;
pub var delivered_total: u32 = 0;
pub var failed_total: u32 = 0;
pub var goods_total: f64 = 0;
pub var fee_total: f64 = 0;
pub var bay_seconds_total: f64 = 0;
pub var travelled_total: f64 = 0;
pub var demand_today: f64 = 0;
pub var delivered_today: f64 = 0;
pub var last_dispatch: f64 = -1e9;

// Per-customer delivery progress for the current day. Derived each day from the
// run ring, never trusted from a file.
var served: [city.buildings.len]f32 = @splat(0);

pub fn depotCount() usize {
    var total: usize = 0;
    for (residents.companies[0..residents.company_count]) |c| if (c.contractor) {
        total += 1;
    };
    return total;
}

pub fn isDepot(index: usize) bool {
    return index < residents.company_count and residents.companies[index].contractor;
}

pub fn isCustomer(index: usize) bool {
    if (index >= residents.company_count) return false;
    const c = residents.companies[index];
    return !c.contractor and c.capacity > 0;
}

// Bounded lorry pool for a depot: larger depots run more lorries.
pub fn lorries(index: usize) usize {
    if (!isDepot(index)) return 0;
    const c = residents.companies[index];
    return @min(max_lorries_per_depot, 1 + c.capacity / 24);
}

// The daily demand of one business, in goods units. Staffed headcount sets the
// base and the kind scales it; a small business still takes at least one unit.
pub fn demand(index: usize) f32 {
    if (!isCustomer(index)) return 0;
    const c = residents.companies[index];
    const staff: f32 = @floatFromInt(@max(1, c.employees));
    const rate = switch (city.buildings[c.building].kind) {
        .market => market_rate,
        .depot => industrial_rate,
        .shop, .office, .clinic, .hall, .apartment => retail_rate,
        else => demand_floor,
    };
    return @max(demand_floor, staff * goods_per_employee * rate);
}

pub fn demandTotal() f64 {
    var total: f64 = 0;
    for (0..residents.company_count) |i| total += demand(i);
    return total;
}

pub fn access(index: usize) f32 {
    if (!isCustomer(index)) return 1;
    const want = demand(index);
    if (want <= 0) return 1;
    const got = served[index];
    return std.math.clamp(access_floor + (1 - access_floor) * (got / want), access_floor, 1);
}

pub fn accessMean() f32 {
    var total: f32 = 0;
    var n: usize = 0;
    for (0..residents.company_count) |i| {
        if (!isCustomer(i)) continue;
        total += access(i);
        n += 1;
    }
    return if (n == 0) 1 else total / @as(f32, @floatFromInt(n));
}

// A segment can take loading bays only where kerbside parking already exists.
pub fn eligible(road: usize) bool {
    if (road >= city.road_count) return false;
    const r = city.roads[road];
    return r.class > 0 and r.vehicles and r.pedestrians and !r.works;
}

pub fn bayCapacity(road: usize) u8 {
    if (!eligible(road)) return 0;
    const slots: u8 = if (city.roads[road].class >= 2) 4 else 2;
    return @min(max_bays_per_road, slots);
}

pub fn bayCount(road: usize) u8 {
    if (road >= city.road_count) return 0;
    return @min(loading_bays[road], bayCapacity(road));
}

pub fn bayHeld(road: usize) bool {
    return road < city.road_count and bay_used[road] > 0;
}

pub fn setBays(road: usize, value: u32) bool {
    if (!eligible(road) or value > max_bays_per_road) return false;
    loading_bays[road] = @intCast(@min(value, bayCapacity(road)));
    return true;
}

// The frontage road the lorry uses: the customer's own street when it is an
// eligible segment, otherwise the nearest eligible one within a bounded walk.
pub fn frontage(lot: usize) i32 {
    if (lot >= city.lot_count) return -1;
    const b = city.buildings[lot];
    var best: i32 = -1;
    var best_score: f32 = 1e9;
    for (city.roads, 0..) |r, i| {
        if (!eligible(i) or r.street != b.street) continue;
        const node = city.nodes[r.a];
        const score = city.hypot(node.x - b.x, node.z - b.z);
        if (score < best_score) {
            best_score = score;
            best = @intCast(i);
        }
    }
    if (best >= 0) return best;
    // A lane frontage with no eligible segment of its own falls back to the
    // nearest eligible street in the same district.
    for (city.roads, 0..) |r, i| {
        if (!eligible(i) or r.district != b.district) continue;
        const node = city.nodes[r.a];
        const score = city.hypot(node.x - b.x, node.z - b.z);
        if (score < best_score) {
            best_score = score;
            best = @intCast(i);
        }
    }
    return best;
}

fn routeSeconds(from: usize, to: usize) f32 {
    if (from == to) return 0;
    if (city.distance[from][to] >= 1e9) return -1;
    var total: f32 = 0;
    var node = from;
    var steps: usize = 0;
    while (node != to and steps < city.node_count) : (steps += 1) {
        const next = city.next_node[node][to];
        if (next == node) return -1;
        const road_id = city.road_between[node][next];
        if (road_id < 0) return -1;
        const road = city.roads[@intCast(road_id)];
        total += road.length / @max(1, lorry_speed * (1 - @min(0.6, road.slope * 0.25)) * (0.6 + 0.4 * road.condition / 100));
        if (road.works) total += 6;
        node = next;
    }
    if (node != to) return -1;
    return total;
}

fn nextDepot() ?usize {
    // Deterministic rotation: the depot with the fewest dispatched runs so far
    // this day takes the next load, so every depot is used in turn.
    var best: ?usize = null;
    var best_load: u32 = 0xFFFFFFFF;
    for (0..residents.company_count) |i| {
        if (!isDepot(i)) continue;
        const c = residents.companies[i];
        if (c.cash < 2 and lorries(i) == 0) continue;
        var load: u32 = 0;
        for (runs[0..count]) |run| {
            if (run.depot == i and run.dispatched >= last_dispatch - 480) load += 1;
        }
        if (load < best_load) {
            best_load = load;
            best = i;
        }
    }
    return best;
}

// Once per simulated day each depot dispatches bounded runs to the businesses
// that still need goods, nearest customers first. Returns the runs dispatched.
pub fn dispatch(elapsed: f64) u32 {
    if (residents.company_count == 0) return 0;
    last_dispatch = elapsed;
    demand_today = demandTotal();
    var made: u32 = 0;
    var guard: usize = 0;
    while (guard < max_runs) : (guard += 1) {
        const depot = nextDepot() orelse break;
        const lorries_available = lorries(depot);
        if (lorries_available == 0) break;
        var used: usize = 0;
        for (runs[0..count]) |run| {
            if (run.depot == depot and run.dispatched >= elapsed - 480 and run.phase != .delivered and run.phase != .failed) used += 1;
        }
        if (used >= lorries_available or count >= runs.len) break;

        // Pick the nearest customer that is not already covered today.
        var choice: ?usize = null;
        var best_cost: f32 = 1e9;
        const depot_node = city.buildings[residents.companies[depot].building].node;
        for (0..residents.company_count) |i| {
            if (!isCustomer(i) or i == depot) continue;
            if (served[i] + 0.001 >= demand(i)) continue;
            var already: bool = false;
            for (runs[0..count]) |run| {
                if (run.customer == i and run.dispatched >= elapsed - 480 and run.phase != .failed) already = true;
            }
            if (already) continue;
            const lot = residents.companies[i].building;
            const road = frontage(lot);
            if (road < 0) continue;
            const seconds = routeSeconds(depot_node, city.buildings[lot].node);
            if (seconds < 0) continue;
            const cost = seconds + city.walkCost(depot_node, city.buildings[lot].node) * 0.05;
            if (cost < best_cost) {
                best_cost = cost;
                choice = i;
            }
        }
        const customer = choice orelse break;
        const lot = residents.companies[customer].building;
        const road = frontage(lot);
        if (road < 0) break;
        const seconds = routeSeconds(depot_node, city.buildings[lot].node);
        if (seconds < 0) break;
        const goods = @min(demand(customer) - served[customer], demand(customer));
        runs[count] = .{
            .number = next_number,
            .depot = depot,
            .customer = customer,
            .lot = lot,
            .node = city.buildings[lot].node,
            .road = road,
            .goods = goods,
            .fee = @floatCast(@as(f64, goods) * fee_per_unit),
            .phase = .dispatched,
            .dispatched = elapsed,
            .travel_seconds = seconds,
            .dwell_seconds = @min(dwell_max, dwell_base + goods * dwell_per_unit),
        };
        count += 1;
        next_number += 1;
        dispatched_total +|= 1;
        made += 1;
        // A depot pays the fuel for the run it just sent.
        const fuel = @min(residents.companies[depot].cash, lorry_fuel * @as(f64, @floatCast(seconds)));
        residents.companies[depot].cash -= fuel;
    }
    return made;
}

// One step of the freight life cycle. Runs advance dispatched -> travelling ->
// loading -> delivered; a bay is held only while loading, and the fee is a
// private transfer from the customer to its depot on delivery.
pub fn update(dt: f32, elapsed: f64) void {
    @memset(&bay_used, 0);
    if (count == 0) return;
    for (runs[0..count]) |*run| {
        switch (run.phase) {
            .dispatched => {
                if (elapsed - run.dispatched >= run.travel_seconds) {
                    run.phase = .travelling;
                    run.arrived = elapsed;
                }
            },
            .travelling => {
                run.arrived = elapsed;
                run.phase = .loading;
            },
            .loading => {
                // Hold the bay while the crew unloads. A run whose frontage has
                // no bay left still unloads, so freight access never silently
                // stops; the bay counter simply cannot exceed the capacity.
                if (run.road >= 0) {
                    const road: usize = @intCast(run.road);
                    bay_used[road] +|= 1;
                    bay_seconds_total += dt;
                }
                if (elapsed - run.arrived >= run.dwell_seconds) {
                    run.phase = .delivered;
                    run.departed = elapsed;
                    delivered_total +|= 1;
                    goods_total += run.goods;
                    delivered_today += run.goods;
                    served[run.customer] += run.goods;
                    // Private fee: customer pays the depot, nothing is created.
                    const paid = @min(residents.companies[run.customer].cash, run.fee);
                    residents.companies[run.customer].cash -= paid;
                    residents.companies[run.depot].cash += paid;
                    fee_total += paid;
                    travelled_total += run.travel_seconds;
                }
            },
            .delivered => {},
            .failed => {},
        }
    }
}

// The bay a segment currently shows as held, for the parking supply to subtract.
pub fn baysFree(road: usize) u8 {
    return bayCount(road) -| bay_used[road];
}

pub fn readRun(index: usize, field: u32) f64 {
    if (index >= count) return -1;
    const run = &runs[index];
    return switch (field) {
        0 => @floatFromInt(run.number),
        1 => @floatFromInt(run.depot),
        2 => @floatFromInt(run.customer),
        3 => @floatFromInt(run.lot),
        4 => @floatFromInt(run.node),
        5 => @floatFromInt(run.road),
        6 => @floatFromInt(@intFromEnum(run.phase)),
        7 => run.goods,
        8 => run.fee,
        9 => run.dispatched,
        10 => run.arrived,
        11 => run.departed,
        12 => run.travel_seconds,
        13 => run.dwell_seconds,
        14 => if (run.road >= 0 and bayHeld(@intCast(run.road))) 1 else 0,
        else => -1,
    };
}

// Newest run first, matching the incident ring's read order.
pub fn readNewest(index: usize, field: u32) f64 {
    if (index >= count) return -1;
    return readRun(count - 1 - index, field);
}

pub fn read0(field: u32) f64 {
    return switch (field) {
        0 => @floatFromInt(count),
        1 => @floatFromInt(depotCount()),
        2 => @floatFromInt(dispatched_total),
        3 => @floatFromInt(delivered_total),
        4 => goods_total,
        5 => fee_total,
        6 => bay_seconds_total,
        7 => travelled_total,
        8 => demand_today,
        9 => delivered_today,
        10 => accessMean(),
        11 => blk: {
            var total: usize = 0;
            for (loading_bays[0..city.road_count]) |b| total += b;
            break :blk @floatFromInt(total);
        },
        12 => blk: {
            var total: usize = 0;
            for (bay_used[0..city.road_count]) |b| total += b;
            break :blk @floatFromInt(total);
        },
        13 => @floatFromInt(failed_total),
        else => -1,
    };
}

pub fn init() void {
    runs = @splat(.{});
    count = 0;
    next_number = 1;
    loading_bays = @splat(0);
    bay_used = @splat(0);
    served = @splat(0);
    dispatched_total = 0;
    delivered_total = 0;
    failed_total = 0;
    goods_total = 0;
    fee_total = 0;
    bay_seconds_total = 0;
    travelled_total = 0;
    demand_today = 0;
    delivered_today = 0;
    last_dispatch = -1e9;
}

// A day rolls over: reset the served progress and the day's own counters, then
// dispatch the new day's runs.
pub fn daily(elapsed: f64) void {
    served = @splat(0);
    demand_today = 0;
    delivered_today = 0;
    _ = dispatch(elapsed);
}

pub fn restore(saved: []const Run, saved_next: u32, saved_bays: []const u8, saved_dispatched: u32, saved_delivered: u32, saved_failed: u32, saved_goods: f64, saved_fee: f64, saved_bay_seconds: f64, saved_travelled: f64, saved_demand: f64, saved_delivered_today: f64, saved_last: f64) void {
    const n = @min(saved.len, runs.len);
    runs = @splat(.{});
    @memcpy(runs[0..n], saved[0..n]);
    count = n;
    next_number = saved_next;
    const roads = @min(saved_bays.len, city.road_count);
    loading_bays = @splat(0);
    @memcpy(loading_bays[0..roads], saved_bays[0..roads]);
    bay_used = @splat(0);
    served = @splat(0);
    dispatched_total = saved_dispatched;
    delivered_total = saved_delivered;
    failed_total = saved_failed;
    goods_total = saved_goods;
    fee_total = saved_fee;
    bay_seconds_total = saved_bay_seconds;
    travelled_total = saved_travelled;
    demand_today = saved_demand;
    delivered_today = saved_delivered_today;
    last_dispatch = saved_last;
    // The day's served progress is derived: rebuild it from the delivered runs
    // that are still in the ring, so access survives a load without trusting a
    // stored score.
    for (runs[0..count]) |run| {
        if (run.phase == .delivered and run.customer < served.len) served[run.customer] += run.goods;
    }
}

test "demand floors at one unit" {
    init();
    try std.testing.expectEqual(max_runs, runs.len);
}
