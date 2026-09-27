const std = @import("std");
const city = @import("../scene/city.zig");

// Numbered list item 15: traffic incidents.
//
// Until now a blocked lane simply did not exist: cars queued behind congestion
// and that was the whole story. This module gives the town explicit incidents -
// collisions, breakdowns, obstructions and a roadworks spillover - with a
// reported, responding, clearing and cleared life cycle. An incident occupies a
// real lane on a real segment, so it slows the traffic actually routed through
// it, and it is cleared by a bounded response that costs municipal money.
//
// Everything here is deterministic. The decision to raise a collision is a pure
// function of the live congestion on a segment and an integer hash of the step,
// so a save/load round trip replays the same incidents instead of depending on
// a floating-point random stream.
pub const max_incidents = 64;
pub const max_recent = 8;

// How many simulation seconds an incident stays in each phase. A collision is
// reported, attended, then cleared; the bounds are policy numbers, not a
// dispatch model.
pub const min_response: f32 = 6;
pub const max_response: f32 = 120;
pub const default_response: f32 = 24;
pub const min_clear: f32 = 6;
pub const max_clear: f32 = 240;
pub const default_clear: f32 = 40;

// A collision can only be raised when the segment is genuinely busy, and never
// more often than this many simulation seconds town-wide.
pub const collision_congestion_floor: f32 = 0.35;
pub const collision_cooldown: f64 = 45;
pub const max_severity: u8 = 3;

pub const Kind = enum(u8) { collision = 0, breakdown = 1, obstruction = 2, works = 3 };
pub const Phase = enum(u8) { reported = 0, responding = 1, clearing = 2, cleared = 3 };

pub const Record = struct {
    number: u32 = 0,
    kind: Kind = .collision,
    phase: Phase = .reported,
    road: usize = 0,
    node: usize = 0,
    lane: u8 = 0,
    severity: u8 = 1,
    // Absolute simulation times for each transition. A zero end time means the
    // phase has not been reached yet.
    reported: f64 = 0,
    responded: f64 = 0,
    arrived: f64 = 0,
    cleared: f64 = 0,
    // How long this incident held its lane, and the extra vehicle-seconds it
    // has cost the segment, both accumulated while it is live.
    blocked_seconds: f32 = 0,
    delay_total: f32 = 0,
    responders: u8 = 0,
    cost: f64 = 0,
};

pub var records: [max_incidents]Record = @splat(.{});
pub var count: usize = 0;
pub var next_number: u32 = 1;
pub var raised_total: u32 = 0;
pub var cleared_total: u32 = 0;
pub var collisions_total: u32 = 0;
pub var cost_total: f64 = 0;
pub var blocked_seconds_total: f32 = 0;
pub var delay_total: f32 = 0;
pub var last_raised: f64 = -1e9;

fn cents(value: f64) f64 {
    return @round(value * 100) / 100;
}

fn clampSeverity(value: u8) u8 {
    return @min(value, max_severity);
}

pub fn init() void {
    records = @splat(.{});
    count = 0;
    next_number = 1;
    raised_total = 0;
    cleared_total = 0;
    collisions_total = 0;
    cost_total = 0;
    blocked_seconds_total = 0;
    delay_total = 0;
    last_raised = -1e9;
}

pub fn restore(saved: []const Record, saved_next: u32, saved_raised: u32, saved_cleared: u32, saved_collisions: u32, saved_cost: f64, saved_blocked: f32, saved_delay: f32, saved_last: f64) void {
    records = @splat(.{});
    count = @min(saved.len, records.len);
    for (saved[0..count], 0..) |entry, i| records[i] = entry;
    next_number = @max(1, saved_next);
    raised_total = saved_raised;
    cleared_total = saved_cleared;
    collisions_total = saved_collisions;
    cost_total = cents(saved_cost);
    blocked_seconds_total = saved_blocked;
    delay_total = saved_delay;
    last_raised = saved_last;
}

pub fn activeCount() usize {
    var total: usize = 0;
    for (records[0..count]) |record_value| {
        if (record_value.phase != .cleared) total += 1;
    }
    return total;
}

