const std = @import("std");
const c = @import("cmark.zig");
const t = @import("types.zig");
const SourceMap = @import("source_map.zig").SourceMap;
const source_locator = @import("source_locator.zig");

pub const Parsed = struct {
    allocator: std.mem.Allocator,
    parser: *c.Parser,
    root: *c.Node,
    source_map: SourceMap,
    nodes: []t.SemanticNode,
    spans: []t.DecorationSpan,

    pub fn deinit(self: *Parsed) void {
        self.allocator.free(self.nodes);
        self.allocator.free(self.spans);
        self.source_map.deinit(self.allocator);
        c.cmark_node_free(self.root);
        c.cmark_parser_free(self.parser);
        self.* = undefined;
    }
};

const Extension = struct {
    name: [*:0]const u8,
    flag: u32,
};

const extensions = [_]Extension{
    .{ .name = "table", .flag = t.extension_table },
    .{ .name = "strikethrough", .flag = t.extension_strikethrough },
    .{ .name = "autolink", .flag = t.extension_autolink },
    .{ .name = "tagfilter", .flag = t.extension_tagfilter },
    .{ .name = "tasklist", .flag = t.extension_tasklist },
};

var extensions_initialized = std.atomic.Value(bool).init(false);

fn ensureExtensions() void {
    // First caller wins the CAS and performs the one-time registration.
    if (extensions_initialized.cmpxchgStrong(false, true, .acq_rel, .monotonic) == null) {
        c.cmark_gfm_core_extensions_ensure_registered();
    }
}

fn attachExtensions(cmark_parser: *c.Parser, extension_flags: u32) bool {
    for (extensions) |extension_spec| {
        if ((extension_flags & extension_spec.flag) == 0) continue;
        const extension = c.cmark_find_syntax_extension(extension_spec.name) orelse return false;
        if (c.cmark_parser_attach_syntax_extension(cmark_parser, extension) == 0) return false;
    }
    return true;
}

fn countNodes(root: *c.Node) !usize {
    const iter = c.cmark_iter_new(root) orelse return error.ParseFailed;
    defer c.cmark_iter_free(iter);
    var count: usize = 0;
    while (true) {
        const event = c.cmark_iter_next(iter);
        if (event == .done) break;
        if (event == .enter) count += 1;
    }
    return count;
}

fn eqlType(value: [*:0]const u8, expected: []const u8) bool {
    return std.mem.eql(u8, std.mem.span(value), expected);
}

fn kindFor(node: *c.Node) t.NodeKind {
    const name = c.cmark_node_get_type_string(node);
    if (eqlType(name, "document")) return .document;
    if (eqlType(name, "block_quote")) return .block_quote;
    if (eqlType(name, "list")) return .list;
    if (eqlType(name, "item")) return .list_item;
    if (eqlType(name, "tasklist")) return .task_list_item;
    if (eqlType(name, "paragraph")) return .paragraph;
    if (eqlType(name, "heading")) return .heading;
    if (eqlType(name, "thematic_break")) return .thematic_break;
    if (eqlType(name, "code_block")) return .code_block;
    if (eqlType(name, "html_block")) return .html_block;
    if (eqlType(name, "table")) return .table;
    if (eqlType(name, "table_header")) return .table_head;
    if (eqlType(name, "table_row")) return .table_row;
    if (eqlType(name, "table_cell")) return .table_cell;
    if (eqlType(name, "text")) return .text;
    if (eqlType(name, "softbreak")) return .soft_break;
    if (eqlType(name, "linebreak")) return .hard_break;
    if (eqlType(name, "code")) return .code_span;
    if (eqlType(name, "emph")) return .emphasis;
    if (eqlType(name, "strong")) return .strong;
    if (eqlType(name, "strikethrough")) return .strikethrough;
    if (eqlType(name, "link")) return .link;
    if (eqlType(name, "image")) return .image;
    if (eqlType(name, "html_inline")) return .html_inline;
    if (eqlType(name, "custom_block")) return .custom_block;
    if (eqlType(name, "custom_inline")) return .custom_inline;
    return .unknown;
}

