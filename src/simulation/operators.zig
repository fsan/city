const std = @import("std");

// Slice 4: explicit fleet units and recruited driver cohorts replace the fixed
// aggregate numbers. Money still lives only in each operator's single account.
pub const max_units = 8;

pub const Unit = struct {
    present: bool = false,
    // Physical bus slot currently occupying this unit (car_count + line*3 + slot),
    // -1 when the unit is free. A clearing bus keeps its unit until it is empty.
    bus: i32 = -1,
    // Unavailable for dispatch. Ends at `service_end`; an unpaid repair stays
    // unavailable rather than creating hidden debt.
    service: bool = false,
    paid: bool = false,
    service_end: f64 = 0,
    condition: f64 = 100,
};

pub const Account = struct {
    // Depot/yard capacity is the maximum number of owned units.
    depot: usize,
    name_index: usize = 0,
    opening: f64,
    cash: f64,
    // Driver roster: contracted day-qualified and night-qualified drivers.
    day: usize,
    night: usize,
    // Lifetime account components.
    fares: f64 = 0,
    subsidies: f64 = 0,
    receipts: f64 = 0,
    vehicle: f64 = 0,
    labour: f64 = 0,
    purchases: f64 = 0,
    sales: f64 = 0,
    recruitment: f64 = 0,
    severance: f64 = 0,
    maintenance: f64 = 0,
    // Slice 5: service credits paid to the municipality for chronic under-delivery.
    credits: f64 = 0,
    units: [max_units]Unit = @splat(.{}),
};

// Priced against the authored opening capital so the first fleet decision is
// reachable in a fresh town; this is a bounded abstraction, not a market price.
pub const vehicle_price: f64 = 520;
pub const vehicle_resale: f64 = 0.55;
pub const maintenance_cost: f64 = 160;
pub const maintenance_seconds: f64 = 240;
pub const day_recruit_cost: f64 = 150;
pub const night_recruit_cost: f64 = 260;
pub const severance_cost: f64 = 60;
pub const recruit_buffer: f64 = 60;
// Condition lost per in-service bus-second; a full daytime shift is about 19
// points, so maintenance is a routine operating decision rather than a crisis.
pub const wear_rate: f64 = 0.05;

pub var accounts: [3]Account = undefined;
pub var last_blocker: [3]u32 = @splat(0);

pub const ActionBlocker = enum(u32) {
    ok = 0,
    cash = 1,
    depot = 2,
    qualification = 3,
    coverage = 4,
    maintenance = 5,
    committed = 6,
    terms = 7,
};

pub fn init() void {
    accounts = .{
        .{ .depot = 6, .opening = 600, .cash = 600, .day = 4, .night = 2, .units = initial(4) },
        .{ .depot = 5, .opening = 300, .cash = 300, .day = 3, .night = 1, .units = initial(3) },
        .{ .depot = 3, .opening = 5, .cash = 5, .day = 2, .night = 0, .units = initial(2) },
    };
    last_blocker = @splat(0);
}

fn initial(count: usize) [max_units]Unit {
    var list: [max_units]Unit = @splat(.{});
    for (0..count) |i| list[i] = .{ .present = true, .condition = 100 };
    return list;
}

pub fn daytime(time: f64) bool {
    const t = @mod(time, 480);
    return t >= 120 and t < 440;
}

pub fn scheduled(window: u32, time: f64) bool {
    return window == 0 or daytime(time);
}

// Recruited drivers available for the current shift. The night cohort covers
// the 22:00-06:00 window only; daytime service uses day-qualified drivers.
pub fn drivers(id: usize, time: f64) usize {
    if (daytime(time)) return accounts[id].day;
    // Night duty needs both the endorsement and a driver physically assigned to
    // the night shift; a day-qualified driver without the endorsement cannot
    // cover it. The night cohort is a subset of the roster, so cap it by day.
    return @min(accounts[id].night, accounts[id].day);
}

