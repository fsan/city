const std = @import("std");
const city = @import("../scene/city.zig");
const residents = @import("residents.zig");
const finance = @import("finance.zig");
pub const Status = enum(u32) { offered, mobilising, working, completed, cancelled, blocked };
pub const Order = struct { road: usize, scope: f32, price: f64, status: Status = .offered, company: i32 = -1, progress: f32 = 0, created: f64, accepted: f64 = 0, finished: f64 = 0, reason: u32 = 0, costs: f64 = 0, paid: f64 = 0 };
pub var orders: [64]Order = undefined;
pub var count: usize = 0;
pub var next_review: f64 = 0;
pub fn init() void {
    count = 0;
    next_review = 0;
}
pub fn active(order: Order) bool {
    return order.status != .completed and order.status != .cancelled;
}
pub fn siteBusy(road: usize) bool {
    for (orders[0..count]) |o| {
        if (o.road == road and active(o)) return true;
    }
    return false;
}
// Return codes are explained in the UI; a failed command never changes funds.
pub fn offer(road: usize, scope: f32, price: f64, time: f64) u32 {
    if (road >= city.roads.len or !std.math.isFinite(scope) or scope < 5 or scope > 60 or !std.math.isFinite(price) or price < 100 or price > 1000000) return 1;
    if (count == orders.len) return 2;
    if (siteBusy(road)) return 3;
    if (price > finance.available()) return 4;
    orders[count] = .{ .road = road, .scope = @min(scope, 100 - city.roads[road].condition), .price = finance.cents(price), .created = time };
    if (orders[count].scope < 1) return 5;
    finance.reserved = finance.cents(finance.reserved + orders[count].price);
    count += 1;
    next_review = 0;
    return 0;
}
pub fn revise(id: usize, price: f64) u32 {
    if (id >= count or orders[id].status != .offered or !std.math.isFinite(price) or price < 100 or price > 1000000) return 1;
    const difference = finance.cents(price) - orders[id].price;
    if (difference > finance.available()) return 4;
    finance.reserved = finance.cents(finance.reserved + difference);
    orders[id].price = finance.cents(price);
    next_review = 0;
    return 0;
}
pub fn estimate(company: usize, road: usize, scope: f32) f64 {
    const c = residents.companies[company];
    const site = city.roads[road].a;
    var travel: f64 = 0;
    for (c.crew[0..c.crew_count]) |id| {
        const p = residents.people[id];
        const remaining = @sqrt((p.x - city.nodes[p.next].x) * (p.x - city.nodes[p.next].x) + (p.z - city.nodes[p.next].z) * (p.z - city.nodes[p.next].z));
        travel = @max(travel, city.distance[p.next][site] + remaining * 2);
    }
    return finance.cents((800 + (travel + @as(f64, scope) * 0.75) * 4 * c.labour) * c.margin);
}
pub fn reason(company: usize, road: usize, scope: f32, price: f64) u32 {
    const c = residents.companies[company];
    if (!c.contractor) return 3;
    if (c.order >= 0) return 2;
    if (c.crew_count < 4) return 3;
    for (c.crew[0..c.crew_count]) |id| if (city.distance[residents.people[id].next][city.roads[road].a] >= 1e8) return 5;
    const minimum = estimate(company, road, scope);
    if (c.cash < minimum / c.margin) return 4;
    if (price < minimum) return 1;
    return 0;
}
fn settle(id: usize, cancelled: bool, time: f64) void {
    const o = &orders[id];
    finance.reserved = finance.cents(@max(0, finance.reserved - o.price));
    if (o.company >= 0) {
        const company: usize = @intCast(o.company);
        const payment = if (cancelled) finance.cents(@min(o.price, o.price * (0.05 + o.progress * 0.95))) else o.price;
        finance.record(time, -payment, if (cancelled) 6 else 5, @intCast(company), @intCast(id));
        residents.companies[company].cash += payment;
        o.paid = payment;
        city.roads[o.road].condition = @min(100, city.roads[o.road].condition + o.scope * o.progress);
        residents.release(company);
    }
    city.roads[o.road].works = false;
    o.status = if (cancelled) .cancelled else .completed;
    o.finished = time;
    city.rebuildRoutes();
}
pub fn cancel(id: usize, time: f64) bool {
    if (id >= count or !active(orders[id])) return false;
    settle(id, true, time);
    return true;
}
pub fn update(dt: f32, time: f64) void {
    if (time >= next_review) {
        next_review = time + 5;
        for (orders[0..count], 0..) |*o, id| {
            if (o.status != .offered) continue;
            o.reason = 3;
            for (residents.companies[0..residents.company_count], 0..) |*c, company| {
                if (!c.contractor) continue;
                const why = reason(company, o.road, o.scope, o.price);
                if (why != 0) {
                    o.reason = why;
                    continue;
                }
                c.order = @intCast(id);
                c.cash -= 800;
                c.costs += 800;
                o.costs = 800;
                o.company = @intCast(company);
                o.status = .mobilising;
                o.accepted = time;
                o.reason = 0;
                for (c.crew[0..c.crew_count]) |person| residents.send(person, city.roads[o.road].a, @intCast(id));
                break;
            }
        }
    }
    for (orders[0..count], 0..) |*o, id| {
        if (o.company < 0 or !active(o.*)) continue;
        const c = &residents.companies[@intCast(o.company)];
        var arrived: usize = 0;
        for (c.crew[0..c.crew_count]) |person| {
            if (residents.people[person].arrived) arrived += 1;
        }
        const cost = c.labour * 4 * @as(f64, dt);
        if (c.cash < cost) {
            o.status = .blocked;
            o.reason = 4;
            city.roads[o.road].works = false;
            continue;
        }
        c.cash -= cost;
        c.costs += cost;
        o.costs += cost;
        o.reason = 0;
        if (arrived == 4) {
            o.status = .working;
            city.roads[o.road].works = true;
            o.progress = @min(1, o.progress + dt * 4 / (o.scope * 3));
            if (o.progress >= 1) settle(id, false, time);
        } else {
            o.status = .mobilising;
            city.roads[o.road].works = false;
        }
    }
}
