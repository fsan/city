const std = @import("std");
const transport = @import("transport.zig");
const finance = @import("finance.zig");
pub const Operator = struct { capacity: usize, assigned: usize = 0, cash: f64 = 0 };
pub var operators: [3]Operator = .{ .{ .capacity = 4 }, .{ .capacity = 3 }, .{ .capacity = 2 } };
pub const Agreement = struct {
    status: u32 = 0, // none, offered, active, expired, cancelled
    company: usize = 0,
    fleet: usize = 2,
    duration: f64 = 480,
    price: f64 = 0,
    paid: f64 = 0,
    reserved: f64 = 0,
    start: f64 = 0,
    delivered: f64 = 0,
    baseline: f64 = 0,
    updated: f64 = 0,
    reason: u32 = 0,
};
pub var agreements: [transport.max_lines]Agreement = @splat(.{});
pub fn init() void {
    operators = .{ .{ .capacity = 4 }, .{ .capacity = 3 }, .{ .capacity = 2 } };
    agreements = @splat(.{});
}
pub fn offer(line: usize, company: usize, fleet: usize, days: f64, price: f64) bool {
    if (line >= transport.max_lines or company >= operators.len or fleet < 1 or fleet > 3 or !std.math.isFinite(days) or days < 1 or days > 7 or !std.math.isFinite(price) or finance.cents(price) <= 0) return false;
    const a = &agreements[line];
    if (!transport.lines[line].active or a.status == 2 or finance.cents(price) > finance.available() + a.reserved) return false;
    finance.reserved -= a.reserved;
    a.* = .{ .status = 1, .company = company, .fleet = fleet, .duration = days * 480, .price = finance.cents(price), .reserved = finance.cents(price) };
    finance.reserved += a.reserved;
    return true;
}
pub fn cancel(line: usize) void {
    if (line >= agreements.len) return;
    const a = &agreements[line];
    if (a.status != 1 and a.status != 2) return;
    if (a.status == 2) {
        const earned = @min(a.price, finance.cents(a.price * a.delivered / (a.duration * @as(f64, @floatFromInt(a.fleet)))));
        const payment = finance.cents(@max(0, earned - a.paid));
        if (payment > 0) {
            a.paid += payment;
            a.reserved = finance.cents(a.reserved - payment);
            finance.reserved = finance.cents(finance.reserved - payment);
            finance.record(a.updated, -payment, 8, @intCast(a.company), @intCast(line));
            operators[a.company].cash += payment;
            transport.lines[line].cash += payment;
            transport.lines[line].revenue += payment;
        }
        operators[a.company].assigned -= a.fleet;
    }
    finance.reserved = finance.cents(finance.reserved - a.reserved);
    a.reserved = 0;
    a.status = 4;
}
pub fn update(time: f64) void {
    for (&agreements, 0..) |*a, line| {
        if (a.status != 1 and a.status != 2) continue;
        if (!transport.lines[line].active) {
            cancel(line);
            continue;
        }
        a.updated = time;
        const company = &operators[a.company];
        if (a.status == 1) {
            a.reason = if (company.capacity - company.assigned < a.fleet) 1 else if (a.price < a.duration * @as(f64, @floatFromInt(a.fleet)) * 0.18 * 1.15) 2 else 0;
            if (a.reason != 0) continue;
            a.status = 2;
            a.start = time;
            a.baseline = transport.lines[line].delivered;
            company.assigned += a.fleet;
            transport.lines[line].fleet = a.fleet;
        }
        a.delivered = @min(a.duration * @as(f64, @floatFromInt(a.fleet)), transport.lines[line].delivered - a.baseline);
        const earned = @min(a.price, finance.cents(a.price * a.delivered / (a.duration * @as(f64, @floatFromInt(a.fleet)))));
        if (earned - a.paid >= 1 or time >= a.start + a.duration) {
            const payment = finance.cents(@max(0, earned - a.paid));
            if (payment > 0) {
                a.paid += payment;
                a.reserved = finance.cents(a.reserved - payment);
                finance.reserved = finance.cents(finance.reserved - payment);
                finance.record(time, -payment, 8, @intCast(a.company), @intCast(line));
                company.cash += payment;
                transport.lines[line].cash += payment;
                transport.lines[line].revenue += payment;
            }
        }
        if (time >= a.start + a.duration) {
            company.assigned -= a.fleet;
            finance.reserved = finance.cents(finance.reserved - a.reserved);
            a.reserved = 0;
            a.status = 3;
        }
    }
}