fn integral(window: u32, time: f64) f64 {
    if (window == 0) return time;
    return @floor(time / 480) * 320 + std.math.clamp(@mod(time, 480) - 120, 0, 320);
}

pub fn hours(window: u32, from: f64, to: f64) f64 {
    return @max(0, integral(window, to) - integral(window, from));
}

// Charge the per-second vehicle and wage costs. A failed charge never partly
// debits the account; the caller retires the bus safely.
pub fn expense(id: usize, vehicle: f64, labour: f64) bool {
    const a = &accounts[id];
    if (a.cash < vehicle + labour) return false;
    a.cash -= vehicle + labour;
    a.vehicle += vehicle;
    a.labour += labour;
    return true;
}

fn debit(id: usize, amount: f64, field: *f64) bool {
    const a = &accounts[id];
    const value = std.math.round(amount * 100) / 100;
    if (value <= 0 or a.cash < value) return false;
    a.cash -= value;
    field.* += value;
    return true;
}

pub fn owned(id: usize) usize {
    var count: usize = 0;
    for (accounts[id].units) |unit| if (unit.present) {
        count += 1;
    };
    return count;
}

pub fn underMaintenance(id: usize) usize {
    var count: usize = 0;
    for (accounts[id].units) |unit| if (unit.present and unit.service) {
        count += 1;
    };
    return count;
}

pub fn available(id: usize) usize {
    return owned(id) -| underMaintenance(id);
}

pub fn attached(id: usize) usize {
    var count: usize = 0;
    for (accounts[id].units) |unit| if (unit.present and unit.bus >= 0) {
        count += 1;
    };
    return count;
}

pub fn freeUnits(id: usize) usize {
    var count: usize = 0;
    for (accounts[id].units) |unit| if (unit.present and unit.bus < 0 and !unit.service) {
        count += 1;
    };
    return count;
}

pub fn condition(id: usize) f64 {
    var total: f64 = 0;
    var count: usize = 0;
    for (accounts[id].units) |unit| if (unit.present) {
        total += unit.condition;
        count += 1;
    };
    if (count == 0) return 0;
    return total / @as(f64, @floatFromInt(count));
}

fn bestFreeUnit(id: usize) i32 {
    const a = &accounts[id];
    var best: i32 = -1;
    var score: f64 = -1;
    for (&a.units, 0..) |*unit, i| {
        if (!unit.present or unit.bus >= 0 or unit.service) continue;
        if (unit.condition > score) {
            score = unit.condition;
            best = @intCast(i);
        }
    }
    return best;
}

// Attach the best free unit to a physical bus. Returns the unit index or -1.
pub fn takeUnit(id: usize, bus: usize) i32 {
    const unit = bestFreeUnit(id);
    if (unit < 0) return -1;
    accounts[id].units[@intCast(unit)].bus = @intCast(bus);
    return unit;
}

// Release a unit when its bus has safely cleared. A unit scheduled for
// maintenance remains unavailable until its service window finishes.
pub fn releaseUnit(id: usize, unit: i32) void {
    if (unit < 0 or unit >= max_units) return;
    accounts[id].units[@intCast(unit)].bus = -1;
}

pub fn attachedUnit(id: usize, bus: usize) i32 {
    for (&accounts[id].units, 0..) |*unit, i| {
        if (unit.present and unit.bus == @as(i32, @intCast(bus))) return @intCast(i);
    }
    return -1;
}

// A unit is unavailable for service while it is under maintenance, and also
// while an unpaid queued repair blocks it.
pub fn unitUnavailable(id: usize, unit: i32) bool {
    if (id >= accounts.len or unit < 0 or unit >= max_units) return false;
    return accounts[id].units[@intCast(unit)].service;
}

// Wear only while the bus is delivering service: moving, dwelling at a stop or
// held in traffic all consume the unit. Clearing and unpaid repair do not.
pub fn wear(id: usize, bus: usize, amount: f64) void {
    const index = attachedUnit(id, bus);
    if (index < 0) return;
    const unit = &accounts[id].units[@intCast(index)];
    unit.condition = @max(0, unit.condition - amount);
    if (unit.condition <= 0 and !unit.service) beginRepair(id, @intCast(index), false);
}

