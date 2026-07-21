const std = @import("std");
const utf = @import("utf.zig");
const t = @import("types.zig");

const Range = struct { start: usize, end: usize };

pub const Plan = struct {
    allocator: std.mem.Allocator,
    start_byte: u64,
    old_end_byte: u64,
    replacement: []u8,
    result_selection: t.ByteRange,

    pub fn deinit(self: *Plan) void {
        self.allocator.free(self.replacement);
        self.* = undefined;
    }
};

pub const EditList = struct {
    allocator: std.mem.Allocator,
    edits: []t.PlannedEdit,
    replacement: []u8,
    result_selection: t.ByteRange,

    pub fn fromPlan(allocator: std.mem.Allocator, source_plan: *Plan) !*EditList {
        const list = try allocator.create(EditList);
        errdefer allocator.destroy(list);
        const edits = try allocator.alloc(t.PlannedEdit, 1);
        errdefer allocator.free(edits);
        edits[0] = .{
            .start_byte = source_plan.start_byte,
            .old_end_byte = source_plan.old_end_byte,
            .replacement = .{
                .ptr = if (source_plan.replacement.len == 0) null else source_plan.replacement.ptr,
                .len = source_plan.replacement.len,
            },
        };
        list.* = .{
            .allocator = allocator,
            .edits = edits,
            .replacement = source_plan.replacement,
            .result_selection = source_plan.result_selection,
        };
        source_plan.* = undefined;
        return list;
    }

    pub fn destroy(self: *EditList) void {
        self.allocator.free(self.edits);
        self.allocator.free(self.replacement);
        self.allocator.destroy(self);
    }
};

fn checkedSelection(source: []const u8, selection: t.ByteRange) !Range {
    if (selection.start > selection.end) return error.InvalidArgument;
    if (selection.start > std.math.maxInt(usize) or selection.end > std.math.maxInt(usize)) return error.InvalidArgument;
    const start: usize = @intCast(selection.start);
    const end: usize = @intCast(selection.end);
    if (end > source.len) return error.InvalidArgument;
    if (!utf.isBoundary(source, start) or !utf.isBoundary(source, end)) return error.InvalidBoundary;
    return .{ .start = start, .end = end };
}

fn copyOwned(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    return allocator.dupe(u8, value);
}

fn concat3(allocator: std.mem.Allocator, a: []const u8, b: []const u8, c: []const u8) ![]u8 {
    const first = @addWithOverflow(a.len, b.len);
    if (first[1] != 0) return error.Overflow;
    const total = @addWithOverflow(first[0], c.len);
    if (total[1] != 0) return error.Overflow;
    const out = try allocator.alloc(u8, total[0]);
    @memcpy(out[0..a.len], a);
    @memcpy(out[a.len .. a.len + b.len], b);
    @memcpy(out[a.len + b.len ..], c);
    return out;
}

fn inlineToggle(allocator: std.mem.Allocator, source: []const u8, selection: t.ByteRange, delimiter: []const u8) !Plan {
    const range = try checkedSelection(source, selection);
    const selected = source[range.start..range.end];

    if (selected.len >= delimiter.len * 2 and
        std.mem.startsWith(u8, selected, delimiter) and
        std.mem.endsWith(u8, selected, delimiter))
    {
        const content = selected[delimiter.len .. selected.len - delimiter.len];
        const replacement = try copyOwned(allocator, content);
        return .{
            .allocator = allocator,
            .start_byte = selection.start,
            .old_end_byte = selection.end,
            .replacement = replacement,
            .result_selection = .{ .start = selection.start, .end = selection.start + @as(u64, @intCast(content.len)) },
        };
    }

    if (range.start >= delimiter.len and range.end + delimiter.len <= source.len and
        std.mem.eql(u8, source[range.start - delimiter.len .. range.start], delimiter) and
        std.mem.eql(u8, source[range.end .. range.end + delimiter.len], delimiter))
    {
        const replacement = try copyOwned(allocator, selected);
        const edit_start = range.start - delimiter.len;
        return .{
            .allocator = allocator,
            .start_byte = @intCast(edit_start),
            .old_end_byte = @intCast(range.end + delimiter.len),
            .replacement = replacement,
            .result_selection = .{ .start = @intCast(edit_start), .end = @intCast(edit_start + selected.len) },
        };
    }

    const replacement = try concat3(allocator, delimiter, selected, delimiter);
    return .{
        .allocator = allocator,
        .start_byte = selection.start,
        .old_end_byte = selection.end,
        .replacement = replacement,
        .result_selection = .{
            .start = selection.start + @as(u64, @intCast(delimiter.len)),
            .end = selection.start + @as(u64, @intCast(delimiter.len)) + @as(u64, @intCast(selected.len)),
        },
    };
}

