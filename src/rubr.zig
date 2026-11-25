// Output from `rake export[cli]` from https://github.com/gfannes/rubr from 2026-11-19

const std = @import("std");
const builtin = @import("builtin");

// Export from 'src/cli.zig'
pub const cli = struct {
    // Allocates everything on env.aa: no need for deinit() or lifetime management
    pub const Args = struct {
        const Self = @This();
    
        a: std.mem.Allocator,
        argv: [][]const u8 = &.{},
        head: usize = 0,
    
        pub fn deinit(self: *Self) void {
            for (self.argv) |arg|
                self.a.free(arg);
            self.a.free(self.argv);
        }
    
        pub fn setupFromOS(self: *Self, os_args: std.process.Args) !void {
            self.argv = try self.a.alloc([]const u8, os_args.vector.len);
    
            var it = try os_args.iterateAllocator(self.a);
            defer it.deinit();
    
            var ix: usize = 0;
            while (it.next()) |os_arg| : (ix += 1)
                self.argv[ix] = try self.a.dupe(u8, os_arg);
    
            // This is necessary for Windows: os_args.vector.len is too long.
            self.argv.len = ix;
        }
        pub fn setupFromData(self: *Self, argv: []const []const u8) !void {
            self.argv = try self.a.alloc([]const u8, argv.len);
    
            for (argv, 0..) |slice, ix|
                self.argv[ix] = try self.a.dupe(u8, slice);
        }
    
        pub fn pop(self: *Self) ?Arg {
            if (self.head == self.argv.len)
                return null;
    
            defer self.head += 1;
            return Arg{ .arg = self.argv[self.head] };
        }
    
        // Can only be called when there was something popped first
        pub fn unpop(self: *Self) void {
            if (self.head > 0)
                self.head -= 1;
        }
    };
    
    pub const Arg = struct {
        const Self = @This();
    
        arg: []const u8,
    
        pub fn is(self: Arg, sh: []const u8, lh: []const u8) bool {
            return std.mem.eql(u8, self.arg, sh) or std.mem.eql(u8, self.arg, lh);
        }
    
        pub fn as(self: Self, T: type) !T {
            return try std.fmt.parseInt(T, self.arg, 10);
        }
    };
    
};

// Export from 'src/Env.zig'
pub const Env = struct {
    const Env_ = @This();
    
    // General purpose allocator
    a: std.mem.Allocator = undefined,
    // Arena allocator
    aa: std.mem.Allocator = undefined,
    
    io: std.Io = undefined,
    envmap: *const std.process.Environ.Map = undefined,
    
    log: *const Log = undefined,
    
    stdout: *std.Io.Writer = undefined,
    stderr: *std.Io.Writer = undefined,
    
    pub const Instance = struct {
        const Self = @This();
        const DA = std.heap.DebugAllocator(.{});
        const AA = std.heap.ArenaAllocator;
        const StdIO = struct {
            stdout_writer: std.Io.File.Writer = undefined,
            stderr_writer: std.Io.File.Writer = undefined,
            stdout_buffer: [4096]u8 = undefined,
            stderr_buffer: [4096]u8 = undefined,
            fn init(self: *@This(), io: std.Io) void {
                self.stdout_writer = std.Io.File.stdout().writer(io, &self.stdout_buffer);
                self.stderr_writer = std.Io.File.stderr().writer(io, &self.stderr_buffer);
            }
            fn deinit(self: *@This()) void {
                self.stdout_writer.interface.flush() catch {};
                self.stderr_writer.interface.flush() catch {};
            }
        };
    
        environ: std.process.Environ = std.process.Environ.empty,
        envmap: std.process.Environ.Map = undefined,
        log: Log = undefined,
        gpa: DA = undefined,
        aa: AA = undefined,
        io_threaded: std.Io.Threaded = undefined,
        io: std.Io = undefined,
        start_ts: std.Io.Timestamp = undefined,
        stdio: StdIO = undefined,
    
        pub fn init(self: *Self) void {
            self.gpa = DA{};
            const a = self.gpa.allocator();
            self.envmap = self.environ.createMap(a) catch std.process.Environ.Map.init(a);
            self.aa = AA.init(a);
            self.io_threaded = std.Io.Threaded.init(a, .{ .environ = self.environ });
            self.io = self.io_threaded.io();
            self.log = Log{ .io = self.io };
            self.log.init();
            self.start_ts = std.Io.Clock.now(.real, self.io);
            self.stdio.init(self.io);
        }
        pub fn deinit(self: *Self) void {
            self.stdio.deinit();
            self.log.deinit();
            self.io_threaded.deinit();
            self.aa.deinit();
            self.envmap.deinit();
            if (self.gpa.deinit() == .leak) {
                self.log.err("Found memory leaks in Env\n", .{}) catch {};
            }
        }
    
        pub fn env(self: *Self) Env_ {
            return .{
                .a = self.gpa.allocator(),
                .aa = self.aa.allocator(),
                .io = self.io,
                .envmap = &self.envmap,
                .log = &self.log,
                .stdout = &self.stdio.stdout_writer.interface,
                .stderr = &self.stdio.stderr_writer.interface,
            };
        }
    
        pub fn duration_ns(self: Self) i96 {
            const duration = self.start_ts.durationTo(std.Io.Clock.now(.real, self.io));
            return duration.nanoseconds;
        }
    };
    
    pub fn for_ut() Env_ {
        const ut = std.testing;
        return .{
            .a = ut.allocator,
            .aa = ut.allocator,
            .io = ut.io,
        };
    }
    
    pub fn duration_ns(env: Env_) i96 {
        const inst: *const Instance = @alignCast(@fieldParentPtr("log", env.log));
        return inst.duration_ns();
    }
    
};

