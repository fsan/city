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
