const std = @import("std");
const city = @import("scene/city.zig");
const game = @import("simulation/game.zig");
const scene = @import("render/scene.zig");
const residents = game.residents;
const finance = game.finance;
const contracts = game.contracts;
const transport = game.transport;
var speed: f32 = 1;
var accumulator: f32 = 0;
export fn init() void {
    city.init();
    game.init();
    scene.reset();
    scene.selected = -1;
    scene.selected_person = -1;
    speed = 1;
    accumulator = 0;
}
export fn update(seconds: f32) void {
    accumulator += std.math.clamp(seconds, 0, 0.1) * speed;
    while (accumulator >= 1.0 / 30.0) {
        game.update(1.0 / 30.0);
        accumulator -= 1.0 / 30.0;
    }
}
export fn draw(width: f32, height: f32) usize {
    scene.draw(width, height);
    return scene.count;
}
export fn vertex_pointer() [*]const f32 {
    return &scene.vertices;
}
export fn pan(x: f32, y: f32) void {
    scene.pan(x, y);
}
export fn rotate(amount: f32) void {
    scene.angle += amount;
}
export fn reset_camera() void {
    scene.reset();
}
export fn pick(x: f32, y: f32) void {
    scene.pick(x, y);
}
export fn zoom_at(amount: f32, x: f32, y: f32) void {
    scene.zoomAt(amount, x, y);
}
export fn set_speed(value: f32) void {
    speed = std.math.clamp(value, 0, 16);
}
export fn set_funding(value: u32) void {
    finance.funding = @min(value, 2);
}
export fn set_overlay(value: u32) void {
    scene.overlay = @min(value, 2);
}
export fn apply_taxes(home: f64, commercial: f64) bool {
    return finance.applyTaxes(home, commercial);
}
export fn offer(road: u32, scope: f32, price: f64) u32 {
    return contracts.offer(road, scope, price, game.elapsed);
}
export fn revise(id: u32, price: f64) u32 {
    return contracts.revise(id, price);
}
export fn cancel_order(id: u32) bool {
    return contracts.cancel(id, game.elapsed);
}
export fn quote(company: u32, road: u32, scope: f32, price: f64, field: u32) f64 {
    if (company >= residents.company_count or road >= city.roads.len or !std.math.isFinite(scope)) return -1;
    return if (field == 0) contracts.estimate(company, road, scope) else @floatFromInt(contracts.reason(company, road, scope, price));
}
export fn focus(kind: u32, id: u32) void {
    if (kind == 1 and id < city.buildings.len) {
        const b = &city.buildings[id];
        scene.focus(b.x, b.z);
        scene.selected = @intCast(id);
    }
    if (kind == 3 and id < residents.people.len) {
        const p = &residents.people[id];
        scene.focus(p.x, p.z);
    }
    if (kind == 12 and id < transport.vehicles.len) {
        const v = &transport.vehicles[id];
        scene.focus(v.x, v.z);
    }
    if (kind == 5 and id < city.roads.len) {
        const n = city.nodes[city.roads[id].a];
        scene.focus(n.x, n.z);
    }
}
export fn name_pointer(id: u32) [*]const u8 {
    return city.district_names[@min(id, city.district_count - 1)].ptr;
}
export fn name_length(id: u32) usize {
    return city.district_names[@min(id, city.district_count - 1)].len;
}
// Read-only scalar ABI: groups and fields are described in docs/abi.md and web/data.js.
export fn read(group: u32, id: u32, field: u32) f64 {
    switch (group) {
        0 => return switch (field) {
            0 => game.elapsed,
            1 => finance.cash,
            2 => finance.reserved,
            3 => finance.available(),
            4 => finance.projection(),
            5 => finance.maintenance[finance.funding] + finance.services,
            6 => @floatFromInt(residents.walking),
            7 => city.population,
            8 => @floatFromInt(residents.employed),
            9 => @floatFromInt(residents.company_count),
            10 => @floatFromInt(scene.selected),
            11 => @floatFromInt(finance.funding),
            12 => finance.maintenance_paid,
            13 => speed,
            14 => city.buildings.len,
            15 => city.roads.len,
            16 => city.district_count,
            17 => @floatFromInt(contracts.count),
            18 => @floatFromInt(finance.entry_count),
            19 => @floatFromInt(game.history_count),
            20 => finance.residential_rate,
            21 => finance.commercial_rate,
            22 => finance.base(true),
            23 => finance.base(false),
            24 => finance.collected,
            25 => finance.spent,
            else => -1,
        },
        1 => {
            if (id >= city.buildings.len) return -1;
            const b = &city.buildings[id];
            return switch (field) {
                0 => @floatFromInt(@intFromEnum(b.kind)),
                1 => @floatFromInt(b.district),
                2 => b.height,
                3 => b.ground,
                4 => b.value,
                5 => @floatFromInt(b.occupants),
                6 => @floatFromInt(b.employer),
                7 => finance.bill(id),
                8 => finance.arrears[id],
                9 => b.x,
                10 => b.z,
                11 => @floatFromInt(b.node),
                else => -1,
            };
        },
        2 => {
            if (id >= city.district_count) return -1;
            var population: usize = 0;
            var employed: usize = 0;
            for (&residents.people) |p| if (city.buildings[p.home].district == id) {
                population += 1;
                if (p.employer >= 0) employed += 1;
            };
            return switch (field) {
                0 => city.condition(id),
                1 => game.trust[id],
                2 => @floatFromInt(population),
                3 => @floatFromInt(employed),
                else => -1,
            };
        },
        3 => {
            if (id >= residents.people.len) return -1;
            const p = &residents.people[id];
            return switch (field) {
                0 => @floatFromInt(p.home),
                1 => @floatFromInt(p.employer),
                2 => @floatFromInt(p.destination),
                3 => @floatFromInt(p.node),
                4 => @floatFromInt(p.next),
                5 => p.x,
                6 => p.z,
                7 => @floatFromInt(p.order),
                8 => if (p.arrived and p.order >= 0) 2 else if (p.wait > 0 or p.phase == 3) 0 else 1,
                9 => @floatFromInt(p.trips),
                10 => p.travel,
                11 => p.last_trip,
                12 => residents.remaining(id),
                13 => @floatFromInt(p.mode),
                14 => p.wallet,
                15 => p.income,
                16 => if (p.owns_car) 1 else 0,
                17 => if (p.owns_bike) 1 else 0,
                18 => p.bus_wait,
                19 => @floatFromInt(p.bus),
                20 => @floatFromInt(p.car_node),
                21...24 => p.scores[field - 21],
                25 => @floatFromInt(p.bus_line),
                26 => @floatFromInt(p.bike_node),
                else => -1,
            };
        },
        4 => {
            if (id >= residents.company_count) return -1;
            const c = &residents.companies[id];
            return switch (field) {
                0 => @floatFromInt(c.building),
                1 => @floatFromInt(c.employees),
                2 => @floatFromInt(c.capacity),
                3 => c.cash,
                4 => if (c.contractor) 1 else 0,
                5 => @floatFromInt(c.order),
                6 => @floatFromInt(c.crew_count),
                7 => c.costs,
                8...11 => @floatFromInt(c.crew[field - 8]),
                else => -1,
            };
        },
        5 => {
            if (id >= city.roads.len) return -1;
            const r = &city.roads[id];
            return switch (field) {
                0 => @floatFromInt(r.a),
                1 => @floatFromInt(r.b),
                2 => r.length,
                3 => r.slope,
                4 => @floatFromInt(r.district),
                5 => r.condition,
                6 => if (r.works) 1 else 0,
                7 => city.nodes[r.a].y,
                8 => city.nodes[r.b].y,
                9 => if (contracts.siteBusy(id)) 1 else 0,
                10 => @floatFromInt(transport.occupancy[id]),
                11 => @floatFromInt(transport.queues[id]),
                12 => transport.congestion[id],
                13 => @floatFromInt(transport.lanes[id]),
                else => -1,
            };
        },
        6 => {
            if (id >= contracts.count) return -1;
            const o = &contracts.orders[id];
            return switch (field) {
                0 => @floatFromInt(o.road),
                1 => o.scope,
                2 => o.price,
                3 => @floatFromInt(@intFromEnum(o.status)),
                4 => @floatFromInt(o.company),
                5 => o.progress,
                6 => o.created,
                7 => o.accepted,
                8 => o.finished,
                9 => @floatFromInt(o.reason),
                10 => o.costs,
                11 => o.paid,
                else => -1,
            };
        },
        7 => {
            const count = @min(finance.entry_count, finance.entries.len);
            if (id >= count) return -1;
            const e = finance.entries[(finance.entry_count - 1 - id) % finance.entries.len];
            return switch (field) {
                0 => e.time,
                1 => e.amount,
                2 => e.balance,
                3 => @floatFromInt(e.kind),
                4 => @floatFromInt(e.party),
                5 => @floatFromInt(e.order),
                else => -1,
            };
        },
        8 => {
            const count = @min(game.history_count, game.history.len);
            if (id >= count) return -1;
            const e = game.history[(game.history_count - count + id) % game.history.len];
            return switch (field) {
                0 => e.time,
                1 => e.cash,
                2 => e.reserved,
                3 => @floatFromInt(e.walking),
                4 => e.condition,
                else => -1,
            };
        },
        9 => {
            return switch (field) {
                0 => transport.fare_cap,
                1 => transport.subsidy,
                2 => transport.subsidy_total,
                3 => transport.fare(),
                4 => city.node_count,
                5...8 => blk: {
                    var total: usize = 0;
                    for (&residents.people) |p| {
                        if (p.phase != 3 and p.wait <= 0 and p.chosen and !p.arrived and p.mode == field - 5) total += 1;
                    }
                    break :blk @floatFromInt(total);
                },
                9 => blk: {
                    var total: usize = 0;
                    for (&residents.people) |p| {
                        if (p.mode == 3 and p.phase == 1 and p.bus < 0 and p.bus_stage == 0 and p.node == p.next and p.node == p.boarding) total += 1;
                    }
                    break :blk @floatFromInt(total);
                },
                else => -1,
            };
        },
        10 => {
            if (id >= transport.max_lines) return -1;
            const l = &transport.lines[id];
            return switch (field) {
                0 => if (l.active) 1 else 0,
                1 => @floatFromInt(l.count),
                2 => @floatFromInt(l.boardings),
                3 => l.revenue,
                4 => l.costs,
                5 => l.cash,
                6 => @floatFromInt(l.fleet),
                7 => blk: {
                    var total: usize = 0;
                    for (transport.vehicles[transport.car_count + id * transport.buses_per_line ..][0..transport.buses_per_line]) |v| total += v.passengers;
                    break :blk @floatFromInt(total);
                },
                8 => @floatFromInt(l.version),
                16...31 => if (field - 16 < l.count) @floatFromInt(l.stops[field - 16]) else -1,
                else => -1,
            };
        },
        11 => {
            if (id >= city.node_count) return -1;
            return switch (field) {
                0 => city.nodes[id].x,
                1 => city.nodes[id].z,
                2 => city.nodes[id].y,
                3 => scene.project(id, 0),
                4 => scene.project(id, 1),
                else => -1,
            };
        },
        12 => {
            if (id >= transport.vehicles.len) return -1;
            const v = &transport.vehicles[id];
            return switch (field) {
                0 => if (v.active) 1 else 0,
                1 => v.x,
                2 => v.z,
                3 => v.speed,
                4 => @floatFromInt(v.passengers),
                5 => @floatFromInt(v.node),
                6 => @floatFromInt(v.next),
                7 => v.progress,
                8 => @floatFromInt(v.line),
                9 => v.dwell,
                10 => @floatFromInt(v.lane),
                else => -1,
            };
        },
        else => return -1,
    }
}

