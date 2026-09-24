const std = @import("std");
const city = @import("../scene/city.zig");
const residents = @import("residents.zig");
const households = @import("households.zig");

pub const Tenure = enum(u8) { owned = 0, rented = 1 };
pub const MoveState = enum(u8) { idle = 0, pending = 1, moved = 2, displaced = 3, refused = 4 };

pub const Unit = struct {
    present: bool = false,
    tenure: Tenure = .owned,
    rent: f64 = 0,
    ownership_cost: f64 = 0,
    owner_cash: f64 = 0,
    arrears: f64 = 0,
    occupants: u32 = 0,
    application: i32 = -1,
    move_state: MoveState = .idle,
    paid_rent: f64 = 0,
    paid_ownership: f64 = 0,
};

pub var units: [city.buildings.len]Unit = @splat(.{});
pub var moves_today: u32 = 0;
pub var displacements_today: u32 = 0;
pub var applications_today: u32 = 0;
pub var rent_collected_today: f64 = 0;
pub var ownership_collected_today: f64 = 0;
pub var rent_collected_total: f64 = 0;
pub var ownership_collected_total: f64 = 0;
pub var failed_moves_today: u32 = 0;
const max_moves_per_day: usize = 12;

pub fn init() void {
    units = @splat(.{});
    moves_today = 0;
    displacements_today = 0;
    applications_today = 0;
    rent_collected_today = 0;
    ownership_collected_today = 0;
    rent_collected_total = 0;
    ownership_collected_total = 0;
    failed_moves_today = 0;
    for (city.lots(), 0..) |*building, i| {
        if (!city.isHome(building.kind)) continue;
        const value = @max(1, building.value);
        units[i].present = true;
        units[i].tenure = if (i % 5 == 0) .rented else .owned;
        units[i].rent = @max(5, @round(value * 0.000045 * 100) / 100);
        units[i].ownership_cost = @max(3, @round(value * 0.000022 * 100) / 100);
        units[i].occupants = @intCast(building.occupants);
        units[i].application = -1;
        units[i].move_state = .idle;
    }
}

pub fn valid(index: usize) bool {
    return index < units.len and units[index].present;
}

pub fn occupancy(index: usize) usize {
    return if (valid(index)) @as(usize, units[index].occupants) else 0;
}

pub fn isVacant(index: usize) bool {
    return valid(index) and units[index].occupants == 0;
}

pub fn charge(index: usize) f64 {
    if (!valid(index)) return 0;
    const unit = &units[index];
    return if (unit.tenure == .rented) unit.rent else unit.ownership_cost;
}

pub fn collectToday() f64 {
    return rent_collected_today + ownership_collected_today;
}

pub fn arrearsTotal() f64 {
    var total: f64 = 0;
    for (units) |unit| if (unit.present) {
        total += unit.arrears;
    };
    return total;
}

fn commuteCost(home: usize, work: usize) f64 {
    return @as(f64, city.distance[city.buildings[home].node][city.buildings[work].node]);
}

fn hasCrewOrOrder(old: usize) bool {
    for (&residents.people) |*person| {
        if (person.home != old) continue;
        if (person.crew or person.order >= 0 or person.bus >= 0 or person.mode == 3 or person.phase == 1) return true;
    }
    return false;
}

fn canMove(old: usize) bool {
    if (old >= city.lot_count or !valid(old)) return false;
    if (city.buildings[old].occupants == 0) return false;
    if (city.buildings[old].occupants > city.population) return false;
    return !hasCrewOrOrder(old);
}

