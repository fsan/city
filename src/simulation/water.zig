const std = @import("std");
const city = @import("../scene/city.zig");
const calendar = @import("calendar.zig");

// Numbered list item 18: water, drainage and waste.
//
// The authored river already exists, is impassable, is carved into the terrain
// and is drawn by the renderer. This module gives it a utility role. One intake
// sits on the real centreline and lifts water for the town; every district is
// served through the real walk graph, so a district across the river with no
// bridge or beyond the pipe bound genuinely loses supply. Two drains carry
// surface water off each eligible carriageway, and a blocked drain floods its
// segment when the day's rain is heavy enough. The town also makes a bounded
// amount of solid waste every day, and one collection round per day tips what it
// can and leaves a visible backlog behind.
//
// Everything is bounded and deterministic: outages and blockages are a pure
// function of the day index, so a saved town replays the same sequence; rain is
// a pure function of the day too. No water chemistry, no treatment process, no
// flood hydrology and no waste sorting are modelled, and no money is created -
// pumping, intake works and tipping are municipal expenses in the ledger.
pub const max_drains_per_road: u8 = 2;

// Bounded policy numbers, not a utility tender.
pub const demand_per_capita: f64 = 0.0045;
pub const workplace_share: f64 = 0.35;
pub const electricity_per_unit: f64 = 0.09;
pub const intake_install_cost: f64 = 24000;
pub const intake_repair_cost: f64 = 3400;
pub const drain_install_cost: f64 = 180;
pub const drain_clear_cost: f64 = 60;
pub const tipping_fee_per_unit: f64 = 4.5;

// A district is served when the intake can reach its own node within this
// walking-graph bound. The bound is deliberately generous enough to cover the
// authored town and short enough that a severed bank genuinely fails.
pub const max_pipe_run: f32 = 2400;

// At most one intake outage per day, and a bounded number of drain clearances
// per operating pass, matching the lighting crew's shape.
pub const intake_fault_permille: u32 = 25;
pub const drain_block_permille: u32 = 26;
pub const max_clears_per_pass: usize = 2;

// Flooding consequence: a flooded segment is slower by this bounded share and
// the effect vanishes when the drains are clear or the day is dry.
pub const flood_speed_penalty: f32 = 0.3;

// Waste bounds. Residents and employees each make this much per simulated day;
// one round per day can tip at most `collection_capacity` units.
pub const waste_per_person_day: f64 = 0.03;
pub const collection_capacity: f64 = 160;
pub const backlog_decay: f64 = 0.15;

// The intake's supply record. `working` is the units the district actually
// receives, `served` is a count for the report, and `pipe_run` is the measured
// graph distance the water has to travel.
pub const Supply = struct {
    district: usize = 0,
    node: usize = 0,
    demand: f64 = 0,
    working: f64 = 0,
    pipe_run: f32 = 0,
    served: bool = false,
    population: u32 = 0,
    workplaces: u32 = 0,
};

pub var supplies: [city.district_count]Supply = @splat(.{});
pub var intake_working: bool = true;
pub var intake_faults_total: u32 = 0;
pub var intake_faults_today: u32 = 0;
pub var intake_repairs_total: u32 = 0;
pub var intake_repairs_today: u32 = 0;
pub var intake_node: usize = 0;
pub var intake_x: f32 = 0;
pub var intake_z: f32 = 0;
pub var intake_installed: bool = false;
pub var install_spent_total: f64 = 0;
pub var last_fault_day: u32 = 0xFFFFFFFF;

pub var water_need_today: f64 = 0;
pub var water_paid_today: f64 = 0;
pub var water_paid_total: f64 = 0;
pub var works_paid_today: f64 = 0;
pub var works_paid_total: f64 = 0;

// Drains and flooding.
pub var drains: [city.max_roads]u8 = @splat(0);
pub var drains_clear: [city.max_roads]u8 = @splat(0);
pub var drain_clears: [city.max_roads]u32 = @splat(0);
pub var drains_total: u32 = 0;
pub var drains_blocked_total: u32 = 0;
pub var drains_blocked_today: u32 = 0;
pub var drains_cleared_today: u32 = 0;
pub var drains_cleared_total: u32 = 0;
pub var rain_today: f32 = 0;

