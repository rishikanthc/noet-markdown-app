const std = @import("std");
const t = @import("types.zig");

const marker_behavior: u16 = t.span_dim_when_inactive | t.span_reveal_at_caret;

const Sink = struct {
    out: ?[]t.DecorationSpan,
    index: usize = 0,

    fn emit(self: *Sink, node_id: u64, start: usize, end: usize, role: t.SpanRole, behavior: u16) void {
        if (end <= start) return;
        if (self.out) |buffer| {
            std.debug.assert(self.index < buffer.len);
            buffer[self.index] = .{
                .node_id = node_id,
                .start_byte = @intCast(start),
                .end_byte = @intCast(end),
                .role = @intFromEnum(role),
                .behavior = behavior,
                .metadata_index = std.math.maxInt(u32),
            };
        }
        self.index += 1;
    }
};

fn clampOffset(source: []const u8, value: u64) usize {
    const source_len: u64 = @intCast(source.len);
    return @intCast(@min(value, source_len));
}

fn boundedRange(source: []const u8, node: t.SemanticNode) struct { start: usize, end: usize } {
    const start = clampOffset(source, node.source_start_byte);
    const end = clampOffset(source, @max(node.source_end_byte, node.source_start_byte));
    return .{ .start = start, .end = @max(start, end) };
}

fn lineEnd(source: []const u8, start: usize, limit: usize) usize {
    var cursor = start;
    while (cursor < limit and source[cursor] != '\n' and source[cursor] != '\r') cursor += 1;
    return cursor;
}

fn nextLineStart(source: []const u8, end: usize, limit: usize) usize {
    var cursor = end;
    if (cursor < limit and source[cursor] == '\r') cursor += 1;
    if (cursor < limit and source[cursor] == '\n') cursor += 1;
    return cursor;
}

fn isAsciiSpace(byte: u8) bool {
    return byte == ' ' or byte == '\t';
}

fn skipAsciiSpace(source: []const u8, start: usize, end: usize) usize {
    var cursor = start;
    while (cursor < end and isAsciiSpace(source[cursor])) cursor += 1;
    return cursor;
}

fn trimAsciiSpaceRight(source: []const u8, start: usize, end: usize) usize {
    var cursor = end;
    while (cursor > start and isAsciiSpace(source[cursor - 1])) cursor -= 1;
    return cursor;
}

fn startsWithAt(source: []const u8, start: usize, end: usize, needle: []const u8) bool {
    if (start > end or needle.len > end - start) return false;
    return std.mem.eql(u8, source[start .. start + needle.len], needle);
}

fn endsWithAt(source: []const u8, start: usize, end: usize, needle: []const u8) bool {
    if (start > end or needle.len > end - start) return false;
    return std.mem.eql(u8, source[end - needle.len .. end], needle);
}

fn findUnescaped(source: []const u8, start: usize, end: usize, needle: u8) ?usize {
    var cursor = start;
    while (cursor < end) : (cursor += 1) {
        if (source[cursor] != needle) continue;
        var slashes: usize = 0;
        var back = cursor;
        while (back > start and source[back - 1] == '\\') {
            slashes += 1;
            back -= 1;
        }
        if ((slashes & 1) == 0) return cursor;
    }
    return null;
}

fn refineDelimited(source: []const u8, node: *t.SemanticNode, delimiters: []const []const u8) void {
    const range = boundedRange(source, node.*);
    for (delimiters) |delimiter| {
        if (startsWithAt(source, range.start, range.end, delimiter) and endsWithAt(source, range.start, range.end, delimiter) and range.end - range.start >= delimiter.len * 2) {
            node.content_start_byte = @intCast(range.start + delimiter.len);
            node.content_end_byte = @intCast(range.end - delimiter.len);
            return;
        }
    }
}