fn maxBacktickRun(value: []const u8) usize {
    var maximum: usize = 0;
    var current: usize = 0;
    for (value) |byte| {
        if (byte == '`') {
            current += 1;
            maximum = @max(maximum, current);
        } else {
            current = 0;
        }
    }
    return maximum;
}

fn inlineCode(allocator: std.mem.Allocator, source: []const u8, selection: t.ByteRange) !Plan {
    const range = try checkedSelection(source, selection);
    const selected = source[range.start..range.end];
    if (selected.len >= 2 and selected[0] == '`' and selected[selected.len - 1] == '`') {
        var open_end: usize = 0;
        while (open_end < selected.len and selected[open_end] == '`') open_end += 1;
        var close_start = selected.len;
        while (close_start > open_end and selected[close_start - 1] == '`') close_start -= 1;
        if (open_end == selected.len - close_start) {
            const content = selected[open_end..close_start];
            const replacement = try copyOwned(allocator, content);
            return .{
                .allocator = allocator,
                .start_byte = selection.start,
                .old_end_byte = selection.end,
                .replacement = replacement,
                .result_selection = .{ .start = selection.start, .end = selection.start + @as(u64, @intCast(content.len)) },
            };
        }
    }

    const run_sum = @addWithOverflow(maxBacktickRun(selected), 1);
    if (run_sum[1] != 0) return error.Overflow;
    const run = run_sum[0];
    const padding: usize = if (selected.len > 0 and (selected[0] == '`' or selected[selected.len - 1] == '`')) 1 else 0;
    const doubled = @mulWithOverflow(run, 2);
    if (doubled[1] != 0) return error.Overflow;
    const padded = @mulWithOverflow(padding, 2);
    if (padded[1] != 0) return error.Overflow;
    const first = @addWithOverflow(doubled[0], padded[0]);
    if (first[1] != 0) return error.Overflow;
    const total = @addWithOverflow(first[0], selected.len);
    if (total[1] != 0) return error.Overflow;

    const replacement = try allocator.alloc(u8, total[0]);
    @memset(replacement[0..run], '`');
    var cursor = run;
    if (padding == 1) {
        replacement[cursor] = ' ';
        cursor += 1;
    }
    @memcpy(replacement[cursor .. cursor + selected.len], selected);
    cursor += selected.len;
    if (padding == 1) {
        replacement[cursor] = ' ';
        cursor += 1;
    }
    @memset(replacement[cursor .. cursor + run], '`');

    return .{
        .allocator = allocator,
        .start_byte = selection.start,
        .old_end_byte = selection.end,
        .replacement = replacement,
        .result_selection = .{
            .start = selection.start + @as(u64, @intCast(run)) + @as(u64, @intCast(padding)),
            .end = selection.start + @as(u64, @intCast(run)) + @as(u64, @intCast(padding)) + @as(u64, @intCast(selected.len)),
        },
    };
}

fn escapedDestinationLength(value: []const u8) !usize {
    var length: usize = 0;
    for (value) |byte| {
        const add: usize = if (byte == '\\' or byte == '(' or byte == ')') 2 else 1;
        const sum = @addWithOverflow(length, add);
        if (sum[1] != 0) return error.Overflow;
        length = sum[0];
    }
    return length;
}

fn writeEscapedDestination(out: []u8, value: []const u8) usize {
    var cursor: usize = 0;
    for (value) |byte| {
        if (byte == '\\' or byte == '(' or byte == ')') {
            out[cursor] = '\\';
            cursor += 1;
        }
        out[cursor] = byte;
        cursor += 1;
    }
    return cursor;
}

