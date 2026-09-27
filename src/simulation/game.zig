const std = @import("std");
pub const city = @import("../scene/city.zig");
pub const transport = @import("transport.zig");
pub const residents = @import("residents.zig");
pub const finance = @import("finance.zig");
pub const roadworks = @import("roads.zig");
pub const parcels = @import("../scene/parcels.zig");
pub const agreements = @import("agreements.zig");
pub const contracts = @import("contracts.zig");
pub const calendar = @import("calendar.zig");
pub const households = @import("households.zig");
pub const employment = @import("employment.zig");
pub const housing = @import("housing.zig");
pub const parking = @import("parking.zig");
pub const development = @import("development.zig");
pub const travel = @import("travel.zig");
pub const parks = @import("parks.zig");
pub const incidents = @import("incidents.zig");
pub const freight = @import("freight.zig");
pub const lighting = @import("lighting.zig");
pub var elapsed: f64 = 160;
pub var trust: [city.district_count]f32 = undefined;
pub const Sample = struct { time: f64, cash: f64, reserved: f64, walking: usize, condition: f32 };
pub var history: [96]Sample = undefined;
pub var history_count: usize = 0;
pub var next_sample: f64 = 160;
pub var next_routes: f64 = 220;
pub var next_operating: f64 = 190;
pub var next_week: f64 = 0;
pub fn init() void {
    elapsed = 160;
    next_sample = 160;
    next_routes = 220;
    next_operating = 190;
    next_week = calendar.nextWeekStart(elapsed);
    history_count = 0;
    transport.init();
    residents.init();
    finance.init(elapsed);
    finance.operating(elapsed);
    contracts.init();
    // Slice 20 repair: the development plan marks a works surface while the
    // authored town is laid out, but the contract register that must own a
    // works flag is reset here. A road with no live order may not claim works
    // (the snapshot validator enforces the pairing), so clear the orphan.
    for (city.roads) |*r| r.works = false;
    agreements.init();
    employment.init();
    housing.init();
    parking.init();
    parks.init();
    incidents.init();
    freight.init();
    lighting.init();
    development.init();
    roadworks.reset();
    parcels.init();
    // Numbered item 17 integration: the development plan's job is to exercise
    // every feature and the integrations between them in one town, so it does
    // not wait for a player. `city.forceAllFeatures` has already given every
    // district green space, a depot and a crosswalk on every junction arm;
    // `lighting.seed` lights every eligible segment, and here the town zones the
    // vacant land, designates loading bays on the central streets and lodges a
    // real work order.
    if (city.developmentPlan()) seedIntegrationTown();
    // Measure the first demand and buildability snapshot after zoning exists.
    development.measure();
    for (&trust, 0..) |*value, i| value.* = 20 + city.condition(i) * 0.65;
}
pub fn update(dt: f32) void {
    const day = @floor(elapsed / 480);
    elapsed += dt;
    // Slice 12: queued police or firefighter alerts reach the signals here, and
    // any timed emergency hold expires back to the normal cycle.
    transport.signals.update(elapsed);
    if (@floor(elapsed / 480) > day) {
        // Explicit simplified local trading: staffed businesses earn a daily operating surplus.
        // Contractors live on contracts; municipal institutions do not have taxable assessments.
        // Numbered item 16: freight is dispatched for the new day before the
        // trading step reads the access it produced. A business that received
        // its deliveries keeps the full documented surplus; one that could not
        // be reached trades at a bounded loss.
        freight.daily(elapsed);
        lighting.daily(calendar.dayIndex(elapsed));
        for (residents.companies[0..residents.company_count], 0..) |*c, i| {
            // Explicit simplified local trading: a staffed non-contractor position
            // earns its posted wage plus the documented GBP 12 daily surplus, so
            // the firm can cover the wage bill and still accumulate working cash.
            if (!c.contractor) c.cash += @as(f64, @floatFromInt(c.employees)) * (c.wage + 12 * @as(f64, freight.access(i)));
        }
        finance.daily(elapsed);
        employment.daily();
        households.daily();
        housing.daily();
        parking.daily();
        parking.refreshPrices(&transport.movement);
        residents.daily();
        // Slice 13: park condition and amenity are measured on the settled
        // rollover, after the day's visits have been counted.
        parks.daily();
        // Slice 18: private developers read the day's settled town - occupied
        // homes, staffed premises and the zoning the player has applied - so a
        // proposal is only ever lodged against measured demand.
        development.daily(elapsed);
    }
    // Bounded construction: a permit granted earlier completes on its own
    // schedule, and the check costs nothing while nothing is being built.
    development.update(dt, elapsed);
    parks.update(dt);
    // Numbered item 15: incidents advance through reported/responding/clearing
    // and book the recovery crew's bounded spend as ledger kind 15.
    const incident_spend = incidents.update(dt, elapsed);
    if (incident_spend > 0) finance.record(elapsed, -incident_spend, 15, -1, -1);
    // Numbered item 16: delivery runs travel, hold a kerbside loading bay while
    // they unload, and pay their private fee on delivery.
    freight.update(dt, elapsed);
    if (elapsed >= next_operating) {
        finance.operating(elapsed);
        const parks_due = parks.instalmentDue();
        if (parks_due > 0) {
            const parks_paid = @min(parks_due, finance.available());
            if (parks_paid > 0) {
                finance.record(elapsed, -parks_paid, 13, -1, -1);
                parks.applyPayment(parks_paid);
            }
        }
        // Numbered item 17: the day's electricity is paid in bounded
        // instalments and failed columns are repaired, both capped by the cash
        // actually available. Electricity is ledger kind 16 and the works
        // (capital columns plus repairs) are kind 17.
        const lighting_spend = lighting.update(dt, elapsed, finance.available());
        if (lighting_spend.electricity > 0) finance.record(elapsed, -lighting_spend.electricity, 16, -1, -1);
        if (lighting_spend.works > 0) finance.record(elapsed, -lighting_spend.works, 17, -1, -1);
        next_operating = elapsed + 30;
    }
    if (elapsed >= next_week) {
        finance.closeWeek(calendar.weekIndex(elapsed));
        next_week = calendar.nextWeekStart(elapsed);
    }
    for (city.roads) |*r| {
        const gain: f32 = @floatCast(@as(f64, @floatFromInt(finance.active_funding)) * 0.03 * finance.maintenance_paid - 0.025);
        r.condition = std.math.clamp(r.condition + gain * dt, 5, 100);
    }
    for (&trust, 0..) |*value, i| value.* += (20 + city.condition(i) * 0.65 + parks.districtBenefit(i) * 6 - value.*) * dt / 120;
    transport.subsidy_available = finance.available();
    transport.subsidy_due = 0;
    // Finish or fund routine fleet maintenance before dispatch decides.
    transport.operators.update(elapsed);
    transport.update(dt, elapsed);
    residents.update(dt, elapsed);
    // Slice 10: the learned trip-time and parking models are folded in as one
    // bounded batch of arrivals, and parking fees reach the municipal ledger.
    residents.flushBatch();
    if (parking.dues > 0) {
        finance.record(elapsed, parking.dues, 11, -1, -1);
        parking.dues = 0;
    }
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

// Numbered item 17 integration: switch the authored town's remaining features
// on in place, using ordinary records so the snapshot, the renderer and every
// report agree by construction.
fn seedIntegrationTown() void {
    // 1. Zone the vacant land so the permit queue has buildable sites. The zone
    // cycles through residential, commercial, industrial and mixed, so the
    // demand measurement sees more than one market.
    for (0..parcels.count) |i| {
        const p = &parcels.storage[i];
        if (p.building >= 0 or p.zone != 0) continue;
        p.zone = 1 + @as(u32, @intCast(i % 4));
    }

    // 2. Designate loading bays on the eligible streets near the centre, so
    // freight holds a real kerbside bay and the parking supply pays for it.
    const centre_x = city.origin_x + city.size_x * 0.5;
    const centre_z = city.origin_z + city.size_z * 0.5;
    var bays_set: usize = 0;
    for (city.roads, 0..) |r, i| {
        if (bays_set >= 8) break;
        if (!freight.eligible(i)) continue;
        const mid_x = (city.nodes[r.a].x + city.nodes[r.b].x) * 0.5;
        const mid_z = (city.nodes[r.a].z + city.nodes[r.b].z) * 0.5;
        if (city.hypot(mid_x - centre_x, mid_z - centre_z) > 300) continue;
        if (!freight.setBays(i, 2)) continue;
        bays_set += 1;
    }
    if (bays_set > 0) parking.rebuild();

    // 3. Lodge a real work order on a central street. It goes through the
    // ordinary offer and review path, so a contractor is genuinely assigned and
    // its crew genuinely travels to the site before the works surface lights.
    var orders_made: usize = 0;
    for (city.roads, 0..) |r, i| {
        if (orders_made >= 2) break;
        if (r.class < 1 or r.works or contracts.siteBusy(i)) continue;
        const mid_x = (city.nodes[r.a].x + city.nodes[r.b].x) * 0.5;
        const mid_z = (city.nodes[r.a].z + city.nodes[r.b].z) * 0.5;
        if (city.hypot(mid_x - centre_x, mid_z - centre_z) > 300) continue;
        const scope: f32 = 25;
        const price = orderPriceFor(i, scope);
        if (price <= 0) continue;
        if (contracts.offer(i, scope, price, elapsed) == 0) orders_made += 1;
    }
}

// The price a work order must carry to be accepted: the cheapest reachable
// contractor's own estimate plus a small margin, so the offer clears `reason`.
// Zero means no contractor can take the site.
fn orderPriceFor(road: usize, scope: f32) f64 {
    var best: f64 = 0;
    for (residents.companies[0..residents.company_count], 0..) |c, company| {
        if (!c.contractor or c.crew_count < 4 or c.order >= 0) continue;
        // A price far above any estimate isolates the non-price refusals.
        if (contracts.reason(company, road, scope, 1e9) != 0) continue;
        const minimum = contracts.estimate(company, road, scope);
        if (best == 0 or minimum < best) best = minimum;
    }
    if (best <= 0) return 0;
    return finance.cents(@min(best * 1.15, finance.available() * 0.4));
}
