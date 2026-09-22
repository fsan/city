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
var paid_homes: [city.buildings.len]f64 = undefined;

pub fn init() void {
    hires = 0;
    dismissals = 0;
    wages_paid = 0;
    wages_arrears = 0;
    @memset(&paid_homes, 0);
    for (residents.companies[0..residents.company_count]) |*c| {
        c.wage_arrears = 0;
        c.staffing_pressure = 0;
    }
    residents.employed = employedCount();
    for (&households.homes) |*h| h.paid_wages = 0;
}

pub fn vacancies(company: usize) usize {
    if (company >= residents.company_count) return 0;
    return residents.companies[company].capacity -| residents.companies[company].employees;
}

pub fn totalVacancies() usize {
    var total: usize = 0;
    for (residents.companies[0..residents.company_count]) |c| total += c.capacity -| c.employees;
    return total;
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

// Skill 0 general, 1 clerical, 2 professional. A resident may take a post only
// when their skill meets the requirement; a mismatch is never silently filled.
pub fn qualifies(person: *const residents.Person, company: usize) bool {
    if (company >= residents.company_count) return false;
    return residents.companies[company].skill_required <= person.skill;
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

// Bounded daily staffing, in this order: fill qualified vacancies from
// unemployed residents, dismiss a bounded number of ordinary staff at any
// employer still carrying previous wage arrears, then pay the wages each
// employer can actually afford. Every paid pound is credited to a household
// through the household daily budget; nothing is created in between.
pub fn daily() void {
    if (residents.company_count == 0) return;
    hires = 0;
    dismissals = 0;
    wages_paid = 0;
    wages_arrears = 0;
    @memset(&paid_homes, 0);
    households.recomputeIncome();

    // 1. Fill vacancies from unemployed residents whose skill matches,
    // preferring the closest home-to-work trip. A mismatch is a refusal: the
    // resident simply stays a jobseeker until a post they qualify for appears.
    var attempts: usize = 0;
    for (&residents.people) |*p| {
        if (hires >= max_hires_per_day or attempts >= max_hires_per_day * 8) break;
        if (p.employer >= 0) {
            attempts += 1;
            continue;
        }
        const best = closestVacancy(p);
        attempts += 1;
        if (best < 0) continue;
        const id: usize = @intCast(best);
        p.employer = best;
        p.income = residents.companies[id].wage;
        residents.companies[id].employees += 1;
        hires += 1;
    }

    // 2. An employer that ended the previous day in arrears dismisses a bounded
    // number of lowest-skill ordinary employees. Crew members and workers bound
    // to an active order are never dismissed, and each dismissal is real
    // unemployment recorded through the resident's own employment link.
    for (residents.companies[0..residents.company_count], 0..) |*c, id| {
        if (c.employees == 0) {
            c.wage_arrears = 0;
            c.staffing_pressure = 0;
            continue;
        }
        if (c.wage_arrears > 0) {
            var fired: usize = 0;
            while (fired < max_dismissals_per_company_per_day) : (fired += 1) {
                var worst: ?usize = null;
                var worst_skill: u8 = 255;
                for (&residents.people, 0..) |*p, i| {
                    if (p.employer != @as(i32, @intCast(id)) or p.crew or p.order >= 0) continue;
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
        }
        c.wage_arrears = 0;
        c.staffing_pressure = 0;
    }

    // Recompute posted household income now that hiring and dismissal have
    // settled, so the posted figure always matches the live employment links.
    households.recomputeIncome();

    // 3. Pay the wages each employer can afford. Unpaid amounts stay as that
    // employer's explicit wage arrears; employer cash never goes negative and
    // only the paid share reaches household balances.
    for (residents.companies[0..residents.company_count], 0..) |*c, id| {
        if (c.employees == 0) continue;
        const bill = @as(f64, @floatFromInt(c.employees)) * c.wage;
        const paid = @min(c.cash, bill);
        c.cash -= paid;
        c.wage_arrears = bill - paid;
        c.staffing_pressure = if (bill > 0) (bill - paid) / bill else 0;
        wages_paid += paid;
        wages_arrears += c.wage_arrears;
        if (paid <= 0) continue;
        const ratio = paid / bill;
        for (&residents.people) |*p| {
            if (p.employer != @as(i32, @intCast(id))) continue;
            paid_homes[p.home] += c.wage * ratio;
        }
    }
    for (&households.homes, 0..) |*h, i| {
        if (h.present) h.paid_wages = paid_homes[i];
    }
    residents.employed = employedCount();
}

pub fn read(company: usize, field: u32) f64 {
    if (company >= residents.company_count) return -1;
    const c = residents.companies[company];
    return switch (field) {
        0 => @floatFromInt(vacancies(company)),
        1 => c.wage,
        2 => @floatFromInt(c.skill_required),
        3 => c.wage_arrears,
        4 => c.staffing_pressure,
        5 => @floatFromInt(c.employees),
        6 => @floatFromInt(c.capacity),
        7 => c.cash,
        8 => if (c.contractor) 1 else 0,
        else => -1,
    };
}
