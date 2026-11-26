const std = @import("std");
const rubr = @import("rubr.zig");

const Self = @This();

const Mode = enum { PrintHelp, Check };

a: std.mem.Allocator,

cli_args: rubr.cli.Args = undefined,

exe_name: ?[]const u8 = null,

mode: Mode = .Check,
input: ?[]const u8 = null,
output: ?[]const u8 = null,

pub fn init(self: *Self, pinit: std.process.Init) !void {
    self.cli_args = .{ .a = self.a };
    try self.cli_args.setupFromOS(pinit.minimal.args);
}

pub fn deinit(self: *Self) void {
    self.cli_args.deinit();
}

pub fn parse(self: *Self) !void {
    const args = &self.cli_args;

    self.exe_name = (args.pop() orelse return error.ExpectedExeName).arg;

    while (args.pop()) |arg| {
        if (arg.is("-h", "--help")) {
            self.mode = .PrintHelp;
        } else if (arg.is("ch", "check")) {
            self.mode = .Check;
        } else if (arg.is("-i", "--input")) {
            self.input = (args.pop() orelse return error.ExpectedInput).arg;
        } else if (arg.is("-o", "--output")) {
            self.output = (args.pop() orelse return error.ExpectedOutput).arg;
        } else {
            std.log.err("Unknown argument '{s}'", .{arg.arg});
            return error.UnknownArgument;
        }
    }
}

pub fn printHelp(self: Self, w: *std.Io.Writer) !void {
    try w.print("Help for {s}\n", .{self.exe_name orelse "<no exe_name>"});
    try w.print("  ch/check     Check mode\n", .{});
    try w.print("  -h/--help    Print this help\n", .{});
    try w.print("  -i/--input   Input filename\n", .{});
    try w.print("  -o/--output  Output filename\n", .{});
    try w.print("Developed by Geert Fannes.\n", .{});
}
