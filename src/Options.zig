const std = @import("std");
const rubr = @import("rubr.zig");

const Self = @This();

a: std.mem.Allocator,

cli_args: rubr.cli.Args = undefined,
// args: []const [:0]const u8,

input: ?[]const u8 = null,
output: ?[]const u8 = null,

pub fn init(self: *Self, pinit: std.process.Init) void {
    _ = pinit;
    self.cli_args = .{ .a = self.a };
}

pub fn parse(self: *Self) !void {
    var cli = rubr.cli.Args{ .a = self.a };
    try cli.setupFromData(self.args);

    for (self.args) |arg| {
        std.log.info("arg: {s}", .{arg});
    }
}