pub fn blockingCount() usize {
    var total: usize = 0;
    for (records[0..count]) |record_value| {
        if (blocks(&record_value)) total += 1;
    }
    return total;
}

pub fn respondersActive() usize {
    var total: usize = 0;
    for (records[0..count]) |record_value| {
        if (record_value.phase == .responding or record_value.phase == .clearing) total += record_value.responders;
    }
    return total;
}

// A lane is physically blocked once a responder or the recovery crew is on
// scene, and stays blocked until the incident is cleared.
pub fn blocks(record_value: *const Record) bool {
    return record_value.phase == .responding or record_value.phase == .clearing;
}

// The extra seconds a driver should lose on this segment because of a live
// incident. A collision across the whole carriageway costs more than a single
// lane, and severity scales the penalty.
pub fn penalty(road: usize) f32 {
    var total: f32 = 0;
    for (records[0..count]) |record_value| {
        if (!blocks(&record_value) or record_value.road != road) continue;
        const lane_factor: f32 = if (record_value.lane >= 2) 1 else 0.5;
        total += @as(f32, @floatFromInt(record_value.severity + 1)) * 2.2 * lane_factor;
    }
    return total;
}

// True when any live incident occupies this exact lane on this segment.
pub fn laneBlocked(road: usize, lane: u8) bool {
    for (records[0..count]) |record_value| {
        if (!blocks(&record_value) or record_value.road != road) continue;
        if (record_value.lane >= 2 or record_value.lane == lane) return true;
    }
    return false;
}

pub fn severityFor(congestion: f32) u8 {
    if (congestion > 0.85) return 3;
    if (congestion > 0.65) return 2;
    if (congestion > 0.45) return 1;
    return 0;
}

pub fn clearCost(kind: Kind, severity: u8) f64 {
    const base: f64 = switch (kind) {
        .collision => 900,
        .breakdown => 320,
        .obstruction => 240,
        .works => 480,
    };
    return cents(base * (1 + @as(f64, @floatFromInt(@min(severity, max_severity))) * 0.6));
}

fn find(number: u32) ?usize {
    for (records[0..count], 0..) |record_value, i| if (record_value.number == number) return i;
    return null;
}

// Raise an incident. The caller has already decided that the segment is busy
// enough; this only records it. Returns the new incident's number, or zero when
// the ring is full.
pub fn raise(kind: Kind, road: usize, node: usize, lane: u8, severity: u8, elapsed: f64) u32 {
    if (road >= city.road_count or count >= records.len) return 0;
    const number = next_number;
    const record_value = Record{
        .number = number,
        .kind = kind,
        .phase = .reported,
        .road = road,
        .node = node,
        .lane = lane,
        .severity = clampSeverity(severity),
        .reported = elapsed,
        .responders = if (kind == .collision) 2 else 1,
    };
    records[count] = record_value;
    count += 1;
    next_number += 1;
    raised_total +|= 1;
    if (kind == .collision) collisions_total +|= 1;
    last_raised = elapsed;
    return number;
}

// The deterministic collision decision: a busy segment raises a collision when
// the integer hash of the step lands under a small probability scaled by the
// live congestion. Returns the incident number or zero.
pub fn maybeCollide(road: usize, node: usize, congestion: f32, elapsed: f64, step: u64, risk: f32) u32 {
    if (road >= city.road_count) return 0;
    if (congestion < collision_congestion_floor) return 0;
    if (elapsed - last_raised < collision_cooldown) return 0;
    const h = hash(road, node, step);
    // Numbered item 17: `risk` is the caller's bounded night-time multiplier;
    // it is 1.0 in daylight and on a fully lit segment.
    const threshold: u32 = @intFromFloat(std.math.clamp(congestion - collision_congestion_floor, 0, 1) * 4000 * @max(0.1, risk));
    if ((h % 100000) >= threshold) return 0;
    const lane: u8 = if (city.roads[road].class >= 2) 2 else 0;
    return raise(.collision, road, node, lane, severityFor(congestion), elapsed);
}

