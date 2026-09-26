const std = @import("std");
const city = @import("../scene/city.zig");
const parcels = @import("../scene/parcels.zig");

// Numbered list item 13: parks and public spaces.
//
// The authored green lots already existed and residents already walked to them
// for weekend errands. This module gives that behaviour consequences: every
// park, playground and plaza now has a measured walking catchment, a condition
// that is maintained from an explicit municipal budget, resident visits, and a
// bounded neighbourhood amenity value. Nothing here creates a second map: the
// records are keyed to the authored lot identity, so redevelopment, the
// renderer and the snapshot all keep reading the same rows.
pub const max_parks = city.buildings.len;
pub const access_max_walk: f32 = 900;
pub const value_rate: f32 = 0.05;
pub const construction_base: f64 = 6000;
pub const construction_area_rate: f64 = 8;
pub const maintenance_funding: [3]f32 = .{ 0.5, 1.0, 1.5 };
// Per full simulated day. These are bounded policy numbers, not a contractor
// tender: area covers grounds work, the kind covers equipment/cleaning, and
// visits add wear.
pub const park_daily_base: f64 = 9;
pub const playground_daily_base: f64 = 14;
pub const plaza_daily_base: f64 = 11;
pub const daily_area_rate: f64 = 0.025;
pub const daily_visit_rate: f64 = 0.02;
pub const recovery_per_day: f32 = 3.0;
pub const wear_per_day: f32 = 2.5;

pub const Record = struct {
    building: usize = 0,
    condition: f32 = 70,
    visits_today: u32 = 0,
    visits_total: u32 = 0,
    maintenance_paid_total: f64 = 0,
};

const Derived = struct {
    access_homes: u32 = 0,
    access_population: u32 = 0,
    mean_access: f32 = 0,
    access_score: f32 = 0,
    need_today: f64 = 0,
    paid_today: f64 = 0,
    coverage: f32 = 0,
    benefit: f32 = 0,
};

pub var records: [max_parks]Record = @splat(.{});
pub var count: usize = 0;
var derived: [max_parks]Derived = @splat(.{});
pub var funding: u8 = 1;
pub var maintenance_spent_total: f64 = 0;
pub var maintenance_need_today: f64 = 0;
pub var maintenance_paid_today: f64 = 0;
pub var created_total: u32 = 0;
pub var construction_spent_total: f64 = 0;

fn clamp01(value: f32) f32 {
    return std.math.clamp(value, 0, 1);
}

fn conditionScore(condition: f32) f32 {
    return clamp01((condition - 20) / 80);
}

fn initialCondition(lot: usize, kind: city.Kind) f32 {
    const kind_offset: f32 = switch (kind) {
        .playground => -4,
        .plaza => 2,
        else => 0,
    };
    return std.math.clamp(66 + city.hash01(@as(u32, @intCast(lot)) * 19 + 7) * 18 + kind_offset, 40, 92);
}

fn indexOfBuilding(lot: usize) ?usize {
    for (records[0..count], 0..) |entry, i| if (entry.building == lot) return i;
    return null;
}

fn addRecord(lot: usize, kind: city.Kind) void {
    if (indexOfBuilding(lot) != null or count >= records.len) return;
    records[count] = .{ .building = lot, .condition = initialCondition(lot, kind) };
    count += 1;
}

pub fn init() void {
    records = @splat(.{});
    derived = @splat(.{});
    count = 0;
    funding = 1;
    maintenance_spent_total = 0;
    maintenance_need_today = 0;
    maintenance_paid_today = 0;
    created_total = 0;
    construction_spent_total = 0;
    for (city.lots(), 0..) |b, i| if (city.isGreen(b.kind)) addRecord(i, b.kind);
    rebuildBenefits();
    city.reassess();
}

// Restore the persisted records, then derive every catchment and value effect
// from the restored town. Derived values are never trusted from a file.
pub fn restore(saved: []const Record, saved_funding: u8, saved_maintenance: f64, saved_created: u32, saved_construction: f64) void {
    records = @splat(.{});
    derived = @splat(.{});
    count = @min(saved.len, records.len);
    for (saved[0..count], 0..) |entry, i| records[i] = entry;
    funding = @min(saved_funding, 2);
    maintenance_spent_total = saved_maintenance;
    created_total = saved_created;
    construction_spent_total = saved_construction;
    maintenance_paid_today = 0;
    rebuildDailyNeeds();
    rebuildBenefits();
    city.reassess();
}

