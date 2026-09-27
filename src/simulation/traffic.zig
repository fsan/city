const std = @import("std");
const city = @import("../scene/city.zig");

// Numbered item 19: traffic law, per-place overrides and enforcement.
//
// The earlier road work gave the player street classes and priority lanes but
// no say over how many lanes a street carries, which turns are legal, whether
// a signal must actually be obeyed, what the speed limit is, or whether anyone
// is watching. This module owns all of that:
//
//   * one city-wide body of law - the legal maximum speed, whether left,
//     right and U-turns are allowed, whether a traffic light stops traffic, the
//     default rule at an unsignalised junction and the fine for speeding;
//   * a bounded override on any single segment (its own limit, its own turn
//     permissions) and on any single junction (its own control rule), so the
//     city law can be changed back at one place without changing it everywhere;
//   * speed traps, which are a placeable municipal work rather than a global
//     switch, and which record real catches and real fines.
//
// The module holds no geometry and no vehicles: it resolves numbers that the
// vehicle loop, the routing helper and the panel all read back, so the panel
// can never show a rule the simulation is not applying.

pub const max_traps = 32;
pub const min_speed_kmh: f32 = 5;
pub const max_speed_kmh: f32 = 60;
// The authored town was tuned around a 25 km/h street, so the opening law is
// that number and a new city drives exactly as it did before the law existed.
pub const default_speed_kmh: f32 = 25;
pub const default_fine: f64 = 40;
pub const min_fine: f64 = 5;
pub const max_fine: f64 = 200;
// A driver has to be this far over the posted limit before a trap records.
pub const trap_tolerance: f32 = 1.10;
// One trap costs this much to install, charged as municipal works.
pub const trap_capital: f64 = 420;
pub const max_overrides = 4096;

// 0 inherit, 1 uncontrolled, 2 give way, 3 stop. Overrides on a junction.
pub const JunctionRule = enum(u8) { inherit = 0, uncontrolled = 1, give_way = 2, stop = 3 };
pub const Movement = enum(u8) { left = 0, right = 1, uturn = 2 };
// 0 inherit the city law, 1 allowed here, 2 banned here, so a specific place
// can both forbid a turn the city allows and allow one the city forbids.
pub const Permission = enum(u8) { inherit = 0, allowed = 1, banned = 2 };

pub const Laws = struct {
    max_speed_kmh: f32 = default_speed_kmh,
    left: bool = true,
    right: bool = true,
    uturn: bool = false,
    // The user's "if cars need to stop or not to them": when this is false a
    // signalised junction is a caution, not a stop, and drivers cross it the
    // way they cross a flashing amber.
    stop_at_signals: bool = true,
    junction_rule: JunctionRule = .uncontrolled,
    enforcement: bool = true,
    fine: f64 = default_fine,
};

pub const Trap = struct {
    road: usize = 0,
    active: bool = false,
    // 0 inherits the segment's own legal limit, so a trap follows an override
    // unless the player pins a number to it.
    limit_kmh: f32 = 0,
    catches: u32 = 0,
    fines: f64 = 0,
    spent: f64 = 0,
};

pub var laws: Laws = .{};
pub var speed_override: [city.max_roads]f32 = @splat(0);
// Two bits per movement: low pair left, then right, then u-turn.
pub var turn_override: [city.max_roads]u8 = @splat(0);
pub var junction_override: [city.max_nodes]u8 = @splat(0);
pub var traps: [max_traps]Trap = @splat(.{});
var trap_index: [city.max_roads]i16 = @splat(-1);
pub var trap_count: usize = 0;
pub var traps_installed: u32 = 0;
pub var traps_removed: u32 = 0;
pub var catches: u32 = 0;
pub var catches_today: u32 = 0;
pub var fines_total: f64 = 0;
pub var fines_today: f64 = 0;
pub var install_spent: f64 = 0;
pub var overrides_total: u32 = 0;

pub fn init() void {
    laws = .{};
    speed_override = @splat(0);
    turn_override = @splat(0);
    junction_override = @splat(0);
    traps = @splat(.{});
    trap_index = @splat(-1);
    trap_count = 0;
    traps_installed = 0;
    traps_removed = 0;
    catches = 0;
    catches_today = 0;
    fines_total = 0;
    fines_today = 0;
    install_spent = 0;
    overrides_total = 0;
}

