const std = @import("std");
const city = @import("../scene/city.zig");
const parcels = @import("../scene/parcels.zig");
const residents = @import("residents.zig");
const housing = @import("housing.zig");
const finance = @import("finance.zig");

// Slice 18 (numbered list item 10) created the bounded private development
// queue. Slice 19 (numbered list item 11) gives an approved permit a physical
// construction path: measured road access, a travelling contractor crew, staged
// materials, terrain grading and an explicit foundation cost. The lot is still
// redeveloped in place; only its use, height, value and capacity change.
//
// The applicant's construction budget is private. Groundwork, foundation,
// materials and crew labour are paid from that budget to the selected
// contractor; the municipal ledger still records only the development levy
// under kind 12.

pub const max_proposals = 24;
pub const max_pending = 8;
pub const max_lodged_per_day = 2;
pub const offer_days = 5;
pub const demand_threshold: f32 = 1.35;
pub const levy_rate: f64 = 0.0005;
pub const days = 480.0;

// Item 11 constants. They are deliberately explicit so a probe and the UI read
// the same rules the simulation applied.
pub const developer_budget_rate: f64 = 0.16;
pub const access_free_distance: f32 = 12;
pub const access_max_distance: f32 = 30;
pub const access_rate: f64 = 18;
pub const max_buildable_slope: f32 = 0.38;
pub const grading_rate: f64 = 140;
pub const foundation_rate: f64 = 95;
pub const materials_area_rate: f64 = 55;
pub const materials_height_rate: f64 = 12;
pub const labour_per_second: f64 = 0.04;
pub const work_order_base: i32 = 1_000_000;

pub const Decision = enum(u8) { offered = 0, approved = 1, refused = 2, lapsed = 3, built = 4 };

// One reason code per way a proposal can be refused, lapse or block. The
// original item-10 codes keep their numbers.
pub const Reason = enum(u8) {
    none = 0,
    no_site = 1,
    unzoned = 2,
    no_demand = 3,
    occupied = 4,
    refused = 5,
    lapsed = 6,
    no_access = 7,
    too_steep = 8,
    insufficient_funds = 9,
    crew_unavailable = 10,
    budget_exhausted = 11,
    crew_lost = 12,
};

// The physical stage of an approved job. `blocked` and `complete` are terminal
// until the next state-changing command or a reload.
pub const Phase = enum(u8) { none = 0, mobilising = 1, delivering = 2, building = 3, blocked = 4, complete = 5 };

pub const Proposal = struct {
    number: u32 = 0,
    parcel: usize = 0,
    // The authored lot this proposal redevelops. It equals `parcel` for every
    // site the scan can offer, because `parcels.init` writes a parcel and a lot
    // with the same index; it is stored rather than assumed.
    building: usize = 0,
    district: u8 = 0,
    zone: u8 = 0,
    kind: u8 = 0,
    height: f32 = 0,
    value: f64 = 0,
    capacity: usize = 0,
    levy: f64 = 0,
    offered: f64 = 0,
    deadline: f64 = 0,
    decided: f64 = 0,
    complete: f64 = 0,
    pressure: f32 = 0,
    decision: Decision = .offered,
    reason: Reason = .none,

    // Slice 19: the physical construction account. These fields are populated
    // when a proposal is lodged, revalidated when it is granted, and then
    // updated by the physical job.
    access: u8 = 0, // 0 unavailable, 1 free frontage, 2 paid access
    slope: f32 = 0,
    access_cost: f64 = 0,
    grade_cost: f64 = 0,
    foundation_cost: f64 = 0,
    materials_cost: f64 = 0,
    labour_cost: f64 = 0,
    budget: f64 = 0,
    spent: f64 = 0,
    materials_required: f64 = 0,
    materials_delivered: f64 = 0,
    company: i32 = -1,
    crew_count: u8 = 0,
    crew: [4]u32 = .{ 0, 0, 0, 0 },
    phase: Phase = .none,
    blocked: Reason = .none,
    progress: f32 = 0,
};

pub var storage: [max_proposals]Proposal = @splat(.{});
pub var count: u32 = 0; // applications ever lodged
pub var next_number: u32 = 1;

