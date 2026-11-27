const std = @import("std");
const rubr = @import("rubr.zig");

const Self = @This();

a: std.mem.Allocator,

cli_args: rubr.cli.Args = undefined,

exe_name: ?[]const u8 = null,
print_help: bool = false,
utf8: bool = false,
input_fp: ?[]const u8 = null,
output_fp: ?[]const u8 = null,

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
            self.print_help = true;
        } else if (arg.is("-u", "--utf8")) {
            self.utf8 = true;
        } else if (arg.is("-i", "--input")) {
            self.input_fp = (args.pop() orelse return error.ExpectedInput).arg;
        } else if (arg.is("-o", "--output")) {
            self.output_fp = (args.pop() orelse return error.ExpectedOutput).arg;
        } else {
            std.log.err("Unknown argument '{s}'", .{arg.arg});
            return error.UnknownArgument;
        }
    }
}

pub fn printHelp(self: Self, w: *std.Io.Writer) !void {
    try w.print("Help for {s}\n", .{self.exe_name orelse "<no exe_name>"});
    try w.print("  -h/--help    Print this help\n", .{});
    try w.print("  -u/--utf8    Remove UTF-8 codepoints\n", .{});
    try w.print("  -i/--input   Input filename\n", .{});
    try w.print("  -o/--output  Output filename\n", .{});
    try w.print("Developed by Geert Fannes.\n", .{});
}