pub fn setFunding(value: u32) bool {
    if (value > 2) return false;
    funding = @intCast(value);
    return true;
}

pub fn fundingName(value: u8) []const u8 {
    return switch (value) {
        0 => "minimum",
        1 => "standard",
        2 => "enhanced",
        else => "standard",
    };
}

pub fn lotAt(index: usize) ?usize {
    if (index >= count) return null;
    return records[index].building;
}

pub fn conditionFor(index: usize) f32 {
    if (index >= count) return 0;
    return records[index].condition;
}

pub fn conditionAtLot(lot: usize) f32 {
    const i = indexOfBuilding(lot) orelse return 0;
    return records[i].condition;
}

pub fn visitsToday(index: usize) u32 {
    if (index >= count) return 0;
    return records[index].visits_today;
}

pub fn visitsTotal(index: usize) u32 {
    if (index >= count) return 0;
    return records[index].visits_total;
}

fn record(index: usize) ?*Record {
    if (index >= count) return null;
    return &records[index];
}

fn needFor(record_value: *const Record) f64 {
    if (record_value.building >= city.lot_count) return 0;
    const b = &city.buildings[record_value.building];
    const area = @as(f64, b.width) * @as(f64, b.depth);
    const base: f64 = switch (b.kind) {
        .playground => playground_daily_base,
        .plaza => plaza_daily_base,
        else => park_daily_base,
    };
    return financeCents(base + area * daily_area_rate + @as(f64, @floatFromInt(record_value.visits_today)) * daily_visit_rate);
}

fn financeCents(value: f64) f64 {
    return @round(value * 100) / 100;
}

fn fundingMultiplier() f32 {
    return maintenance_funding[funding];
}

fn rebuildDailyNeeds() void {
    maintenance_need_today = 0;
    for (records[0..count], 0..) |*record_value, i| {
        derived[i].need_today = needFor(record_value);
        maintenance_need_today += derived[i].need_today;
    }
    maintenance_need_today = financeCents(maintenance_need_today);
}

// The exact amount the next 30-second operating payment should offer. One day
// is 480 simulation seconds, so standard funding is paid in sixteen bounded
// instalments; a shortfall simply means the park receives less care.
pub fn instalmentDue() f64 {
    if (count == 0) return 0;
    const due_today = financeCents(maintenance_need_today * @as(f64, @floatCast(fundingMultiplier())));
    const unpaid = @max(0, due_today - maintenance_paid_today);
    return financeCents(@min(unpaid, due_today / 16));
}

pub fn applyPayment(amount: f64) void {
    const paid = financeCents(@min(amount, instalmentDue()));
    if (paid <= 0 or maintenance_need_today <= 0) return;
    maintenance_paid_today = financeCents(maintenance_paid_today + paid);
    maintenance_spent_total = financeCents(maintenance_spent_total + paid);
    var credited: f64 = 0;
    for (records[0..count], 0..) |*record_value, i| {
        const share = if (i + 1 == count) financeCents(paid - credited) else financeCents(paid * derived[i].need_today / maintenance_need_today);
        credited = financeCents(credited + share);
        derived[i].paid_today = financeCents(derived[i].paid_today + share);
        record_value.maintenance_paid_total = financeCents(record_value.maintenance_paid_total + share);
    }
}

pub fn coverage() f32 {
    const due_today = maintenance_need_today * @as(f64, @floatCast(fundingMultiplier()));
    if (due_today <= 0) return 1;
    return @floatCast(std.math.clamp(maintenance_paid_today / due_today, 0, 1));
}

pub fn meanCondition() f32 {
    if (count == 0) return 0;
    var total: f32 = 0;
    for (records[0..count]) |record_value| total += record_value.condition;
    return total / @as(f32, @floatFromInt(count));
}

pub fn belowStandard() usize {
    var total: usize = 0;
    for (records[0..count]) |record_value| if (record_value.condition < 45) {
        total += 1;
    };
    return total;
}

pub fn totalVisits() u64 {
    var total: u64 = 0;
    for (records[0..count]) |record_value| total += record_value.visits_total;
    return total;
}

pub fn visitsTodayTotal() u64 {
    var total: u64 = 0;
    for (records[0..count]) |record_value| total += record_value.visits_today;
    return total;
}

pub fn visit(lot: usize) void {
    const i = indexOfBuilding(lot) orelse return;
    const record_value = &records[i];
    if (record_value.visits_today < 1_000_000_000) record_value.visits_today += 1;
    if (record_value.visits_total < 1_000_000_000) record_value.visits_total += 1;
    derived[i].need_today = needFor(record_value);
}