fn flagsFor(node: *c.Node, kind: t.NodeKind) u16 {
    var flags: u16 = t.node_flag_range_approximate;
    switch (kind) {
        .task_list_item => {
            if (c.cmark_gfm_extensions_get_tasklist_item_checked(node)) flags |= t.node_flag_checked;
        },
        .table_head => flags |= t.node_flag_table_header,
        .table_row => {
            if (c.cmark_gfm_extensions_get_table_row_is_header(node) != 0) flags |= t.node_flag_table_header;
        },
        else => {},
    }
    return flags;
}

fn roleFor(node: *c.Node, kind: t.NodeKind) ?struct { role: t.SpanRole, behavior: u16 } {
    return switch (kind) {
        .heading => blk: {
            const level = c.cmark_node_get_heading_level(node);
            const role: t.SpanRole = switch (level) {
                1 => .heading_1,
                2 => .heading_2,
                3 => .heading_3,
                4 => .heading_4,
                5 => .heading_5,
                else => .heading_6,
            };
            break :blk .{ .role = role, .behavior = 0 };
        },
        .emphasis => .{ .role = .emphasis, .behavior = 0 },
        .strong => .{ .role = .strong, .behavior = 0 },
        .strikethrough => .{ .role = .strikethrough, .behavior = 0 },
        .code_span, .code_block => .{ .role = .code, .behavior = t.span_monospaced | t.span_no_spellcheck },
        .link, .autolink => .{ .role = .link_label, .behavior = t.span_interactive },
        .image => .{ .role = .image_label, .behavior = t.span_interactive },
        .html_block, .html_inline => .{ .role = .html, .behavior = t.span_monospaced | t.span_no_spellcheck },
        else => null,
    };
}

fn lookupIndex(index_of: *std.AutoHashMap(*c.Node, u32), needle: ?*c.Node) u32 {
    const ptr = needle orelse return std.math.maxInt(u32);
    return index_of.get(ptr) orelse std.math.maxInt(u32);
}

fn countChildren(node: *c.Node) u32 {
    var count: u32 = 0;
    var child = c.cmark_node_first_child(node);
    while (child) |current| : (child = c.cmark_node_next(current)) count += 1;
    return count;
}

fn stableId(kind: t.NodeKind, start: u64, end: u64, index: usize) u64 {
    var hasher = std.hash.Wyhash.init(0x4d44434f5245);
    const kind_raw: u16 = @intFromEnum(kind);
    const index_raw: u64 = @intCast(index);
    hasher.update(std.mem.asBytes(&kind_raw));
    hasher.update(std.mem.asBytes(&start));
    hasher.update(std.mem.asBytes(&end));
    hasher.update(std.mem.asBytes(&index_raw));
    return hasher.final();
}

