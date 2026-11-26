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

    if (self.options.print_help) {
        try self.options.printHelp(self.stdout_writer);
    } else if (self.options.mode) |mode| {
        switch (mode) {
            .Check => {},
        }
    }
}
