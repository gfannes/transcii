const std = @import("std");

const Options = @import("Options.zig");
const App = @import("App.zig");

test "root" {
    const ut = std.testing;

    ut.refAllDecls(@This());
    ut.refAllDecls(App);
    ut.refAllDecls(Options);
}