fn refineHeading(source: []const u8, node: *t.SemanticNode) void {
    const range = boundedRange(source, node.*);
    const end = lineEnd(source, range.start, range.end);
    var cursor = range.start;
    var indentation: usize = 0;
    while (cursor < end and source[cursor] == ' ' and indentation < 3) : (indentation += 1) cursor += 1;
    const marker_start = cursor;
    while (cursor < end and source[cursor] == '#' and cursor - marker_start < 6) cursor += 1;
    if (cursor == marker_start) {
        const underline_start = nextLineStart(source, end, range.end);
        if (underline_start >= range.end) return;
        const underline_end = lineEnd(source, underline_start, range.end);
        var marker_cursor = skipAsciiSpace(source, underline_start, underline_end);
        if (marker_cursor >= underline_end or (source[marker_cursor] != '=' and source[marker_cursor] != '-')) return;
        const marker = source[marker_cursor];
        while (marker_cursor < underline_end and source[marker_cursor] == marker) marker_cursor += 1;
        if (trimAsciiSpaceRight(source, marker_cursor, underline_end) != marker_cursor) return;
        node.content_start_byte = @intCast(range.start);
        node.content_end_byte = @intCast(trimAsciiSpaceRight(source, range.start, end));
        return;
    }
    if (cursor < end and !isAsciiSpace(source[cursor])) return;
    cursor = skipAsciiSpace(source, cursor, end);
    var content_end = trimAsciiSpaceRight(source, cursor, end);
    if (content_end > cursor) {
        var hashes = content_end;
        while (hashes > cursor and source[hashes - 1] == '#') hashes -= 1;
        if (hashes < content_end and hashes > cursor and isAsciiSpace(source[hashes - 1])) {
            content_end = trimAsciiSpaceRight(source, cursor, hashes - 1);
        }
    }
    node.content_start_byte = @intCast(cursor);
    node.content_end_byte = @intCast(content_end);
}

fn codeFence(source: []const u8, start: usize, end: usize) ?struct { marker_start: usize, marker_end: usize, line_end: usize, char: u8 } {
    const first_end = lineEnd(source, start, end);
    var cursor = start;
    var indentation: usize = 0;
    while (cursor < first_end and source[cursor] == ' ' and indentation < 3) : (indentation += 1) cursor += 1;
    if (cursor >= first_end or (source[cursor] != '`' and source[cursor] != '~')) return null;
    const char = source[cursor];
    const marker_start = cursor;
    while (cursor < first_end and source[cursor] == char) cursor += 1;
    if (cursor - marker_start < 3) return null;
    return .{ .marker_start = marker_start, .marker_end = cursor, .line_end = first_end, .char = char };
}

const ClosingFence = struct { start: usize, marker_start: usize, marker_end: usize, line_end: usize };

fn closingFence(source: []const u8, content_start: usize, end: usize, char: u8, min_len: usize) ?ClosingFence {
    var line_start = content_start;
    var found: ?ClosingFence = null;
    while (line_start < end) {
        const end_line = lineEnd(source, line_start, end);
        var cursor = line_start;
        var indentation: usize = 0;
        while (cursor < end_line and source[cursor] == ' ' and indentation < 3) : (indentation += 1) cursor += 1;
        const marker_start = cursor;
        while (cursor < end_line and source[cursor] == char) cursor += 1;
        if (cursor - marker_start >= min_len and trimAsciiSpaceRight(source, cursor, end_line) == cursor) {
            found = .{ .start = line_start, .marker_start = marker_start, .marker_end = cursor, .line_end = end_line };
        }
        const next = nextLineStart(source, end_line, end);
        if (next <= line_start) break;
        line_start = next;
    }
    return found;
}

fn refineCodeBlock(source: []const u8, node: *t.SemanticNode) void {
    const range = boundedRange(source, node.*);
    const opening = codeFence(source, range.start, range.end) orelse return;
    const content_start = nextLineStart(source, opening.line_end, range.end);
    const close = closingFence(source, content_start, range.end, opening.char, opening.marker_end - opening.marker_start);
    node.content_start_byte = @intCast(content_start);
    node.content_end_byte = @intCast(if (close) |value| value.start else range.end);
}