// Export from 'src/Log.zig'
pub const Log = struct {
    pub const Error = error{FilePathTooLong};
    
    // &improv: Support both buffered and non-buffered logging
    const Self = @This();
    
    const Autoclean = struct {
        buffer: [std.fs.max_path_bytes]u8 = undefined,
        filepath: []const u8 = &.{},
    };
    
    io: std.Io,
    
    _do_close: bool = false,
    _file: std.Io.File = undefined,
    
    _buffer: [1024]u8 = undefined,
    _writer: std.Io.File.Writer = undefined,
    
    _io: *std.Io.Writer = undefined,
    
    _lvl: usize = 0,
    
    _autoclean: ?Autoclean = null,
    
    pub fn init(self: *Self) void {
        self._file = std.Io.File.stdout();
        self.initWriter();
    }
    pub fn deinit(self: *Self) void {
        self.closeWriter() catch {};
        if (self._autoclean) |autoclean| {
            std.Io.Dir.deleteFileAbsolute(self.io, autoclean.filepath) catch {};
        }
    }
    
    // Any '%' in 'filepath' will be replaced with the process id
    const Options = struct {
        autoclean: bool = false,
    };
    pub fn toFile(self: *Self, filepath: []const u8, options: Options) !void {
        try self.closeWriter();
    
        var pct_count: usize = 0;
        for (filepath) |ch| {
            if (ch == '%')
                pct_count += 1;
        }
    
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const filepath_clean = if (pct_count > 0) blk: {
            var pid_buf: [32]u8 = undefined;
            const pid_str = try std.fmt.bufPrint(&pid_buf, "{}", .{std.c.getpid()});
            if (filepath.len + pct_count * pid_str.len >= buf.len)
                return Error.FilePathTooLong;
            var ix: usize = 0;
            for (filepath) |ch| {
                if (ch == '%') {
                    for (pid_str) |c| {
                        buf[ix] = c;
                        ix += 1;
                    }
                } else {
                    buf[ix] = ch;
                    ix += 1;
                }
            }
            break :blk buf[0..ix];
        } else blk: {
            break :blk filepath;
        };
    
        if (std.fs.path.isAbsolute(filepath_clean)) {
            self._file = try std.Io.Dir.createFileAbsolute(self.io, filepath_clean, .{});
            if (options.autoclean) {
                self._autoclean = undefined;
                const fp = self._autoclean.?.buffer[0..filepath_clean.len];
                std.mem.copyForwards(u8, fp, filepath_clean);
                if (self._autoclean) |*autoclean| {
                    autoclean.filepath = fp;
                }
            }
        } else {
            self._file = try std.Io.Dir.cwd().createFile(self.io, filepath_clean, .{});
        }
        self._do_close = true;
    
        self.initWriter();
    }
    
    pub fn toStdout(self: *Self) !void {
        try self.closeWriter();
    
        self._file = std.Io.File.stdout();
        self.initWriter();
    }
    pub fn toStderr(self: *Self) !void {
        try self.closeWriter();
    
        self._file = std.Io.File.stderr();
        self.initWriter();
    }
    
    pub fn setLevel(self: *Self, lvl: usize) void {
        self._lvl = lvl;
    }
    
    pub fn writer(self: Self) *std.Io.Writer {
        return self._io;
    }
    
    pub fn print(self: Self, comptime fmtstr: []const u8, args: anytype) !void {
        try self._io.print(fmtstr, args);
        try self._io.flush();
    }
    pub fn info(self: Self, comptime fmtstr: []const u8, args: anytype) !void {
        try self.print("Info: " ++ fmtstr, args);
    }
    pub fn warning(self: Self, comptime fmtstr: []const u8, args: anytype) !void {
        try self.print("Warning: " ++ fmtstr, args);
    }
    pub fn err(self: Self, comptime fmtstr: []const u8, args: anytype) !void {
        try self.print("Error: " ++ fmtstr, args);
    }
    
    pub fn level(self: Self, lvl: usize) ?*std.Io.Writer {
        if (self._lvl >= lvl)
            return self._io;
        return null;
    }
    
    fn initWriter(self: *Self) void {
        self._writer = self._file.writer(self.io, &self._buffer);
        self._io = &self._writer.interface;
    }
    fn closeWriter(self: *Self) !void {
        try self._io.flush();
        if (self._do_close) {
            self._file.close(self.io);
            self._do_close = false;
        }
    }
    
};