pub fn parse(allocator: std.mem.Allocator, source: []const u8, extension_flags: u32) !Parsed {
    if ((extension_flags & ~t.extension_all) != 0) return error.InvalidArgument;
    ensureExtensions();

    const cmark_parser = c.cmark_parser_new(c.opt_default) orelse return error.OutOfMemory;
    errdefer c.cmark_parser_free(cmark_parser);
    if (!attachExtensions(cmark_parser, extension_flags)) return error.ParseFailed;
    if (source.len > 0) c.cmark_parser_feed(cmark_parser, source.ptr, source.len);

    const root = c.cmark_parser_finish(cmark_parser) orelse return error.ParseFailed;
    errdefer c.cmark_node_free(root);

    var source_map = try SourceMap.init(allocator, source);
    errdefer source_map.deinit(allocator);

    const count = try countNodes(root);
    const nodes = try allocator.alloc(t.SemanticNode, count);
    errdefer allocator.free(nodes);
    const raw_nodes = try allocator.alloc(*c.Node, count);
    defer allocator.free(raw_nodes);

    const iter = c.cmark_iter_new(root) orelse return error.ParseFailed;
    defer c.cmark_iter_free(iter);
    var node_index: usize = 0;
    while (true) {
        const event = c.cmark_iter_next(iter);
        if (event == .done) break;
        if (event != .enter) continue;
        raw_nodes[node_index] = c.cmark_iter_get_node(iter);
        node_index += 1;
    }
    if (node_index != count) return error.ParseFailed;

    // Map each cmark node pointer to its preorder index so parent/child lookups
    // are O(1); a linear scan here would make normalization O(nodes^2).
    var index_of = std.AutoHashMap(*c.Node, u32).init(allocator);
    defer index_of.deinit();
    try index_of.ensureTotalCapacity(@intCast(count));
    for (raw_nodes, 0..) |node, index| {
        index_of.putAssumeCapacity(node, @intCast(index));
    }

    for (raw_nodes, 0..) |node, index| {
        const kind = kindFor(node);
        const start = source_map.positionToByte(
            source,
            c.cmark_node_get_start_line(node),
            c.cmark_node_get_start_column(node),
            false,
        );
        var end = source_map.positionToByte(
            source,
            c.cmark_node_get_end_line(node),
            c.cmark_node_get_end_column(node),
            true,
        );
        if (end < start) end = start;

        const parent_index = lookupIndex(&index_of, c.cmark_node_parent(node));
        var first_child_index: u32 = std.math.maxInt(u32);
        if (c.cmark_node_first_child(node)) |child| first_child_index = lookupIndex(&index_of, child);

        const id = stableId(kind, start, end, index);
        nodes[index] = .{
            .id = id,
            .parent_index = parent_index,
            .first_child_index = first_child_index,
            .child_count = countChildren(node),
            .kind = @intFromEnum(kind),
            .flags = flagsFor(node, kind),
            .source_start_byte = start,
            .source_end_byte = end,
            .content_start_byte = start,
            .content_end_byte = end,
            .metadata_index = std.math.maxInt(u32),
            .reserved = 0,
        };

    }

    source_locator.refineNodes(source, nodes);

    var semantic_span_count: usize = 0;
    for (raw_nodes, 0..) |node, index| {
        if (roleFor(node, kindFor(node)) != null and nodes[index].content_end_byte > nodes[index].content_start_byte) {
            semantic_span_count += 1;
        }
    }
    const marker_span_count = source_locator.countMarkerSpans(source, nodes);
    const total = @addWithOverflow(semantic_span_count, marker_span_count);
    if (total[1] != 0) return error.Overflow;
    const span_total = total[0];
    const spans = try allocator.alloc(t.DecorationSpan, span_total);
    errdefer allocator.free(spans);

    var span_index: usize = 0;
    for (raw_nodes, 0..) |node, index| {
        const kind = kindFor(node);
        if (roleFor(node, kind)) |style| {
            const semantic = nodes[index];
            if (semantic.content_end_byte <= semantic.content_start_byte) continue;
            spans[span_index] = .{
                .node_id = semantic.id,
                .start_byte = semantic.content_start_byte,
                .end_byte = semantic.content_end_byte,
                .role = @intFromEnum(style.role),
                .behavior = style.behavior,
                .metadata_index = semantic.metadata_index,
            };
            span_index += 1;
        }
    }
    _ = source_locator.writeMarkerSpans(source, nodes, spans[span_index..]);
    std.debug.assert(span_index + marker_span_count == spans.len);

    return .{
        .allocator = allocator,
        .parser = cmark_parser,
        .root = root,
        .source_map = source_map,
        .nodes = nodes,
        .spans = spans,
    };
}