// One daily rollover clears the day's counters; lifetime totals stand.
pub fn daily() void {
    catches_today = 0;
    fines_today = 0;
}

pub fn clampSpeed(value: f32) f32 {
    if (!std.math.isFinite(value)) return default_speed_kmh;
    return std.math.clamp(value, min_speed_kmh, max_speed_kmh);
}

pub fn clampFine(value: f64) f64 {
    if (!std.math.isFinite(value)) return default_fine;
    return std.math.clamp(value, min_fine, max_fine);
}

pub fn mps(kmh: f32) f32 {
    return kmh / 3.6;
}

pub fn setLawSpeed(kmh: f32) bool {
    laws.max_speed_kmh = clampSpeed(kmh);
    return true;
}

pub fn setLawTurns(left: bool, right: bool, uturn: bool) bool {
    laws.left = left;
    laws.right = right;
    laws.uturn = uturn;
    return true;
}

// The switch behind the user's "if cars need to stop or not to them".
pub fn setLawStopAtSignals(stop: bool) bool {
    laws.stop_at_signals = stop;
    return true;
}

pub fn setLawJunctionRule(rule: u8) bool {
    if (rule > @intFromEnum(JunctionRule.stop)) return false;
    laws.junction_rule = @enumFromInt(rule);
    return true;
}

pub fn setLawEnforcement(on: bool) bool {
    laws.enforcement = on;
    return true;
}

pub fn setLawFine(value: f64) bool {
    laws.fine = clampFine(value);
    return true;
}

// The legal limit in force on one segment: a per-segment override wins, and
// otherwise the city-wide law applies. The class design speed is a separate
// physical ceiling the vehicle loop already applies.
pub fn speedLimitKmh(road: usize) f32 {
    if (road >= city.road_count) return laws.max_speed_kmh;
    if (speed_override[road] > 0) return clampSpeed(speed_override[road]);
    return laws.max_speed_kmh;
}

pub fn speedLimit(road: usize) f32 {
    return mps(speedLimitKmh(road));
}

pub fn hasSpeedOverride(road: usize) bool {
    return road < city.road_count and speed_override[road] > 0;
}

// Setting zero clears the override and hands the segment back to the law.
pub fn setSpeedOverride(road: usize, kmh: f32) bool {
    if (road >= city.max_roads) return false;
    if (kmh <= 0 or !std.math.isFinite(kmh)) {
        speed_override[road] = 0;
        return true;
    }
    speed_override[road] = clampSpeed(kmh);
    overrides_total +|= 1;
    return true;
}

fn slot(movement: Movement) u3 {
    return switch (movement) {
        .left => 0,
        .right => 2,
        .uturn => 4,
    };
}

pub fn movementPermission(road: usize, movement: Movement) Permission {
    if (road >= city.max_roads) return .inherit;
    const value = (turn_override[road] >> slot(movement)) & 3;
    return switch (value) {
        1 => .allowed,
        2 => .banned,
        else => .inherit,
    };
}

// The resolved permission: an explicit override wins, otherwise the city law.
pub fn movementAllowed(road: usize, movement: Movement) bool {
    return switch (movementPermission(road, movement)) {
        .allowed => true,
        .banned => false,
        .inherit => switch (movement) {
            .left => laws.left,
            .right => laws.right,
            .uturn => laws.uturn,
        },
    };
}

pub fn setMovementOverride(road: usize, movement: Movement, permission: Permission) bool {
    if (road >= city.max_roads) return false;
    const shift = slot(movement);
    turn_override[road] &= ~(@as(u8, 3) << shift);
    turn_override[road] |= @as(u8, @intFromEnum(permission)) << shift;
    overrides_total +|= 1;
    return true;
}

pub fn clearMovementOverride(road: usize, movement: Movement) bool {
    return setMovementOverride(road, movement, .inherit);
}

pub fn junctionRule(node: usize) JunctionRule {
    if (node < city.max_nodes and junction_override[node] != 0) return @enumFromInt(junction_override[node]);
    return laws.junction_rule;
}

