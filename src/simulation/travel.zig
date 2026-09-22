const std = @import("std");
const calendar = @import("calendar.zig");

// Slice 10: proportionally realistic free-flow speeds and the very small
// learned model each resident keeps. Nothing here allocates or iterates a
// resident array; every helper is pure so the module stays cheap to compute.
pub const walk_speed: f32 = 1.4; // about 5 km/h
pub const bike_speed: f32 = 4.2; // about 15 km/h
pub const bike_lane_speed: f32 = 5.0; // protected cycle lane
pub const car_limit: f32 = 7.0; // about 25 km/h on an ordinary street
pub const bus_limit: f32 = 5.5;
// Street class speed multipliers: 0 lane, 1 street, 2 avenue.
pub const class_car_speed = [_]f32{ 0.82, 1.0, 1.18 };
pub const class_names = [_][]const u8{ "Lane", "Street", "Avenue" };
pub const class_price = [_]f64{ 18, 25, 40 };

pub fn classSpeed(class: u8, condition: f32, slope: f32, works: bool) f32 {
    const index: usize = @min(class, class_car_speed.len - 1);
    return car_limit * class_car_speed[index] * (0.5 + condition / 200) / (1 + slope * 2) * (if (works) @as(f32, 0.45) else 1);
}

pub fn bikeRide(condition: f32, slope: f32, works: bool, cycle_lane: bool) f32 {
    return (if (cycle_lane) bike_lane_speed else bike_speed) * (0.6 + condition / 250) / (1 + slope * 3.2) * (if (works) @as(f32, 0.6) else 1);
}

pub fn walkRide(condition: f32, slope: f32, works: bool) f32 {
    return walk_speed * (0.7 + condition / 100) / (1 + slope * 3) * (if (works) @as(f32, 0.65) else 1);
}

// Four arrival/departure buckets per day: night, morning, afternoon, evening.
pub const bucket_count = 4;
pub const bucket_names = [_][]const u8{ "night 00-06", "morning 06-12", "afternoon 12-17", "evening 17-24" };

pub fn bucket(time: f64) usize {
    const hour = calendar.hour(time);
    if (hour < 6) return 0;
    if (hour < 12) return 1;
    if (hour < 17) return 2;
    return 3;
}

// Learned trip seconds are stored in two-second units, so a u8 covers 510
// seconds and a person still learns "the commute got slower" within a day.
pub const time_unit: f32 = 2;
pub const max_samples: u8 = 8;
pub const memory_count = 3;
pub const no_facility: u16 = 0xffff;
pub const default_chance: u8 = 140; // mild optimism before any experience
pub const chance_floor: u8 = 6;
pub const chance_ceiling: u8 = 250;
pub const chance_alpha: f32 = 1.0 / 3.0;

pub const Model = struct {
    // Mean observed door-to-door trip time per mode and departure bucket.
    time: [4][bucket_count]u8 = @splat(@splat(0)),
    samples: [4][bucket_count]u8 = @splat(@splat(0)),
    // Tiny memory of the parking places this person has actually tried.
    facility: [memory_count]u16 = @splat(no_facility),
    chance: [memory_count][bucket_count]u8 = @splat(@splat(default_chance)),
    // Last departure bucket this person travelled in.
    departed: u8 = 0,
};

pub fn observed(model: *const Model, mode: usize, slot: usize) ?f32 {
    if (mode > 3 or slot >= bucket_count) return null;
    if (model.samples[mode][slot] == 0) return null;
    return @as(f32, @floatFromInt(model.time[mode][slot])) * time_unit;
}

pub fn record(model: *Model, mode: usize, slot: usize, seconds: f32) void {
    if (mode > 3 or slot >= bucket_count or !std.math.isFinite(seconds)) return;
    const units: u32 = @intFromFloat(@max(0, @min(255 * @as(f32, time_unit), @round(seconds / time_unit) * time_unit)));
    const clamped: u8 = @intCast(@min(255, units / 2));
    const sample = model.samples[mode][slot];
    if (sample == 0) {
        model.time[mode][slot] = clamped;
    } else {
        const previous: f32 = @floatFromInt(model.time[mode][slot]);
        const next = previous + (@as(f32, @floatFromInt(clamped)) - previous) / @as(f32, @floatFromInt(@as(u16, sample) + 1));
        model.time[mode][slot] = @intFromFloat(@max(0, @min(255, @round(next))));
    }
    if (sample < max_samples) model.samples[mode][slot] = sample + 1;
}

pub fn remembered(model: *const Model, facility: u16) ?usize {
    for (model.facility, 0..) |value, slot| {
        if (value == facility) return slot;
    }
    return null;
}

pub fn chanceFor(model: *const Model, facility: u16, slot: usize) u8 {
    if (remembered(model, facility)) |index| return model.chance[index][slot];
    return default_chance;
}

// Simple first-order Markov estimate: the remembered chance of a free space
// moves a fixed share of the way toward the outcome of the last attempt.
pub fn observeChance(model: *Model, facility: u16, slot: usize, free: bool) void {
    if (slot >= bucket_count or facility == no_facility) return;
    var index = remembered(model, facility);
    if (index == null) {
        // A bounded memory: reuse the least recently updated slot. The model
        // keeps only a handful of places, which is the whole point.
        var target: usize = 0;
        for (model.facility, 0..) |value, k| {
            if (value == no_facility) {
                target = k;
                break;
            }
        }
        model.facility[target] = facility;
        model.chance[target] = @splat(default_chance);
        index = target;
    }
    const current: f32 = @floatFromInt(model.chance[index.?][slot]);
    const outcome: f32 = if (free) 255 else 0;
    const next = current + (outcome - current) * chance_alpha;
    model.chance[index.?][slot] = @intFromFloat(@max(@as(f32, chance_floor), @min(@as(f32, chance_ceiling), @round(next))));
}

pub fn chanceValue(value: u8) f32 {
    return @as(f32, @floatFromInt(value)) / 255.0;
}

// Bounded patience so a crosser can never be stuck forever.
pub const crossing_patience: f32 = 30;

pub fn crossingAdmitted(marked: bool, parallel_green: bool, gap: bool, waited: f32) bool {
    if (marked and parallel_green) return true;
    if (!marked and gap) return true;
    return waited >= crossing_patience;
}

// Slice 10: the mode a plan is being made for, used by the reports.
pub const mode_names = [_][]const u8{ "walk", "cycle", "car", "bus" };
