const std = @import("std");
const city = @import("scene/city.zig");
const game = @import("simulation/game.zig");
const scene = @import("render/scene.zig");
const persistence = @import("simulation/persistence.zig");
const residents = game.residents;
const finance = game.finance;
const contracts = game.contracts;
const transport = game.transport;
const signals = transport.signals;
const parking = game.parking;
const travel = game.travel;
var speed: f32 = 1;
var resume_speed: f32 = 1;
var accumulator: f32 = 0;
export fn init() void {
    city.init();
    game.init();
    scene.reset();
    scene.selected = -1;
    scene.selected_person = -1;
    scene.selected_signal = -1;
    speed = 1;
    resume_speed = 1;
    accumulator = 0;
}
export fn update(seconds: f32) void {
    accumulator += std.math.clamp(seconds, 0, 0.1) * speed;
    while (accumulator >= 1.0 / 30.0) {
        game.update(1.0 / 30.0);
        accumulator -= 1.0 / 30.0;
    }
}
export fn save_capacity() usize {
    return persistence.capacity;
}
export fn save_pointer() [*]u8 {
    return &persistence.buffer;
}
export fn save_write() usize {
    return persistence.write(speed, resume_speed, accumulator);
}
export fn save_load(length: u32) u32 {
    const result = persistence.load(length);
    if (result == 0) {
        speed = persistence.restored_speed;
        resume_speed = persistence.restored_resume;
        accumulator = persistence.restored_accumulator;
    }
    return result;
}
export fn saved_resume_speed() f32 {
    return resume_speed;
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
    if (speed > 0) resume_speed = speed;
}
export fn set_funding(value: u32) void {
    finance.funding = @min(value, 2);
}
export fn set_overlay(value: u32) void {
    scene.overlay = @min(value, 3);
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
    if (kind == 11 and id < city.node_count) {
        scene.focus(city.nodes[id].x, city.nodes[id].z);
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
            15 => @floatFromInt(city.roads.len),
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
            26 => @floatFromInt(scene.selected_person),
            27 => scene.zoom,
            28 => @floatFromInt(city.revision),
            // Slice 6 civic calendar.
            29 => @floatFromInt(@intFromEnum(game.calendar.weekday(game.elapsed))),
            30 => if (game.calendar.isWeekend(game.elapsed)) 1 else 0,
            31 => @floatFromInt(@intFromEnum(game.calendar.phase(game.elapsed))),
            32 => @floatFromInt(game.calendar.weekIndex(game.elapsed)),
            33 => game.next_week,
            34 => @floatFromInt(@min(finance.period_count, finance.periods.len)),
            // Slice 7 household budgets.
            35 => @floatFromInt(game.households.inArrears()),
            36 => game.households.totalArrears(),
            37 => @floatFromInt(@as(u32, @intFromFloat(@min(@as(f64, @floatFromInt(city.buildings.len)), @as(f64, 1e9))))),
            // Slice 8 employment: jobseekers, open posts, last-day hiring and pay.
            38 => @floatFromInt(game.employment.unemployedCount()),
            39 => @floatFromInt(game.employment.totalVacancies()),
            40 => @floatFromInt(game.employment.hires),
            41 => @floatFromInt(game.employment.dismissals),
            42 => game.employment.wages_paid,
            43 => game.employment.wages_arrears,
            // Slice 9 housing and occupancy.
            44 => blk: {
                var total: usize = 0;
                for (&game.housing.units) |*unit| {
                    if (unit.present) total += 1;
                }
                break :blk @floatFromInt(total);
            },
            45 => blk: {
                var total: usize = 0;
                for (&game.housing.units) |*unit| {
                    if (unit.present and unit.occupants > 0) total += 1;
                }
                break :blk @floatFromInt(total);
            },
            46 => blk: {
                var total: usize = 0;
                for (&game.housing.units) |*unit| {
                    if (unit.present and unit.occupants == 0) total += 1;
                }
                break :blk @floatFromInt(total);
            },
            47 => blk: {
                var total: usize = 0;
                for (&game.housing.units) |*unit| {
                    if (unit.present and unit.tenure == .rented) total += 1;
                }
                break :blk @floatFromInt(total);
            },
            48 => blk: {
                var total: usize = 0;
                for (&game.housing.units) |*unit| {
                    if (unit.present and unit.tenure == .owned) total += 1;
                }
                break :blk @floatFromInt(total);
            },
            49 => @floatFromInt(game.housing.moves_today),
            50 => @floatFromInt(game.housing.displacements_today),
            51 => @floatFromInt(game.housing.applications_today),
            52 => game.housing.arrearsTotal(),
            53 => game.housing.rent_collected_today,
            54 => game.housing.ownership_collected_today,
            // Slice 10 street types, parking and learned travel.
            55 => @floatFromInt(game.parking.count),
            56 => @floatFromInt(game.parking.slotsTotal()),
            57 => @floatFromInt(game.parking.occupiedTotal()),
            58 => @floatFromInt(game.parking.attempts),
            59 => @floatFromInt(game.parking.successes),
            60 => @floatFromInt(game.parking.fallbacks),
            61 => @floatFromInt(game.parking.refusals),
            62 => game.parking.revenue_total,
            63 => @floatFromInt(game.parking.kindSlots(.bike)),
            64 => @floatFromInt(game.parking.kindUsed(.bike)),
            65 => @floatFromInt(game.parking.kindSlots(.car)),
            66 => @floatFromInt(game.parking.kindUsed(.car)),
            67 => @floatFromInt(game.parking.kerbside_used),
            68 => @floatFromInt(game.residents.batches_applied),
            69 => @floatFromInt(game.residents.batches_dropped),
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
                12 => b.sun,
                13 => @floatFromInt(b.street),
                14 => @floatFromInt(b.number),
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
                27 => @floatFromInt(p.origin),
                28 => @floatFromInt(p.destination_building),
                29 => @floatFromInt(p.origin_building),
                30 => p.bus_wait_start,
                31 => @floatFromInt(p.bus_full_mask),
                // Slice 6: shift and routine phase.
                32 => @floatFromInt(p.shift),
                33 => @floatFromInt(p.routine),
                34 => @floatFromInt(p.home),
                // Slice 8: deterministic skill 0 general, 1 clerical, 2 professional.
                35 => @floatFromInt(p.skill),
                // Slice 10 ownership, parking and the learned model.
                36 => if (p.prefers_car) 1 else 0,
                37 => @floatFromInt(p.park_facility),
                38 => @floatFromInt(p.parked_vehicle),
                39 => @floatFromInt(p.plan_mode),
                40 => if (p.access) 1 else 0,
                41 => @floatFromInt(p.cross_waits),
                42 => @floatFromInt(p.crossings),
                43 => p.cross_wait,
                44 => @floatFromInt(p.park_tries),
                45 => @floatFromInt(p.park_taken),
                46 => @floatFromInt(p.park_searched),
                47 => @floatFromInt(p.park_refused),
                48 => @floatFromInt(p.depart_bucket),
                49 => blk: {
                    if (travel.observed(&p.model, p.mode, p.depart_bucket)) |known| break :blk known;
                    break :blk -1;
                },
                50 => blk: {
                    for (0..travel.memory_count) |slot| {
                        if (p.model.facility[slot] != travel.no_facility) break :blk @floatFromInt(p.model.facility[slot]);
                    }
                    break :blk -1;
                },
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
                14 => if (r.crosswalk) 1 else 0,
                15 => @floatFromInt(r.street),
                16 => @floatFromInt(residents.pedestrians[id]),
                // Slice 10: street class, measured movement and banded price.
                17 => @floatFromInt(r.class),
                18 => transport.movement[id],
                19 => @floatFromInt(parking.band(transport.movement[id])),
                20 => parking.bandPrice(transport.movement[id]),
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
                4 => @floatFromInt(city.node_count),
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
                5 => transport.operators.accounts[l.company].cash,
                6 => @floatFromInt(l.fleet),
                7 => blk: {
                    var total: usize = 0;
                    for (transport.vehicles[transport.car_count + id * transport.buses_per_line ..][0..transport.buses_per_line]) |v| total += v.passengers;
                    break :blk @floatFromInt(total);
                },
                8 => @floatFromInt(l.version),
                9 => blk: {
                    var total: usize = 0;
                    for (&residents.people) |p| {
                        if (p.bus_line == @as(i32, @intCast(id)) and p.mode == 3 and p.phase == 1 and p.bus < 0 and p.bus_stage == 0 and p.node == p.next and p.node == p.boarding) total += 1;
                    }
                    break :blk @floatFromInt(total);
                },
                10...14 => @floatFromInt(transport.serviceCount(id, field - 10)),
                35...40 => linePassengerTotal(id, field),

                32 => @floatFromInt(l.company),
                33 => @floatFromInt(l.window),
                34 => @floatFromInt(transport.blocker(id)),
                16...31 => if (field - 16 < l.count) @floatFromInt(l.stops[field - 16]) else -1,
                else => -1,
            };
        },
        11 => {
            if (id >= city.node_count) return -1;
            const stop = city.stopPoint(id);
            return switch (field) {
                0 => city.nodes[id].x,
                1 => city.nodes[id].z,
                2 => city.nodes[id].y,
                3 => scene.project(id, 0),
                4 => scene.project(id, 1),
                5 => @floatFromInt(city.nodes[id].street),
                6 => @floatFromInt(city.nodes[id].number),
                7 => stop.x,
                8 => stop.z,
                9 => if (city.validStop(id)) 1 else 0,
                10 => scene.projectWorld(stop.x, city.nodes[id].y, stop.z, 0),
                11 => scene.projectWorld(stop.x, city.nodes[id].y, stop.z, 1),
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
                11 => @floatFromInt(v.company),
                12 => if (v.retiring) 1 else 0,
                13 => if (v.shift_day) 1 else 0,
                14 => @floatFromInt(v.unit),
                else => -1,
            };
        },
        13 => {
            if (id >= transport.max_lines) return -1;
            return game.agreements.read(&game.agreements.agreements[id], field);
        },
        14 => {
            if (id >= 3) return -1;
            const c = transport.operators.accounts[id];
            return switch (field) {
                0 => @floatFromInt(transport.operators.owned(id)),
                1 => @floatFromInt(transport.committed(id, false, transport.max_lines)),
                2 => c.receipts,
                3 => c.opening,
                4 => c.cash,
                5 => c.fares,
                6 => c.subsidies,
                7 => c.vehicle,
                8 => c.labour,
                9 => @floatFromInt(transport.operators.drivers(id, game.elapsed)),
                10 => @floatFromInt(c.day),
                11 => @floatFromInt(c.night),
                12 => @floatFromInt(transport.committed(id, true, transport.max_lines)),
                13 => @floatFromInt(transport.occupied(id)),
                14 => @floatFromInt(transport.operators.drivers(id, game.elapsed) -| transport.occupied(id)),
                // Slice 4 fleet and roster detail.
                15 => @floatFromInt(c.depot),
                16 => @floatFromInt(transport.operators.underMaintenance(id)),
                17 => @floatFromInt(transport.operators.available(id)),
                18 => @floatFromInt(transport.operators.freeUnits(id)),
                19 => @floatFromInt(transport.operators.attached(id)),
                20 => transport.operators.condition(id),
                21 => c.purchases,
                22 => c.sales,
                23 => c.recruitment,
                24 => c.severance,
                25 => c.maintenance,
                26 => @floatFromInt(@as(u32, @intFromEnum(transport.operators.buyReason(id)))),
                27 => @floatFromInt(@as(u32, @intFromEnum(transport.operators.recruitReason(id, false)))),
                28 => @floatFromInt(@as(u32, @intFromEnum(transport.operators.recruitReason(id, true)))),
                29 => @floatFromInt(@as(u32, @intFromEnum(transport.operators.dismissReason(id, false)))),
                30 => @floatFromInt(@as(u32, @intFromEnum(transport.operators.dismissReason(id, true)))),
                31 => transport.operators.quote(id, 0),
                32 => transport.operators.quote(id, 2),
                33 => transport.operators.quote(id, 3),
                34 => transport.operators.quote(id, 4),
                35 => transport.operators.quote(id, 5),
                36 => @floatFromInt(c.depot -| transport.operators.owned(id)),
                37 => @floatFromInt(transport.operators.covered(id, false)),
                38 => @floatFromInt(transport.operators.covered(id, true)),
                39 => c.credits,
                else => -1,
            };
        },
        23 => {
            const company = id / transport.operators.max_units;
            const unit = id % transport.operators.max_units;
            if (company >= 3) return -1;
            return transport.operators.unitQuote(company, unit, field);
        },
        20, 21 => {
            const record = id / transport.max_stops;
            const stop = id % transport.max_stops;
            if (group == 20) {
                if (record >= transport.max_lines) return -1;
                return game.agreements.readStop(&game.agreements.agreements[record], stop, field);
            }
            const count = game.agreements.history_count;
            if (record >= @min(count, game.agreements.history.len)) return -1;
            return game.agreements.readStop(&game.agreements.history[(count - 1 - record) % game.agreements.history.len], stop, field);
        },
        18, 19 => {
            const line = id / transport.max_stops;
            const stop = id % transport.max_stops;
            if (line >= transport.max_lines) return -1;
            const o = if (group == 18) &transport.observations[line] else &transport.previous_observations[line];
            if (stop >= o.count) return -1;
            const s = &o.stops[stop];
            return switch (field) {
                0 => @floatFromInt(o.version),
                1 => @floatFromInt(o.window),
                2 => @floatFromInt(o.nodes[stop]),
                3 => @floatFromInt(s.visits),
                4 => s.latest,
                5 => @floatFromInt(s.intervals),
                6 => s.last_interval,
                7 => if (s.intervals > 0) s.total / @as(f64, @floatFromInt(s.intervals)) else -1,
                8 => s.minimum,
                9 => s.maximum,
                10 => blk: {
                    if (group == 19) break :blk -1;
                    var total: usize = 0;
                    for (&residents.people) |p| {
                        if (p.bus_line == @as(i32, @intCast(line)) and p.bus_version == o.version and p.mode == 3 and p.phase == 1 and p.bus < 0 and p.bus_stage == 0 and p.node == p.next and p.node == p.boarding and p.boarding == o.nodes[stop]) total += 1;
                    }
                    break :blk @floatFromInt(total);
                },
                11 => @floatFromInt(s.wait_starts),
                12 => @floatFromInt(s.completed),
                13 => if (s.completed > 0) s.wait_total / @as(f64, @floatFromInt(s.completed)) else -1,
                14 => s.wait_min,
                15 => s.wait_max,
                16 => @floatFromInt(s.capacity_denials),
                17 => @floatFromInt(s.abandoned_timeout),
                18 => @floatFromInt(s.abandoned_offhours),
                19 => @floatFromInt(s.abandoned_fare),
                20 => @floatFromInt(s.abandoned_service),
                21 => @floatFromInt(s.abandoned_after_capacity),
                22 => s.wait_total,
                else => -1,
            };
        },
        25 => {
            if (id >= city.buildings.len) return -1;
            return game.households.read(id, field);
        },
        27 => return game.employment.read(id, field),
        28 => {
            if (id >= parking.count) return -1;
            const f = &parking.facilities[id];
            return switch (field) {
                0 => @floatFromInt(@intFromEnum(f.kind)),
                1 => @floatFromInt(f.building),
                2 => @floatFromInt(f.road),
                3 => @floatFromInt(f.node),
                4 => @floatFromInt(f.slots),
                5 => @floatFromInt(f.occupied),
                6 => @floatFromInt(f.slots -| f.occupied),
                7 => f.price,
                8 => @floatFromInt(f.observed[0]),
                9 => @floatFromInt(f.observed[1]),
                10 => @floatFromInt(f.observed[2]),
                11 => @floatFromInt(f.observed[3]),
                else => -1,
            };
        },
        26 => return game.housing.read(id, field),

        22 => {
            if (id >= city.district_count) return -1;
            const d = &residents.district_outcomes[id];
            return switch (field) {
                0 => @floatFromInt(d.wait_starts),
                1 => @floatFromInt(d.completed),
                2 => if (d.completed > 0) d.wait_total / @as(f64, @floatFromInt(d.completed)) else -1,
                3 => @floatFromInt(d.capacity_denials),
                4 => @floatFromInt(d.abandoned),
                5 => @floatFromInt(d.abandoned_after_capacity),
                6 => blk: {
                    var total: usize = 0;
                    for (&residents.people) |p| {
                        if (city.buildings[p.home].district == id and p.mode == 3 and p.phase == 1 and p.bus < 0 and p.bus_stage == 0 and p.node == p.next and p.node == p.boarding) total += 1;
                    }
                    break :blk @floatFromInt(total);
                },
                7 => if (d.completed + d.abandoned > 0) @as(f64, @floatFromInt(d.completed)) / @as(f64, @floatFromInt(d.completed + d.abandoned)) else -1,
                else => -1,
            };
        },
        17 => {
            const count = game.agreements.history_count;
            if (id >= @min(count, game.agreements.history.len)) return -1;
            return game.agreements.read(&game.agreements.history[(count - 1 - id) % game.agreements.history.len], field);
        },
        15 => return switch (field) {
            0 => @floatFromInt(game.roadworks.error_code),
            1 => game.roadworks.cost,
            2 => game.roadworks.length,
            3 => @floatFromInt(game.parcels.count),
            4 => @floatFromInt(game.parcels.selected),
            5 => @floatFromInt(game.parcels.block_count),
            6 => @floatFromInt(game.roadworks.class),
            else => -1,
        },
        16 => {
            if (id >= game.parcels.count) return -1;
            const p = game.parcels.storage[id];
            return switch (field) {
                0 => p.x,
                1 => p.z,
                2 => @floatFromInt(p.zone),
                3 => @floatFromInt(p.building),
                4 => @floatFromInt(p.block),
                5 => @floatFromInt(p.street),
                6 => @floatFromInt(p.number),
                else => -1,
            };
        },
        29 => {
            // Slice 11 signal heads, addressed by a flat index over junctions
            // and their arms. Green and yellow are simulation seconds.
            const head = signalHead(id);
            if (head < 0) return -1;
            const junction = &signals.junctions[headJunction(@intCast(head))];
            const arm = headArm(@intCast(head));
            const road_id: usize = @intCast(junction.arms[arm]);
            const state = signals.armState(junction, arm, game.elapsed);
            return switch (field) {
                0 => @floatFromInt(headJunction(@intCast(head))),
                1 => @floatFromInt(junction.node),
                2 => @floatFromInt(road_id),
                3 => @floatFromInt(arm),
                4 => @floatFromInt(junction.arm_count),
                5 => @floatFromInt(@intFromEnum(state)),
                6 => junction.green,
                7 => junction.yellow,
                8 => signals.cycleSeconds(junction),
                9 => signals.secondsLeft(junction, arm, game.elapsed),
                10 => blk: {
                    const p2 = signals.headPosition(junction.node, road_id) orelse break :blk -1;
                    break :blk p2.x;
                },
                11 => blk: {
                    const p2 = signals.headPosition(junction.node, road_id) orelse break :blk -1;
                    break :blk p2.z;
                },
                12 => @floatFromInt(signals.count),
                13 => signals.min_green,
                14 => signals.max_green,
                // Slice 12: the granular properties the player can set on this
                // individual light, and where it sits in a coordination group.
                15 => junction.red,
                16 => @floatFromInt(@intFromEnum(junction.flash)),
                17 => if (signals.flashing(junction, game.elapsed)) 1 else 0,
                18 => if (junction.flash_enabled) 1 else 0,
                19 => junction.flash_start,
                20 => junction.flash_end,
                21 => @floatFromInt(junction.group),
                22 => junction.delay,
                23 => @floatFromInt(@intFromEnum(junction.preempt)),
                24 => signals.min_red,
                25 => signals.max_red,
                26 => signals.min_yellow,
                27 => signals.max_yellow,
                28 => signals.min_delay,
                29 => signals.max_delay,
                30 => if (signals.flashLit(junction, game.elapsed)) 1 else 0,
                31 => @floatFromInt(@intFromEnum(signals.slotState(headJunction(@intCast(head)), 0, game.elapsed))),
                32 => @floatFromInt(@intFromEnum(signals.slotState(headJunction(@intCast(head)), 1, game.elapsed))),
                33 => @floatFromInt(@intFromEnum(signals.slotState(headJunction(@intCast(head)), 2, game.elapsed))),
                34 => @floatFromInt(@intFromEnum(signals.slotState(headJunction(@intCast(head)), 3, game.elapsed))),
                35 => @floatFromInt(signals.junctionRoad(headJunction(@intCast(head)), 0)),
                36 => @floatFromInt(signals.junctionRoad(headJunction(@intCast(head)), 1)),
                37 => @floatFromInt(signals.junctionRoad(headJunction(@intCast(head)), 2)),
                38 => @floatFromInt(signals.junctionRoad(headJunction(@intCast(head)), 3)),
                else => -1,
            };
        },
        30 => {
            // Slice 12 coordination map: a link names the light that leads, the
            // light that follows, and the delay in simulation seconds between
            // their actions.
            if (id >= signals.link_count) return -1;
            const l = signals.links[id];
            const from = signals.junctions[l.from];
            const to = signals.junctions[l.to];
            return switch (field) {
                0 => @floatFromInt(l.from),
                1 => @floatFromInt(l.to),
                2 => @floatFromInt(from.node),
                3 => @floatFromInt(to.node),
                4 => l.delay,
                5 => if (l.active) 1 else 0,
                6 => @floatFromInt(from.group),
                7 => @floatFromInt(to.group),
                8 => if (signals.flashing(&to, game.elapsed)) 1 else 0,
                else => -1,
            };
        },
        else => return -1,
    }
}

