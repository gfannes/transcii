const std = @import("std");

const App = @import("App.zig");

pub fn main(pinit: std.process.Init) !void {
    var app: App = .{ .a = pinit.gpa, .io = pinit.io };
    try app.init(pinit);
    defer app.deinit();

    try app.run();
}
