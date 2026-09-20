const std = @import("std");
const transport = @import("transport.zig");
const finance = @import("finance.zig");
const operators = @import("operators.zig");
pub const Agreement = struct {
    window: u32 = 0,
    target: f64 = 0,
    status: u32 = 0, // none, offered, active, expired, cancelled, revised, line withdrawn
    number: usize = 0,
    line: usize = 0,
    company: usize = 0,
    fleet: usize = 2,
    duration: f64 = 480,
    price: f64 = 0,
    paid: f64 = 0,
    reserved: f64 = 0,
    released: f64 = 0,
    offered: f64 = 0,
    start: f64 = 0,
    ended: f64 = 0,
    delivered: f64 = 0,
    expected: f64 = 0,
    baseline: f64 = 0,
    updated: f64 = 0,
    reason: u32 = 0,
    route_version: u32 = 0,
    stop_count: usize = 0,
    stops: [transport.max_stops]usize = @splat(0),
};
pub var agreements: [transport.max_lines]Agreement = @splat(.{});
pub var history: [64]Agreement = undefined;
pub var history_count: usize = 0;
var next_number: usize = 1;
pub fn init() void {
    agreements = @splat(.{});
    history_count = 0;
    next_number = 1;
}
fn validTerms(company: usize, fleet: usize, days: f64, price: f64) bool {
    return company < operators.accounts.len and fleet >= 1 and fleet <= transport.buses_per_line and std.math.isFinite(days) and days >= 1 and days <= 7 and @floor(days) == days and std.math.isFinite(price) and price > 0 and price <= 1e9 and finance.cents(price) > 0;
}
pub fn minimum(fleet: usize, days: f64, window: u32) f64 {
    return @ceil((days * (if (window == 0) @as(f64, 480) else 320) * 0.18 + @ceil(days) * 2) * @as(f64, @floatFromInt(fleet)) * 1.15 * 100 - 1e-7) / 100;
}
pub fn reason(line: usize, company: usize, fleet: usize, days: f64, price: f64, window: u32) u32 {
    if (!validTerms(company, fleet, days, price) or window > 1) return 3;
    const c = &operators.accounts[company];
    const used = transport.committed(company, false, line);
    if (c.capacity -| used < fleet) return 1;
    if (c.day -| used < fleet or (window == 0 and c.night -| transport.committed(company, true, line) < fleet)) return 4;
    if (c.cash < @as(f64, @floatFromInt(used + fleet)) * 12.8) return 5;
    if (finance.cents(price) < minimum(fleet, days, window)) return 2;
    return 0;
}
pub fn quote(line: usize, company: usize, fleet: usize, days: f64, price: f64, window: u32, field: u32) f64 {
    if (!validTerms(company, fleet, days, price) or window > 1) return if (field == 1) 3 else -1;
    return switch (field) {
        0 => minimum(fleet, days, window),
        1 => @floatFromInt(reason(line, company, fleet, days, price, window)),
        2 => @floatFromInt(operators.accounts[company].capacity -| transport.committed(company, false, line)),
        3 => @as(f64, @floatFromInt(transport.committed(company, false, line) + fleet)) * 12.8,
        else => -1,
    };
}
pub fn offer(line: usize, company: usize, fleet: usize, days: f64, price: f64, window: u32, time: f64) bool {
    if (line >= transport.max_lines or !validTerms(company, fleet, days, price) or window > 1) return false;
    const a = &agreements[line];
    if (!transport.lines[line].active or a.status == 2 or finance.cents(price) > finance.available() + a.reserved) return false;
    if (a.status == 1) finish(a, time, 5);
    const l = &transport.lines[line];
    a.* = .{ .window = window, .status = 1, .number = next_number, .line = line, .company = company, .fleet = fleet, .duration = days * 480, .price = finance.cents(price), .reserved = finance.cents(price), .offered = time, .updated = time, .reason = reason(line, company, fleet, days, price, window), .route_version = l.version, .stop_count = l.count, .stops = l.stops };
    next_number += 1;
    finance.reserved = finance.cents(finance.reserved + a.reserved);
    return true;
}
pub fn earned(a: *const Agreement) f64 {
    return @min(a.price, finance.cents(a.price * a.delivered / (@max(1, a.target))));
}
fn measure(a: *Agreement, time: f64) void {
    const end = @min(time, a.start + a.duration);
    // transport advances before agreement settlement. Prorate only the last step
    // across expiry, rather than charging for service after the agreed end.
    const share = if (time > a.updated) std.math.clamp((end - a.updated) / (time - a.updated), 0, 1) else 0;
    const current = transport.lines[a.line].delivered;
    const delta = @max(0, current - a.baseline) * share;
    a.expected = operators.hours(a.window, a.start, end) * @as(f64, @floatFromInt(a.fleet));
    a.delivered = @min(a.expected, a.delivered + delta);
    a.baseline = current;
    a.updated = time;
}
fn settle(a: *Agreement, time: f64) void {
    const payment = finance.cents(@max(0, earned(a) - a.paid));
    if (payment <= 0) return;
    a.paid = finance.cents(a.paid + payment);
    a.reserved = finance.cents(a.reserved - payment);
    finance.reserved = finance.cents(finance.reserved - payment);
    finance.record(time, -payment, 8, @intCast(a.company), @intCast(a.number));
    operators.accounts[a.company].cash += payment;
    operators.accounts[a.company].receipts += payment;
    transport.lines[a.line].revenue += payment;
}
fn finish(a: *Agreement, time: f64, status: u32) void {
    if (a.status == 2) {
        measure(a, time);
        settle(a, time);
    }
    a.released = a.reserved;
    finance.reserved = finance.cents(finance.reserved - a.reserved);
    a.reserved = 0;
    a.ended = time;
    a.status = status;
    history[history_count % history.len] = a.*;
    history_count += 1;
}
pub fn cancel(line: usize, time: f64, withdrawn: bool) void {
    if (line >= agreements.len) return;
    const a = &agreements[line];
    if (a.status != 1 and a.status != 2) return;
    finish(a, time, if (withdrawn) 6 else 4);
}
pub fn update(time: f64) void {
    for (&agreements, 0..) |*a, line| {
        if (a.status != 1 and a.status != 2) continue;
        if (!transport.lines[line].active) {
            cancel(line, time, true);
            continue;
        }
        if (a.status == 1) {
            a.reason = reason(line, a.company, a.fleet, a.duration / 480, a.price, a.window);
            if (a.reason != 0) continue;
            a.status = 2;
            a.start = time;
            a.updated = time;
            a.baseline = transport.lines[line].delivered;
            a.target = operators.hours(a.window, time, time + a.duration) * @as(f64, @floatFromInt(a.fleet));
            transport.lines[line].company = a.company;
            transport.lines[line].window = a.window;
            transport.lines[line].fleet = a.fleet;
        }
        if (time >= a.start + a.duration) {
            finish(a, time, 3);
        } else {
            measure(a, time);
            if (earned(a) - a.paid >= 1) settle(a, time);
        }
    }
}
pub fn read(a: *const Agreement, field: u32) f64 {
    return switch (field) {
        0 => @floatFromInt(a.status),
        1 => @floatFromInt(a.company),
        2 => @floatFromInt(a.fleet),
        3 => a.duration,
        4 => a.price,
        5 => a.paid,
        6 => a.reserved,
        7 => a.delivered,
        8 => @floatFromInt(a.reason),
        9 => a.start,
        10 => @floatFromInt(a.number),
        11 => a.expected,
        12 => earned(a),
        13 => a.released,
        14 => a.offered,
        15 => a.ended,
        16 => @floatFromInt(a.line),
        17 => @floatFromInt(a.route_version),
        18 => @floatFromInt(a.stop_count),
        19 => @floatFromInt(@min(history_count, history.len)),
        20 => @floatFromInt(history_count),
        21 => @floatFromInt(a.window),
        22 => a.target,
        32...47 => if (field - 32 < a.stop_count) @floatFromInt(a.stops[field - 32]) else -1,
        else => -1,
    };
}