pub var lodged_total: u32 = 0;
pub var approved_total: u32 = 0;
pub var refused_total: u32 = 0;
pub var lapsed_total: u32 = 0;
pub var built_total: u32 = 0;
pub var levies_collected: f64 = 0;
pub var lodged_today: u32 = 0;
pub var building: usize = 0; // approved proposals still physically under construction

// Slice 19 aggregate private construction counters. They are not municipal
// ledger movements; the ledger still records only the levy as kind 12.
pub var construction_spent_total: f64 = 0;
pub var materials_delivered_total: f64 = 0;

// Which district leads the next day's rotation, restored with the town so a
// save and reload keep offering the same sites in the same order.
pub var cursor: u8 = 0;
var demand_cache: [city.district_count]Demand = @splat(.{});

pub const Demand = struct { residential: f32 = 0, commercial: f32 = 0 };

const SiteMetrics = struct {
    access: u8 = 0,
    distance: f32 = 0,
    slope: f32 = 0,
    access_cost: f64 = 0,
    grade_cost: f64 = 0,
    foundation_cost: f64 = 0,
    materials_cost: f64 = 0,
    labour_cost: f64 = 0,
    total_cost: f64 = 0,
    materials_required: f64 = 0,
    budget: f64 = 0,
};

pub fn init() void {
    storage = @splat(.{});
    count = 0;
    next_number = 1;
    lodged_total = 0;
    approved_total = 0;
    refused_total = 0;
    lapsed_total = 0;
    built_total = 0;
    levies_collected = 0;
    lodged_today = 0;
    building = 0;
    construction_spent_total = 0;
    materials_delivered_total = 0;
    cursor = 0;
    demand_cache = @splat(.{});
}

// Newest-first access, matching the agreement history convention.
pub fn record(index: usize) ?*Proposal {
    if (index >= retainedCount()) return null;
    return &storage[(retainedCount() - 1 - index) % storage.len];
}

pub fn retainedCount() usize {
    return @min(@as(usize, count), storage.len);
}

fn pendingCount() usize {
    var total: usize = 0;
    for (storage[0..retainedCount()]) |p| if (p.decision == .offered) {
        total += 1;
    };
    return total;
}

pub fn pending() u32 {
    return @intCast(pendingCount());
}

fn districtHasPending(d: usize) bool {
    const want: u8 = @intCast(d);
    for (storage[0..retainedCount()]) |p| {
        if (p.decision == .offered and p.district == want) return true;
    }
    return false;
}

fn findNumber(number: u32) ?*Proposal {
    for (storage[0..retainedCount()]) |*p| {
        if (p.number == number) return p;
    }
    return null;
}

// A construction work order is deliberately outside the road-contract index
// range. Residents and companies keep their existing `order` field, so the
// movement, renderer, housing and employment code paths all already recognise a
// travelling crew; only persistence has to accept both meanings.
pub fn workOrder(number: u32) i32 {
    return work_order_base + @as(i32, @intCast(number));
}

pub fn jobNumber(order: i32) ?u32 {
    if (order < work_order_base) return null;
    const number = order - work_order_base;
    if (number <= 0) return null;
    return @intCast(number);
}

pub fn validWorkOrder(order: i32) bool {
    const number = jobNumber(order) orelse return false;
    const p = findNumber(number) orelse return false;
    return p.decision == .approved and p.company >= 0 and p.phase != .complete and p.phase != .none;
}

pub fn crewFor(order: i32, person: usize) bool {
    const number = jobNumber(order) orelse return false;
    const p = findNumber(number) orelse return false;
    if (p.decision != .approved) return false;
    for (p.crew[0..@as(usize, p.crew_count)]) |id| if (id == person) return true;
    return false;
}

pub fn companyFor(order: i32) i32 {
    const number = jobNumber(order) orelse return -1;
    const p = findNumber(number) orelse return -1;
    if (p.decision != .approved) return -1;
    return p.company;
}