// Signal heads are numbered junction by junction, then arm by arm, matching
// the renderer's own flat numbering.
fn headJunction(head: usize) usize {
    var index: usize = 0;
    var j: usize = 0;
    while (j < signals.count) : (j += 1) {
        const next = index + signals.junctions[j].arm_count;
        if (head < next) return j;
        index = next;
    }
    return if (signals.count > 0) signals.count - 1 else 0;
}

fn headArm(head: usize) usize {
    var index: usize = 0;
    var j: usize = 0;
    while (j < signals.count) : (j += 1) {
        const next = index + signals.junctions[j].arm_count;
        if (head < next) return head - index;
        index = next;
    }
    return 0;
}

fn headCount() usize {
    var total: usize = 0;
    for (signals.junctions[0..signals.count]) |j| total += j.arm_count;
    return total;
}

// The ABI passes an unsigned id; any id beyond the head count is "no head".
fn signalHead(index: u32) i64 {
    const head: usize = index;
    return if (head < headCount()) @intCast(head) else -1;
}

// Slice 11: flat index of one signal head inside a junction's own arm list.
fn signalFlat(junction_index: usize, arm: usize) i32 {
    if (junction_index >= signals.count) return -1;
    var index: usize = 0;
    var j: usize = 0;
    while (j < junction_index) : (j += 1) index += signals.junctions[j].arm_count;
    if (arm >= signals.junctions[junction_index].arm_count) return -1;
    return @intCast(index + arm);
}