export fn select_resident(id: u32) void {
    scene.selected_person = if (id < city.population) @intCast(id) else -1;
}

export fn transport_policy(cap: f64, subsidy: f64) bool {
    if (!std.math.isFinite(cap) or !std.math.isFinite(subsidy) or cap < 0 or cap > 10 or subsidy < 0 or subsidy > 10) return false;
    transport.fare_cap = cap;
    transport.subsidy = subsidy;
    return true;
}
export fn transport_select(id: i32) void {
    transport.selected = if (id >= 0 and id < transport.max_lines) id else -1;
}
export fn transport_draft(count: u32) void {
    transport.draft_count = @min(count, transport.max_stops);
    transport.editing = true;
}
export fn transport_stop(index: u32, node: u32) void {
    if (index < transport.max_stops and node < city.node_count) transport.draft[index] = node;
}
export fn transport_edit_end() void {
    transport.editing = false;
}
export fn transport_apply(id: u32) bool {
    return transport.apply(id);
}
export fn transport_remove(id: u32) void {
    transport.remove(id);
}
export fn transport_lane(road: u32, lane: u32) void {
    if (road < city.road_count and lane <= 2) transport.lanes[road] = @intCast(lane);
}
export fn route_next(from: u32, to: u32) u32 {
    return if (from < city.node_count and to < city.node_count) city.next_node[from][to] else 0;
}