pub fn measure() void {
    var homes: [city.district_count]usize = @splat(0);
    var dwellers: [city.district_count]usize = @splat(0);
    var premises: [city.district_count]usize = @splat(0);
    var total_homes: usize = 0;
    var total_premises: usize = 0;
    var total_dwellers: usize = 0;
    for (city.lots()) |*b| {
        const d = @min(b.district, city.district_count - 1);
        if (city.isHome(b.kind)) {
            homes[d] += 1;
            total_homes += 1;
            dwellers[d] += b.occupants;
            total_dwellers += b.occupants;
        }
        if (b.capacity > 0) {
            premises[d] += 1;
            total_premises += 1;
        }
    }
    const city_res = if (total_homes == 0) 0 else @as(f32, @floatFromInt(total_dwellers)) / @as(f32, @floatFromInt(total_homes));
    const city_com = if (total_premises == 0) 0 else @as(f32, @floatFromInt(total_dwellers)) / @as(f32, @floatFromInt(total_premises));
    for (0..city.district_count) |d| {
        const res = if (homes[d] == 0) 0 else @as(f32, @floatFromInt(dwellers[d])) / @as(f32, @floatFromInt(homes[d]));
        const com = if (premises[d] == 0) 0 else @as(f32, @floatFromInt(dwellers[d])) / @as(f32, @floatFromInt(premises[d]));
        demand_cache[d] = .{
            .residential = if (city_res > 0) res / city_res else 0,
            .commercial = if (city_com > 0) com / city_com else 0,
        };
    }
}

pub fn demand(d: usize) Demand {
    if (d >= city.district_count) return .{};
    return demand_cache[d];
}

fn zoneOf(parcel: usize) u8 {
    if (parcel >= parcels.count) return 0;
    return @intCast(parcels.storage[parcel].zone);
}

// The use a zone asks for, and the use that actually gets proposed. A mixed
// zone takes whichever of the two measured pressures is higher.
fn useFor(zone: u8, d: Demand) ?city.Kind {
    return switch (zone) {
        1 => if (d.residential >= 2.0) .apartment else .home,
        2 => if (d.commercial >= 2.0) .office else .shop,
        3 => .depot,
        4 => if (d.residential >= d.commercial) (if (d.residential >= 2.0) .apartment else .home) else (if (d.commercial >= 2.0) .office else .shop),
        else => null,
    };
}

const Site = struct { parcel: usize, building: usize, kind: city.Kind, height: f32, metrics: SiteMetrics };

fn accessDistance(b: *const city.Building) f32 {
    if (b.node >= city.node_count) return 1e9;
    var best: f32 = 1e9;
    for (city.roads) |r| {
        if (!r.vehicles) continue;
        const a = city.nodes[r.a];
        const c = city.nodes[r.b];
        const u = city.projection(.{ .x = b.entry_x, .z = b.entry_z }, a, c);
        const px = a.x + (c.x - a.x) * u;
        const pz = a.z + (c.z - a.z) * u;
        const d = city.hypot(px - b.entry_x, pz - b.entry_z);
        if (d < best) best = d;
    }
    return best;
}

fn slopeAt(x: f32, z: f32, width: f32, depth: f32) f32 {
    var low: f32 = 1e9;
    var high: f32 = -1e9;
    for ([_]f32{ 0, 0.5, 1 }) |u| {
        for ([_]f32{ 0, 0.5, 1 }) |v| {
            const y = city.elevation(x + width * u, z + depth * v);
            low = @min(low, y);
            high = @max(high, y);
        }
    }
    return (high - low) / @max(1, @min(width, depth));
}

fn siteMetrics(b: *const city.Building, kind: city.Kind, height: f32) SiteMetrics {
    const footprint = city.proposalFootprint(kind, b.x, b.z);
    const width = footprint[0];
    const depth = footprint[1];
    const distance = accessDistance(b);
    const valid_node = b.node < city.node_count and city.degree(b.node) > 0;
    const access: u8 = if (!valid_node or distance > access_max_distance) 0 else if (distance <= access_free_distance) 1 else 2;
    const slope = slopeAt(b.x, b.z, width, depth);
    const area: f64 = @as(f64, width) * @as(f64, depth);
    const height64: f64 = @floatCast(height);
    const access_cost = finance.cents(@max(0, @as(f64, distance - access_free_distance)) * access_rate);
    const grade_cost = finance.cents(area * @as(f64, @floatCast(slope)) * grading_rate);
    const foundation_cost = finance.cents(area * foundation_rate);
    const materials_cost = finance.cents(area * (materials_area_rate + height64 * materials_height_rate));
    const labour_cost = finance.cents(labour_per_second * 4 * buildDays(height) * days * 2);
    const total_cost = finance.cents(access_cost + grade_cost + foundation_cost + materials_cost + labour_cost);
    const materials_required = @max(1, area * (1 + height64 * 0.08));
    const budget = finance.cents(city.lotValue(kind) * developer_budget_rate);
    return .{
        .access = access,
        .distance = distance,
        .slope = slope,
        .access_cost = access_cost,
        .grade_cost = grade_cost,
        .foundation_cost = foundation_cost,
        .materials_cost = materials_cost,
        .labour_cost = labour_cost,
        .total_cost = total_cost,
        .materials_required = materials_required,
        .budget = budget,
    };
}