// Snapping for the placement tools: the nearest junction node to a ground
// point, preferring whichever end of the nearest segment is a real junction.
fn nearJunctionNode(p: city.Vec) ?usize {
    var best: f32 = 9;
    var result: ?usize = null;
    for (city.roads) |r| {
        const a = city.nodes[r.a];
        const b = city.nodes[r.b];
        const length_sq = @max(0.0001, (b.x - a.x) * (b.x - a.x) + (b.z - a.z) * (b.z - a.z));
        const t = std.math.clamp(((p.x - a.x) * (b.x - a.x) + (p.z - a.z) * (b.z - a.z)) / length_sq, 0, 1);
        const qx = a.x + (b.x - a.x) * t;
        const qz = a.z + (b.z - a.z) * t;
        const d = city.hypot(p.x - qx, p.z - qz);
        if (d >= best) continue;
        const da = city.hypot(p.x - a.x, p.z - a.z);
        const db = city.hypot(p.x - b.x, p.z - b.z);
        const first = if (da <= db) r.a else r.b;
        const second = if (da <= db) r.b else r.a;
        const node = if (city.degree(first) >= 3) first else second;
        if (city.degree(node) < 3) continue;
        best = d;
        result = node;
    }
    return result;
}

fn linePassengerTotal(line: usize, field: u32) f64 {
    if (line >= transport.max_lines) return -1;
    const o = &transport.observations[line];
    var starts: u64 = 0;
    var completed: u64 = 0;
    var wait_total: f64 = 0;
    var capacity: u64 = 0;
    var abandoned: u64 = 0;
    var after: u64 = 0;
    for (o.stops[0..o.count]) |stop| {
        starts += stop.wait_starts;
        completed += stop.completed;
        wait_total += stop.wait_total;
        capacity += stop.capacity_denials;
        abandoned += @as(u64, stop.abandoned_timeout) + stop.abandoned_offhours + stop.abandoned_fare + stop.abandoned_service;
        after += stop.abandoned_after_capacity;
    }
    return switch (field) {
        35 => @floatFromInt(starts),
        36 => @floatFromInt(completed),
        37 => @floatFromInt(capacity),
        38 => @floatFromInt(abandoned),
        39 => if (completed > 0) wait_total / @as(f64, @floatFromInt(completed)) else -1,
        40 => @floatFromInt(after),
        else => -1,
    };
}