pub fn render(parsed: *Parsed, format: t.RenderFormat, flags: u32) ![]u8 {
    var cmark_options: c_int = c.opt_default;
    if ((flags & t.render_unsafe) != 0) cmark_options |= c.opt_unsafe;
    if ((flags & t.render_sourcepos) != 0) cmark_options |= c.opt_sourcepos;
    if ((flags & t.render_hardbreaks) != 0) cmark_options |= c.opt_hardbreaks;
    if ((flags & t.render_nobreaks) != 0) cmark_options |= c.opt_nobreaks;
    if ((flags & t.render_table_style_align) != 0) cmark_options |= c.opt_table_style_attributes;
    if ((flags & t.render_full_info_string) != 0) cmark_options |= c.opt_full_info_string;

    const rendered = switch (format) {
        .html => c.cmark_render_html(parsed.root, cmark_options, c.cmark_parser_get_syntax_extensions(parsed.parser)),
        .plaintext => c.cmark_render_plaintext(parsed.root, cmark_options, 0),
    } orelse return error.OutOfMemory;
    defer c.free(@ptrCast(rendered));

    const source = std.mem.span(rendered);
    return parsed.allocator.dupe(u8, source);
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, haystack, needle) != null);
}

test "all formal GFM extensions render" {
    const source =
        "| A | B |\n" ++
        "| - | - |\n" ++
        "| 1 | 2 |\n\n" ++
        "- [x] done\n\n" ++
        "~~gone~~ www.example.com\n\n" ++
        "<script>alert(1)</script>\n";
    var parsed = try parse(std.testing.allocator, source, t.extension_all);
    defer parsed.deinit();

    const html = try render(&parsed, .html, t.render_unsafe);
    defer std.testing.allocator.free(html);
    try expectContains(html, "<table>");
    try expectContains(html, "type=\"checkbox\"");
    try expectContains(html, "<del>gone</del>");
    try expectContains(html, "href=\"http://www.example.com\"");
    try expectContains(html, "&lt;script>");

    var saw_checked_task = false;
    var saw_header = false;
    for (parsed.nodes) |node| {
        if (node.kind == @intFromEnum(t.NodeKind.task_list_item) and (node.flags & t.node_flag_checked) != 0) {
            saw_checked_task = true;
        }
        if (node.kind == @intFromEnum(t.NodeKind.table_head) and (node.flags & t.node_flag_table_header) != 0) {
            saw_header = true;
        }
    }
    try std.testing.expect(saw_checked_task);
    try std.testing.expect(saw_header);
}

test "semantic ranges and decoration spans stay within UTF-8 source boundaries" {
    const source = "# héading\n\n> **bold** and [link](https://example.com)\n\n- [x] task\n";
    var parsed = try parse(std.testing.allocator, source, t.extension_all);
    defer parsed.deinit();

    for (parsed.nodes) |node| {
        try std.testing.expect(node.source_start_byte <= node.source_end_byte);
        try std.testing.expect(node.source_end_byte <= source.len);
        try std.testing.expect(node.content_start_byte <= node.content_end_byte);
        try std.testing.expect(node.content_start_byte >= node.source_start_byte);
        try std.testing.expect(node.content_end_byte <= node.source_end_byte);
        try std.testing.expect(@import("utf.zig").isBoundary(source, @intCast(node.source_start_byte)));
        try std.testing.expect(@import("utf.zig").isBoundary(source, @intCast(node.source_end_byte)));
    }
    for (parsed.spans) |span| {
        try std.testing.expect(span.start_byte < span.end_byte);
        try std.testing.expect(span.end_byte <= source.len);
        try std.testing.expect(@import("utf.zig").isBoundary(source, @intCast(span.start_byte)));
        try std.testing.expect(@import("utf.zig").isBoundary(source, @intCast(span.end_byte)));
    }
}

test "CommonMark-only mode does not enable strikethrough" {
    var parsed = try parse(std.testing.allocator, "~~plain~~\n", 0);
    defer parsed.deinit();
    const html = try render(&parsed, .html, t.render_unsafe);
    defer std.testing.allocator.free(html);
    try std.testing.expectEqualStrings("<p>~~plain~~</p>\n", html);
}
