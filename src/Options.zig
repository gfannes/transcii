const std = @import("std");
const rubr = @import("rubr.zig");

const Self = @This();

a: std.mem.Allocator,

cli_args: rubr.cli.Args = undefined,

exe_name: ?[]const u8 = null,
print_help: bool = false,
junk: bool = false,
ansi: bool = false,
utf8: bool = false,
replace: ?[2]u8 = null,
newline: bool = false,
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
        } else if (arg.is("-j", "--junk")) {
            self.junk = true;
        } else if (arg.is("-a", "--ansi")) {
            self.ansi = true;
        } else if (arg.is("-u", "--utf8")) {
            self.utf8 = true;
        } else if (arg.is("-r", "--replace")) {
            const ab = args.pop() orelse return error.ExpectedAB;
            if (ab.arg.len != 2)
                return error.ExpectedTwoChars;
            self.replace = [2]u8{ ab.arg[0], ab.arg[1] };
        } else if (arg.is("-n", "--newline")) {
            self.newline = true;
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
    try w.print("  -h/--help        Print this help\n", .{});
    try w.print("  -j/--junk        Remove binary junk\n", .{});
    try w.print("  -a/--ansi        Remove ANSI color codes\n", .{});
    try w.print("  -u/--utf8        Remove UTF-8 codepoints\n", .{});
    try w.print("  -r/--replace AB  Replace char A with B\n", .{});
    try w.print("  -n/--newline     Change newlines to Linux format\n", .{});
    try w.print("  -i/--input       Input filename\n", .{});
    try w.print("  -o/--output      Output filename\n", .{});
    try w.print("Developed by Geert Fannes.\n", .{});
}
