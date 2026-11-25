const std = @import("std");

const App = @import("App.zig");

pub fn main(init: std.process.Init) !void {
    var app: App = .{ .a = init.gpa, .io = init.io };
    app.init(init);
    defer app.deinit();
}