fn refineCodeSpan(source: []const u8, node: *t.SemanticNode) void {
    const range = boundedRange(source, node.*);
    if (range.start >= range.end or source[range.start] != '`') return;
    var open_end = range.start;
    while (open_end < range.end and source[open_end] == '`') open_end += 1;
    const run = open_end - range.start;
    if (run == 0 or range.end - range.start < run * 2) return;
    var close_start = range.end;
    while (close_start > open_end and source[close_start - 1] == '`') close_start -= 1;
    if (range.end - close_start != run) return;
    node.content_start_byte = @intCast(open_end);
    node.content_end_byte = @intCast(close_start);
}

fn linkParts(source: []const u8, node: t.SemanticNode) ?struct {
    image_mark: ?usize,
    open_label: usize,
    close_label: usize,
    open_destination: ?usize,
    destination_start: ?usize,
    destination_end: ?usize,
    close_destination: ?usize,
} {
    const range = boundedRange(source, node);
    var cursor = range.start;
    var image_mark: ?usize = null;
    if (cursor < range.end and source[cursor] == '!') {
        image_mark = cursor;
        cursor += 1;
    }
    if (cursor >= range.end or source[cursor] != '[') return null;
    const open_label = cursor;
    const close_label = findUnescaped(source, cursor + 1, range.end, ']') orelse return null;
    cursor = close_label + 1;
    if (cursor < range.end and source[cursor] == '(') {
        const close_destination = findUnescaped(source, cursor + 1, range.end, ')') orelse return .{
            .image_mark = image_mark,
            .open_label = open_label,
            .close_label = close_label,
            .open_destination = cursor,
            .destination_start = cursor + 1,
            .destination_end = range.end,
            .close_destination = null,
        };
        var destination_start = skipAsciiSpace(source, cursor + 1, close_destination);
        var destination_end = trimAsciiSpaceRight(source, destination_start, close_destination);
        if (destination_start < destination_end and source[destination_start] == '<' and source[destination_end - 1] == '>') {
            destination_start += 1;
            destination_end -= 1;
        } else {
            var split = destination_start;
            while (split < destination_end and !isAsciiSpace(source[split])) split += 1;
            destination_end = split;
        }
        return .{
            .image_mark = image_mark,
            .open_label = open_label,
            .close_label = close_label,
            .open_destination = cursor,
            .destination_start = destination_start,
            .destination_end = destination_end,
            .close_destination = close_destination,
        };
    }
    return .{
        .image_mark = image_mark,
        .open_label = open_label,
        .close_label = close_label,
        .open_destination = null,
        .destination_start = null,
        .destination_end = null,
        .close_destination = null,
    };
}

fn refineLink(source: []const u8, node: *t.SemanticNode) void {
    if (linkParts(source, node.*)) |parts| {
        node.content_start_byte = @intCast(parts.open_label + 1);
        node.content_end_byte = @intCast(parts.close_label);
        return;
    }
    const range = boundedRange(source, node.*);
    if (range.end - range.start >= 2 and source[range.start] == '<' and source[range.end - 1] == '>') {
        node.content_start_byte = @intCast(range.start + 1);
        node.content_end_byte = @intCast(range.end - 1);
    }
}

fn listMarker(source: []const u8, node: t.SemanticNode) ?struct { start: usize, end: usize } {
    const range = boundedRange(source, node);
    const end = lineEnd(source, range.start, range.end);
    var cursor = range.start;
    var indentation: usize = 0;
    while (cursor < end and source[cursor] == ' ' and indentation < 4) : (indentation += 1) cursor += 1;
    const start = cursor;
    if (cursor < end and (source[cursor] == '-' or source[cursor] == '+' or source[cursor] == '*')) {
        cursor += 1;
        if (cursor == end or isAsciiSpace(source[cursor])) return .{ .start = start, .end = cursor };
        return null;
    }
    while (cursor < end and source[cursor] >= '0' and source[cursor] <= '9' and cursor - start < 10) cursor += 1;
    if (cursor == start or cursor >= end or (source[cursor] != '.' and source[cursor] != ')')) return null;
    cursor += 1;
    if (cursor == end or isAsciiSpace(source[cursor])) return .{ .start = start, .end = cursor };
    return null;
}