fn insertLink(allocator: std.mem.Allocator, source: []const u8, selection: t.ByteRange, argument: []const u8) !Plan {
    const range = try checkedSelection(source, selection);
    if (!utf.validate(argument)) return error.InvalidUtf8;
    if (std.mem.indexOfScalar(u8, argument, '\n') != null or std.mem.indexOfScalar(u8, argument, '\r') != null) return error.InvalidArgument;

    const selected = source[range.start..range.end];
    const label = if (selected.len == 0) "text" else selected;
    const destination_length = try escapedDestinationLength(argument);
    const fixed = @addWithOverflow(label.len, destination_length);
    if (fixed[1] != 0) return error.Overflow;
    const total = @addWithOverflow(fixed[0], 4);
    if (total[1] != 0) return error.Overflow;
    const replacement = try allocator.alloc(u8, total[0]);
    replacement[0] = '[';
    @memcpy(replacement[1 .. 1 + label.len], label);
    var cursor = 1 + label.len;
    replacement[cursor] = ']';
    replacement[cursor + 1] = '(';
    cursor += 2;
    cursor += writeEscapedDestination(replacement[cursor .. cursor + destination_length], argument);
    replacement[cursor] = ')';

    return .{
        .allocator = allocator,
        .start_byte = selection.start,
        .old_end_byte = selection.end,
        .replacement = replacement,
        .result_selection = .{ .start = selection.start + 1, .end = selection.start + 1 + @as(u64, @intCast(label.len)) },
    };
}

fn lineStart(source: []const u8, offset: usize) usize {
    var cursor = @min(offset, source.len);
    while (cursor > 0 and source[cursor - 1] != '\n') cursor -= 1;
    return cursor;
}

fn lineEnd(source: []const u8, offset: usize) usize {
    var cursor = @min(offset, source.len);
    while (cursor < source.len and source[cursor] != '\n' and source[cursor] != '\r') cursor += 1;
    return cursor;
}

fn selectedLineRange(source: []const u8, range: Range) Range {
    const start = lineStart(source, range.start);
    const end_anchor = if (range.end > range.start and range.end > 0 and source[range.end - 1] == '\n') range.end - 1 else range.end;
    return .{ .start = start, .end = lineEnd(source, end_anchor) };
}

fn setHeading(allocator: std.mem.Allocator, source: []const u8, selection: t.ByteRange, level: u32) !Plan {
    if (level > 6) return error.InvalidArgument;
    const range = try checkedSelection(source, selection);
    const start = lineStart(source, range.start);
    const end = lineEnd(source, range.start);
    const line = source[start..end];

    var indentation: usize = 0;
    while (indentation < line.len and line[indentation] == ' ' and indentation < 3) indentation += 1;
    var content_start = indentation;
    var hashes: usize = 0;
    while (content_start < line.len and line[content_start] == '#' and hashes < 6) {
        content_start += 1;
        hashes += 1;
    }
    if (hashes > 0 and content_start < line.len and (line[content_start] == ' ' or line[content_start] == '\t')) {
        while (content_start < line.len and (line[content_start] == ' ' or line[content_start] == '\t')) content_start += 1;
    } else if (hashes > 0 and content_start != line.len) {
        content_start = indentation;
    }

    const prefix_length: usize = if (level == 0) 0 else @as(usize, @intCast(level)) + 1;
    const content = line[content_start..];
    const first = @addWithOverflow(indentation, prefix_length);
    if (first[1] != 0) return error.Overflow;
    const total = @addWithOverflow(first[0], content.len);
    if (total[1] != 0) return error.Overflow;
    const replacement = try allocator.alloc(u8, total[0]);
    @memcpy(replacement[0..indentation], line[0..indentation]);
    var cursor = indentation;
    if (level > 0) {
        @memset(replacement[cursor .. cursor + @as(usize, @intCast(level))], '#');
        cursor += @intCast(level);
        replacement[cursor] = ' ';
        cursor += 1;
    }
    @memcpy(replacement[cursor..], content);

    return .{
        .allocator = allocator,
        .start_byte = @intCast(start),
        .old_end_byte = @intCast(end),
        .replacement = replacement,
        .result_selection = .{
            .start = @intCast(start + indentation + prefix_length),
            .end = @intCast(start + indentation + prefix_length + content.len),
        },
    };
}

fn quotePrefix(source: []const u8, start: usize, end: usize) ?struct { start: usize, end: usize } {
    var cursor = start;
    var indentation: usize = 0;
    while (cursor < end and source[cursor] == ' ' and indentation < 3) : (indentation += 1) cursor += 1;
    if (cursor >= end or source[cursor] != '>') return null;
    const marker_start = cursor;
    cursor += 1;
    if (cursor < end and source[cursor] == ' ') cursor += 1;
    return .{ .start = marker_start, .end = cursor };
}