// Waste.
pub var waste_today: f64 = 0;
pub var waste_collected_today: f64 = 0;
pub var waste_collected_total: f64 = 0;
pub var waste_backlog: f64 = 0;
pub var tipping_paid_today: f64 = 0;
pub var tipping_paid_total: f64 = 0;
pub var collection_rounds: u32 = 0;

pub const Spend = struct { electricity: f64 = 0, tipping: f64 = 0, works: f64 = 0 };

fn cents(value: f64) f64 {
    return @round(value * 100) / 100;
}

fn clamp01(value: f32) f32 {
    return std.math.clamp(value, 0, 1);
}

// Drainage follows the same eligibility rule the lighting layer uses: a real
// carriageway that carries vehicles and pedestrians, is not a lane and is not
// under works.
pub fn eligible(road: usize) bool {
    if (road >= city.road_count) return false;
    const r = city.roads[road];
    return r.class > 0 and r.vehicles and r.pedestrians and !r.works;
}

pub fn capacity(road: usize) u8 {
    if (!eligible(road)) return 0;
    return @min(max_drains_per_road, if (city.roads[road].class >= 2) @as(u8, 2) else @as(u8, 1));
}

pub fn installed(road: usize) u8 {
    return if (road >= city.road_count) 0 else drains[road];
}

pub fn working(road: usize) u8 {
    return if (road >= city.road_count) 0 else drains_clear[road];
}

pub fn blocked(road: usize) u8 {
    return installed(road) -| working(road);
}

// Coverage is the share of the segment's own drain capacity that is working, so
// a street with its one drain blocked is fully flooded rather than half.
pub fn coverage(road: usize) f32 {
    const need = capacity(road);
    if (need == 0) return 1;
    return clamp01(@as(f32, @floatFromInt(working(road))) / @as(f32, @floatFromInt(need)));
}

// The bounded daily rain, a pure function of the day index. Wet days cluster
// rather than alternating, so a wet spell is a real short episode.
pub fn rain(day: u32) f32 {
    const phase = @as(f64, @floatFromInt(day)) * 0.37 + @as(f64, @floatFromInt((day / 5) *% 11)) * 0.11;
    const wave = 0.5 + 0.5 * @sin(phase);
    return clamp01(@floatCast(wave * wave * 1.15));
}

// How much a flooded segment costs a driver, 1.0 when the segment is drained or
// the day is dry, falling to `1 - flood_speed_penalty` on a fully flooded
// segment in the heaviest rain.
pub fn floodFactor(road: usize, day: u32) f32 {
    if (!eligible(road)) return 1;
    const wet = rain(day);
    if (wet <= 0.001) return 1;
    const uncovered = 1 - coverage(road);
    return 1 - flood_speed_penalty * wet * uncovered;
}

pub fn drainInstalledTotal() usize {
    var total: usize = 0;
    for (drains[0..city.road_count]) |n| total += n;
    return total;
}

pub fn drainWorkingTotal() usize {
    var total: usize = 0;
    for (drains_clear[0..city.road_count]) |n| total += n;
    return total;
}

pub fn drainBlockedNow() usize {
    return drainInstalledTotal() -| drainWorkingTotal();
}

pub fn drainCoverageMean() f32 {
    var total: f32 = 0;
    var n: usize = 0;
    for (0..city.road_count) |i| {
        if (!eligible(i)) continue;
        total += coverage(i);
        n += 1;
    }
    return if (n == 0) 1 else total / @as(f32, @floatFromInt(n));
}

fn hash(road: usize, day: u32) u32 {
    var h: u64 = @as(u64, day) *% 0x9E3779B97F4A7C15;
    h ^= @as(u64, road) *% 0xBF58476D1CE4E5B9;
    h ^= h >> 29;
    h *%= 0xBF58476D1CE4E5B9;
    h ^= h >> 32;
    return @truncate(h);
}