fn taskMarker(source: []const u8, marker_end: usize, line_end_value: usize) ?struct { start: usize, end: usize } {
    const cursor = skipAsciiSpace(source, marker_end, line_end_value);
    if (cursor + 3 > line_end_value or source[cursor] != '[' or source[cursor + 2] != ']') return null;
    const state = source[cursor + 1];
    if (state != ' ' and state != 'x' and state != 'X') return null;
    return .{ .start = cursor, .end = cursor + 3 };
}

pub fn refineNodes(source: []const u8, nodes: []t.SemanticNode) void {
    for (nodes) |*node| {
        node.content_start_byte = node.source_start_byte;
        node.content_end_byte = node.source_end_byte;
        const kind = node.kind;
        if (kind == @intFromEnum(t.NodeKind.heading)) {
            refineHeading(source, node);
        } else if (kind == @intFromEnum(t.NodeKind.emphasis)) {
            const delimiters = [_][]const u8{ "*", "_" };
            refineDelimited(source, node, &delimiters);
        } else if (kind == @intFromEnum(t.NodeKind.strong)) {
            const delimiters = [_][]const u8{ "**", "__" };
            refineDelimited(source, node, &delimiters);
        } else if (kind == @intFromEnum(t.NodeKind.strikethrough)) {
            const delimiters = [_][]const u8{"~~"};
            refineDelimited(source, node, &delimiters);
        } else if (kind == @intFromEnum(t.NodeKind.code_span)) {
            refineCodeSpan(source, node);
        } else if (kind == @intFromEnum(t.NodeKind.code_block)) {
            refineCodeBlock(source, node);
        } else if (kind == @intFromEnum(t.NodeKind.link) or kind == @intFromEnum(t.NodeKind.image)) {
            refineLink(source, node);
        } else if (kind == @intFromEnum(t.NodeKind.task_list_item)) {
            if (listMarker(source, node.*)) |marker| {
                const end = lineEnd(source, marker.end, clampOffset(source, node.source_end_byte));
                if (taskMarker(source, marker.end, end)) |task| {
                    node.content_start_byte = @intCast(skipAsciiSpace(source, task.end, end));
                }
            }
        }
    }
}

fn emitDelimitedMarkers(sink: *Sink, node: t.SemanticNode) void {
    const start: usize = @intCast(node.source_start_byte);
    const end: usize = @intCast(node.source_end_byte);
    const content_start: usize = @intCast(node.content_start_byte);
    const content_end: usize = @intCast(node.content_end_byte);
    if (content_start > start) sink.emit(node.id, start, content_start, .syntax_marker, marker_behavior);
    if (end > content_end) sink.emit(node.id, content_end, end, .syntax_marker, marker_behavior);
}

fn emitHeading(sink: *Sink, source: []const u8, node: t.SemanticNode) void {
    const range = boundedRange(source, node);
    const end_line = lineEnd(source, range.start, range.end);
    var cursor = range.start;
    var indentation: usize = 0;
    while (cursor < end_line and source[cursor] == ' ' and indentation < 3) : (indentation += 1) cursor += 1;
    const opening_start = cursor;
    while (cursor < end_line and source[cursor] == '#' and cursor - opening_start < 6) cursor += 1;
    if (cursor > opening_start) {
        sink.emit(node.id, opening_start, cursor, .syntax_marker, marker_behavior);
    } else {
        const underline_start = nextLineStart(source, end_line, range.end);
        if (underline_start < range.end) {
            const underline_end = lineEnd(source, underline_start, range.end);
            sink.emit(node.id, underline_start, underline_end, .syntax_marker, marker_behavior);
        }
        return;
    }

    const content_end = clampOffset(source, node.content_end_byte);
    cursor = skipAsciiSpace(source, content_end, end_line);
    const closing_start = cursor;
    while (cursor < end_line and source[cursor] == '#') cursor += 1;
    if (cursor > closing_start and trimAsciiSpaceRight(source, cursor, end_line) == cursor) {
        sink.emit(node.id, closing_start, cursor, .syntax_marker, marker_behavior);
    }
}

