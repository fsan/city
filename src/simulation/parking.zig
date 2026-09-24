const std = @import("std");
const city = @import("../scene/city.zig");
const travel = @import("travel.zig");

// Slice 10: bounded parking supply. Bicycle parks and car parks come from
// seeded buildings; larger streets also offer kerbside car spaces at a price
// banded by the movement actually observed on that segment. Every facility has
// a hard slot count, so parking can genuinely fail and be searched for.
pub const max_facilities = 1400;
pub const kerbside_price_cap: f64 = 1.2;
pub const bands = [_]f64{ 0, 0.3, 0.6, 0.9, 1.2 };
pub const band_names = [_][]const u8{ "free", "band 1", "band 2", "band 3", "band 4 (cap)" };
pub const Kind = enum(u8) { bike = 0, car = 1 };
pub const Facility = struct {
    kind: Kind,
    building: i32 = -1,
    road: i32 = -1,
    node: usize = 0,
    slots: u16 = 0,
    occupied: u16 = 0,
    price: f64 = 0,
    observed: [travel.bucket_count]u8 = @splat(travel.default_chance),
};
pub var facilities: [max_facilities]Facility = undefined;
// Staging buffer for rebuilds; kept off the stack because the array is large.
var staged: [max_facilities]Facility = undefined;
pub var count: usize = 0;
pub var attempts: u32 = 0;
pub var successes: u32 = 0;
pub var fallbacks: u32 = 0;
pub var refusals: u32 = 0;
pub var revenue_today: f64 = 0;
pub var dues: f64 = 0;
pub var revenue_total: f64 = 0;
pub var kerbside_used: usize = 0;

pub fn init() void {
    attempts = 0;
    successes = 0;
    fallbacks = 0;
    refusals = 0;
    revenue_today = 0;
    revenue_total = 0;
    dues = 0;
    kerbside_used = 0;
    count = 0;
    rebuild();
}

// Building lots first, then kerbside supply on streets and avenues. Occupancy,
// aggregate experience and posted prices carry across a rebuild by identity.
pub fn rebuild() void {
    const previous_count = count;
    @memcpy(staged[0..previous_count], facilities[0..previous_count]);
    var next: usize = 0;
    for (city.lots(), 0..) |*b, i| {
        const kind: Kind = switch (b.kind) {
            .bike_park => .bike,
            .car_park => .car,
            else => continue,
        };
        if (next >= max_facilities or b.slots == 0) continue;
        facilities[next] = .{ .kind = kind, .building = @intCast(i), .node = b.node, .slots = @intCast(@min(b.slots, 1000)) };
        if (carry(previous_count, facilities[next])) |old| {
            facilities[next].occupied = @min(facilities[next].slots, old.occupied);
            facilities[next].observed = old.observed;
            facilities[next].price = old.price;
        }
        next += 1;
    }
    kerbside_used = 0;
    for (city.roads, 0..) |*r, i| {
        if (next >= max_facilities) break;
        if (r.class == 0 or !r.vehicles or !r.pedestrians or r.works) continue;
        const slots: u16 = if (r.class >= 2) 4 else 2;
        facilities[next] = .{ .kind = .car, .road = @intCast(i), .node = r.a, .slots = slots };
        if (carry(previous_count, facilities[next])) |old| {
            facilities[next].occupied = @min(slots, old.occupied);
            facilities[next].observed = old.observed;
            facilities[next].price = old.price;
        }
        if (facilities[next].road >= 0) kerbside_used += facilities[next].occupied;
        next += 1;
    }
    count = next;
}

fn carry(previous_count: usize, wanted: Facility) ?Facility {
    for (staged[0..previous_count]) |old| {
        if (old.kind != wanted.kind) continue;
        if (wanted.building >= 0 and old.building == wanted.building and old.road < 0) return old;
        if (wanted.road >= 0 and old.road == wanted.road and old.building < 0) return old;
    }
    return null;
}

pub fn kerbside(index: usize) bool {
    return index < count and facilities[index].road >= 0;
}

pub fn free(index: usize) usize {
    if (index >= count) return 0;
    return facilities[index].slots -| facilities[index].occupied;
}

pub fn full(index: usize) bool {
    return index >= count or facilities[index].occupied >= facilities[index].slots;
}

// 0 free, then four movement bands. Movement is the smoothed traffic actually
// observed on that segment; the price is capped so no space is ever expensive.
pub fn band(movement: f32) usize {
    if (movement < 0.6) return 0;
    if (movement < 2) return 1;
    if (movement < 4.5) return 2;
    if (movement < 8) return 3;
    return 4;
}

pub fn bandPrice(movement: f32) f64 {
    return @min(kerbside_price_cap, bands[band(movement)]);
}

pub fn refreshPrices(movement: []const f32) void {
    for (facilities[0..count]) |*f| {
        if (f.road < 0) continue;
        const road: usize = @intCast(f.road);
        f.price = if (road < movement.len) bandPrice(movement[road]) else 0;
    }
}

pub fn take(index: usize) bool {
    if (index >= count) return false;
    const f = &facilities[index];
    if (f.occupied >= f.slots) return false;
    f.occupied += 1;
    if (f.road >= 0) kerbside_used += 1;
    return true;
}

pub fn release(index: usize) void {
    if (index >= count) return;
    const f = &facilities[index];
    if (f.occupied == 0) return;
    f.occupied -= 1;
    if (f.road >= 0) kerbside_used -|= 1;
}

pub fn observe(index: usize, slot: usize, free_slot: bool) void {
    if (index >= count or slot >= travel.bucket_count) return;
    const f = &facilities[index];
    const current: f32 = @floatFromInt(f.observed[slot]);
    const outcome: f32 = if (free_slot) 255 else 0;
    // Aggregate experience learns more slowly than one person's own memory.
    const next = current + (outcome - current) * 0.125;
    f.observed[slot] = @intFromFloat(@max(@as(f32, travel.chance_floor), @min(@as(f32, travel.chance_ceiling), @round(next))));
}

pub fn occupiedTotal() usize {
    var total: usize = 0;
    for (facilities[0..count]) |f| total += f.occupied;
    return total;
}

pub fn slotsTotal() usize {
    var total: usize = 0;
    for (facilities[0..count]) |f| total += f.slots;
    return total;
}

pub fn kindSlots(kind: Kind) usize {
    var total: usize = 0;
    for (facilities[0..count]) |f| if (f.kind == kind) {
        total += f.slots;
    };
    return total;
}

pub fn kindUsed(kind: Kind) usize {
    var total: usize = 0;
    for (facilities[0..count]) |f| if (f.kind == kind) {
        total += f.occupied;
    };
    return total;
}

pub fn daily() void {
    revenue_today = 0;
}
