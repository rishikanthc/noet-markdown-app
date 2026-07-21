const std = @import("std");

pub const SourceMap = struct {
    line_starts: []u64,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) !SourceMap {
        var line_count: usize = 1;
        var cursor: usize = 0;
        while (cursor < source.len) {
            if (source[cursor] == '\r') {
                line_count += 1;
                cursor += 1;
                if (cursor < source.len and source[cursor] == '\n') cursor += 1;
            } else if (source[cursor] == '\n') {
                line_count += 1;
                cursor += 1;
            } else {
                cursor += 1;
            }
        }

        const starts = try allocator.alloc(u64, line_count);
        starts[0] = 0;
        var index: usize = 1;
        cursor = 0;
        while (cursor < source.len) {
            if (source[cursor] == '\r') {
                cursor += 1;
                if (cursor < source.len and source[cursor] == '\n') cursor += 1;
                starts[index] = @intCast(cursor);
                index += 1;
            } else if (source[cursor] == '\n') {
                cursor += 1;
                starts[index] = @intCast(cursor);
                index += 1;
            } else {
                cursor += 1;
            }
        }
        std.debug.assert(index == starts.len);
        return .{ .line_starts = starts };
    }

    pub fn deinit(self: *SourceMap, allocator: std.mem.Allocator) void {
        allocator.free(self.line_starts);
        self.* = undefined;
    }

    pub fn positionToByte(self: SourceMap, source: []const u8, line_one_based: c_int, column_one_based: c_int, end_inclusive: bool) u64 {
        if (line_one_based <= 0 or column_one_based <= 0) return 0;
        const line_index: usize = @intCast(line_one_based - 1);
        if (line_index >= self.line_starts.len) return @intCast(source.len);

        const start: usize = @intCast(self.line_starts[line_index]);
        const next = if (line_index + 1 < self.line_starts.len)
            @as(usize, @intCast(self.line_starts[line_index + 1]))
        else
            source.len;
        const content_end = trimLineEnding(source, start, next);
        const column: usize = @intCast(column_one_based - 1);
        const offset_sum = @addWithOverflow(start, column);
        const unclamped = if (offset_sum[1] == 0) offset_sum[0] else std.math.maxInt(usize);
        var offset = @min(unclamped, content_end);
        if (end_inclusive and offset < content_end) offset += 1;
        return @intCast(offset);
    }
};

fn trimLineEnding(source: []const u8, start: usize, next: usize) usize {
    var end = next;
    if (end > start and source[end - 1] == '\n') end -= 1;
    if (end > start and source[end - 1] == '\r') end -= 1;
    return end;
}

test "line and byte-column mapping supports LF CRLF and CR" {
    const source = "alpha\nβeta\r\ngamma\rdelta";
    var map = try SourceMap.init(std.testing.allocator, source);
    defer map.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 4), map.line_starts.len);
    try std.testing.expectEqual(@as(u64, 0), map.positionToByte(source, 1, 1, false));
    try std.testing.expectEqual(@as(u64, 6), map.positionToByte(source, 2, 1, false));
    try std.testing.expectEqual(@as(u64, 8), map.positionToByte(source, 2, 3, false));
    try std.testing.expectEqual(@as(u64, 13), map.positionToByte(source, 3, 1, false));
    try std.testing.expectEqual(@as(u64, 19), map.positionToByte(source, 4, 1, false));
    try std.testing.expectEqual(@as(u64, 24), map.positionToByte(source, 4, 99, false));
}