export fn select_resident(id: u32) void {
    scene.selected_person = if (id < city.population) @intCast(id) else -1;
}

export fn transport_policy(cap: f64, subsidy: f64) bool {
    if (!std.math.isFinite(cap) or !std.math.isFinite(subsidy) or cap < 0 or cap > 10 or subsidy < 0 or subsidy > 10) return false;
    transport.fare_cap = finance.cents(cap);
    transport.subsidy = finance.cents(subsidy);
    return true;
}
export fn fleet_buy(company: u32) bool {
    return company < 3 and transport.operators.buy(company);
}
export fn fleet_sell(company: u32, unit: u32) bool {
    return company < 3 and transport.operators.sell(company, unit);
}
export fn fleet_maintain(company: u32, unit: u32) bool {
    if (company >= 3 or unit >= transport.operators.max_units) return false;
    // Mark the occupying bus for safe retirement before the unit leaves service.
    const bus = transport.operators.accounts[company].units[unit].bus;
    if (bus >= 0) transport.retire(bus);
    return transport.operators.maintain(company, unit);
}
export fn staff_recruit(company: u32, night: u32) bool {
    return company < 3 and night <= 1 and transport.operators.recruit(company, night == 1);
}
export fn staff_dismiss(company: u32, night: u32) bool {
    return company < 3 and night <= 1 and transport.operators.dismiss(company, night == 1);
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
    const applied = transport.apply(id);
    if (applied) {
        residents.closeLineWaits(id, game.elapsed);
        game.agreements.checkRoute(id, game.elapsed);
    }
    return applied;
}
export fn transport_remove(id: u32) void {
    if (id < transport.max_lines) residents.closeLineWaits(id, game.elapsed);
    game.agreements.cancel(id, game.elapsed, true);
    transport.remove(id);
}
export fn transport_lane(road: u32, lane: u32) void {
    if (road < city.road_count and lane <= 2) transport.lanes[road] = @intCast(lane);
}
export fn route_next(from: u32, to: u32) u32 {
    return if (from < city.node_count and to < city.node_count) city.next_node[from][to] else 0;
}

