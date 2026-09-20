const std = @import("std");
const city = @import("../scene/city.zig");
const residents = @import("residents.zig");
pub const Entry = struct { time: f64, amount: f64, balance: f64, kind: u32, party: i32, order: i32 };
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
    @memset(&arrears, 0);
    record(time, 180000, 0, -1, -1);
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
