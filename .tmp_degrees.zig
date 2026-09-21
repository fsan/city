const city = @import("src/scene/city.zig");
pub fn main() void {
    city.init();
    const ids = [_]usize{8,10,12,26,40,38,36,22,0,3,6,27,48,45,42,21};
    for (ids) |id| std.debug.print("{d}:{d} ", .{id, city.degree(id)});
    std.debug.print("\n", .{});
}
const std = @import("std");