export fn set_crosswalk(road: u32, enabled: u32) bool {
    if (road >= city.road_count or enabled > 1) return false;
    city.roads[road].crosswalk = enabled == 1;
    city.rebuildRoutes();
    return true;
}

export fn service_quote(company: u32, fleet: u32, days: f64, price: f64, field: u32) f64 {
    return game.agreements.quote(transport.max_lines, company, fleet, days, price, 0, field);
}
export fn service_offer(line: u32, company: u32, fleet: u32, days: f64, price: f64) bool {
    return game.agreements.offer(line, company, fleet, days, price, 0, game.elapsed);
}
export fn service_window_quote(line: u32, company: u32, fleet: u32, days: f64, price: f64, window: u32, field: u32) f64 {
    return game.agreements.quote(line, company, fleet, days, price, window, field);
}
export fn service_window_offer(line: u32, company: u32, fleet: u32, days: f64, price: f64, window: u32) bool {
    return game.agreements.offer(line, company, fleet, days, price, window, game.elapsed);
}
export fn service_target_offer(line: u32, company: u32, fleet: u32, days: f64, price: f64, window: u32, max_interval: f64) bool {
    return game.agreements.offerTarget(line, company, fleet, days, price, window, max_interval, game.elapsed);
}
export fn service_target_valid(max_interval: f64) bool {
    return game.agreements.validInterval(max_interval);
}
export fn service_cancel(line: u32) void {
    game.agreements.cancel(line, game.elapsed, false);
}