fn transformBlockQuote(allocator: std.mem.Allocator, source: []const u8, selection: t.ByteRange) !Plan {
    const range = try checkedSelection(source, selection);
    const lines = selectedLineRange(source, range);

    var all_quoted = true;
    var line_start_value = lines.start;
    var line_count: usize = 0;
    var removal: usize = 0;
    while (true) {
        const end = lineEnd(source, line_start_value);
        line_count += 1;
        if (quotePrefix(source, line_start_value, end)) |prefix| {
            removal += prefix.end - prefix.start;
        } else {
            all_quoted = false;
        }
        if (end >= lines.end) break;
        var next = end;
        if (next < lines.end and source[next] == '\r') next += 1;
        if (next < lines.end and source[next] == '\n') next += 1;
        if (next <= line_start_value) break;
        line_start_value = next;
    }

    const original = source[lines.start..lines.end];
    const new_length = if (all_quoted)
        original.len - removal
    else blk: {
        const extra = @mulWithOverflow(line_count, 2);
        if (extra[1] != 0) return error.Overflow;
        const total = @addWithOverflow(original.len, extra[0]);
        if (total[1] != 0) return error.Overflow;
        break :blk total[0];
    };
    const replacement = try allocator.alloc(u8, new_length);

    var input: usize = lines.start;
    var output: usize = 0;
    while (true) {
        const end = lineEnd(source, input);
        if (all_quoted) {
            const prefix = quotePrefix(source, input, end).?;
            @memcpy(replacement[output .. output + prefix.start - input], source[input..prefix.start]);
            output += prefix.start - input;
            @memcpy(replacement[output .. output + end - prefix.end], source[prefix.end..end]);
            output += end - prefix.end;
        } else {
            replacement[output] = '>';
            replacement[output + 1] = ' ';
            output += 2;
            @memcpy(replacement[output .. output + end - input], source[input..end]);
            output += end - input;
        }
        if (end >= lines.end) break;
        var next = end;
        if (next < lines.end and source[next] == '\r') {
            replacement[output] = '\r';
            output += 1;
            next += 1;
        }
        if (next < lines.end and source[next] == '\n') {
            replacement[output] = '\n';
            output += 1;
            next += 1;
        }
        if (next <= input) break;
        input = next;
    }
    std.debug.assert(output == replacement.len);

    return .{
        .allocator = allocator,
        .start_byte = @intCast(lines.start),
        .old_end_byte = @intCast(lines.end),
        .replacement = replacement,
        .result_selection = .{ .start = @intCast(lines.start), .end = @intCast(lines.start + replacement.len) },
    };
}

fn listMarker(line: []const u8) ?struct { start: usize, end: usize, content: usize } {
    var cursor: usize = 0;
    while (cursor < line.len and line[cursor] == ' ' and cursor < 4) cursor += 1;
    const start = cursor;
    if (cursor < line.len and (line[cursor] == '-' or line[cursor] == '+' or line[cursor] == '*')) {
        cursor += 1;
    } else {
        while (cursor < line.len and line[cursor] >= '0' and line[cursor] <= '9' and cursor - start < 10) cursor += 1;
        if (cursor == start or cursor >= line.len or (line[cursor] != '.' and line[cursor] != ')')) return null;
        cursor += 1;
    }
    if (cursor < line.len and line[cursor] != ' ' and line[cursor] != '\t') return null;
    const end = cursor;
    while (cursor < line.len and (line[cursor] == ' ' or line[cursor] == '\t')) cursor += 1;
    return .{ .start = start, .end = end, .content = cursor };
}

fn toggleTask(allocator: std.mem.Allocator, source: []const u8, selection: t.ByteRange) !Plan {
    const range = try checkedSelection(source, selection);
    const start = lineStart(source, range.start);
    const end = lineEnd(source, range.start);
    const line = source[start..end];
    const marker = listMarker(line);

    if (marker) |value| {
        if (value.content + 3 <= line.len and line[value.content] == '[' and line[value.content + 2] == ']' and
            (line[value.content + 1] == ' ' or line[value.content + 1] == 'x' or line[value.content + 1] == 'X'))
        {
            const replacement = try copyOwned(allocator, line);
            replacement[value.content + 1] = if (replacement[value.content + 1] == ' ') 'x' else ' ';
            return .{
                .allocator = allocator,
                .start_byte = @intCast(start),
                .old_end_byte = @intCast(end),
                .replacement = replacement,
                .result_selection = .{ .start = @intCast(start + value.content + 1), .end = @intCast(start + value.content + 2) },
            };
        }

        const prefix = line[0..value.end];
        const content = line[value.content..];
        const replacement = try concat3(allocator, prefix, " [ ] ", content);
        return .{
            .allocator = allocator,
            .start_byte = @intCast(start),
            .old_end_byte = @intCast(end),
            .replacement = replacement,
            .result_selection = .{ .start = @intCast(start + prefix.len + 2), .end = @intCast(start + prefix.len + 3) },
        };
    }

    const replacement = try concat3(allocator, "- [ ] ", line, "");
    return .{
        .allocator = allocator,
        .start_byte = @intCast(start),
        .old_end_byte = @intCast(end),
        .replacement = replacement,
        .result_selection = .{ .start = @intCast(start + 3), .end = @intCast(start + 4) },
    };
}

