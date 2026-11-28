const std = @import("std");
const Range = @import("Options.zig").Range;

pub fn setState(
    a: std.mem.Allocator,
    content: []const u8,
    state: []const u8,
    line_number: ?usize,
    ranges: []Range,
    helix_ranges: bool,
) !?[]u8 {
    if (line_number == null and ranges.len == 0) return null;

    if (line_number == null) {
        const length = if (helix_ranges) try std.unicode.utf8CountCodepoints(content) else content.len;
        for (ranges) |*range| {
            if (range.start == length and range.start > 0 and range.size == 0)
                range.start -= 1;
            if (range.start >= length) return error.RangeOutsideFile;
        }
        std.mem.sort(Range, ranges, {}, rangeStartsBefore);
    }

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(a);
    var remaining = ranges;
    var found_line = false;
    var start: usize = 0;
    var range_end: usize = 0;
    var selection_end: usize = 0;
    var number: usize = 1;
    var separator: u8 = '\n';

    while (start < content.len) : (number += 1) {
        var newline = std.mem.indexOfScalarPos(u8, content, start, separator);
        if (newline == null and separator == '\n') {
            separator = '\r';
            newline = std.mem.indexOfScalarPos(u8, content, start, separator);
        }
        const end = if (newline) |index| index + 1 else content.len;
        var selected = false;
        if (line_number) |target| {
            selected = number == target;
        } else {
            const range_start = range_end;
            range_end = if (helix_ranges)
                range_end + try std.unicode.utf8CountCodepoints(content[start..end])
            else
                end;
            while (remaining.len != 0 and remaining[0].start < range_end) {
                const range = remaining[0];
                selected = true;
                if (helix_ranges)
                    selection_end = @max(selection_end, range.start +| range.size);
                remaining = remaining[1..];
            }
            // Carry overlapping Helix selections into later lines.
            selected = selected or selection_end > range_start;
        }

        if (selected) {
            found_line = true;
            var body_end = newline orelse end;
            if (separator == '\n' and body_end > start and content[body_end - 1] == '\r') body_end -= 1;
            try appendUpdatedLine(a, &output, content[start..body_end], state);
            try output.appendSlice(a, content[body_end..end]);
        } else {
            try output.appendSlice(a, content[start..end]);
        }
        start = end;
    }

    if (!found_line) return error.LineOutsideFile;
    return try output.toOwnedSlice(a);
}

fn rangeStartsBefore(_: void, lhs: Range, rhs: Range) bool {
    return lhs.start < rhs.start;
}

test "Helix selections update every overlapping line once" {
    const a = std.testing.allocator;
    const content = "é first\r\n- second\r\n# third\r\n- fourth\r\nlast";
    var ranges = [_]Range{
        .{ .start = 12, .size = 1 },
        .{ .start = 2, .size = 26 },
        .{ .start = 38, .size = 0 },
    };
    const updated = (try setState(a, content, "CUSTOM", null, &ranges, true)).?;
    defer a.free(updated);
    try std.testing.expectEqualStrings(
        "CUSTOM é first\r\n- CUSTOM second\r\n# CUSTOM third\r\n- fourth\r\nCUSTOM last",
        updated,
    );
}

const states = [_]struct { name: []const u8, bullet: ?[]const u8 }{
    .{ .name = "TODO", .bullet = "[ ]" },
    .{ .name = "NEXT", .bullet = null },
    .{ .name = "GO", .bullet = "[*]" },
    .{ .name = "WIP", .bullet = "[/]" },
    .{ .name = "DONE", .bullet = "[x]" },
    .{ .name = "QUESTION", .bullet = "[?]" },
    .{ .name = "INFO", .bullet = "[i]" },
    .{ .name = "BLOCKED", .bullet = "[!]" },
    .{ .name = "HANDLED", .bullet = "[>]" },
    .{ .name = "PLANNED", .bullet = "[<]" },
    .{ .name = "ASSIGNED", .bullet = "[~]" },
    .{ .name = "CANCELED", .bullet = "[-]" },
};

fn appendUpdatedLine(a: std.mem.Allocator, output: *std.ArrayList(u8), line: []const u8, state: []const u8) !void {
    const heading = std.mem.trimStart(u8, line, "#");
    const item = std.mem.trimStart(u8, line, " \t");
    const is_bullet = std.mem.startsWith(u8, item, "- ") or std.mem.startsWith(u8, item, "* ");
    const body = if (heading.len < line.len and std.mem.startsWith(u8, heading, " "))
        heading[1..]
    else if (is_bullet)
        item[2..]
    else
        line;

    try output.appendSlice(a, line[0 .. line.len - body.len]);
    const rest = stripState(body);
    if (!std.mem.eql(u8, state, "-")) {
        var marker = state;
        if (is_bullet) {
            for (states) |entry| {
                if (std.mem.eql(u8, entry.name, state)) {
                    marker = entry.bullet orelse state;
                    break;
                }
            }
        }
        try output.appendSlice(a, marker);
        if (rest.len != 0 and marker[marker.len - 1] != ' ') try output.append(a, ' ');
    }
    try output.appendSlice(a, rest);
}

fn stripState(body: []const u8) []const u8 {
    if (body.len >= 2 and body[0] == '[') {
        const close: usize = if (body[1] == ']') 1 else 2;
        if (close < body.len and body[close] == ']') {
            const end = close + 1;
            if (end == body.len) return body[end..];
            if (body[end] == ' ') return body[end + 1 ..];
        }
    }
    for (states) |entry| {
        if (!std.mem.startsWith(u8, body, entry.name)) continue;
        const end = entry.name.len;
        if (end == body.len) return body[end..];
        if (body[end] == ' ') return body[end + 1 ..];
    }
    return body;
}