fn emitCodeBlock(sink: *Sink, source: []const u8, node: t.SemanticNode) void {
    const range = boundedRange(source, node);
    const opening = codeFence(source, range.start, range.end) orelse return;
    sink.emit(node.id, opening.marker_start, opening.marker_end, .code_fence, marker_behavior | t.span_monospaced);
    const info_start = skipAsciiSpace(source, opening.marker_end, opening.line_end);
    const info_end = trimAsciiSpaceRight(source, info_start, opening.line_end);
    if (info_end > info_start) sink.emit(node.id, info_start, info_end, .code_language, t.span_monospaced | t.span_no_spellcheck);
    const content_start = nextLineStart(source, opening.line_end, range.end);
    if (closingFence(source, content_start, range.end, opening.char, opening.marker_end - opening.marker_start)) |close| {
        sink.emit(node.id, close.marker_start, close.marker_end, .code_fence, marker_behavior | t.span_monospaced);
    }
}

fn emitLink(sink: *Sink, source: []const u8, node: t.SemanticNode, is_image: bool) void {
    const parts = linkParts(source, node) orelse {
        const range = boundedRange(source, node);
        if (!is_image and range.end - range.start >= 2 and source[range.start] == '<' and source[range.end - 1] == '>') {
            sink.emit(node.id, range.start, range.start + 1, .syntax_marker, marker_behavior);
            sink.emit(node.id, range.end - 1, range.end, .syntax_marker, marker_behavior);
        }
        return;
    };
    if (parts.image_mark) |mark| sink.emit(node.id, mark, mark + 1, .syntax_marker, marker_behavior);
    sink.emit(node.id, parts.open_label, parts.open_label + 1, .syntax_marker, marker_behavior);
    sink.emit(node.id, parts.close_label, parts.close_label + 1, .syntax_marker, marker_behavior);
    if (parts.open_destination) |open| sink.emit(node.id, open, open + 1, .syntax_marker, marker_behavior);
    if (parts.destination_start) |start| {
        if (parts.destination_end) |end| {
            sink.emit(node.id, start, end, if (is_image) .image_destination else .link_destination, t.span_interactive | t.span_no_spellcheck);
        }
    }
    if (parts.close_destination) |close| sink.emit(node.id, close, close + 1, .syntax_marker, marker_behavior);
}

fn emitBlockQuote(sink: *Sink, source: []const u8, node: t.SemanticNode) void {
    const range = boundedRange(source, node);
    var start = range.start;
    while (start < range.end) {
        const end = lineEnd(source, start, range.end);
        var cursor = start;
        var indentation: usize = 0;
        while (cursor < end and source[cursor] == ' ' and indentation < 3) : (indentation += 1) cursor += 1;
        if (cursor < end and source[cursor] == '>') {
            const marker_end = if (cursor + 1 < end and source[cursor + 1] == ' ') cursor + 2 else cursor + 1;
            sink.emit(node.id, cursor, marker_end, .block_quote_marker, marker_behavior);
        }
        const next = nextLineStart(source, end, range.end);
        if (next <= start) break;
        start = next;
    }
}

