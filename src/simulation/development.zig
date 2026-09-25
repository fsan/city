const std = @import("std");
const city = @import("../scene/city.zig");
const parcels = @import("../scene/parcels.zig");
const residents = @import("residents.zig");
const housing = @import("housing.zig");
const finance = @import("finance.zig");

// Slice 18 (numbered list item 10): private development proposals and permits.
// A private developer lodges a proposal for a zoned vacant site, measured
// against the demand the live simulation has actually generated; the player
// grants or refuses the permit; an approved proposal pays a development levy
// into the municipal ledger and is built over a bounded number of simulation
// days. No crews, materials, terrain grading or foundation costs are added -
// those belong to numbered item 11.
//
// Every proposal redevelops an authored vacant lot in place. The lot keeps its
// identity, position, frontage, node, street and address number; only its use,
// height, value and capacity change. Nothing grows, so the snapshot, the
// renderer, the assessment roll and every report agree by construction.

pub const max_proposals = 24;
pub const max_pending = 8;
pub const max_lodged_per_day = 2;
pub const offer_days = 5;
pub const demand_threshold: f32 = 1.35;
pub const levy_rate: f64 = 0.0005;
pub const days = 480.0;

pub const Decision = enum(u8) { offered = 0, approved = 1, refused = 2, lapsed = 3, built = 4 };

// One reason code per way a proposal can end, so a report never has to infer
// why a site stayed empty.
pub const Reason = enum(u8) { none = 0, no_site = 1, unzoned = 2, no_demand = 3, occupied = 4, refused = 5, lapsed = 6 };

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
pub var building: usize = 0; // approved proposals still under construction

// Which district leads the next day's rotation, restored with the town so a
// save and reload keep offering the same sites in the same order.
pub var cursor: u8 = 0;
var demand_cache: [city.district_count]Demand = @splat(.{});

// The two deficits the scan reads. Each is a district's own residents per
// dwelling (or per commercial premises), divided by the same ratio for the
// whole city, so a district is only eligible when it is measurably more
// crowded than the town it belongs to.
pub const Demand = struct { residential: f32 = 0, commercial: f32 = 0 };

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

const Site = struct { parcel: usize, building: usize, kind: city.Kind };

// The first authored vacant lot in the district whose zone permits a use. Lots
// are read in plan order, so the same demand and the same zoning always offer
// the same site rather than a random one.
fn siteFor(d: usize, demand_now: Demand) ?Site {
    for (city.lots(), 0..) |*b, i| {
        if (b.kind != .vacant) continue;
        if (@min(b.district, city.district_count - 1) != d) continue;
        if (i >= parcels.count) continue;
        const zone = zoneOf(i);
        const kind = useFor(zone, demand_now) orelse continue;
        return .{ .parcel = i, .building = i, .kind = kind };
    }
    return null;
}

fn lodge(time: f64, site: Site, demand_now: Demand) void {
    const b = city.buildings[site.building];
    const height = city.proposalHeight(site.kind, site.building, b.x, b.z);
    const value = city.lotValue(site.kind);
    const proposal = Proposal{
        .number = next_number,
        .parcel = site.parcel,
        .building = site.building,
        .district = @intCast(@min(b.district, city.district_count - 1)),
        .zone = zoneOf(site.parcel),
        .kind = @intCast(@intFromEnum(site.kind)),
        .height = height,
        .value = value,
        .capacity = city.lotCapacity(site.kind),
        .levy = finance.cents(value * levy_rate),
        .offered = time,
        .deadline = time + @as(f64, offer_days) * days,
        .pressure = if (site.kind == .home or site.kind == .apartment) demand_now.residential else demand_now.commercial,
        .decision = .offered,
        .reason = .none,
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

// An approved proposal builds for a bounded number of simulation days. The lot
// stays vacant until the work is finished, so nothing appears early.
pub fn update(time: f64) void {
    if (building == 0) return;
    for (storage[0..retainedCount()]) |*p| {
        if (p.decision != .approved or time < p.complete) continue;
        construct(p);
        p.decision = .built;
        p.reason = .none;
        p.decided = time;
        built_total += 1;
        building -= 1;
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

// Grant the permit. The levy is the only money this batch moves: it is rounded
// to pennies and recorded under the proposal's own one-based number, and the
// construction itself is the developer's cost.
pub fn accept(index: usize, time: f64) bool {
    const p = record(index) orelse return false;
    if (p.decision != .offered) return false;
    if (p.building >= city.lot_count or city.buildings[p.building].kind != .vacant) {
        p.decision = .refused;
        p.reason = .occupied;
        p.decided = time;
        refused_total += 1;
        return false;
    }
    p.decision = .approved;
    p.decided = time;
    p.complete = time + buildDays(p.height) * days;
    approved_total += 1;
    building += 1;
    if (p.levy > 0) {
        finance.record(time, p.levy, 12, -1, @intCast(p.number));
        levies_collected = finance.cents(levies_collected + p.levy);
    }
    return true;
}

pub fn refuse(index: usize, time: f64) bool {
    const p = record(index) orelse return false;
    if (p.decision != .offered) return false;
    p.decision = .refused;
    p.reason = .refused;
    p.decided = time;
    refused_total += 1;
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
        else => -1,
    };
}

pub fn eligibleSites() usize {
    var total: usize = 0;
    for (city.lots(), 0..) |*b, i| {
        if (b.kind != .vacant or i >= parcels.count) continue;
        if (zoneOf(i) >= 1 and zoneOf(i) <= 4) total += 1;
    }
    return total;
}