// The first authored vacant lot in the district whose zone permits a use and
// whose access and terrain pass the hard buildability checks. Lots are read in
// plan order, so the same demand and the same zoning always offer the same
// site rather than a random one.
fn siteFor(d: usize, demand_now: Demand) ?Site {
    for (city.lots(), 0..) |*b, i| {
        if (b.kind != .vacant) continue;
        if (@min(b.district, city.district_count - 1) != d) continue;
        if (i >= parcels.count) continue;
        const zone = zoneOf(i);
        const kind = useFor(zone, demand_now) orelse continue;
        const height = city.proposalHeight(kind, i, b.x, b.z);
        const metrics = siteMetrics(b, kind, height);
        if (metrics.access == 0 or metrics.slope > max_buildable_slope) continue;
        return .{ .parcel = i, .building = i, .kind = kind, .height = height, .metrics = metrics };
    }
    return null;
}

fn lodge(time: f64, site: Site, demand_now: Demand) void {
    const b = city.buildings[site.building];
    const proposal = Proposal{
        .number = next_number,
        .parcel = site.parcel,
        .building = site.building,
        .district = @intCast(@min(b.district, city.district_count - 1)),
        .zone = zoneOf(site.parcel),
        .kind = @intCast(@intFromEnum(site.kind)),
        .height = site.height,
        .value = city.lotValue(site.kind),
        .capacity = city.lotCapacity(site.kind),
        .levy = finance.cents(city.lotValue(site.kind) * levy_rate),
        .offered = time,
        .deadline = time + @as(f64, offer_days) * days,
        .pressure = if (site.kind == .home or site.kind == .apartment) demand_now.residential else demand_now.commercial,
        .decision = .offered,
        .reason = .none,
        .access = site.metrics.access,
        .slope = site.metrics.slope,
        .access_cost = site.metrics.access_cost,
        .grade_cost = site.metrics.grade_cost,
        .foundation_cost = site.metrics.foundation_cost,
        .materials_cost = site.metrics.materials_cost,
        .labour_cost = site.metrics.labour_cost,
        .budget = site.metrics.budget,
        .materials_required = site.metrics.materials_required,
    };
    storage[@as(usize, count) % storage.len] = proposal;
    count += 1;
    next_number += 1;
    lodged_total += 1;
    lodged_today += 1;
}

// Silence is a decision. A proposal nobody answers is retired with its own
// reason and can never be revived.
fn lapse(time: f64) void {
    for (storage[0..retainedCount()]) |*p| {
        if (p.decision != .offered or time < p.deadline) continue;
        p.decision = .lapsed;
        p.reason = .lapsed;
        p.blocked = .lapsed;
        p.decided = time;
        lapsed_total += 1;
    }
}

pub fn daily(time: f64) void {
    lodged_today = 0;
    lapse(time);
    measure();
    var step: usize = 0;
    while (step < city.district_count) : (step += 1) {
        if (lodged_today >= max_lodged_per_day or pendingCount() >= max_pending) break;
        const d = (@as(usize, cursor) + step) % city.district_count;
        if (districtHasPending(d)) continue;
        const demand_now = demand_cache[d];
        if (demand_now.residential < demand_threshold and demand_now.commercial < demand_threshold) continue;
        const site = siteFor(d, demand_now) orelse continue;
        lodge(time, site, demand_now);
    }
    cursor = @intCast((@as(usize, cursor) + 1) % city.district_count);
}

