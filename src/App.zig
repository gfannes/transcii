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
    self.stdout_writer.flush() catch {}; // Don't forget to flush!
}

pub fn run(self: *Self) !void {
    try self.options.parse();

    switch (self.options.mode) {
        .PrintHelp => try self.options.printHelp(self.stdout_writer),
        .Check => try self.check(),
    }
}

fn check(self: *const Self) !void {
    const input = self.options.input orelse return error.ExpectedInputFilename;
    const content = try std.Io.Dir.cwd().readFileAlloc(self.io, input, self.a, .unlimited);
    defer self.a.free(content);

    var trans = try self.a.alloc(u8, content.len);
    defer self.a.free(trans);
    var ix: usize = 0;

    var size: usize = 0;
    var count: usize = 0;
    var codepoint: u32 = undefined;

    for (content) |byte| {
        if (size == 0) {
            switch (byte) {
                0x00...0x7f => size = 1,
                0xc2...0xdf => size = 2,
                0xe0...0xef => size = 3,
                0xf0...0xf4 => size = 4,
                else => {
                    std.log.err("Found illegal UTF8 start byte {x}", .{byte});
                    continue;
                },
            }
            codepoint = 0;
            count = 0;
        }

        codepoint <<= 8;
        codepoint |= byte;
        count += 1;

        if (count == size) {
            const ascii: u8 = switch (codepoint) {
                0x00...0x7f => @intCast(codepoint),
                0xe280a2 => '-',
                0xe28099 => '\'',
                0xe28093 => '-',
                0xe38081 => ',',
                else => ret: {
                    std.log.debug("Unsupported {}-byte codepoint {x}", .{ size, codepoint });
                    break :ret '?';
                },
            };

            trans[ix] = ascii;
            ix += 1;

            size = 0;
        }
    }

    if (self.options.output) |output| {
        try std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = output, .data = trans[0..ix] });
    }
}