export fn road_begin(curved: u32) void {
    game.roadworks.reset();
    game.roadworks.active = true;
    game.roadworks.curved = curved == 1;
    game.roadworks.class = @min(2, game.roadworks.class);
}

export fn road_class(value: u32) void {
    if (value <= 2) game.roadworks.class = @intCast(value);
}

export fn parking_rebuild() void {
    game.parking.rebuild();
    game.parking.refreshPrices(&transport.movement);
}
export fn road_point(index: u32, x: f32, z: f32) void {
    if (index >= 3 or !std.math.isFinite(x) or !std.math.isFinite(z)) return;
    game.roadworks.knots[index] = .{ .x = x, .z = z };
    game.roadworks.knot_count = index + 1;
    game.roadworks.preview();
}
export fn road_screen_point(index: u32, x: f32, y: f32) void {
    const p = scene.groundPoint(x, y);
    road_point(index, p.x, p.z);
}
export fn road_build() bool {
    return game.roadworks.build(game.elapsed);
}
export fn road_cancel() void {
    game.roadworks.reset();
}
export fn zoning_show(value: u32) void {
    game.parcels.visible = value == 1;
}
export fn zoning_pick(x: f32, y: f32) i32 {
    const p = scene.groundPoint(x, y);
    game.parcels.selected = game.parcels.pick(p.x, p.z);
    return game.parcels.selected;
}
export fn zoning_apply(id: u32, zone: u32, block: u32) bool {
    return game.parcels.paint(id, zone, block == 1);
}