fn hash(road: usize, node: usize, step: u64) u64 {
    var h: u64 = step *% 0x9E3779B97F4A7C15;
    h ^= @as(u64, road) *% 0xBF58476D1CE4E5B9;
    h ^= @as(u64, node) *% 0x94D049BB133111EB;
    h ^= h >> 29;
    h *%= 0xBF58476D1CE4E5B9;
    h ^= h >> 32;
    return h;
}

// One step of the incident life cycle. Returns the money the recovery crews
// spent this step, which the caller books through the municipal ledger.
pub fn update(dt: f32, elapsed: f64) f64 {
    if (count == 0) return 0;
    var spend: f64 = 0;
    for (records[0..count]) |*record_value| {
        switch (record_value.phase) {
            .reported => {
                if (elapsed - record_value.reported >= responseTime(record_value)) {
                    record_value.phase = .responding;
                    record_value.responded = elapsed;
                    record_value.arrived = elapsed;
                }
            },
            .responding => {
                const cost = cents(clearCost(record_value.kind, record_value.severity) / 4 * @as(f64, dt) / clearTime(record_value));
                record_value.cost = cents(record_value.cost + cost);
                spend += cost;
                if (elapsed - record_value.responded >= clearTime(record_value)) {
                    record_value.phase = .clearing;
                    record_value.cleared = elapsed;
                }
            },
            .clearing => {
                const cost = cents(clearCost(record_value.kind, record_value.severity) / 4 * @as(f64, dt) / clearTime(record_value));
                record_value.cost = cents(record_value.cost + cost);
                spend += cost;
                if (elapsed - record_value.cleared >= 4) {
                    record_value.phase = .cleared;
                    cleared_total +|= 1;
                }
            },
            .cleared => {},
        }
        if (blocks(record_value)) {
            record_value.blocked_seconds += dt;
            blocked_seconds_total += dt;
            const cost = penalty(record_value.road) * dt * 0.05;
            record_value.delay_total += cost;
            delay_total += cost;
        }
    }
    if (spend > 0) {
        cost_total = cents(cost_total + spend);
    }
    return spend;
}

fn responseTime(record_value: *const Record) f32 {
    const base = default_response + @as(f32, @floatFromInt(record_value.severity)) * 4;
    return std.math.clamp(base, min_response, max_response);
}

fn clearTime(record_value: *const Record) f32 {
    const base = default_clear + @as(f32, @floatFromInt(record_value.severity)) * 12;
    return std.math.clamp(base, min_clear, max_clear);
}

// Report one record by flat index, newest first, for the inspector. The newest
// incident is index zero so the panel does not have to know the ring layout.
pub fn readNewest(index: usize, field: u32) f64 {
    if (index >= count) return -1;
    const record_value = records[count - 1 - index];
    return switch (field) {
        0 => @floatFromInt(record_value.number),
        1 => @floatFromInt(@intFromEnum(record_value.kind)),
        2 => @floatFromInt(@intFromEnum(record_value.phase)),
        3 => @floatFromInt(record_value.road),
        4 => @floatFromInt(record_value.node),
        5 => @floatFromInt(record_value.lane),
        6 => @floatFromInt(record_value.severity),
        7 => record_value.reported,
        8 => record_value.responded,
        9 => record_value.arrived,
        10 => record_value.cleared,
        11 => record_value.blocked_seconds,
        12 => record_value.delay_total,
        13 => @floatFromInt(record_value.responders),
        14 => record_value.cost,
        15 => if (blocks(&record_value)) 1 else 0,
        16 => if (record_value.road < city.road_count) @floatFromInt(city.roads[record_value.road].class) else -1,
        else => -1,
    };
}

pub fn kindName(kind: Kind) []const u8 {
    return switch (kind) {
        .collision => "collision",
        .breakdown => "breakdown",
        .obstruction => "obstruction",
        .works => "roadworks",
    };
}

pub fn phaseName(phase: Phase) []const u8 {
    return switch (phase) {
        .reported => "reported",
        .responding => "responding",
        .clearing => "clearing",
        .cleared => "cleared",
    };
}