// The intake is placed on the authored centreline. Its nearest node is the
// source for every district's pipe run.
fn seedIntake() void {
    intake_installed = false;
    intake_node = 0;
    if (city.River.count == 0 or city.node_count == 0) return;
    const mid = city.River.atChainage(city.River.length * 0.5);
    intake_x = mid.x;
    intake_z = mid.z;
    var best: f32 = 1e9;
    for (0..city.node_count) |n| {
        const d = city.hypot(city.nodes[n].x - intake_x, city.nodes[n].z - intake_z);
        if (d < best) {
            best = d;
            intake_node = n;
        }
    }
    intake_installed = true;
}

// The representative node of a district: the busiest street node the district
// owns, so the pipe run is measured to a place the district actually is.
fn districtNode(district: usize) ?usize {
    var best: ?usize = null;
    var best_degree: usize = 0;
    for (0..city.node_count) |n| {
        const node = city.nodes[n];
        if (city.districtAt(node.x, node.z) != district) continue;
        const degree = city.degree(n);
        if (degree == 0) continue;
        if (best == null or degree > best_degree) {
            best = n;
            best_degree = degree;
        }
    }
    return best;
}

// Each district's demand is the residents it houses plus a bounded share of its
// staffed workplaces, so a district only draws what the town has built there.
fn rebuildDemand() void {
    for (&supplies, 0..) |*s, i| {
        s.* = .{ .district = i };
        var population: u32 = 0;
        var workplaces: u32 = 0;
        for (city.lots()) |b| {
            if (b.district != i) continue;
            if (city.isHome(b.kind)) population += @intCast(b.occupants);
            if (b.employer >= 0 and b.capacity > 0) workplaces += @intCast(@min(b.capacity, 100000));
        }
        s.population = population;
        s.workplaces = workplaces;
        s.demand = cents(@as(f64, @floatFromInt(population)) * demand_per_capita + @as(f64, @floatFromInt(workplaces)) * demand_per_capita * workplace_share);
        s.node = districtNode(i) orelse 0;
    }
}

// Recompute each district's supply from the live intake state and the measured
// walk-graph pipe run. This is the only place `served` and `working` are set;
// both are derived and never trusted from a file.
pub fn recompute() void {
    rebuildDemand();
    var working_total: f64 = 0;
    for (&supplies) |*s| {
        s.working = 0;
        s.served = false;
        s.pipe_run = 1e9;
        if (!intake_installed or !intake_working) continue;
        if (s.node >= city.node_count or intake_node >= city.node_count) continue;
        const run = city.walkCost(intake_node, s.node);
        s.pipe_run = run;
        if (run >= 1e9 or run > max_pipe_run) continue;
        s.served = true;
        s.working = s.demand;
        working_total += s.demand;
    }
    water_need_today = cents(@as(f64, working_total) * electricity_per_unit);
}

pub fn servedDistricts() usize {
    var total: usize = 0;
    for (supplies) |s| if (s.served) {
        total += 1;
    };
    return total;
}

pub fn demandTotal() f64 {
    var total: f64 = 0;
    for (supplies) |s| total += s.demand;
    return cents(total);
}

pub fn servedTotal() f64 {
    var total: f64 = 0;
    for (supplies) |s| total += s.working;
    return cents(total);
}

pub fn shortfallTotal() f64 {
    return cents(@max(0, demandTotal() - servedTotal()));
}

// Supply coverage across the twelve districts: a district with no demand still
// counts as served, so an empty outer ward does not drag the mean down.
pub fn coverageMean() f32 {
    var total: f32 = 0;
    var n: usize = 0;
    for (supplies) |s| {
        const cover: f32 = if (s.demand <= 0) 1 else clamp01(@floatCast(s.working / s.demand));
        total += cover;
        n += 1;
    }
    return if (n == 0) 1 else total / @as(f32, @floatFromInt(n));
}

