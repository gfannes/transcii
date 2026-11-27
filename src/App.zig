const std = @import("std");
const Options = @import("Options.zig");

const Self = @This();

a: std.mem.Allocator,
io: std.Io,

options: Options = undefined,

stdout_buf: [1024]u8 = undefined,
stdout_file_writer: std.Io.File.Writer = undefined,
stdout_writer: *std.Io.Writer = undefined,

pub fn init(self: *Self, pinit: std.process.Init) !void {
    self.options = .{ .a = self.a };
    try self.options.init(pinit);

    self.stdout_file_writer = .init(.stdout(), self.io, &self.stdout_buf);
    self.stdout_writer = &self.stdout_file_writer.interface;
}

pub fn deinit(self: *Self) void {
    self.options.deinit();
    self.stdout_writer.flush() catch {};
}

pub fn run(self: *Self) !void {
    try self.options.parse();

    if (self.options.print_help) {
        try self.options.printHelp(self.stdout_writer);
        return;
    }

    const input_fp = self.options.input_fp orelse return error.ExpectedInputFilename;
    const file_content = try std.Io.Dir.cwd().readFileAlloc(self.io, input_fp, self.a, .unlimited);
    defer self.a.free(file_content);

    var content = file_content;

    var did_something: bool = false;
    if (self.options.utf8) {
        var utf8: Utf8 = .{ .input = content, .output = content };
        try utf8.call();
        content = utf8.output;
        did_something = true;
    }

    if (!did_something) {
        std.log.err("Did not do anything", .{});
    } else if (self.options.output_fp) |output| {
        try std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = output, .data = content });
    }
}

const ByteRange = struct {
    content: []const u8,
    ix: usize = 0,

    fn pop(self: *@This()) ?u8 {
        if (self.ix >= self.content.len)
            return null;
        defer self.ix += 1;
        return self.content[self.ix];
    }
};

const Utf8 = struct {
    input: []const u8,
    output: []u8,
    write_ix: usize = undefined,

    fn call(self: *@This()) !void {
        self.write_ix = 0;
        defer self.output.len = self.write_ix;

        var byte_range: ByteRange = .{ .content = self.input };

        while (byte_range.pop()) |b0| {
            if (b0 <= 0x7f) {
                self.process_1(b0);
            } else if (b0 < 0xc2) {
                return error.IllegalUtf8;
            } else {
                const b1 = byte_range.pop() orelse return error.ExpectedData;
                if (b0 <= 0xdf) {
                    try self.process_2(b0, b1);
                } else {
                    const b2 = byte_range.pop() orelse return error.ExpectedData;
                    if (b0 <= 0xef) {
                        try self.process_3(b0, b1, b2);
                    } else {
                        if (b0 <= 0xef) {
                            const b3 = byte_range.pop() orelse return error.ExpectedData;
                            try self.process_4(b0, b1, b2, b3);
                        } else {
                            return error.IllegalUtf8;
                        }
                    }
                }
            }
        }
    }

    fn process_1(self: *@This(), b0: u8) void {
        const ascii = b0;
        self.output[self.write_ix] = ascii;
        self.write_ix += 1;
    }
    fn process_2(self: *@This(), b0: u8, b1: u8) !void {
        const codepoint: u16 = (@as(u16, b0) << 8) | b1;
        const ascii: u8 = switch (codepoint) {
            else => {
                std.log.err("Unsupported 2-byte codepoint 0x{x}", .{codepoint});
                return error.UnknownCodePoint;
            },
        };

        self.output[self.write_ix] = ascii;
        self.write_ix += 1;
    }
    fn process_3(self: *@This(), b0: u8, b1: u8, b2: u8) !void {
        const codepoint: u24 = (@as(u24, b0) << 16) | (@as(u24, b1) << 8) | b2;
        const ascii: u8 = switch (codepoint) {
            0xe280a2 => '-',
            0xe28099 => '\'',
            0xe28093 => '-',
            0xe38081 => ',',
            else => {
                std.log.err("Unsupported 3-byte codepoint 0x{x}", .{codepoint});
                return error.UnknownCodePoint;
            },
        };

        self.output[self.write_ix] = ascii;
        self.write_ix += 1;
    }
    fn process_4(self: *@This(), b0: u8, b1: u8, b2: u8, b3: u8) !void {
        const codepoint: u32 = (@as(u32, b0) << 24) | (@as(u32, b1) << 16) | (@as(u32, b2) << 8) | b3;
        const ascii: u8 = switch (codepoint) {
            else => {
                std.log.err("Unsupported 4-byte codepoint 0x{x}", .{codepoint});
                return error.UnknownCodePoint;
            },
        };

        self.output[self.write_ix] = ascii;
        self.write_ix += 1;
    }
};