// Slice 11: the traffic submenu places crosswalks and signals by clicking the
// map. The ground point snaps to the nearest junction arm.
export fn signal_place(road: u32, node: u32) i32 {
    if (road >= city.roads.len or node >= city.node_count) return -1;
    const r = city.roads[road];
    if (r.a != node and r.b != node) return -1;
    const junction = signals.signalise(node) orelse return -1;
    const arm = signals.armIndex(node, road) orelse return -1;
    return signalFlat(junction, arm);
}

export fn signal_remove(node: u32) bool {
    if (node >= city.node_count) return false;
    if (!signals.remove(node)) return false;
    scene.selected_signal = -1;
    return true;
}

// Set the green duration in simulation seconds. Returns the applied value, or
// -1 when there is no signal at that junction.
export fn signal_set_green(node: u32, seconds: f64) f64 {
    if (node >= city.node_count or !std.math.isFinite(seconds)) return -1;
    if (!signals.setGreen(node, @floatCast(seconds))) return -1;
    const index = signals.find(node) orelse return -1;
    return signals.junctions[index].green;
}

export fn signal_set_yellow(node: u32, seconds: f64) f64 {
    if (node >= city.node_count or !std.math.isFinite(seconds)) return -1;
    if (!signals.setYellow(node, @floatCast(seconds))) return -1;
    const index = signals.find(node) orelse return -1;
    return signals.junctions[index].yellow;
}

// Click a head: screen pixels in, flat head index out.
export fn signal_pick(x: f32, y: f32) i32 {
    return scene.pickSignal(x, y, 20);
}

// Slice 12: per-light granular timing. The all-red clearance is the "off" time
// shown next to green and amber in the inspector.
export fn signal_set_red(node: u32, seconds: f64) f64 {
    if (node >= city.node_count or !std.math.isFinite(seconds)) return -1;
    if (!signals.setRed(node, @floatCast(seconds))) return -1;
    const index = signals.find(node) orelse return -1;
    return signals.junctions[index].red;
}

// The daily window, in hours of the simulation day, where this light flashes
// amber instead of cycling. A window whose start is later than its end runs
// overnight, as most quiet-hour windows do.
export fn signal_set_flash_schedule(node: u32, start_hour: f64, end_hour: f64, enabled: u32) bool {
    if (node >= city.node_count) return false;
    if (!std.math.isFinite(start_hour) or !std.math.isFinite(end_hour)) return false;
    return signals.setFlashHours(node, @floatCast(start_hour), @floatCast(end_hour), enabled == 1);
}

// The manual flashing switch: 1 puts this light on flashing amber now, -1 puts
// it back on its normal cycle, 0 hands both back to the daily window.
export fn signal_flash_manual(node: u32, mode: i32) bool {
    if (node >= city.node_count) return false;
    return signals.setFlashMode(node, flashMode(mode));
}

fn flashMode(mode: i32) signals.FlashMode {
    if (mode > 0) return .on;
    if (mode < 0) return .off;
    return .auto;
}

// The same manual switch applied to a whole street (scope 1, key = road id), to
// one junction (scope 2, key = node) or to every light (scope 0). Returns how
// many lights changed.
export fn signal_flash_bulk(scope: u32, key: u32, mode: i32) u32 {
    if (scope > 2) return 0;
    return signals.bulkFlash(@intCast(scope), key, flashMode(mode));
}