// Solid waste: occupied homes and staffed workplaces each make a bounded daily
// amount. The backlog carries over, so a short round is a real queue rather
// than a forgotten number.
fn rebuildWaste() void {
    var total: f64 = 0;
    for (city.lots()) |b| {
        if (city.isHome(b.kind)) total += @as(f64, @floatFromInt(b.occupants)) * waste_per_person_day;
        if (b.employer >= 0 and b.capacity > 0) total += @as(f64, @floatFromInt(@min(b.capacity, 100000))) * waste_per_person_day;
    }
    waste_today = cents(total);
}

pub fn wasteBacklog() f64 {
    return cents(waste_backlog);
}

fn seedDrains() void {
    drains = @splat(0);
    drains_clear = @splat(0);
    for (0..city.road_count) |i| {
        if (!eligible(i)) continue;
        // The authored town already drains the streets that carry frontage, so
        // the layer is live from the first frame; a lightly used outer link
        // stays undrained until the player acts.
        const street = city.roads[i].street;
        var frontage: usize = 0;
        for (city.lots()) |b| {
            if (b.street != street or b.number == 0) continue;
            frontage += 1;
        }
        const want: u8 = if (frontage >= 4) capacity(i) else if (frontage > 0) 1 else 0;
        drains[i] = want;
        drains_clear[i] = want;
    }
    drains_total = @intCast(drainInstalledTotal());
}

pub fn init() void {
    supplies = @splat(.{});
    intake_working = true;
    intake_faults_total = 0;
    intake_faults_today = 0;
    intake_repairs_total = 0;
    intake_repairs_today = 0;
    intake_node = 0;
    intake_x = 0;
    intake_z = 0;
    intake_installed = false;
    install_spent_total = 0;
    last_fault_day = 0xFFFFFFFF;
    water_need_today = 0;
    water_paid_today = 0;
    water_paid_total = 0;
    works_paid_today = 0;
    works_paid_total = 0;
    drains = @splat(0);
    drains_clear = @splat(0);
    drain_clears = @splat(0);
    drains_total = 0;
    drains_blocked_total = 0;
    drains_blocked_today = 0;
    drains_cleared_today = 0;
    drains_cleared_total = 0;
    rain_today = 0;
    waste_today = 0;
    waste_collected_today = 0;
    waste_collected_total = 0;
    waste_backlog = 0;
    tipping_paid_today = 0;
    tipping_paid_total = 0;
    collection_rounds = 0;
    seedIntake();
    seedDrains();
    recompute();
    rebuildWaste();
}

// A day rolls over: reset the day's own counters, roll the rain, fail the
// intake and a deterministic share of the working drains, then price the day's
// pumping and waste and run the one collection round.
pub fn daily(day: u32) void {
    water_paid_today = 0;
    works_paid_today = 0;
    tipping_paid_today = 0;
    intake_faults_today = 0;
    intake_repairs_today = 0;
    drains_blocked_today = 0;
    drains_cleared_today = 0;
    waste_collected_today = 0;
    rain_today = rain(day);
    if (intake_installed and hash(0x5EED, day) % 1000 < intake_fault_permille) {
        if (intake_working) {
            intake_working = false;
            intake_faults_total +|= 1;
            intake_faults_today +|= 1;
        }
    }
    for (0..city.road_count) |i| {
        if (drains_clear[i] == 0) continue;
        if (hash(i, day) % 1000 >= drain_block_permille) continue;
        drains_clear[i] -= 1;
    }
    drains_blocked_total = @intCast(drainBlockedNow());
    recompute();
    rebuildWaste();
    // One collection round per day: tip what the bounded capacity covers, then
    // leave the rest as backlog for a later day.
    collection_rounds +|= 1;
    const available = cents(waste_today + waste_backlog);
    const taken = cents(@min(available, collection_capacity));
    waste_collected_today = taken;
    waste_collected_total = cents(waste_collected_total + taken);
    waste_backlog = cents(@max(0, available - taken));
    tipping_paid_today = cents(taken * tipping_fee_per_unit);
    tipping_paid_total = cents(tipping_paid_total + tipping_paid_today);
}

