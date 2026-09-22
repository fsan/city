const std = @import("std");
const city = @import("../scene/city.zig");
const residents = @import("residents.zig");
const housing = @import("housing.zig");
const households = @import("households.zig");
const calendar = @import("calendar.zig");
pub const Entry = struct { time: f64, amount: f64, balance: f64, kind: u32, party: i32, order: i32 };
// Slice 6: bounded weekly budget period derived from recorded ledger entries.
pub const Period = struct { week: u32 = 0, opening: f64 = 0, receipts: f64 = 0, expenses: f64 = 0, closing: f64 = 0, entries: u32 = 0 };
pub var entries: [1024]Entry = undefined;
pub var entry_count: usize = 0;
pub var cash: f64 = 180000;
pub var reserved: f64 = 0;
pub var residential_rate: f64 = 1.2;
pub var commercial_rate: f64 = 1.8;
pub var funding: usize = 1;
pub const maintenance = [_]f64{ 2000, 6000, 11000 };
pub const services: f64 = 4000;
pub var arrears: [city.buildings.len]f64 = undefined;
pub var maintenance_paid: f64 = 1;
pub var active_funding: usize = 1;
pub var collected: f64 = 0;
pub var spent: f64 = 0;
pub var periods: [12]Period = @splat(.{});
pub var period_count: u32 = 0;
pub var period_opening: f64 = 0;
pub var period_receipts: f64 = 0;
pub var period_expenses: f64 = 0;
pub var period_entries: u32 = 0;
pub var period_week: u32 = 0;
pub fn init(time: f64) void {
    cash = 0;
    reserved = 0;
    entry_count = 0;
    residential_rate = 1.2;
    commercial_rate = 1.8;
    funding = 1;
    maintenance_paid = 1;
    active_funding = 1;
    collected = 0;
    spent = 0;
    periods = @splat(.{});
    period_count = 0;
    period_opening = 0;
    period_receipts = 0;
    period_expenses = 0;
    period_entries = 0;
    period_week = calendar.weekIndex(time);
    @memset(&arrears, 0);
    record(time, 180000, 0, -1, -1);
    period_opening = cash;
}
pub fn cents(value: f64) f64 {
    return @round(value * 100) / 100;
}
pub fn available() f64 {
    return @max(0, cents(cash - reserved));
}
pub fn record(time: f64, amount: f64, kind: u32, party: i32, order: i32) void {
    const value = cents(amount);
    cash = cents(cash + value);
    if (kind == 1 or kind == 2) collected += value;
    if (value < 0) spent -= value;
    entries[entry_count % entries.len] = .{ .time = time, .amount = value, .balance = cash, .kind = kind, .party = party, .order = order };
    entry_count += 1;
    // The opening reserves entry establishes the period opening balance, not a
    // recurring receipt; every other movement is part of the weekly summary.
    if (kind != 0) {
        if (value >= 0) period_receipts = cents(period_receipts + value) else period_expenses = cents(period_expenses - value);
    }
    period_entries +|= 1;
}

// Close the current week from recorded ledger movements only. No money is
// created, destroyed or moved; opening + receipts - expenses must equal closing.
pub fn closeWeek(week: u32) void {
    const summary = Period{ .week = week, .opening = period_opening, .receipts = period_receipts, .expenses = period_expenses, .closing = cash, .entries = period_entries };
    periods[period_count % periods.len] = summary;
    period_count +|= 1;
    period_opening = cash;
    period_receipts = 0;
    period_expenses = 0;
    period_entries = 0;
    period_week = week + 1;
}

pub fn periodRead(index: u32, field: u32) f64 {
    const count = @min(period_count, periods.len);
    if (index >= count) return -1;
    const p = periods[(period_count - 1 - index) % periods.len];
    return switch (field) {
        0 => @floatFromInt(p.week),
        1 => p.opening,
        2 => p.receipts,
        3 => p.expenses,
        4 => p.closing,
        5 => @floatFromInt(p.entries),
        else => -1,
    };
}
pub fn base(home: bool) f64 {
    var total: f64 = 0;
    for (city.buildings) |b| {
        if ((b.kind == .home) == home) total += b.value;
    }
    return total;
}
pub fn bill(building: usize) f64 {
    const b = city.buildings[building];
    return cents(b.value * (if (b.kind == .home) residential_rate else commercial_rate) / 100 / 360);
}
pub fn projection() f64 {
    var total: f64 = 0;
    for (0..city.buildings.len) |i| total += bill(i);
    return total;
}
pub fn daily(time: f64) void {
    for (city.buildings, 0..) |b, i| {
        if (b.value == 0) continue;
        arrears[i] = cents(arrears[i] + bill(i));
        var payment = arrears[i];
        if (b.employer >= 0) {
            const company = &residents.companies[@intCast(b.employer)];
            payment = @min(payment, company.cash);
            company.cash = cents(company.cash - payment);
        } else if (b.kind == .home and housing.valid(i)) {
            // Slice 10: tenure decides who pays the municipal assessment. An
            // owner-occupier pays from the shared household balance; a rented
            // home is paid by its property owner out of rent actually collected.
            // An unpaid assessment stays as explicit municipal arrears.
            payment = if (housing.units[i].tenure == .rented) blk: {
                const paid = @min(payment, housing.units[i].owner_cash);
                housing.units[i].owner_cash = @max(0, housing.units[i].owner_cash - paid);
                break :blk paid;
            } else blk: {
                const paid = @min(payment, households.balance(i));
                if (paid > 0 and !households.spend(i, paid)) break :blk 0;
                break :blk paid;
            };
        }
        if (payment > 0) record(time, payment, if (b.kind == .home) 1 else 2, @intCast(i), -1);
        arrears[i] = cents(arrears[i] - payment);
    }
}
pub fn operating(time: f64) void {
    active_funding = funding;
    const service_payment = @min(available(), services / 16);
    if (service_payment > 0) record(time, -service_payment, 3, -1, -1);
    const payment = @min(available(), maintenance[funding] / 16);
    maintenance_paid = payment / (maintenance[funding] / 16);
    if (payment > 0) record(time, -payment, 4, -1, -1);
}
pub fn applyTaxes(home: f64, commercial: f64) bool {
    if (!std.math.isFinite(home) or !std.math.isFinite(commercial) or home < 0 or home > 5 or commercial < 0 or commercial > 5) return false;
    residential_rate = home;
    commercial_rate = commercial;
    return true;
}