// Start a repair. A player-initiated repair is paid up front and refused when
// cash is short; an exhaustion repair is queued and paid when funds allow.
fn beginRepair(id: usize, index: usize, charge_now: bool) void {
    const unit = &accounts[id].units[index];
    unit.service = true;
    unit.service_end = 0; // completed by update(), which knows simulation time
    unit.paid = charge_now and debit(id, maintenance_cost, &accounts[id].maintenance);
}

pub fn repairDue(id: usize, time: f64) usize {
    var count: usize = 0;
    for (accounts[id].units) |unit| if (unit.present and unit.service and unit.paid and unit.service_end > 0 and time >= unit.service_end) {
        count += 1;
    };
    return count;
}

// Advance maintenance: finish paid repairs and pay queued ones as cash allows.
pub fn update(time: f64) void {
    for (&accounts, 0..) |*account, id| {
        for (&account.units, 0..) |*unit, index| {
            _ = index;
            if (!unit.present or !unit.service) continue;
            if (!unit.paid) {
                if (debit(id, maintenance_cost, &account.maintenance)) unit.paid = true;
            }
            if (unit.paid and unit.service_end <= 0) unit.service_end = time + maintenance_seconds;
            if (unit.paid and unit.service_end > 0 and time >= unit.service_end) {
                unit.service = false;
                unit.paid = false;
                unit.service_end = 0;
                unit.condition = 100;
            }
        }
    }
}

pub fn quote(id: usize, field: u32) f64 {
    if (id >= accounts.len) return -1;
    return switch (field) {
        0 => vehicle_price,
        1 => vehicle_resale,
        2 => maintenance_cost,
        3 => day_recruit_cost,
        4 => night_recruit_cost,
        5 => severance_cost,
        6 => @floatFromInt(accounts[id].depot -| owned(id)),
        7 => @floatFromInt(underMaintenance(id)),
        8 => @floatFromInt(freeUnits(id)),
        9 => @floatFromInt(@as(u32, @intFromEnum(buyReason(id)))),
        10 => @floatFromInt(@as(u32, @intFromEnum(recruitReason(id, false)))),
        11 => @floatFromInt(@as(u32, @intFromEnum(recruitReason(id, true)))),
        12 => @floatFromInt(@as(u32, @intFromEnum(maintainReason(id)))),
        13 => @floatFromInt(accounts[id].day),
        14 => @floatFromInt(accounts[id].night),
        15 => @floatFromInt(covered(id, false)),
        16 => @floatFromInt(covered(id, true)),
        else => -1,
    };
}

// Drivers that can actually be rostered today: night coverage needs the
// endorsement and enough day-qualified drivers to keep the roster real.
pub fn covered(id: usize, night: bool) usize {
    if (!night) return accounts[id].day;
    return @min(accounts[id].night, accounts[id].day);
}

pub fn unitQuote(id: usize, unit: usize, field: u32) f64 {
    if (id >= accounts.len or unit >= max_units) return -1;
    const value = accounts[id].units[unit];
    if (!value.present) return -1;
    return switch (field) {
        0 => 1,
        1 => value.condition,
        2 => if (value.service) 1 else 0,
        3 => if (value.bus >= 0) 1 else 0,
        4 => @floatFromInt(value.bus),
        5 => if (value.paid) 1 else 0,
        6 => value.service_end,
        7 => std.math.round(vehicle_price * vehicle_resale * value.condition / 100 * 100) / 100,
        8 => if (value.bus < 0 and !value.service) @as(f64, @floatFromInt(@as(u32, @intFromEnum(ActionBlocker.ok)))) else if (value.service) @floatFromInt(@as(u32, @intFromEnum(ActionBlocker.maintenance))) else @floatFromInt(@as(u32, @intFromEnum(ActionBlocker.committed))),
        9 => std.math.round((100 - value.condition) / 100 * maintenance_cost * 100) / 100,
        else => -1,
    };
}