pub fn junctionRuleOverride(node: usize) JunctionRule {
    if (node >= city.max_nodes or junction_override[node] == 0) return .inherit;
    return @enumFromInt(junction_override[node]);
}

pub fn setJunctionRule(node: usize, rule: JunctionRule) bool {
    if (node >= city.max_nodes) return false;
    junction_override[node] = @intFromEnum(rule);
    overrides_total +|= 1;
    return true;
}

// A junction whose lights are present but not mandatory, or one under a give
// way or stop rule, is a caution: the vehicle loop slows drivers and the entry
// gate makes them yield to whoever is already in the box.
pub fn cautionJunction(node: usize, signalled: bool) bool {
    if (signalled) return !laws.stop_at_signals;
    return switch (junctionRule(node)) {
        .give_way, .stop => true,
        else => false,
    };
}

pub fn trapAt(road: usize) ?usize {
    if (road >= city.road_count) return null;
    const index = trap_index[road];
    return if (index >= 0) @as(usize, @intCast(index)) else null;
}

pub fn trapLimitKmh(road: usize) f32 {
    if (trapAt(road)) |index| {
        if (traps[index].limit_kmh > 0) return clampSpeed(traps[index].limit_kmh);
    }
    return speedLimitKmh(road);
}

// A catch is recorded only when the driver is genuinely over the posted limit
// by the tolerance, the trap is switched on, and the city is enforcing.
pub fn trapThreshold(road: usize) f32 {
    return mps(trapLimitKmh(road)) * trap_tolerance;
}

pub fn enforceTrap(road: usize, speed: f32) bool {
    if (!laws.enforcement) return false;
    const index = trapAt(road) orelse return false;
    const trap = &traps[index];
    if (!trap.active) return false;
    const threshold = trapThreshold(road);
    if (!std.math.isFinite(speed) or speed <= threshold) return false;
    const amount = laws.fine;
    trap.catches +|= 1;
    trap.fines += amount;
    catches +|= 1;
    catches_today +|= 1;
    fines_total += amount;
    fines_today += amount;
    return true;
}

// Installing a trap charges the caller the capital cost; the return value is
// that cost, or -1 when the segment is already covered, out of range, or the
// trap register is full.
pub fn installTrap(road: usize, limit_kmh: f32) f64 {
    if (road >= city.road_count) return -1;
    if (trapAt(road) != null) return -1;
    if (trap_count >= max_traps) return -1;
    if (city.roads[road].class == 0) return -1;
    traps[trap_count] = .{ .road = road, .active = true, .limit_kmh = if (limit_kmh > 0) clampSpeed(limit_kmh) else 0, .spent = trap_capital };
    trap_index[road] = @intCast(trap_count);
    trap_count += 1;
    traps_installed +|= 1;
    install_spent += trap_capital;
    return trap_capital;
}

pub fn removeTrap(road: usize) bool {
    const index = trapAt(road) orelse return false;
    const last = trap_count - 1;
    const moved = traps[last];
    traps[index] = moved;
    trap_index[road] = -1;
    trap_index[moved.road] = @intCast(index);
    traps[last] = .{};
    trap_count -= 1;
    traps_removed +|= 1;
    return true;
}

pub fn setTrapLimit(road: usize, limit_kmh: f32) bool {
    const index = trapAt(road) orelse return false;
    traps[index].limit_kmh = if (limit_kmh > 0) clampSpeed(limit_kmh) else 0;
    return true;
}

pub fn setTrapActive(road: usize, active: bool) bool {
    const index = trapAt(road) orelse return false;
    traps[index].active = active;
    return true;
}

