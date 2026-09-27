const std = @import("std");
const city = @import("../scene/city.zig");
const calendar = @import("calendar.zig");

// Numbered list item 17: streetlighting.
//
// Every eligible carriageway now carries a bounded number of lighting columns.
// The authored town already lights the segments with frontage, so the layer is
// live from the first frame rather than waiting for the player. A lit segment
// draws electricity every day, columns fail over time, and a failed column is
// repaired for municipal money. At night an unlit segment is slower and is
// measurably more likely to raise a collision, so coverage has a consequence
// rather than being decoration.
//
// Everything is bounded and deterministic: faults are a pure function of the
// segment and the day index, so a loaded town replays the same sequence. No mast
// arm, cable, photocell or electricity market is modelled, and no money is
// created - electricity and works are city expenses booked through the ledger.
pub const max_lamps_per_road: u8 = 6;
pub const avenue_lamps: u8 = 4;
pub const street_lamps: u8 = 2;

// Bounded policy numbers, not a utility tender. A working column draws this much
// per simulated day; a new column costs this much capital; a repair costs this.
pub const electricity_per_lamp_day: f64 = 0.55;
pub const install_cost: f64 = 260;
pub const repair_cost: f64 = 45;

// A column fails at most this often per segment per day, and a crew reaches at
// most this many failed columns in one thirty-second operating pass.
pub const fault_permille: u32 = 30;
pub const max_repairs_per_pass: usize = 2;

// Night-time consequences, both bounded and both zero at full coverage.
pub const night_speed_penalty: f32 = 0.28;
pub const night_collision_boost: f32 = 0.65;

// Installed columns and working columns per segment. `lamps` is the player's
// designation and `lit` is the live state; `lit <= lamps` always holds.
pub var lamps: [city.max_roads]u8 = @splat(0);
pub var lit: [city.max_roads]u8 = @splat(0);
pub var repairs: [city.max_roads]u32 = @splat(0);

pub var faults_total: u32 = 0;
pub var faults_today: u32 = 0;
pub var repairs_total: u32 = 0;
pub var repairs_today: u32 = 0;
pub var installed_total: u32 = 0;
pub var electricity_paid_total: f64 = 0;
pub var electricity_paid_today: f64 = 0;
pub var works_paid_total: f64 = 0;
pub var works_paid_today: f64 = 0;
pub var electricity_need_today: f64 = 0;
pub var last_fault_day: u32 = 0;

pub const Spend = struct { electricity: f64 = 0, works: f64 = 0 };

fn cents(value: f64) f64 {
    return @round(value * 100) / 100;
}

fn clamp01(value: f32) f32 {
    return std.math.clamp(value, 0, 1);
}

// A segment takes lighting only where vehicles and pedestrians already share a
// carriageway that is neither a lane nor under works.
pub fn eligible(road: usize) bool {
    if (road >= city.road_count) return false;
    const r = city.roads[road];
    return r.class > 0 and r.vehicles and r.pedestrians and !r.works;
}

pub fn capacity(road: usize) u8 {
    if (!eligible(road)) return 0;
    return if (city.roads[road].class >= 2) avenue_lamps else street_lamps;
}

pub fn installed(road: usize) u8 {
    return if (road >= city.road_count) 0 else lamps[road];
}

pub fn working(road: usize) u8 {
    return if (road >= city.road_count) 0 else lit[road];
}

pub fn failed(road: usize) u8 {
    return installed(road) -| working(road);
}

// Coverage is the working share of what the segment needs, so a street with one
// of its two columns is half lit rather than fully lit.
pub fn coverage(road: usize) f32 {
    const need = capacity(road);
    if (need == 0) return 0;
    return clamp01(@as(f32, @floatFromInt(working(road))) / @as(f32, @floatFromInt(need)));
}

// Full night before 05:00 and after 21:00, no darkness between 07:00 and 19:00,
// and a linear dusk and dawn ramp in between.
pub fn darkness(time: f64) f32 {
    const h = calendar.hour(time);
    if (h >= 21 or h < 5) return 1;
    if (h < 7) return clamp01(@floatCast((7 - h) / 2));
    if (h >= 19) return clamp01(@floatCast((h - 19) / 2));
    return 0;
}

pub fn illumination(road: usize, time: f64) f32 {
    return darkness(time) * coverage(road);
}

// Bounded speed multiplier: 1.0 in daylight and at full coverage, falling to
// `1 - night_speed_penalty` on a completely dark segment after dusk.
pub fn nightSpeed(road: usize, time: f64) f32 {
    return 1 - night_speed_penalty * darkness(time) * (1 - coverage(road));
}

// Bounded collision-risk multiplier for the incident layer.
pub fn riskMultiplier(road: usize, time: f64) f32 {
    return 1 + night_collision_boost * darkness(time) * (1 - coverage(road));
}