pub fn attractiveness(lot: usize) f32 {
    const i = indexOfBuilding(lot) orelse return 0;
    return 0.35 + 0.65 * conditionScore(records[i].condition);
}

// Recompute each park's walking catchment and each lot's best nearby amenity.
// The walk cost is the same graph cost residents use, so a park behind a river
// or across an unconnected edge is not counted as nearby.
pub fn rebuildBenefits() void {
    rebuildDailyNeeds();
    for (records[0..count], 0..) |*record_value, i| {
        derived[i].access_homes = 0;
        derived[i].access_population = 0;
        derived[i].mean_access = 0;
        derived[i].access_score = 0;
        if (record_value.building >= city.lot_count) continue;
        const park_node = city.buildings[record_value.building].node;
        var homes: u32 = 0;
        var population: u32 = 0;
        var total: f64 = 0;
        for (city.lots()) |*b| {
            if (!city.isHome(b.kind)) continue;
            const distance = city.walkCost(b.node, park_node);
            if (distance >= access_max_walk) continue;
            homes += 1;
            population += @intCast(b.occupants);
            total += distance;
        }
        derived[i].access_homes = homes;
        derived[i].access_population = population;
        derived[i].mean_access = if (homes == 0) 0 else @floatCast(total / @as(f64, @floatFromInt(homes)));
        const access_factor = if (homes == 0) 0 else clamp01(1 - derived[i].mean_access / access_max_walk);
        derived[i].access_score = access_factor * conditionScore(record_value.condition);
        derived[i].benefit = derived[i].access_score;
    }
    for (city.lots(), 0..) |*b, i| {
        b.park = if (city.isGreen(b.kind)) 0 else benefitAt(i);
    }
}

pub fn benefitAt(lot: usize) f32 {
    if (lot >= city.lot_count) return 0;
    const b = &city.buildings[lot];
    if (b.node >= city.node_count or city.isGreen(b.kind)) return 0;
    var best: f32 = 0;
    for (records[0..count]) |record_value| {
        if (record_value.building >= city.lot_count) continue;
        const distance = city.walkCost(b.node, city.buildings[record_value.building].node);
        if (distance >= access_max_walk) continue;
        const access = clamp01(1 - distance / access_max_walk);
        const quality = conditionScore(record_value.condition);
        const score = access * quality;
        if (score > best) best = score;
    }
    return clamp01(best);
}

pub fn meanBenefit() f32 {
    var total: f32 = 0;
    var rated: usize = 0;
    for (city.lots()) |*b| {
        if (city.lotValue(b.kind) == 0) continue;
        total += b.park;
        rated += 1;
    }
    return if (rated == 0) 0 else total / @as(f32, @floatFromInt(rated));
}

pub fn accessibleHomes() usize {
    var total: usize = 0;
    for (city.lots()) |*b| if (city.isHome(b.kind) and b.park > 0.05) {
        total += 1;
    };
    return total;
}

pub fn accessiblePopulation() usize {
    var total: usize = 0;
    for (city.lots()) |*b| if (city.isHome(b.kind) and b.park > 0.05) {
        total += b.occupants;
    };
    return total;
}

pub fn publicArea() f64 {
    var total: f64 = 0;
    for (records[0..count]) |record_value| {
        if (record_value.building >= city.lot_count) continue;
        const b = &city.buildings[record_value.building];
        total += @as(f64, b.width) * @as(f64, b.depth);
    }
    return financeCents(total);
}

// The mean resident-visible park benefit in a district. Trust reads this in
// addition to street condition, so a neglected park is a real local cost.
pub fn districtBenefit(district: usize) f32 {
    var total: f32 = 0;
    var count_homes: usize = 0;
    for (city.lots()) |*b| {
        if (!city.isHome(b.kind) or @min(b.district, city.district_count - 1) != @min(district, city.district_count - 1)) continue;
        total += b.park;
        count_homes += 1;
    }
    return if (count_homes == 0) 0 else total / @as(f32, @floatFromInt(count_homes));
}

pub fn daily() void {
    for (records[0..count], 0..) |*record_value, i| {
        record_value.visits_today = 0;
        derived[i].paid_today = 0;
    }
    maintenance_paid_today = 0;
    maintenance_need_today = 0;
    rebuildBenefits();
    city.reassess();
}