fn payPrivate(p: *Proposal, amount: f64) void {
    const paid = finance.cents(amount);
    if (paid <= 0) return;
    if (p.spent + paid > p.budget + 0.011) {
        p.phase = .blocked;
        p.blocked = .budget_exhausted;
        return;
    }
    p.spent = finance.cents(p.spent + paid);
    construction_spent_total = finance.cents(construction_spent_total + paid);
    if (p.company >= 0 and p.company < residents.company_count) {
        const company: usize = @intCast(p.company);
        residents.companies[company].cash = finance.cents(residents.companies[company].cash + paid);
        residents.companies[company].costs = finance.cents(residents.companies[company].costs + paid);
    }
}

fn block(p: *Proposal, reason: Reason) void {
    p.phase = .blocked;
    p.blocked = reason;
}

fn retire(p: *Proposal, reason: Reason, time: f64) void {
    p.decision = .refused;
    p.reason = reason;
    p.blocked = reason;
    p.phase = .none;
    p.decided = time;
    refused_total += 1;
}

fn availableContractor() ?usize {
    for (residents.companies[0..residents.company_count], 0..) |company, i| {
        if (!company.contractor or company.crew_count < 4 or company.order >= 0) continue;
        var free = true;
        for (company.crew[0..company.crew_count]) |id| {
            if (id >= residents.people.len or residents.people[id].order >= 0) {
                free = false;
                break;
            }
        }
        if (free) return i;
    }
    return null;
}

fn finish(p: *Proposal, time: f64) void {
    construct(p);
    p.decision = .built;
    p.phase = .complete;
    p.progress = 1;
    p.complete = time;
    p.blocked = .none;
    built_total += 1;
    if (building > 0) building -= 1;
    if (p.company >= 0 and p.company < residents.company_count) {
        residents.release(@intCast(p.company));
    }
    p.company = -1;
    p.crew_count = 0;
    p.crew = .{ 0, 0, 0, 0 };
}

fn updateJob(p: *Proposal, dt: f32, time: f64) void {
    if (p.phase == .blocked) return;
    if (p.company < 0 or p.company >= residents.company_count) {
        block(p, .crew_lost);
        return;
    }
    const company_index: usize = @intCast(p.company);
    const order = workOrder(p.number);
    const company = &residents.companies[company_index];
    if (company.order != order) {
        block(p, .crew_lost);
        return;
    }
    var arrived: usize = 0;
    for (p.crew[0..@as(usize, p.crew_count)]) |id| {
        if (id >= residents.people.len or residents.people[id].order != order) {
            block(p, .crew_lost);
            return;
        }
        if (residents.people[id].arrived) arrived += 1;
    }
    if (arrived < @as(usize, p.crew_count)) {
        p.phase = .mobilising;
        return;
    }

    const total_seconds = buildDays(p.height) * days;
    const delivery_seconds = @max(1, total_seconds * 0.65);
    const delivery_rate = p.materials_required / delivery_seconds;
    const missing = @max(0, p.materials_required - p.materials_delivered);
    const delivered = @min(missing, delivery_rate * @as(f64, @floatCast(dt)));
    if (delivered > 0) {
        const material_cost = if (p.materials_required > 0) p.materials_cost * delivered / p.materials_required else 0;
        payPrivate(p, material_cost);
        if (p.phase == .blocked) return;
        p.materials_delivered = @min(p.materials_required, p.materials_delivered + delivered);
        materials_delivered_total += delivered;
    }
    const labour_cost = labour_per_second * @as(f64, @floatFromInt(arrived)) * @as(f64, @floatCast(dt));
    payPrivate(p, labour_cost);
    if (p.phase == .blocked) return;
    const material_share = if (p.materials_required > 0) std.math.clamp(@as(f32, @floatCast(p.materials_delivered / p.materials_required)), 0, 1) else 1;
    if (total_seconds > 0) p.progress = @min(1, p.progress + @as(f32, @floatCast(dt)) / @as(f32, @floatCast(total_seconds)) * material_share);
    p.phase = if (p.materials_delivered <= 0) .delivering else .building;
    if (p.progress >= 1 and p.materials_delivered + 0.001 >= p.materials_required) finish(p, time);
}