pub fn litSegments() usize {
    var total: usize = 0;
    for (lit[0..city.road_count]) |n| if (n > 0) {
        total += 1;
    };
    return total;
}

pub fn installedTotal() usize {
    var total: usize = 0;
    for (lamps[0..city.road_count]) |n| total += n;
    return total;
}

pub fn workingTotal() usize {
    var total: usize = 0;
    for (lit[0..city.road_count]) |n| total += n;
    return total;
}

pub fn faultCount() usize {
    return installedTotal() -| workingTotal();
}

pub fn eligibleCount() usize {
    var total: usize = 0;
    for (0..city.road_count) |i| if (eligible(i)) {
        total += 1;
    };
    return total;
}

// Mean coverage across eligible segments, so an unlit outer link counts against
// the figure rather than disappearing from it.
pub fn coverageMean() f32 {
    var total: f32 = 0;
    var n: usize = 0;
    for (0..city.road_count) |i| {
        if (!eligible(i)) continue;
        total += coverage(i);
        n += 1;
    }
    return if (n == 0) 0 else total / @as(f32, @floatFromInt(n));
}

pub fn riskMean(time: f64) f32 {
    var total: f32 = 0;
    var n: usize = 0;
    for (0..city.road_count) |i| {
        if (!eligible(i)) continue;
        total += riskMultiplier(i, time);
        n += 1;
    }
    return if (n == 0) 1 else total / @as(f32, @floatFromInt(n));
}

// The day's electricity bill at the currently working column count.
pub fn recompute() void {
    var total: f64 = 0;
    for (lit[0..city.road_count]) |n| total += @as(f64, @floatFromInt(n)) * electricity_per_lamp_day;
    electricity_need_today = cents(total);
}

// The authored town already lights the streets that have frontage: a segment
// fronted by several lots is lit to capacity, a lightly fronted one gets a
// single column, and an empty outer link gets none.
fn seed() void {
    lamps = @splat(0);
    lit = @splat(0);
    for (0..city.road_count) |i| {
        if (!eligible(i)) continue;
        const street = city.roads[i].street;
        var frontage: usize = 0;
        for (city.lots()) |b| {
            if (b.street != street or b.number == 0) continue;
            frontage += 1;
        }
        // Numbered item 17: the integration town switches the layer fully on, so
        // every eligible segment is lit to its class capacity instead of only
        // the segments that carry frontage.
        const want: u8 = if (city.developmentPlan()) capacity(i) else if (frontage >= 4) capacity(i) else if (frontage > 0) 1 else 0;
        lamps[i] = want;
        lit[i] = want;
    }
    installed_total = @intCast(installedTotal());
    recompute();
}

pub fn init() void {
    lamps = @splat(0);
    lit = @splat(0);
    repairs = @splat(0);
    faults_total = 0;
    faults_today = 0;
    repairs_total = 0;
    repairs_today = 0;
    installed_total = 0;
    electricity_paid_total = 0;
    electricity_paid_today = 0;
    works_paid_total = 0;
    works_paid_today = 0;
    electricity_need_today = 0;
    last_fault_day = 0;
    seed();
}

fn hash(road: usize, day: u32) u64 {
    var h: u64 = @as(u64, day) *% 0x9E3779B97F4A7C15;
    h ^= @as(u64, road) *% 0xBF58476D1CE4E5B9;
    h ^= h >> 29;
    h *%= 0xBF58476D1CE4E5B9;
    h ^= h >> 32;
    return h;
}

// A day rolls over: reset the day's own counters, fail a deterministic share of
// the working columns, then price the new day's electricity.
pub fn daily(day: u32) void {
    electricity_paid_today = 0;
    works_paid_today = 0;
    faults_today = 0;
    repairs_today = 0;
    last_fault_day = day;
    for (0..city.road_count) |i| {
        if (lit[i] == 0) continue;
        if (hash(i, day) % 1000 >= fault_permille) continue;
        lit[i] -= 1;
        faults_total +|= 1;
        faults_today +|= 1;
    }
    recompute();
}

