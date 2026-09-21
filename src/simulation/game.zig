const std = @import("std");
pub const city = @import("../scene/city.zig");
pub const transport = @import("transport.zig");
pub const residents = @import("residents.zig");
pub const finance = @import("finance.zig");
pub const roadworks = @import("roads.zig");
pub const parcels = @import("../scene/parcels.zig");
pub const agreements = @import("agreements.zig");
pub const contracts = @import("contracts.zig");
pub var elapsed: f64 = 160;
pub var trust: [city.district_count]f32 = undefined;
pub const Sample = struct { time: f64, cash: f64, reserved: f64, walking: usize, condition: f32 };
pub var history: [96]Sample = undefined;
pub var history_count: usize = 0;
pub var next_sample: f64 = 160;
pub var next_routes: f64 = 220;
pub var next_operating: f64 = 190;
pub fn init() void {
    elapsed = 160;
    next_sample = 160;
    next_routes = 220;
    next_operating = 190;
    history_count = 0;
    transport.init();
    residents.init();
    finance.init(elapsed);
    finance.operating(elapsed);
    contracts.init();
    agreements.init();
    roadworks.reset();
    parcels.init();
    for (&trust, 0..) |*value, i| value.* = 20 + city.condition(i) * 0.65;
}
pub fn update(dt: f32) void {
    const day = @floor(elapsed / 480);
    elapsed += dt;
    if (@floor(elapsed / 480) > day) {
        // Explicit simplified local trading: staffed businesses earn a daily operating surplus.
        // Contractors live on contracts; municipal institutions do not have taxable assessments.
        for (residents.companies[0..residents.company_count]) |*c| {
            if (!c.contractor) c.cash += @as(f64, @floatFromInt(c.employees)) * 12;
        }
        finance.daily(elapsed);
        residents.daily();
    }
    if (elapsed >= next_operating) {
        finance.operating(elapsed);
        next_operating = elapsed + 30;
    }
    for (city.roads) |*r| {
        const gain: f32 = @floatCast(@as(f64, @floatFromInt(finance.active_funding)) * 0.03 * finance.maintenance_paid - 0.025);
        r.condition = std.math.clamp(r.condition + gain * dt, 5, 100);
    }
    for (&trust, 0..) |*value, i| value.* += (20 + city.condition(i) * 0.65 - value.*) * dt / 120;
    transport.subsidy_available = finance.available();
    transport.subsidy_due = 0;
    transport.update(dt, elapsed);
    residents.update(dt, elapsed);
    agreements.update(elapsed);
    if (transport.subsidy_due > 0) finance.record(elapsed, -transport.subsidy_due, 7, -1, -1);
    contracts.update(dt, elapsed);
    if (elapsed >= next_routes) {
        city.rebuildRoutes();
        next_routes = elapsed + 60;
    }
    if (elapsed >= next_sample) {
        var condition: f32 = 0;
        for (city.roads) |r| condition += r.condition;
        history[history_count % history.len] = .{ .time = elapsed, .cash = finance.cash, .reserved = finance.reserved, .walking = residents.walking, .condition = condition / @as(f32, @floatFromInt(city.roads.len)) };
        history_count += 1;
        next_sample = elapsed + 30;
    }
}