// Emergency hook: 1 holds the cross traffic on this junction, 2 opens it to
// flashing amber, 3 releases it back to normal. Police and firefighters are not
// simulated yet, so the player's own controls call this today and a future
// dispatcher will call the same entry point.
export fn signal_alert(node: u32, kind: u32, seconds: f64) u32 {
    if (node >= city.node_count or kind < 1 or kind > 3) return @intCast(signals.alert_count);
    const until: f64 = if (std.math.isFinite(seconds) and seconds > 0) game.elapsed + seconds else 0;
    _ = signals.pushAlert(node, @enumFromInt(@as(u8, @intCast(kind))), until);
    return @intCast(signals.alert_count);
}

export fn signal_alerts_pending() u32 {
    return @intCast(signals.alert_count);
}

export fn signal_alerts_handled() f64 {
    return @floatFromInt(signals.alerts_handled);
}

export fn signal_alerts_pushed() f64 {
    return @floatFromInt(signals.alerts_pushed);
}

// Coordination: which lights act together, and how far the follower lags.
export fn signal_link(from_node: u32, to_node: u32, delay: f64) bool {
    if (from_node >= city.node_count or to_node >= city.node_count) return false;
    if (!std.math.isFinite(delay)) return false;
    return signals.link(from_node, to_node, @floatCast(delay));
}

export fn signal_unlink(from_node: u32, to_node: u32) bool {
    return signals.unlink(from_node, to_node);
}

export fn signal_link_count() u32 {
    return @intCast(signals.link_count);
}

export fn signal_links_total() f64 {
    return @floatFromInt(signals.link_total);
}

// Bulk apply by street, junction or the whole town. field 0 green, 1 amber,
// 2 all-red off time, 3 and 4 the flash window hours, 5 the window switch,
// 6 the manual flash mode. Returns how many lights changed.
export fn signal_apply_bulk(scope: u32, key: u32, field: u32, value: f64) u32 {
    if (scope > 2 or field > 6) return 0;
    if (!std.math.isFinite(value)) return 0;
    return signals.bulkApply(@intCast(scope), key, @intCast(field), @floatCast(value));
}

export fn signal_selected() i32 {
    return scene.selected_signal;
}

// Place a signal at the nearest junction to a screen point. Returns the head.
export fn signal_place_screen(x: f32, y: f32) i32 {
    const p = scene.groundPoint(x, y);
    const node = nearJunctionNode(p) orelse return -1;
    const junction = signals.signalise(node) orelse return -1;
    const j = &signals.junctions[junction];
    if (j.arm_count == 0 or j.arms[0] < 0) return -1;
    return signalFlat(junction, 0);
}

// Slice 11: the nearest segment to a ground point, within limit metres.
fn nearRoad(p: city.Vec, limit: f32) i32 {
    var best: f32 = limit;
    var road: i32 = -1;
    for (city.roads, 0..) |r, id| {
        const a = city.nodes[r.a];
        const b = city.nodes[r.b];
        const length_sq = @max(0.0001, (b.x - a.x) * (b.x - a.x) + (b.z - a.z) * (b.z - a.z));
        const t = std.math.clamp(((p.x - a.x) * (b.x - a.x) + (p.z - a.z) * (b.z - a.z)) / length_sq, 0, 1);
        const d = city.hypot(p.x - (a.x + (b.x - a.x) * t), p.z - (a.z + (b.z - a.z) * t));
        if (d < best) {
            best = d;
            road = @intCast(id);
        }
    }
    return road;
}

// Slice 11 previews: report the snap target under the cursor without placing
// anything, so the traffic tools can show where a click would land.
export fn signal_preview_screen(x: f32, y: f32) i32 {
    const p = scene.groundPoint(x, y);
    const node = nearJunctionNode(p) orelse return -1;
    return @intCast(node);
}

export fn crosswalk_preview_screen(x: f32, y: f32) i32 {
    const p = scene.groundPoint(x, y);
    return nearRoad(p, 9);
}

// Add a crosswalk to the nearest segment and signalise its junction.
export fn crosswalk_place_screen(x: f32, y: f32) i32 {
    const p = scene.groundPoint(x, y);
    const road = nearRoad(p, 9);
    if (road < 0) return -1;
    city.roads[@intCast(road)].crosswalk = true;
    const r = city.roads[@intCast(road)];
    if (city.degree(r.a) >= 3) _ = signals.signalise(r.a);
    if (city.degree(r.b) >= 3) _ = signals.signalise(r.b);
    return road;
}

export fn crosswalk_remove_screen(x: f32, y: f32) i32 {
    const road = crosswalk_place_screen(x, y);
    if (road < 0) return -1;
    city.roads[@intCast(road)].crosswalk = false;
    return road;
}