fn findTarget(old: usize) ?usize {
    const household = &households.homes[old];
    var best: ?usize = null;
    var best_score: f64 = 1e9;
    const old_charge = charge(old);
    const old_commute = if (household.income > 0) commuteCost(old, old) else 0;
    for (city.lots(), 0..) |*building, candidate| {
        if (!city.isHome(building.kind) or building.occupants != 0) continue;
        if (!valid(candidate) or candidate == old) continue;
        const target_charge = charge(candidate);
        if (target_charge >= old_charge - 0.0001) continue;
        const target_commute = if (household.income > 0) commuteCost(old, candidate) else 0;
        if (household.income > 0 and target_commute >= old_commute - 0.0001) continue;
        const score = target_charge + (if (household.income > 0) target_commute / 100 else 0);
        if (score < best_score) {
            best_score = score;
            best = candidate;
        }
    }
    return best;
}

fn moveHousehold(old: usize, target: usize) void {
    const members = city.buildings[old].occupants;
    households.homes[target] = households.homes[old];
    households.homes[old] = .{};
    households.homes[target].present = true;
    units[target].occupants = @intCast(members);
    units[target].application = -1;
    units[target].move_state = .moved;
    units[target].arrears = 0;
    units[target].paid_rent = 0;
    units[target].paid_ownership = 0;
    units[old].occupants = 0;
    units[old].application = -1;
    units[old].move_state = .refused;
    units[old].arrears = 0;
    for (&residents.people, 0..) |*person, id| {
        if (person.home != old) continue;
        person.home = target;
        residents.send(id, city.buildings[target].node, -1);
        person.destination_building = target;
        person.wallet = households.homes[target].balance;
    }
}

fn maybeMove(old: usize) void {
    const source = &units[old];
    const household = &households.homes[old];
    const current_charge = charge(old);
    const income = household.income;
    const affordability_exceeded = income > 0 and current_charge / income > 0.55;
    const forced = source.arrears > 0.0001 or affordability_exceeded;
    if (!forced and household.income <= 0) return;
    const target_opt = findTarget(old);
    if (target_opt) |target| {
        source.application = @intCast(target);
        source.move_state = .pending;
        applications_today += 1;
        moveHousehold(old, target);
        moves_today += 1;
        if (forced) displacements_today += 1;
    } else {
        source.application = -1;
        source.move_state = .refused;
        failed_moves_today += 1;
        applications_today += 1;
    }
}

pub fn daily() void {
    moves_today = 0;
    displacements_today = 0;
    applications_today = 0;
    rent_collected_today = 0;
    ownership_collected_today = 0;
    failed_moves_today = 0;
    var move_count: usize = 0;
    for (city.lots(), 0..) |*building, i| {
        if (!city.isHome(building.kind)) continue;
        const unit = &units[i];
        unit.occupants = @intCast(building.occupants);
        if (!unit.present or building.occupants == 0) {
            unit.application = -1;
            unit.move_state = .idle;
            continue;
        }
        const payment = charge(i);
        if (households.spend(i, payment)) {
            if (unit.tenure == .rented) {
                unit.paid_rent += payment;
                rent_collected_today += payment;
                rent_collected_total += payment;
            } else {
                unit.paid_ownership += payment;
                ownership_collected_today += payment;
                ownership_collected_total += payment;
            }
            unit.owner_cash += payment;
        } else {
            unit.arrears += payment;
        }
        if (move_count < max_moves_per_day and canMove(i)) {
            const before = moves_today;
            maybeMove(i);
            if (moves_today != before) move_count += 1;
        }
    }
}

pub fn read(index: usize, field: u32) f64 {
    if (!valid(index)) return -1;
    const unit = &units[index];
    return switch (field) {
        0 => if (unit.present) 1 else 0,
        1 => if (unit.tenure == .rented) 1 else 0,
        2 => unit.rent,
        3 => unit.ownership_cost,
        4 => unit.owner_cash,
        5 => unit.arrears,
        6 => @floatFromInt(unit.occupants),
        7 => if (isVacant(index)) 1 else 0,
        8 => @floatFromInt(unit.application),
        9 => @floatFromInt(@intFromEnum(unit.move_state)),
        10 => unit.paid_rent,
        11 => unit.paid_ownership,
        else => -1,
    };
}
