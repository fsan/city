const std = @import("std");
pub const Account = struct {
    capacity: usize,
    day: usize,
    night: usize,
    opening: f64,
    cash: f64,
    fares: f64 = 0,
    subsidies: f64 = 0,
    receipts: f64 = 0,
    vehicle: f64 = 0,
    labour: f64 = 0,
};
pub var accounts: [3]Account = undefined;
pub fn init() void {
    accounts = .{
        .{ .capacity = 4, .day = 4, .night = 2, .opening = 600, .cash = 600 },
        .{ .capacity = 3, .day = 3, .night = 1, .opening = 300, .cash = 300 },
        .{ .capacity = 2, .day = 2, .night = 0, .opening = 5, .cash = 5 },
    };
}
pub fn daytime(time: f64) bool {
    const t = @mod(time, 480);
    return t >= 120 and t < 440;
}
pub fn scheduled(window: u32, time: f64) bool {
    return window == 0 or daytime(time);
}
pub fn drivers(id: usize, time: f64) usize {
    return if (daytime(time)) accounts[id].day else accounts[id].night;
}
fn integral(window: u32, time: f64) f64 {
    if (window == 0) return time;
    return @floor(time / 480) * 320 + std.math.clamp(@mod(time, 480) - 120, 0, 320);
}
pub fn hours(window: u32, from: f64, to: f64) f64 {
    return @max(0, integral(window, to) - integral(window, from));
}
pub fn expense(id: usize, vehicle: f64, labour: f64) bool {
    const a = &accounts[id];
    if (a.cash < vehicle + labour) return false;
    a.cash -= vehicle + labour;
    a.vehicle += vehicle;
    a.labour += labour;
    return true;
}