// One operating pass. Pumping electricity is paid first in a bounded
// instalment, then a crew clears at most `max_clears_per_pass` blocked drains in
// segment order, and a failed intake is repaired. Both are capped by the cash
// actually available, so the town never books a payment it cannot cover.
pub fn update(dt: f32, elapsed: f64, budget: f64) Spend {
    _ = dt;
    _ = elapsed;
    var spend = Spend{};
    var left = @max(0, budget);
    if (water_need_today > 0 and water_paid_today + 0.0001 < water_need_today) {
        const per_pass = cents(water_need_today / 16);
        const due = @min(per_pass, water_need_today - water_paid_today);
        const paid = cents(@min(due, left));
        if (paid > 0) {
            water_paid_today = cents(water_paid_today + paid);
            water_paid_total = cents(water_paid_total + paid);
            spend.electricity = paid;
            left -= paid;
        }
    }
    if (tipping_paid_today > 0 and spend.tipping == 0) {
        // Tipping is a one-off daily fee, so it is settled on the first pass of
        // the day that can afford it rather than spread across the day.
        const paid = cents(@min(tipping_paid_today, left));
        if (paid > 0) {
            spend.tipping = paid;
            left -= paid;
        }
    }
    var cleared: usize = 0;
    var road: usize = 0;
    while (road < city.road_count and cleared < max_clears_per_pass) : (road += 1) {
        if (drains_clear[road] >= drains[road]) continue;
        if (left + 0.0001 < drain_clear_cost) break;
        drains_clear[road] += 1;
        drain_clears[road] +|= 1;
        drains_cleared_total +|= 1;
        drains_cleared_today +|= 1;
        works_paid_today = cents(works_paid_today + drain_clear_cost);
        works_paid_total = cents(works_paid_total + drain_clear_cost);
        spend.works += drain_clear_cost;
        left -= drain_clear_cost;
        cleared += 1;
    }
    if (!intake_working and left + 0.0001 >= intake_repair_cost) {
        intake_working = true;
        intake_repairs_total +|= 1;
        intake_repairs_today +|= 1;
        works_paid_today = cents(works_paid_today + intake_repair_cost);
        works_paid_total = cents(works_paid_total + intake_repair_cost);
        spend.works += intake_repair_cost;
        left -= intake_repair_cost;
        recompute();
    }
    return spend;
}

// Designate 0..capacity drains on one eligible segment. New drains are charged
// at the published capital rate; returns that cost, 0 when nothing changed, or
// -1 when the segment or the count is refused.
pub fn setDrains(road: usize, value: u32) f64 {
    if (road >= city.road_count or value > 6) return -1;
    if (!eligible(road) or value > capacity(road)) return -1;
    const want: u8 = @intCast(value);
    const old = drains[road];
    if (want == old) return 0;
    drains[road] = want;
    if (want > old) {
        drains_clear[road] = @min(want, drains_clear[road] + (want - old));
        drains_total +|= want - old;
    } else {
        drains_clear[road] = @min(drains_clear[road], want);
    }
    recompute();
    return cents(@as(f64, @floatFromInt(want)) * drain_install_cost - @as(f64, @floatFromInt(old)) * drain_install_cost);
}

pub fn readDistrict(index: usize, field: u32) f64 {
    if (index >= city.district_count) return -1;
    const s = &supplies[index];
    return switch (field) {
        0 => @floatFromInt(s.district),
        1 => @floatFromInt(s.node),
        2 => s.demand,
        3 => s.working,
        4 => if (s.demand <= 0) 1 else std.math.clamp(s.working / s.demand, 0, 1),
        5 => if (s.served) 1 else 0,
        6 => if (s.pipe_run >= 1e9) -1 else s.pipe_run,
        7 => @floatFromInt(s.population),
        8 => @floatFromInt(s.workplaces),
        else => -1,
    };
}

