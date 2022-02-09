const std = @import("std");
const bedrock = @import("bedrock.zig");

// IF YOU WANT TO CHANGE THE PATTERN, DO THAT HERE!
// Layers along Y, rows along Z, columns along X
const pattern: []const []const []const ?bedrock.Block = &.{&.{
    &.{ .bedrock, .bedrock, .bedrock },
    &.{ .bedrock, .bedrock, .bedrock },
    &.{ .bedrock, .bedrock, .bedrock },
}};

pub fn main() anyerror!void {
    var args = try std.process.argsWithAllocator(std.heap.page_allocator);
    defer args.deinit();
    std.debug.assert(args.skip());

    const seed_str = args.next() orelse return error.NotEnoughArgs;
    const range_str = args.next() orelse return error.NotEnoughArgs;
    const seed = try std.fmt.parseInt(i64, seed_str, 10);
    const range: i32 = try std.fmt.parseInt(u31, range_str, 10);

    const finder = bedrock.PatternFinder{
        .gen = bedrock.GradientGenerator.overworldFloor(seed),
        .pattern = pattern,
    };
    finder.search(.{
        .x = -range,
        .y = -60,
        .z = -range,
    }, .{
        .x = range,
        .y = -60,
        .z = range,
    }, {}, reportResult, null);
}

fn reportResult(_: void, p: bedrock.Point) void {
    const out = std.io.getStdOut().writer();
    out.print("{},{},{}\n", .{ p.x, p.y, p.z }) catch @panic("failed to write to stdout");
}