pub fn buyReason(id: usize) ActionBlocker {
    if (id >= accounts.len) return .terms;
    if (accounts[id].cash < vehicle_price) return .cash;
    if (owned(id) >= accounts[id].depot) return .depot;
    return .ok;
}

pub fn buy(id: usize) bool {
    if (buyReason(id) != .ok) return false;
    const account = &accounts[id];
    if (!debit(id, vehicle_price, &account.purchases)) return false;
    for (&account.units) |*unit| {
        if (!unit.present) {
            unit.* = .{ .present = true, .condition = 100 };
            return true;
        }
    }
    // Unreachable while depot <= max_units; refund rather than lose cash.
    account.purchases -= vehicle_price;
    account.cash += vehicle_price;
    return false;
}

pub fn sell(id: usize, unit: usize) bool {
    if (id >= accounts.len or unit >= max_units) return false;
    const account = &accounts[id];
    const value = &account.units[unit];
    if (!value.present or value.bus >= 0) return false;
    const price = std.math.round(vehicle_price * vehicle_resale * value.condition / 100 * 100) / 100;
    value.* = .{};
    account.sales += price;
    account.cash += price;
    return true;
}

pub fn sellReason(id: usize, unit: usize) ActionBlocker {
    if (id >= accounts.len or unit >= max_units) return .terms;
    const value = accounts[id].units[unit];
    if (!value.present) return .terms;
    if (value.bus >= 0) return .committed;
    return .ok;
}

pub fn recruitReason(id: usize, night: bool) ActionBlocker {
    if (id >= accounts.len) return .terms;
    // Qualification is a prerequisite, not a cash question: report it first.
    if (night and accounts[id].day <= accounts[id].night) return .qualification;
    const cost = if (night) night_recruit_cost else day_recruit_cost;
    if (accounts[id].cash < cost + recruit_buffer) return .cash;
    return .ok;
}

pub fn recruit(id: usize, night: bool) bool {
    if (recruitReason(id, night) != .ok) return false;
    const account = &accounts[id];
    const cost = if (night) night_recruit_cost else day_recruit_cost;
    if (!debit(id, cost, &account.recruitment)) return false;
    if (night) {
        account.night += 1;
    } else {
        account.day += 1;
    }
    return true;
}

pub fn dismissReason(id: usize, night: bool) ActionBlocker {
    if (id >= accounts.len) return .terms;
    const available_count = if (night) accounts[id].night else accounts[id].day;
    if (available_count == 0) return .terms;
    if (accounts[id].cash < severance_cost) return .cash;
    return .ok;
}

pub fn dismiss(id: usize, night: bool) bool {
    if (dismissReason(id, night) != .ok) return false;
    const account = &accounts[id];
    if (!debit(id, severance_cost, &account.severance)) return false;
    if (night) {
        account.night -= 1;
    } else {
        account.day -= 1;
        if (account.night > account.day) account.night = account.day;
    }
    return true;
}

pub fn maintainReason(id: usize) ActionBlocker {
    if (id >= accounts.len) return .terms;
    if (accounts[id].cash < maintenance_cost) return .cash;
    return .ok;
}

// Player-initiated maintenance: a paid, bounded downtime. The unit is released
// from live service (its bus clears safely) and returns at full condition.
pub fn maintain(id: usize, unit: usize) bool {
    if (id >= accounts.len or unit >= max_units) return false;
    const account = &accounts[id];
    const value = &account.units[unit];
    if (!value.present or value.service) return false;
    if (!debit(id, maintenance_cost, &account.maintenance)) return false;
    value.service = true;
    value.paid = true;
    value.service_end = 0;
    // The caller marks the occupying bus for safe retirement; its unit stays
    // attached until the bus is empty, then releaseUnit() drops the link.
    return true;
}