fn emitListItem(sink: *Sink, source: []const u8, node: t.SemanticNode, task: bool) void {
    const marker = listMarker(source, node) orelse return;
    sink.emit(node.id, marker.start, marker.end, .list_marker, marker_behavior);
    if (task) {
        const range = boundedRange(source, node);
        const end = lineEnd(source, marker.end, range.end);
        if (taskMarker(source, marker.end, end)) |checkbox| {
            sink.emit(node.id, checkbox.start, checkbox.end, .task_marker, marker_behavior | t.span_interactive);
        }
    }
}

fn emitTable(sink: *Sink, source: []const u8, node: t.SemanticNode) void {
    const range = boundedRange(source, node);
    var cursor = range.start;
    while (cursor < range.end) : (cursor += 1) {
        if (source[cursor] != '|') continue;
        var slashes: usize = 0;
        var back = cursor;
        while (back > range.start and source[back - 1] == '\\') {
            slashes += 1;
            back -= 1;
        }
        if ((slashes & 1) == 0) sink.emit(node.id, cursor, cursor + 1, .table_delimiter, marker_behavior);
    }

    var line_start_value = range.start;
    var line_number: usize = 0;
    while (line_start_value < range.end) : (line_number += 1) {
        const end = lineEnd(source, line_start_value, range.end);
        if (line_number == 1) {
            var has_dash = false;
            var valid = true;
            for (source[line_start_value..end]) |byte| {
                if (byte == '-') has_dash = true else if (byte != ':' and byte != '|' and !isAsciiSpace(byte)) valid = false;
            }
            if (has_dash and valid) sink.emit(node.id, line_start_value, end, .table_delimiter, marker_behavior);
        }
        const next = nextLineStart(source, end, range.end);
        if (next <= line_start_value) break;
        line_start_value = next;
    }
}

fn locate(source: []const u8, nodes: []const t.SemanticNode, sink: *Sink) void {
    for (nodes) |node| {
        const kind = node.kind;
        if (kind == @intFromEnum(t.NodeKind.heading)) {
            emitHeading(sink, source, node);
        } else if (kind == @intFromEnum(t.NodeKind.emphasis) or
            kind == @intFromEnum(t.NodeKind.strong) or
            kind == @intFromEnum(t.NodeKind.strikethrough) or
            kind == @intFromEnum(t.NodeKind.code_span))
        {
            emitDelimitedMarkers(sink, node);
        } else if (kind == @intFromEnum(t.NodeKind.code_block)) {
            emitCodeBlock(sink, source, node);
        } else if (kind == @intFromEnum(t.NodeKind.link)) {
            emitLink(sink, source, node, false);
        } else if (kind == @intFromEnum(t.NodeKind.image)) {
            emitLink(sink, source, node, true);
        } else if (kind == @intFromEnum(t.NodeKind.block_quote)) {
            emitBlockQuote(sink, source, node);
        } else if (kind == @intFromEnum(t.NodeKind.list_item)) {
            emitListItem(sink, source, node, false);
        } else if (kind == @intFromEnum(t.NodeKind.task_list_item)) {
            emitListItem(sink, source, node, true);
        } else if (kind == @intFromEnum(t.NodeKind.table)) {
            emitTable(sink, source, node);
        } else if (kind == @intFromEnum(t.NodeKind.thematic_break)) {
            const range = boundedRange(source, node);
            sink.emit(node.id, range.start, range.end, .syntax_marker, marker_behavior);
        }
    }
}

pub fn countMarkerSpans(source: []const u8, nodes: []const t.SemanticNode) usize {
    var sink: Sink = .{ .out = null };
    locate(source, nodes, &sink);
    return sink.index;
}

pub fn writeMarkerSpans(source: []const u8, nodes: []const t.SemanticNode, out: []t.DecorationSpan) usize {
    var sink: Sink = .{ .out = out };
    locate(source, nodes, &sink);
    std.debug.assert(sink.index == out.len);
    return sink.index;
}

