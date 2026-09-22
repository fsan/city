const std = @import("std");
const city = @import("../scene/city.zig");
const residents = @import("residents.zig");

// Slice 7: one bounded household per home building. Members share a single
// balance and daily budget. No bank, credit or retail system is added.
pub const Household = struct {
    present: bool = false,
    members: u32 = 0,
    balance: f64 = 0,
    // Posted daily wage of every employed member, recomputed from live links.
    income: f64 = 0,
    // Actually paid by employers on the last rollover; the only amount credited.
    paid_wages: f64 = 0,
    essential: f64 = 0,
    arrears: f64 = 0,
    paid: f64 = 0,
    unpaid: f64 = 0,
};

pub var homes: [city.buildings.len]Household = @splat(.{});
pub var daily_essential_per_member: f64 = 5;
pub var household_fixed_essential: f64 = 20;

pub fn init() void {
    homes = @splat(.{});
    for (&residents.people) |*p| {
        const h = &homes[p.home];
        if (!h.present) h.present = true;
        h.members += 1;
        h.balance += p.wallet;
        if (p.employer >= 0) h.income += p.income;
    }
    for (&homes) |*h| {
        if (h.present) h.essential = household_fixed_essential + @as(f64, @floatFromInt(h.members)) * daily_essential_per_member;
    }
}

pub fn valid(index: usize) bool {
    return index < homes.len and homes[index].present;
}

pub fn balance(index: usize) f64 {
    return if (valid(index)) homes[index].balance else 0;
}

pub fn canAfford(index: usize, amount: f64) bool {
    return valid(index) and homes[index].balance + 0.0001 >= amount;
}

// Spend from the shared household balance. Returns false without mutating when
// the household cannot cover the amount.
pub fn spend(index: usize, amount: f64) bool {
    if (!valid(index) or amount < 0) return false;
    const h = &homes[index];
    if (h.balance + 0.0001 < amount) return false;
    h.balance = @max(0, h.balance - amount);
    return true;
}

pub fn credit(index: usize, amount: f64) void {
    if (!valid(index) or amount <= 0) return;
    homes[index].balance += amount;
}

// Slice 8: household income has two figures. `income` is the posted daily wage
// of every employed member, recomputed from live employment links. `paid_wages`
// is what employers actually paid on the last rollover and the only amount
// credited to the balance, so unpaid wage arrears never create money.
pub fn recomputeIncome() void {
    for (&homes) |*h| h.income = 0;
    for (&residents.people) |*p| {
        if (p.employer >= 0) homes[p.home].income += p.income;
    }
}

pub fn daily() void {
    for (&homes) |*h| {
        if (!h.present) continue;
        h.balance += h.paid_wages;
        const due = h.essential + h.arrears;
        const payment = @min(due, h.balance);
        h.balance -= payment;
        h.arrears = due - payment;
        h.paid += payment;
        h.unpaid = h.arrears;
    }
}

pub fn read(index: usize, field: u32) f64 {
    if (!valid(index)) return -1;
    const h = homes[index];
    return switch (field) {
        0 => 1,
        1 => @floatFromInt(h.members),
        2 => h.balance,
        3 => h.income,
        8 => h.paid_wages,
        4 => h.essential,
        5 => h.arrears,
        6 => h.paid,
        7 => h.unpaid,
        else => -1,
    };
}

pub fn inArrears() usize {
    var count: usize = 0;
    for (homes) |h| if (h.present and h.arrears > 0.0001) {
        count += 1;
    };
    return count;
}

pub fn totalArrears() f64 {
    var total: f64 = 0;
    for (homes) |h| if (h.present) {
        total += h.arrears;
    };
    return total;
}
