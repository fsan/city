const std = @import("std");

// Slice 6: one bounded civic calendar shared by residents, transport staffing
// and the municipal budget period. One day stays 480 simulation seconds, so one
// hour is 20 seconds. Day 1 is Monday.
pub const seconds_per_day: f64 = 480;
pub const seconds_per_hour: f64 = 20;
pub const days_per_week: u32 = 7;
pub const seconds_per_week: f64 = seconds_per_day * @as(f64, @floatFromInt(days_per_week));

pub const Weekday = enum(u32) { monday = 0, tuesday, wednesday, thursday, friday, saturday, sunday };
pub const Phase = enum(u32) { sleep = 0, morning = 1, work = 2, evening = 3, leisure = 4, night = 5 };
pub const Shift = enum(u32) { day = 0, evening = 1, night = 2 };

pub const weekday_names = [_][]const u8{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
pub const phase_names = [_][]const u8{ "sleep", "morning commute", "work", "evening", "leisure", "night" };
pub const shift_names = [_][]const u8{ "day 06-14", "evening 14-22", "night 22-06" };

pub fn dayIndex(time: f64) u32 {
    return @intFromFloat(@max(0, @floor(time / seconds_per_day)));
}
pub fn weekday(time: f64) Weekday {
    return @enumFromInt(dayIndex(time) % days_per_week);
}
pub fn isWeekend(time: f64) bool {
    const day = weekday(time);
    return day == .saturday or day == .sunday;
}
pub fn hour(time: f64) f64 {
    return @mod(time, seconds_per_day) / seconds_per_hour;
}
pub fn phase(time: f64) Phase {
    const h = hour(time);
    if (h < 6) return .sleep;
    if (h < 9) return .morning;
    if (h < 17) return .work;
    if (h < 20) return .evening;
    if (h < 22) return .leisure;
    return .night;
}
pub fn weekIndex(time: f64) u32 {
    return @intFromFloat(@max(0, @floor(time / seconds_per_week)));
}
pub fn nextWeekStart(time: f64) f64 {
    return @as(f64, @floatFromInt(weekIndex(time) + 1)) * seconds_per_week;
}
pub fn shiftFor(index: usize) Shift {
    return @enumFromInt(index % 3);
}
pub fn shiftStart(shift: Shift) f64 {
    return switch (shift) {
        .day => 120, // 06:00
        .evening => 280, // 14:00
        .night => 440, // 22:00
    };
}
pub fn shiftEnd(shift: Shift) f64 {
    return switch (shift) {
        .day => 280, // 14:00
        .evening => 440, // 22:00
        .night => 600, // 06:00 next day, expressed as an extended hour
    };
}
// True while the shift is on duty, including the night shift across midnight.
pub fn onShift(shift: Shift, time: f64) bool {
    const t = @mod(time, seconds_per_day);
    return switch (shift) {
        .day => t >= 120 and t < 280,
        .evening => t >= 280 and t < 440,
        .night => t >= 440 or t < 120,
    };
}

// Slice 13: working hours belong to the place people work, not to a global
// three-shift rotation. Each facility kind keeps its own bounded window (or a
// small set of overlapping windows where the place genuinely runs shifts), so
// offices are 9-5 while a depot or a clinic covers its own day.
pub const Facility = enum(u8) { office, shop, clinic, hall, depot, other };

pub const Schedule = struct { start: f32, end: f32 };

// A window whose start is later than its end runs overnight.
pub fn inSchedule(s: Schedule, at_hour: f32) bool {
    if (@abs(s.start - s.end) < 0.001) return false;
    if (s.start < s.end) return at_hour >= s.start and at_hour < s.end;
    return at_hour >= s.start or at_hour < s.end;
}

// The bounded set of windows a facility kind runs, by slot. `slot` is the
// resident's own shift index, reduced modulo the number of windows, so the
// authored town keeps a stable mix without inventing a roster system here.
pub fn facilityWindows(facility: Facility) []const Schedule {
    return switch (facility) {
        .office => &[_]Schedule{.{ .start = 9, .end = 17 }},
        .hall => &[_]Schedule{.{ .start = 8.5, .end = 17.5 }},
        .shop => &[_]Schedule{ .{ .start = 9, .end = 17 }, .{ .start = 12, .end = 20 } },
        .clinic => &[_]Schedule{ .{ .start = 7, .end = 15 }, .{ .start = 9, .end = 17 }, .{ .start = 14, .end = 22 } },
        .depot => &[_]Schedule{ .{ .start = 6, .end = 14 }, .{ .start = 14, .end = 22 }, .{ .start = 22, .end = 6 } },
        .other => &[_]Schedule{.{ .start = 9, .end = 17 }},
    };
}

pub fn facilityWindow(facility: Facility, slot: u8) Schedule {
    const windows = facilityWindows(facility);
    return windows[@as(usize, slot) % windows.len];
}

// True while this slot of this facility is on duty, including overnight windows.
pub fn onFacilityShift(facility: Facility, slot: u8, time: f64) bool {
    return inSchedule(facilityWindow(facility, slot), @floatCast(hour(time)));
}