test "source locator refines common inline and block constructs" {
    const source = "## Title ##\n\n**bold** and [link](https://example.com)\n\n```zig\nconst x = 1;\n```\n";
    var nodes = [_]t.SemanticNode{
        .{ .id = 1, .parent_index = 0, .first_child_index = 0, .child_count = 0, .kind = @intFromEnum(t.NodeKind.heading), .flags = t.node_flag_range_approximate, .source_start_byte = 0, .source_end_byte = 11, .content_start_byte = 0, .content_end_byte = 11, .metadata_index = 0, .reserved = 0 },
        .{ .id = 2, .parent_index = 0, .first_child_index = 0, .child_count = 0, .kind = @intFromEnum(t.NodeKind.strong), .flags = t.node_flag_range_approximate, .source_start_byte = 13, .source_end_byte = 21, .content_start_byte = 13, .content_end_byte = 21, .metadata_index = 0, .reserved = 0 },
        .{ .id = 3, .parent_index = 0, .first_child_index = 0, .child_count = 0, .kind = @intFromEnum(t.NodeKind.link), .flags = t.node_flag_range_approximate, .source_start_byte = 26, .source_end_byte = 53, .content_start_byte = 26, .content_end_byte = 53, .metadata_index = 0, .reserved = 0 },
        .{ .id = 4, .parent_index = 0, .first_child_index = 0, .child_count = 0, .kind = @intFromEnum(t.NodeKind.code_block), .flags = t.node_flag_range_approximate, .source_start_byte = 55, .source_end_byte = source.len, .content_start_byte = 55, .content_end_byte = source.len, .metadata_index = 0, .reserved = 0 },
    };
    refineNodes(source, &nodes);
    try std.testing.expectEqualStrings("Title", source[@intCast(nodes[0].content_start_byte)..@intCast(nodes[0].content_end_byte)]);
    try std.testing.expectEqualStrings("bold", source[@intCast(nodes[1].content_start_byte)..@intCast(nodes[1].content_end_byte)]);
    try std.testing.expectEqualStrings("link", source[@intCast(nodes[2].content_start_byte)..@intCast(nodes[2].content_end_byte)]);
    try std.testing.expect(std.mem.startsWith(u8, source[@intCast(nodes[3].content_start_byte)..@intCast(nodes[3].content_end_byte)], "const x"));

    const count = countMarkerSpans(source, &nodes);
    try std.testing.expect(count >= 10);
    const spans = try std.testing.allocator.alloc(t.DecorationSpan, count);
    defer std.testing.allocator.free(spans);
    _ = writeMarkerSpans(source, &nodes, spans);
    for (spans) |span| {
        try std.testing.expect(span.start_byte < span.end_byte);
        try std.testing.expect(span.end_byte <= source.len);
    }
}

test "setext headings and angle autolinks recover content and markers" {
    const source = "Heading\n=======\n\n<https://example.com>\n";
    var nodes = [_]t.SemanticNode{
        .{ .id = 1, .parent_index = 0, .first_child_index = 0, .child_count = 0, .kind = @intFromEnum(t.NodeKind.heading), .flags = t.node_flag_range_approximate, .source_start_byte = 0, .source_end_byte = 15, .content_start_byte = 0, .content_end_byte = 15, .metadata_index = 0, .reserved = 0 },
        .{ .id = 2, .parent_index = 0, .first_child_index = 0, .child_count = 0, .kind = @intFromEnum(t.NodeKind.link), .flags = t.node_flag_range_approximate, .source_start_byte = 17, .source_end_byte = 38, .content_start_byte = 17, .content_end_byte = 38, .metadata_index = 0, .reserved = 0 },
    };
    refineNodes(source, &nodes);
    try std.testing.expectEqualStrings("Heading", source[@intCast(nodes[0].content_start_byte)..@intCast(nodes[0].content_end_byte)]);
    try std.testing.expectEqualStrings("https://example.com", source[@intCast(nodes[1].content_start_byte)..@intCast(nodes[1].content_end_byte)]);
    const count = countMarkerSpans(source, &nodes);
    try std.testing.expect(count >= 3);
}