// Numbered item 19: put a validated save back. Every derived value the panel
// reads is recomputed from these records rather than trusted from the file.
pub fn restore(
    law_speed_kmh: f32,
    left: bool,
    right: bool,
    uturn: bool,
    stop_at_signals: bool,
    junction_rule: u8,
    enforcement: bool,
    fine: f64,
    speed: []const f32,
    turns: []const u8,
    junctions: []const u8,
    trap_records: []const Trap,
    installed: u32,
    removed: u32,
    caught: u32,
    caught_today: u32,
    fines: f64,
    fines_day: f64,
    spent: f64,
    overrides: u32,
) void {
    init();
    laws = .{
        .max_speed_kmh = clampSpeed(law_speed_kmh),
        .left = left,
        .right = right,
        .uturn = uturn,
        .stop_at_signals = stop_at_signals,
        .junction_rule = if (junction_rule > @intFromEnum(JunctionRule.stop)) .uncontrolled else @enumFromInt(junction_rule),
        .enforcement = enforcement,
        .fine = clampFine(fine),
    };
    for (speed[0..@min(speed.len, city.max_roads)], 0..) |value, i| speed_override[i] = if (value > 0) clampSpeed(value) else 0;
    @memcpy(turn_override[0..@min(turns.len, city.max_roads)], turns[0..@min(turns.len, city.max_roads)]);
    @memcpy(junction_override[0..@min(junctions.len, city.max_nodes)], junctions[0..@min(junctions.len, city.max_nodes)]);
    trap_count = @min(trap_records.len, max_traps);
    for (trap_records[0..trap_count], 0..) |record, i| {
        traps[i] = record;
        if (record.road < city.max_roads) trap_index[record.road] = @intCast(i);
    }
    traps_installed = installed;
    traps_removed = removed;
    catches = caught;
    catches_today = caught_today;
    fines_total = fines;
    fines_today = fines_day;
    install_spent = spent;
    overrides_total = overrides;
}

pub fn turnName(movement: Movement) []const u8 {
    return switch (movement) {
        .left => "left",
        .right => "right",
        .uturn => "u-turn",
    };
}

pub fn permissionName(permission: Permission) []const u8 {
    return switch (permission) {
        .inherit => "city law",
        .allowed => "allowed",
        .banned => "banned",
    };
}

pub fn junctionRuleName(rule: JunctionRule) []const u8 {
    return switch (rule) {
        .inherit => "city law",
        .uncontrolled => "uncontrolled",
        .give_way => "give way",
        .stop => "stop sign",
    };
}

test "a trap catches a speeding driver and pays the fine" {
    init();
    city.road_count = 8;
    city.roads[2].class = 1;
    try std.testing.expect(installTrap(2, 20) > 0);
    try std.testing.expect(trapAt(2) != null);
    // 20 km/h posted, so 5.56 m/s is the limit and the tolerance puts the
    // threshold a little above it.
    try std.testing.expect(!enforceTrap(2, 5.0));
    try std.testing.expect(enforceTrap(2, 7.0));
    try std.testing.expectEqual(@as(u32, 1), catches);
    try std.testing.expectEqual(@as(u32, 1), traps[0].catches);
    try std.testing.expectEqual(default_fine, fines_total);
    // A second trap on the same segment is refused, and a lane cannot take one.
    try std.testing.expect(installTrap(2, 0) < 0);
    city.roads[3].class = 0;
    try std.testing.expect(installTrap(3, 0) < 0);
    try std.testing.expect(removeTrap(2));
    try std.testing.expectEqual(@as(usize, 0), trap_count);
    city.road_count = 0;
}

test "the city law resolves with and without a local override" {
    init();
    city.road_count = 20;
    try std.testing.expectEqual(default_speed_kmh, speedLimitKmh(3));
    _ = setSpeedOverride(3, 40);
    try std.testing.expectEqual(@as(f32, 40), speedLimitKmh(3));
    try std.testing.expectEqual(default_speed_kmh, speedLimitKmh(4));
    _ = setSpeedOverride(3, 0);
    try std.testing.expectEqual(default_speed_kmh, speedLimitKmh(3));
    city.road_count = 0;
}

test "a local override wins over the city law in both directions" {
    init();
    city.road_count = 20;
    try std.testing.expect(movementAllowed(2, .left));
    _ = setLawTurns(false, true, false);
    try std.testing.expect(!movementAllowed(2, .left));
    _ = setMovementOverride(2, .left, .allowed);
    try std.testing.expect(movementAllowed(2, .left));
    try std.testing.expect(!movementAllowed(2, .uturn));
    city.road_count = 0;
}