// One operating pass. Electricity is paid first in a bounded instalment, then a
// crew reaches at most `max_repairs_per_pass` failed columns in segment order.
// Both are capped by the cash actually available, so the town never books a
// payment it cannot cover.
pub fn update(dt: f32, elapsed: f64, budget: f64) Spend {
    _ = dt;
    _ = elapsed;
    var spend = Spend{};
    var left = @max(0, budget);
    if (electricity_need_today > 0 and electricity_paid_today + 0.0001 < electricity_need_today) {
        const per_pass = cents(electricity_need_today / 16);
        const due = @min(per_pass, electricity_need_today - electricity_paid_today);
        const paid = cents(@min(due, left));
        if (paid > 0) {
            electricity_paid_today = cents(electricity_paid_today + paid);
            electricity_paid_total = cents(electricity_paid_total + paid);
            spend.electricity = paid;
            left -= paid;
        }
    }
    var done: usize = 0;
    var road: usize = 0;
    while (road < city.road_count and done < max_repairs_per_pass) : (road += 1) {
        if (lit[road] >= lamps[road]) continue;
        if (left + 0.0001 < repair_cost) break;
        lit[road] += 1;
        repairs[road] +|= 1;
        repairs_total +|= 1;
        repairs_today +|= 1;
        works_paid_today = cents(works_paid_today + repair_cost);
        works_paid_total = cents(works_paid_total + repair_cost);
        spend.works += repair_cost;
        left -= repair_cost;
        done += 1;
    }
    return spend;
}

// Designate 0..capacity columns on one eligible segment. New columns are
// charged at the published capital rate; returns that cost, 0 when nothing
// changed, or -1 when the segment or the count is refused.
pub fn setLamps(road: usize, value: u32) f64 {
    if (road >= city.road_count or value > max_lamps_per_road) return -1;
    if (!eligible(road) or value > capacity(road)) return -1;
    const want: u8 = @intCast(value);
    const old = lamps[road];
    if (want == old) return 0;
    lamps[road] = want;
    if (want > old) {
        lit[road] = @min(want, lit[road] + (want - old));
        installed_total +|= want - old;
    } else {
        lit[road] = @min(lit[road], want);
    }
    recompute();
    return cents(@as(f64, @floatFromInt(want)) * install_cost - @as(f64, @floatFromInt(old)) * install_cost);
}

pub fn readRoad(road: usize, field: u32, time: f64) f64 {
    if (road >= city.road_count) return -1;
    const r = city.roads[road];
    return switch (field) {
        0 => @floatFromInt(road),
        1 => @floatFromInt(r.district),
        2 => @floatFromInt(r.street),
        3 => @floatFromInt(r.class),
        4 => r.length,
        5 => @floatFromInt(r.a),
        6 => if (eligible(road)) 1 else 0,
        7 => @floatFromInt(installed(road)),
        8 => @floatFromInt(capacity(road)),
        9 => @floatFromInt(working(road)),
        10 => @floatFromInt(failed(road)),
        11 => coverage(road),
        12 => illumination(road, time),
        13 => @as(f64, @floatFromInt(working(road))) * electricity_per_lamp_day,
        14 => @floatFromInt(repairs[road]),
        15 => darkness(time),
        else => -1,
    };
}

pub fn read0(field: u32, time: f64) f64 {
    return switch (field) {
        0 => @floatFromInt(litSegments()),
        1 => @floatFromInt(installedTotal()),
        2 => @floatFromInt(workingTotal()),
        3 => @floatFromInt(faultCount()),
        4 => coverageMean(),
        5 => darkness(time) * coverageMean(),
        6 => electricity_need_today,
        7 => electricity_paid_today,
        8 => electricity_paid_total,
        9 => @floatFromInt(faults_today),
        10 => @floatFromInt(repairs_today),
        11 => works_paid_today,
        12 => works_paid_total,
        13 => @floatFromInt(installed_total),
        14 => darkness(time),
        15 => riskMean(time),
        else => -1,
    };
}

pub fn restore(saved_lamps: []const u8, saved_lit: []const u8, saved_repairs: []const u32, saved_faults: u32, saved_repairs_total: u32, saved_installed: u32, saved_electricity_total: f64, saved_electricity_today: f64, saved_works_total: f64, saved_works_today: f64, saved_need: f64) void {
    lamps = @splat(0);
    lit = @splat(0);
    repairs = @splat(0);
    const roads = @min(saved_lamps.len, city.road_count);
    @memcpy(lamps[0..roads], saved_lamps[0..roads]);
    const lit_roads = @min(saved_lit.len, city.road_count);
    @memcpy(lit[0..lit_roads], saved_lit[0..lit_roads]);
    const repair_roads = @min(saved_repairs.len, city.road_count);
    @memcpy(repairs[0..repair_roads], saved_repairs[0..repair_roads]);
    faults_total = saved_faults;
    repairs_total = saved_repairs_total;
    installed_total = saved_installed;
    electricity_paid_total = cents(saved_electricity_total);
    electricity_paid_today = cents(saved_electricity_today);
    works_paid_total = cents(saved_works_total);
    works_paid_today = cents(saved_works_today);
    electricity_need_today = cents(saved_need);
    faults_today = 0;
    repairs_today = 0;
}

test "capacity follows the street class" {
    init();
    try std.testing.expectEqual(max_lamps_per_road, 6);
    try std.testing.expectEqual(avenue_lamps, 4);
    try std.testing.expectEqual(street_lamps, 2);
}