// An approved proposal builds only while its crew is physically present, its
// materials are being delivered and its private budget can pay the next step.
// The lot stays vacant until all three conditions finish.
pub fn update(dt: f32, time: f64) void {
    if (building == 0) return;
    for (storage[0..retainedCount()]) |*p| {
        if (p.decision != .approved) continue;
        updateJob(p, dt, time);
    }
}

// The one place a lot's use actually changes. Nothing derived is cached per
// kind: the renderer walks city.lots() every frame, building_at_node is keyed
// by node and the lot keeps its node, and the assessment roll, the housing and
// household rolls and the reports all read these same authored rows. The new
// use is therefore visible everywhere without a second list or a refresh hook.
fn construct(p: *Proposal) void {
    const index = p.building;
    if (index >= city.lot_count) return;
    const kind: city.Kind = @enumFromInt(p.kind);
    const b = &city.buildings[index];
    const footprint = city.proposalFootprint(kind, b.x, b.z);
    b.kind = kind;
    b.width = footprint[0];
    b.depth = footprint[1];
    b.height = p.height;
    b.ground = city.elevation(b.x + b.width, b.z + b.depth);
    b.value = p.value;
    b.capacity = p.capacity;
    b.slots = 0;
    b.occupants = 0;
    b.employer = -1;
    b.entry_x = b.x + b.width / 2;
    b.entry_z = b.z + b.depth;
    if (p.parcel < parcels.count) parcels.storage[p.parcel].building = @intCast(index);
    if (city.isHome(kind)) {
        housing.enroll(index);
    } else if (p.capacity > 0) {
        residents.addEmployer(index, kind);
    }
}

fn buildDays(height: f32) f64 {
    const days_needed = 2 + @as(f64, @floatFromInt(@as(u32, @intFromFloat(@max(0, height) / 4))));
    return @min(6, days_needed);
}

// Grant the permit. The levy is the only money that reaches the municipal
// account. The applicant's private budget pays the contractor for groundwork,
// foundation, materials and labour.
pub fn accept(index: usize, time: f64) bool {
    const p = record(index) orelse return false;
    if (p.decision != .offered) return false;
    if (p.building >= city.lot_count or city.buildings[p.building].kind != .vacant) {
        retire(p, .occupied, time);
        return false;
    }
    const b = &city.buildings[p.building];
    const kind: city.Kind = @enumFromInt(p.kind);
    const height = city.proposalHeight(kind, p.building, b.x, b.z);
    const metrics = siteMetrics(b, kind, height);
    p.height = height;
    p.value = city.lotValue(kind);
    p.capacity = city.lotCapacity(kind);
    p.levy = finance.cents(p.value * levy_rate);
    p.access = metrics.access;
    p.slope = metrics.slope;
    p.access_cost = metrics.access_cost;
    p.grade_cost = metrics.grade_cost;
    p.foundation_cost = metrics.foundation_cost;
    p.materials_cost = metrics.materials_cost;
    p.labour_cost = metrics.labour_cost;
    p.budget = metrics.budget;
    p.materials_required = metrics.materials_required;
    if (metrics.access == 0) {
        retire(p, .no_access, time);
        return false;
    }
    if (metrics.slope > max_buildable_slope) {
        retire(p, .too_steep, time);
        return false;
    }
    if (metrics.total_cost > metrics.budget + 0.011) {
        retire(p, .insufficient_funds, time);
        return false;
    }
    const company_index = availableContractor() orelse {
        p.blocked = .crew_unavailable;
        return false;
    };
    const company = &residents.companies[company_index];
    p.decision = .approved;
    p.decided = time;
    p.phase = .mobilising;
    p.blocked = .none;
    p.company = @intCast(company_index);
    p.crew_count = @intCast(company.crew_count);
    for (company.crew[0..company.crew_count], 0..) |id, slot| p.crew[slot] = @intCast(id);
    p.spent = 0;
    p.materials_delivered = 0;
    p.progress = 0;
    p.complete = time + (buildDays(height) + 2) * days;
    approved_total += 1;
    building += 1;
    company.order = workOrder(p.number);
    for (p.crew[0..@as(usize, p.crew_count)]) |id| {
        residents.send(id, b.node, workOrder(p.number));
    }
    payPrivate(p, p.access_cost + p.grade_cost + p.foundation_cost);
    if (p.levy > 0) {
        finance.record(time, p.levy, 12, -1, @intCast(p.number));
        levies_collected = finance.cents(levies_collected + p.levy);
    }
    return true;
}