fn transformIndent(allocator: std.mem.Allocator, source: []const u8, selection: t.ByteRange, width: usize, outdent: bool) !Plan {
    if (width == 0 or width > 16) return error.InvalidArgument;
    const range = try checkedSelection(source, selection);
    const lines = selectedLineRange(source, range);

    var line_count: usize = 0;
    var removed: usize = 0;
    var input = lines.start;
    while (true) {
        const end = lineEnd(source, input);
        line_count += 1;
        if (outdent) {
            var count: usize = 0;
            while (count < width and input + count < end and source[input + count] == ' ') count += 1;
            if (count == 0 and input < end and source[input] == '\t') count = 1;
            removed += count;
        }
        if (end >= lines.end) break;
        var next = end;
        if (next < lines.end and source[next] == '\r') next += 1;
        if (next < lines.end and source[next] == '\n') next += 1;
        if (next <= input) break;
        input = next;
    }

    const original_length = lines.end - lines.start;
    const new_length = if (outdent)
        original_length - removed
    else blk: {
        const extra = @mulWithOverflow(line_count, width);
        if (extra[1] != 0) return error.Overflow;
        const total = @addWithOverflow(original_length, extra[0]);
        if (total[1] != 0) return error.Overflow;
        break :blk total[0];
    };
    const replacement = try allocator.alloc(u8, new_length);

    input = lines.start;
    var output: usize = 0;
    while (true) {
        const end = lineEnd(source, input);
        var content_start = input;
        if (outdent) {
            var count: usize = 0;
            while (count < width and content_start < end and source[content_start] == ' ') {
                count += 1;
                content_start += 1;
            }
            if (count == 0 and content_start < end and source[content_start] == '\t') content_start += 1;
        } else {
            @memset(replacement[output .. output + width], ' ');
            output += width;
        }
        @memcpy(replacement[output .. output + end - content_start], source[content_start..end]);
        output += end - content_start;
        if (end >= lines.end) break;
        var next = end;
        if (next < lines.end and source[next] == '\r') {
            replacement[output] = '\r';
            output += 1;
            next += 1;
        }
        if (next < lines.end and source[next] == '\n') {
            replacement[output] = '\n';
            output += 1;
            next += 1;
        }
        if (next <= input) break;
        input = next;
    }
    std.debug.assert(output == replacement.len);

    return .{
        .allocator = allocator,
        .start_byte = @intCast(lines.start),
        .old_end_byte = @intCast(lines.end),
        .replacement = replacement,
        .result_selection = .{ .start = @intCast(lines.start), .end = @intCast(lines.start + replacement.len) },
    };
}

pub fn plan(
    allocator: std.mem.Allocator,
    source: []const u8,
    command: t.CommandKind,
    selection: t.ByteRange,
    options: ?*const t.CommandOptions,
) !Plan {
    const opts: t.CommandOptions = if (options) |value| value.* else .{
        .struct_size = @sizeOf(t.CommandOptions),
        .flags = 0,
        .value = 0,
        .reserved = 0,
        .argument = .{ .ptr = null, .len = 0 },
    };
    if (options != null and opts.struct_size < @sizeOf(t.CommandOptions)) return error.InvalidArgument;
    if (opts.flags != 0 or opts.reserved != 0) return error.InvalidArgument;
    const argument = opts.argument.slice() orelse return error.InvalidArgument;

    return switch (command) {
        .toggle_emphasis => inlineToggle(allocator, source, selection, "*"),
        .toggle_strong => inlineToggle(allocator, source, selection, "**"),
        .toggle_strikethrough => inlineToggle(allocator, source, selection, "~~"),
        .inline_code => inlineCode(allocator, source, selection),
        .insert_link => insertLink(allocator, source, selection, argument),
        .set_heading => setHeading(allocator, source, selection, opts.value),
        .toggle_block_quote => transformBlockQuote(allocator, source, selection),
        .toggle_task_item => toggleTask(allocator, source, selection),
        .indent_list_item => transformIndent(allocator, source, selection, @intCast(if (opts.value == 0) 2 else opts.value), false),
        .outdent_list_item => transformIndent(allocator, source, selection, @intCast(if (opts.value == 0) 2 else opts.value), true),
    };
}

