const std = @import("std");
const rubr = @import("rubr.zig");

const Self = @This();

pub const Range = struct {
    start: usize,
    size: usize,

    fn parse(arg: []const u8) !Range {
        const colon = std.mem.indexOfScalar(u8, arg, ':') orelse return error.ExpectedRange;
        return .{
            .start = try parseDecimal(arg[0..colon]),
            .size = try parseDecimal(arg[colon + 1 ..]),
        };
    }
};

a: std.mem.Allocator,

cli_args: rubr.cli.Args = undefined,
environ: *const std.process.Environ.Map = undefined,

exe_name: ?[]const u8 = null,
print_help: bool = false,
junk: bool = false,
ansi: bool = false,
utf8: bool = false,
replace: ?[2]u8 = null,
newline: bool = false,
input_fp: ?[]const u8 = null,
output_fp: ?[]const u8 = null,
state: ?[]const u8 = null,
line_number: ?usize = null,
ranges: std.ArrayList(Range) = .empty,
helix_ranges: bool = false,

pub fn init(self: *Self, pinit: std.process.Init) !void {
    self.cli_args = .{ .a = self.a };
    self.environ = pinit.environ_map;
    try self.cli_args.setupFromOS(pinit.minimal.args);
}

pub fn deinit(self: *Self) void {
    self.ranges.deinit(self.a);
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
            if (ab.arg.len == 2) {
                self.replace = [2]u8{ ab.arg[0], ab.arg[1] };
            } else if (std.mem.eql(u8, arg.arg, "-r") and std.mem.indexOfScalar(u8, ab.arg, ':') != null) {
                try self.ranges.append(self.a, try Range.parse(ab.arg));
            } else {
                return error.ExpectedTwoChars;
            }
        } else if (std.mem.eql(u8, arg.arg, "--range")) {
            try self.ranges.append(self.a, try Range.parse((args.pop() orelse return error.ExpectedRange).arg));
        } else if (arg.is("-s", "--state")) {
            const value = (args.pop() orelse return error.ExpectedState).arg;
            const end = std.mem.indexOfScalar(u8, value, ':') orelse value.len;
            if (end == 0) return error.ExpectedState;
            self.state = value[0..end];
            self.line_number = null;
            if (end < value.len) {
                const line = try parseDecimal(value[end + 1 ..]);
                if (line == 0) return error.InvalidLineNumber;
                self.line_number = line;
            }
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

    if (self.print_help) return;
    if (self.state == null) {
        if (self.ranges.items.len != 0) return error.ExpectedState;
        return;
    }

    if (self.input_fp == null) self.input_fp = self.environ.get("helix_filepath");
    if (self.line_number != null or self.ranges.items.len != 0) return;

    const count = try parseDecimal(self.environ.get("helix_range_count") orelse return);
    self.helix_ranges = true;
    for (0..count) |index| {
        var key_buf: [32]u8 = undefined;
        const key = try std.fmt.bufPrint(&key_buf, "helix_range_{d}", .{index});
        const value = self.environ.get(key) orelse return error.ExpectedHelixRange;
        try self.ranges.append(self.a, try Range.parse(value));
    }
}

fn parseDecimal(value: []const u8) !usize {
    for (value) |ch| {
        if (!std.ascii.isDigit(ch)) return error.InvalidCharacter;
    }
    return std.fmt.parseInt(usize, value, 10);
}

pub fn printHelp(self: Self, w: *std.Io.Writer) !void {
    try w.print("Help for {s}\n", .{self.exe_name orelse "<no exe_name>"});
    try w.print("  -h/--help        Print this help\n", .{});
    try w.print("  -j/--junk        Remove binary junk\n", .{});
    try w.print("  -a/--ansi        Remove ANSI color codes\n", .{});
    try w.print("  -u/--utf8        Remove UTF-8 codepoints\n", .{});
    try w.print("  -r/--replace AB  Replace char A with B\n", .{});
    try w.print("  -r/--range START:SIZE  Select a line by byte offset for --state (repeatable)\n", .{});
    try w.print("  -s/--state STATE[:LINE]  Update Markdown state (1-based line); use - to clear\n", .{});
    try w.print("  -n/--newline     Change newlines to Linux format\n", .{});
    try w.print("  -i/--input       Input filename\n", .{});
    try w.print("  -o/--output      Output filename\n", .{});
    try w.print("Markdown state updates default to the input file and use Helix input and ranges as fallbacks.\n", .{});
    try w.print("Developed by Geert Fannes.\n", .{});
}