pub fn update(dt: f32) void {
    if (count == 0) return;
    const paid_share = coverage();
    const day_fraction: f32 = dt / 480;
    for (records[0..count], 0..) |*record_value, i| {
        const visit_pressure: f32 = @floatCast(@min(1.5, @as(f64, @floatFromInt(record_value.visits_today)) * daily_visit_rate / @max(0.01, derived[i].need_today)));
        const wear = wear_per_day * (1 + visit_pressure);
        const recovery = recovery_per_day * paid_share;
        record_value.condition = std.math.clamp(record_value.condition + (recovery - wear) * day_fraction, 0, 100);
    }
}

pub fn constructionCostFor(lot: usize, choice: u32) f64 {
    if (lot >= city.lot_count or lot >= parcels.count or choice > 2) return -1;
    const b = &city.buildings[lot];
    if (b.kind != .vacant or parcels.storage[lot].zone != 5) return -1;
    const kind: city.Kind = switch (choice) {
        0 => .park,
        1 => .playground,
        2 => .plaza,
        else => return -1,
    };
    const kind_rate: f64 = switch (kind) {
        .playground => 0.8,
        .plaza => 1.15,
        else => 1,
    };
    const area = @as(f64, b.width) * @as(f64, b.depth);
    return financeCents((construction_base + area * construction_area_rate) * kind_rate);
}

// Turn a zoned civic-reserve vacant lot into a public space. The caller pays
// the returned amount through the municipal ledger; this function only mutates
// the authored lot and its park record, so money and state stay explicit.
pub fn create(lot: usize, choice: u32) f64 {
    const cost = constructionCostFor(lot, choice);
    if (cost < 0) return -1;
    const kind: city.Kind = switch (choice) {
        0 => .park,
        1 => .playground,
        2 => .plaza,
        else => return -1,
    };
    const b = &city.buildings[lot];
    b.kind = kind;
    b.height = 0.1;
    b.value = 0;
    b.capacity = 0;
    b.slots = 0;
    b.occupants = 0;
    b.employer = -1;
    b.park = 0;
    b.entry_x = b.x + b.width / 2;
    b.entry_z = b.z + b.depth;
    parcels.storage[lot].building = @intCast(lot);
    addRecord(lot, kind);
    created_total += 1;
    rebuildBenefits();
    city.reassess();
    return cost;
}

pub fn noteConstruction(amount: f64) void {
    if (amount <= 0) return;
    construction_spent_total = financeCents(construction_spent_total + amount);
}

pub fn read(index: usize, field: u32) f64 {
    if (index >= count) return -1;
    const record_value = &records[index];
    if (record_value.building >= city.lot_count) return -1;
    const b = &city.buildings[record_value.building];
    const d = &derived[index];
    return switch (field) {
        0 => @floatFromInt(record_value.building),
        1 => @floatFromInt(@intFromEnum(b.kind)),
        2 => @floatFromInt(b.district),
        3 => b.x,
        4 => b.z,
        5 => b.width,
        6 => b.depth,
        7 => record_value.condition,
        8 => @floatFromInt(record_value.visits_today),
        9 => @floatFromInt(record_value.visits_total),
        10 => @floatFromInt(d.access_homes),
        11 => @floatFromInt(d.access_population),
        12 => d.mean_access,
        13 => d.access_score,
        14 => d.need_today,
        15 => d.paid_today,
        16 => d.coverage,
        17 => d.benefit,
        18 => record_value.maintenance_paid_total,
        // Item 13: the address the panel shows, so a green lot is named by the
        // street it fronts instead of raw world coordinates.
        19 => @floatFromInt(b.street),
        20 => @floatFromInt(b.number),
        else => -1,
    };
}

pub fn read0(field: u32) f64 {
    return switch (field) {
        0 => @floatFromInt(count),
        1 => meanCondition(),
        2 => @floatFromInt(totalVisits()),
        3 => @floatFromInt(visitsTodayTotal()),
        4 => maintenance_spent_total,
        5 => maintenance_need_today,
        6 => maintenance_paid_today,
        7 => coverage(),
        8 => @floatFromInt(belowStandard()),
        9 => @floatFromInt(accessibleHomes()),
        10 => meanBenefit(),
        11 => @floatFromInt(funding),
        12 => @floatFromInt(created_total),
        13 => construction_spent_total,
        14 => @floatFromInt(accessiblePopulation()),
        15 => publicArea(),
        else => -1,
    };
}
