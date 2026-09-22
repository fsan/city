const std = @import("std");
const transport = @import("transport.zig");
const finance = @import("finance.zig");
const operators = @import("operators.zig");
pub const StopResult = struct {
    visits: u32 = 0,
    latest: f64 = -1,
    intervals: u32 = 0,
    exceeded: u32 = 0,
    last: f64 = -1,
    worst: f64 = -1,
};
pub const Agreement = struct {
    max_interval: f64 = 0,
    regularity_suspended: bool = false,
    regularity_time: f64 = 0,
    regularity_updated: f64 = 0,
    regularity: [transport.max_stops]StopResult = @splat(.{}),
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
    // Slice 5: cure-first service credit. Only delivered bus-seconds against the
    // windowed target integral are enforceable; regularity stays review-only.
    breach_start: f64 = 0, // 0 while no breach is observed
    cure_until: f64 = 0,
    breach_days: u32 = 0,
    credit_accrued: f64 = 0,
    credit_paid: f64 = 0,
    credit_waived: f64 = 0,
    settled_expected: f64 = 0, // expected integral already charged or excused
    settled_delivered: f64 = 0,
};
// One whole simulation day of grace before a remedy can accrue.
pub const cure_seconds: f64 = 480;
// A breach needs a full day of expected service before it can be declared.
pub const breach_floor: f64 = 0.85;
// Public refund of unrun service, at the operator's own vehicle + labour rate.
pub const credit_rate: f64 = 0.18;
// A remedy may never approach the contract value.
pub const credit_cap_fraction: f64 = 0.25;
pub var agreements: [transport.max_lines]Agreement = @splat(.{});
pub var history: [64]Agreement = undefined;
pub var history_count: usize = 0;
pub var next_number: usize = 1;
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
// Refusals (docs/abi.md): 0 eligible, 1 insufficient owned buses,
// 2 price below cost and margin, 3 invalid terms, 4 insufficient drivers,
// 5 working capital below the buffer, 6 off-hours coverage gap,
// 7 vehicle under maintenance, 8 unit still committed to a live service.
pub fn reason(line: usize, company: usize, fleet: usize, days: f64, price: f64, window: u32) u32 {
    if (!validTerms(company, fleet, days, price) or window > 1) return 3;
    const c = &operators.accounts[company];
    const used = transport.committed(company, false, line);
    if ((operators.owned(company) -| used) < fleet) return 1;
    if ((operators.available(company) -| used) < fleet) return 7;
    if ((c.day -| used) < fleet) return 4;
    if (window == 0 and (operators.covered(company, true) -| transport.committed(company, true, line)) < fleet) return 6;
    if (c.cash < @as(f64, @floatFromInt(used + fleet)) * 12.8) return 5;
    if (finance.cents(price) < minimum(fleet, days, window)) return 2;
    return 0;
}
pub fn quote(line: usize, company: usize, fleet: usize, days: f64, price: f64, window: u32, field: u32) f64 {
    if (!validTerms(company, fleet, days, price) or window > 1) return if (field == 1) 3 else -1;
    return switch (field) {
        0 => minimum(fleet, days, window),
        1 => @floatFromInt(reason(line, company, fleet, days, price, window)),
        2 => @floatFromInt(operators.available(company) -| transport.committed(company, false, line)),
        3 => @as(f64, @floatFromInt(transport.committed(company, false, line) + fleet)) * 12.8,
        else => -1,
    };
}
pub fn validInterval(value: f64) bool {
    return std.math.isFinite(value) and (value == 0 or (value >= 30 and value <= 600 and @floor(value) == value));
}
pub fn offer(line: usize, company: usize, fleet: usize, days: f64, price: f64, window: u32, time: f64) bool {
    return offerTarget(line, company, fleet, days, price, window, 0, time);
}
pub fn offerTarget(line: usize, company: usize, fleet: usize, days: f64, price: f64, window: u32, max_interval: f64, time: f64) bool {
    if (!validInterval(max_interval)) return false;
    if (line >= transport.max_lines or !validTerms(company, fleet, days, price) or window > 1) return false;
    const a = &agreements[line];
    if (!transport.lines[line].active or a.status == 2 or finance.cents(price) > finance.available() + a.reserved) return false;
    if (a.status == 1) finish(a, time, 5);
    const l = &transport.lines[line];
    a.* = .{ .max_interval = max_interval, .window = window, .status = 1, .number = next_number, .line = line, .company = company, .fleet = fleet, .duration = days * 480, .price = finance.cents(price), .reserved = finance.cents(price), .offered = time, .updated = time, .reason = reason(line, company, fleet, days, price, window), .route_version = l.version, .stop_count = l.count, .stops = l.stops };
    next_number += 1;
    finance.reserved = finance.cents(finance.reserved + a.reserved);
    return true;
}
pub fn earned(a: *const Agreement) f64 {
    return @min(a.price, finance.cents(a.price * a.delivered / (@max(1, a.target))));
}
// Regularity review never writes money, delivery or acceptance rules.
pub fn checkRoute(line: usize, time: f64) void {
    if (line >= agreements.len) return;
    const a = &agreements[line];
    if (a.status != 2 or a.max_interval == 0) return;
    const l = &transport.lines[line];
    if (l.version != a.route_version or l.window != a.window or l.company != a.company) {
        a.regularity_suspended = true;
        a.regularity_time = @min(time, a.start + a.duration);
    }
}
fn measureRegularity(a: *Agreement, time: f64) void {
    if (a.max_interval == 0) return;
    checkRoute(a.line, time);
    a.regularity_time = @min(time, a.start + a.duration);
    if (time <= a.regularity_updated) return;
    const from = a.regularity_updated;
    a.regularity_updated = time;
    if (a.regularity_suspended) return;
    for (transport.arrivals[0..transport.arrival_count]) |event| {
        if (event.line != a.line or event.company != a.company or event.version != a.route_version or
            event.time <= from or event.time <= a.start or event.time > a.regularity_time) continue;
        for (a.stops[0..a.stop_count], 0..) |node, index| {
            if (node != event.node) continue;
            const stop = &a.regularity[index];
            if (stop.visits > 0 and (a.window == 0 or @floor((stop.latest - 120) / 480) == @floor((event.time - 120) / 480))) {
                const interval = event.time - stop.latest;
                stop.intervals += 1;
                // Ignore tiny fixed-step floating-point drift at the exact target.
                if (interval > a.max_interval + 0.00001) stop.exceeded += 1;
                stop.last = interval;
                stop.worst = @max(stop.worst, interval);
            }
            stop.visits += 1;
            stop.latest = event.time;
            break;
        }
    }
}
fn windowStart(a: *const Agreement) f64 {
    return if (a.window == 0) a.start else @max(a.start, @floor(a.regularity_time / 480) * 480 + 120);
}
fn gapAge(a: *const Agreement, stop: *const StopResult) f64 {
    return @max(0, a.regularity_time - @max(windowStart(a), stop.latest));
}
// 0 disabled, 1 not accepted, 2 suspended, 3 off hours,
// 4 first-arrival grace, 5 first arrival overdue, 6 within gap, 7 gap overdue.
fn gapState(a: *const Agreement, stop: *const StopResult) u32 {
    if (a.max_interval == 0) return 0;
    if (a.start == 0) return 1;
    if (a.regularity_suspended) return 2;
    if (!operators.scheduled(a.window, a.regularity_time)) return 3;
    const overdue = gapAge(a, stop) > a.max_interval + 0.00001;
    if (stop.latest < windowStart(a)) return if (overdue) 5 else 4;
    return if (overdue) 7 else 6;
}
pub fn readStop(a: *const Agreement, index: usize, field: u32) f64 {
    if (a.status == 0 or index >= a.stop_count) return -1;
    const stop = &a.regularity[index];
    const state = gapState(a, stop);
    return switch (field) {
        0 => @floatFromInt(a.stops[index]),
        1 => @floatFromInt(stop.visits),
        2 => @floatFromInt(stop.intervals),
        3 => @floatFromInt(stop.exceeded),
        4 => stop.latest,
        5 => stop.worst,
        6 => @floatFromInt(state),
        7 => if (state >= 4) gapAge(a, stop) else -1,
        8 => stop.last,
        else => -1,
    };
}
fn regularityTotal(a: *const Agreement, field: u32) usize {
    var total: usize = 0;
    for (a.regularity[0..a.stop_count]) |stop| {
        total += switch (field) {
            24 => stop.intervals,
            25 => stop.exceeded,
            else => @as(usize, if (stop.intervals > 0) 1 else 0),
        };
    }
    return total;
}
pub fn creditCap(a: *const Agreement) f64 {
    return finance.cents(a.price * credit_cap_fraction);
}
// 0 none, 1 curing, 2 breached, 3 capped, 4 closed while breached.
pub fn enforcementState(a: *const Agreement, time: f64) u32 {
    if (a.status >= 3) {
        if (a.breach_days == 0) return 0;
        // Closed during an open cure is still a cure state; closed after that
        // means the agreement ended with the shortfall unresolved or settled.
        if (a.credit_accrued <= 0 and a.updated < a.cure_until) return 1;
        return 4;
    }
    if (enforcementSuspended(a)) return 5; // suspended by a route/service change
    if (a.status != 2 or a.breach_start == 0) return 0;
    if (a.credit_accrued >= creditCap(a) - 0.0001) return 3;
    return if (time < a.cure_until) 1 else 2;
}
fn breach_now(a: *const Agreement) bool {
    return a.expected >= 480 and a.delivered < a.expected * breach_floor;
}
// A route, window or operator change suspends enforcement just as it suspends
// regularity review. The agreed clock keeps running; no charge can accrue
// against a service the operator was no longer contracted to run.
pub fn enforcementSuspended(a: *const Agreement) bool {
    if (a.status != 2 or a.line >= transport.lines.len) return false;
    const l = &transport.lines[a.line];
    return l.version != a.route_version or l.window != a.window or l.company != a.company;
}
// Cure first, then accrue the refund of unrun service up to the cap. Accrual is
// computed from the same measured integrals that earn payment, prorated on the
// final step exactly as measure() does, so no other evidence can charge money.
fn enforce(a: *Agreement, time: f64) void {
    if (enforcementSuspended(a)) {
        // A route, window or operator change permanently suspends enforcement
        // for this agreement. Retained credits are still settled at closure.
        a.breach_start = 0;
        a.cure_until = 0;
        a.breach_days = 0;
        a.settled_expected = a.expected;
        a.settled_delivered = a.delivered;
        return;
    }
    if (!breach_now(a)) {
        a.breach_start = 0;
        a.cure_until = 0;
        a.breach_days = 0;
        a.settled_expected = a.expected;
        a.settled_delivered = a.delivered;
        return;
    }
    if (a.breach_start == 0) {
        a.breach_start = time;
        a.cure_until = time + cure_seconds;
        a.breach_days = 1;
        a.settled_expected = a.expected;
        a.settled_delivered = a.delivered;
        return;
    }
    if (time < a.cure_until) {
        a.settled_expected = a.expected;
        a.settled_delivered = a.delivered;
        return;
    }
    const expected_delta = @max(0, a.expected - a.settled_expected);
    const delivered_delta = @max(0, a.delivered - a.settled_delivered);
    a.settled_expected = a.expected;
    a.settled_delivered = a.delivered;
    const missing = expected_delta - @min(expected_delta, delivered_delta);
    if (missing <= 0) return;
    a.breach_days +|= 1;
    a.credit_accrued = @min(creditCap(a), a.credit_accrued + missing * credit_rate);
}
// Pay from the operator's own cash above the dispatch floor, in whole pennies,
// in one transaction. Anything unpaid is waived, never debt.
pub fn creditOutstanding(a: *const Agreement) f64 {
    return finance.cents(@max(0, a.credit_accrued - a.credit_paid - a.credit_waived));
}
fn collectCredit(a: *Agreement, time: f64) void {
    const due = finance.cents(@max(0, a.credit_accrued - a.credit_paid - a.credit_waived));
    if (due <= 0) return;
    const account = &operators.accounts[a.company];
    const payable = finance.cents(@max(0, @min(due, account.cash - 2.18)));
    const waived = finance.cents(due - payable);
    if (payable > 0) {
        account.cash = finance.cents(account.cash - payable);
        account.credits = finance.cents(account.credits + payable);
        a.credit_paid = finance.cents(a.credit_paid + payable);
        finance.record(time, payable, 10, @intCast(a.company), @intCast(a.number));
    }
    if (waived > 0) a.credit_waived = finance.cents(a.credit_waived + waived);
}
fn measure(a: *Agreement, time: f64) void {
    measureRegularity(a, time);
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
    enforce(a, end);
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
        collectCredit(a, time);
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
            a.regularity_time = time;
            a.regularity_updated = time;
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
            collectCredit(a, time);
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
        23 => a.max_interval,
        24...26 => @floatFromInt(regularityTotal(a, field)),
        27 => if (a.regularity_suspended) 1 else 0,
        28 => a.regularity_time,
        29 => @floatFromInt(enforcementState(a, a.updated)),
        30 => a.credit_accrued,
        31 => a.credit_paid,
        48 => a.credit_waived,
        49 => creditCap(a),
        50 => a.breach_start,
        51 => a.cure_until,
        52 => @floatFromInt(a.breach_days),
        53 => if (a.status == 2 and breach_now(a) and !enforcementSuspended(a)) 1 else 0,
        54 => creditOutstanding(a),
        32...47 => if (field - 32 < a.stop_count) @floatFromInt(a.stops[field - 32]) else -1,
        else => -1,
    };
}
