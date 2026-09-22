const std = @import("std");
const city = @import("../scene/city.zig");
const residents = @import("residents.zig");
const households = @import("households.zig");

// Slice 8: bounded vacancies, skills, wages, hiring and firing. No regional
// trade, production inputs, business credit or national labour market.
pub const max_hires_per_day: usize = 64;
pub const max_dismissals_per_company_per_day: usize = 2;
pub var hires: u32 = 0;
pub var dismissals: u32 = 0;
pub var wages_paid: f64 = 0;
pub var wages_arrears: f64 = 0;

pub fn init() void {
    hires = 0;
    dismissals = 0;
    wages_paid = 0;
    wages_arrears = 0;
    for (residents.companies[0..residents.company_count]) |*c| {
        c.wage_arrears = 0;
        c.staffing_pressure = 0;
    }
}

pub fn vacancies(company: usize) usize {
    if (company >= residents.company_count) return 0;
    return residents.companies[company].capacity -| residents.companies[company].employees;
}

pub fn employedCount() usize {
    var count: usize = 0;
    for (&residents.people) |*p| if (p.employer >= 0) {
        count += 1;
    };
    return count;
}

pub fn unemployedCount() usize {
    return residents.people.len - employedCount();
}

fn closestVacancy(p: *const residents.Person) i32 {
    var best: i32 = -1;
    var best_distance: f32 = 1e9;
    for (residents.companies[0..residents.company_count], 0..) |c, id| {
        if (c.employees >= c.capacity or c.skill_required > p.skill) continue;
        const node = city.buildings[p.home].node;
        const work = city.buildings[c.building].node;
        const distance = city.distance[node][work];
        if (distance < best_distance) {
            best_distance = distance;
            best = @intCast(id);
        }
    }
    return best;
}

// Bounded daily staffing: fill qualified vacancies, dismiss on prior arrears,
// then pay posted wages from employer cash. Every paid pound is credited to a
// household through the household daily budget; nothing is created in between.
pub fn daily() void {
    if (residents.company_count == 0) return;
    hires = 0;
    dismissals = 0;

    // 1. Fill vacancies from unemployed residents whose skill matches.
    var attempts: usize = 0;
    for (&residents.people) |*p| {
        if (hires >= max_hires_per_day or attempts >= max_hires_per_day * 4) break;
        if (p.employer >= 0) {
            attempts += 1;
            continue;
        }
        const best = closestVacancy(p);
        if (best < 0) {
            attempts += 1;
            continue;
        }
        const id: usize = @intCast(best);
        p.employer = best;
        p.income = residents.companies[id].wage;
        residents.companies[id].employees += 1;
        hires += 1;
        attempts += 1;
    }

    // 2. An employer that ended the previous day in arrears dismisses a bounded
    // number of lowest-skill employees; each dismissal is real unemployment.
    for (residents.companies[0..residents.company_count], 0..) |*c, id| {
        if (c.wage_arrears <= 0 or c.employees == 0) continue;
        var fired: usize = 0;
        while (fired < max_dismissals_per_company_per_day and c.employees > 0) : (fired += 1) {
            var worst: ?usize = null;
            var worst_skill: u8 = 255;
            for (&residents.people, 0..) |*p, i| {
                if (p.employer != @as(i32, @intCast(id))) continue;
                if (p.skill < worst_skill) {
                    worst_skill = p.skill;
                    worst = i;
                }
            }
            const index = worst orelse break;
            residents.people[index].employer = -1;
            residents.people[index].income = 0;
            c.employees -= 1;
            dismissals += 1;
        }
        c.wage_arrears = 0;
        c.staffing_pressure = 0;
    }

    // 3. Pay the wages the employer can afford and derive the household's
    // daily income from those actual payments.
    var paid_homes: [city.buildings.len]f64 = @splat(0);
    wages_paid = 0;
    wages_arrears = 0;
    for (residents.companies[0..residents.company_count], 0..) |*c, id| {
        if (c.employees == 0) {
            c.wage_arrears = 0;
            c.staffing_pressure = 0;
            continue;
        }
        const bill = @as(f64, @floatFromInt(c.employees)) * c.wage;
        const paid = @min(c.cash, bill);
        c.cash -= paid;
        c.wage_arrears = bill - paid;
        c.staffing_pressure = if (bill > 0) (bill - paid) / bill else 0;
        wages_paid += paid;
        wages_arrears += c.wage_arrears;
        const ratio = if (bill > 0) paid / bill else 0;
        for (&residents.people) |*p| {
            if (p.employer != @as(i32, @intCast(id))) continue;
            paid_homes[p.home] += c.wage * ratio;
        }
    }
    for (&households.homes, 0..) |*h, i| {
        if (h.present) h.income = paid_homes[i];
    }
}

pub fn read(company: usize, field: u32) f64 {
    if (company >= residents.company_count) return -1;
    const c = residents.companies[company];
    return switch (field) {
        0 => @floatFromInt(vacancies(company)),
        1 => c.wage,
        2 => c.skill_required,
        3 => c.wage_arrears,
        4 => c.staffing_pressure,
        5 => @floatFromInt(c.employees),
        6 => @floatFromInt(c.capacity),
        else => -1,
    };
}