test "inline formatting commands wrap and unwrap selections" {
    var wrapped = try plan(std.testing.allocator, "hello", .toggle_strong, .{ .start = 0, .end = 5 }, null);
    defer wrapped.deinit();
    try std.testing.expectEqualStrings("**hello**", wrapped.replacement);
    try std.testing.expectEqual(@as(u64, 2), wrapped.result_selection.start);
    try std.testing.expectEqual(@as(u64, 7), wrapped.result_selection.end);

    var unwrapped = try plan(std.testing.allocator, "**hello**", .toggle_strong, .{ .start = 0, .end = 9 }, null);
    defer unwrapped.deinit();
    try std.testing.expectEqualStrings("hello", unwrapped.replacement);
}

test "block commands produce source edits without mutating input" {
    const heading_options: t.CommandOptions = .{
        .struct_size = @sizeOf(t.CommandOptions),
        .flags = 0,
        .value = 3,
        .reserved = 0,
        .argument = .{ .ptr = null, .len = 0 },
    };
    var heading = try plan(std.testing.allocator, "Title\n", .set_heading, .{ .start = 0, .end = 5 }, &heading_options);
    defer heading.deinit();
    try std.testing.expectEqualStrings("### Title", heading.replacement);

    var quote = try plan(std.testing.allocator, "a\nb", .toggle_block_quote, .{ .start = 0, .end = 3 }, null);
    defer quote.deinit();
    try std.testing.expectEqualStrings("> a\n> b", quote.replacement);

    var task = try plan(std.testing.allocator, "- item", .toggle_task_item, .{ .start = 0, .end = 0 }, null);
    defer task.deinit();
    try std.testing.expectEqualStrings("- [ ] item", task.replacement);
}

test "link and inline code commands escape delimiters safely" {
    const destination = "https://example.com/a(b)";
    const options: t.CommandOptions = .{
        .struct_size = @sizeOf(t.CommandOptions),
        .flags = 0,
        .value = 0,
        .reserved = 0,
        .argument = .{ .ptr = destination.ptr, .len = destination.len },
    };
    var link = try plan(std.testing.allocator, "site", .insert_link, .{ .start = 0, .end = 4 }, &options);
    defer link.deinit();
    try std.testing.expectEqualStrings("[site](https://example.com/a\\(b\\))", link.replacement);

    var code = try plan(std.testing.allocator, "a`b", .inline_code, .{ .start = 0, .end = 3 }, null);
    defer code.deinit();
    try std.testing.expectEqualStrings("``a`b``", code.replacement);
}

test "indent and outdent commands operate on complete selected lines" {
    var indented = try plan(std.testing.allocator, "- a\n- b", .indent_list_item, .{ .start = 0, .end = 7 }, null);
    defer indented.deinit();
    try std.testing.expectEqualStrings("  - a\n  - b", indented.replacement);

    var outdented = try plan(std.testing.allocator, "  - a\n\t- b", .outdent_list_item, .{ .start = 0, .end = 10 }, null);
    defer outdented.deinit();
    try std.testing.expectEqualStrings("- a\n- b", outdented.replacement);
}

test "command planning rejects invalid UTF-8 boundaries and options" {
    try std.testing.expectError(error.InvalidBoundary, plan(
        std.testing.allocator,
        "é",
        .toggle_emphasis,
        .{ .start = 1, .end = 2 },
        null,
    ));

    const invalid_options: t.CommandOptions = .{
        .struct_size = @sizeOf(t.CommandOptions),
        .flags = 1,
        .value = 0,
        .reserved = 0,
        .argument = .{ .ptr = null, .len = 0 },
    };
    try std.testing.expectError(error.InvalidArgument, plan(
        std.testing.allocator,
        "text",
        .toggle_strong,
        .{ .start = 0, .end = 4 },
        &invalid_options,
    ));
}

test "edit list owns command replacement memory" {
    var command_plan = try plan(std.testing.allocator, "text", .toggle_emphasis, .{ .start = 0, .end = 4 }, null);
    const list = try EditList.fromPlan(std.testing.allocator, &command_plan);
    defer list.destroy();
    try std.testing.expectEqual(@as(usize, 1), list.edits.len);
    try std.testing.expectEqualStrings("*text*", list.edits[0].replacement.slice().?);
}