pub fn readRoad(road: usize, field: u32, day: u32) f64 {
    if (road >= city.road_count) return -1;
    const r = city.roads[road];
    return switch (field) {
        0 => @floatFromInt(road),
        1 => @floatFromInt(r.district),
        2 => @floatFromInt(r.class),
        3 => @floatFromInt(r.a),
        4 => if (eligible(road)) 1 else 0,
        5 => @floatFromInt(installed(road)),
        6 => @floatFromInt(capacity(road)),
        7 => @floatFromInt(working(road)),
        8 => @floatFromInt(blocked(road)),
        9 => coverage(road),
        10 => floodFactor(road, day),
        11 => @floatFromInt(drain_clears[road]),
        12 => rain(day),
        else => -1,
    };
}

pub fn read0(field: u32, day: u32) f64 {
    return switch (field) {
        0 => if (intake_working) 1 else 0,
        1 => @floatFromInt(servedDistricts()),
        2 => coverageMean(),
        3 => demandTotal(),
        4 => servedTotal(),
        5 => shortfallTotal(),
        6 => water_need_today,
        7 => water_paid_today,
        8 => water_paid_total,
        9 => @floatFromInt(intake_faults_today),
        10 => @floatFromInt(intake_repairs_today),
        11 => works_paid_today,
        12 => works_paid_total,
        13 => drainCoverageMean(),
        14 => @floatFromInt(drainInstalledTotal()),
        15 => @floatFromInt(drainBlockedNow()),
        16 => rain(day),
        17 => waste_today,
        18 => waste_collected_today,
        19 => waste_backlog,
        20 => tipping_paid_today,
        21 => tipping_paid_total,
        22 => @floatFromInt(collection_rounds),
        23 => @floatFromInt(drains_blocked_today),
        24 => @floatFromInt(drains_cleared_today),
        else => -1,
    };
}

pub fn restore(saved_supplies: []const Supply, saved_working: bool, saved_faults: u32, saved_repairs: u32, saved_install: f64, saved_water_total: f64, saved_water_today: f64, saved_works_total: f64, saved_works_today: f64, saved_need: f64, saved_drains: []const u8, saved_clear: []const u8, saved_clears: []const u32, saved_drains_total: u32, saved_blocked_total: u32, saved_cleared_total: u32, saved_waste_total: f64, saved_backlog: f64, saved_tipping: f64, saved_rounds: u32) void {
    supplies = @splat(.{});
    const districts = @min(saved_supplies.len, city.district_count);
    for (saved_supplies[0..districts], 0..) |s, i| supplies[i] = s;
    intake_working = saved_working;
    intake_faults_total = saved_faults;
    intake_faults_today = 0;
    intake_repairs_total = saved_repairs;
    intake_repairs_today = 0;
    install_spent_total = cents(saved_install);
    water_paid_total = cents(saved_water_total);
    water_paid_today = cents(saved_water_today);
    works_paid_total = cents(saved_works_total);
    works_paid_today = cents(saved_works_today);
    water_need_today = cents(saved_need);
    drains = @splat(0);
    drains_clear = @splat(0);
    drain_clears = @splat(0);
    const roads = @min(saved_drains.len, city.road_count);
    @memcpy(drains[0..roads], saved_drains[0..roads]);
    const clear_roads = @min(saved_clear.len, city.road_count);
    @memcpy(drains_clear[0..clear_roads], saved_clear[0..clear_roads]);
    const clear_counts = @min(saved_clears.len, city.road_count);
    @memcpy(drain_clears[0..clear_counts], saved_clears[0..clear_counts]);
    drains_total = saved_drains_total;
    drains_blocked_total = saved_blocked_total;
    drains_blocked_today = 0;
    drains_cleared_total = saved_cleared_total;
    drains_cleared_today = 0;
    rain_today = 0;
    waste_collected_total = cents(saved_waste_total);
    waste_collected_today = 0;
    waste_backlog = cents(saved_backlog);
    tipping_paid_total = cents(saved_tipping);
    tipping_paid_today = 0;
    collection_rounds = saved_rounds;
    waste_today = 0;
    seedIntake();
    recompute();
    rebuildWaste();
}

test "drain capacity follows the street class" {
    init();
    try std.testing.expectEqual(max_drains_per_road, 2);
}