pub fn refuse(index: usize, time: f64) bool {
    const p = record(index) orelse return false;
    if (p.decision != .offered) return false;
    retire(p, .refused, time);
    return true;
}

// The pending proposal on a parcel, newest first, or -1. The zoning tool reads
// this so a site with an open application is never mistaken for empty land.
pub fn pendingFor(parcel: usize) i32 {
    for (0..retainedCount()) |i| {
        const p = &storage[(retainedCount() - 1 - i) % storage.len];
        if (p.decision == .offered and p.parcel == parcel) return @intCast(i);
    }
    return -1;
}

pub fn read(index: usize, field: u32) f64 {
    const p = record(index) orelse return -1;
    return switch (field) {
        0 => @floatFromInt(p.number),
        1 => @floatFromInt(p.parcel),
        2 => @floatFromInt(p.building),
        3 => @floatFromInt(p.district),
        4 => @floatFromInt(p.zone),
        5 => @floatFromInt(p.kind),
        6 => p.height,
        7 => p.value,
        8 => @floatFromInt(p.capacity),
        9 => p.levy,
        10 => p.offered,
        11 => p.deadline,
        12 => p.decided,
        13 => p.complete,
        14 => @floatFromInt(@intFromEnum(p.decision)),
        15 => @floatFromInt(@intFromEnum(p.reason)),
        16 => p.pressure,
        17 => @floatFromInt(count),
        18 => @floatFromInt(pending()),
        19 => @floatFromInt(retainedCount()),
        20 => @floatFromInt(p.access),
        21 => p.slope,
        22 => p.access_cost,
        23 => p.grade_cost,
        24 => p.foundation_cost,
        25 => p.materials_cost,
        26 => p.labour_cost,
        27 => p.budget,
        28 => p.spent,
        29 => p.materials_required,
        30 => p.materials_delivered,
        31 => @floatFromInt(p.company),
        32 => @floatFromInt(p.crew_count),
        33 => @floatFromInt(@intFromEnum(p.phase)),
        34 => @floatFromInt(@intFromEnum(p.blocked)),
        35 => p.progress,
        36 => if (p.company >= 0) @floatFromInt(workOrder(p.number)) else -1,
        else => -1,
    };
}

// Aggregate counters for the report header and the city metrics group.
pub fn read0(field: u32) f64 {
    return switch (field) {
        0 => @floatFromInt(pending()),
        1 => @floatFromInt(building),
        2 => @floatFromInt(built_total),
        3 => @floatFromInt(refused_total),
        4 => @floatFromInt(lapsed_total),
        5 => @floatFromInt(count),
        6 => levies_collected,
        7 => @floatFromInt(eligibleSites()),
        8 => @floatFromInt(lodged_today),
        9 => construction_spent_total,
        10 => materials_delivered_total,
        11 => @floatFromInt(activeCrews(.mobilising)),
        12 => @floatFromInt(activeCrews(.building) + activeCrews(.delivering)),
        13 => @floatFromInt(blockedJobs()),
        14 => privateBudgetCommitted(),
        else => -1,
    };
}

pub fn eligibleSites() usize {
    var total: usize = 0;
    for (city.lots(), 0..) |*b, i| {
        if (b.kind != .vacant or i >= parcels.count) continue;
        const zone = zoneOf(i);
        if (zone >= 1 and zone <= 4) total += 1;
    }
    return total;
}

fn activeCrews(phase: Phase) usize {
    var total: usize = 0;
    for (storage[0..retainedCount()]) |p| {
        if (p.decision == .approved and p.phase == phase) total += 1;
    }
    return total;
}

fn blockedJobs() usize {
    var total: usize = 0;
    for (storage[0..retainedCount()]) |p| {
        if (p.decision == .approved and p.phase == .blocked) total += 1;
    }
    return total;
}

fn privateBudgetCommitted() f64 {
    var total: f64 = 0;
    for (storage[0..retainedCount()]) |p| {
        if (p.decision == .approved) total += p.budget;
    }
    return finance.cents(total);
}
