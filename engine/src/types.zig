const std = @import("std");

pub const abi_version: u32 = (1 << 16) | (1 << 8) | 0;
pub const version_string: [:0]const u8 = "0.2.0";

pub const Status = enum(c_int) {
    ok = 0,
    invalid_argument = 1,
    out_of_memory = 2,
    invalid_utf8 = 3,
    stale_revision = 4,
    parse_failed = 5,
    unsupported = 6,
    internal_error = 255,
};

pub const Bytes = extern struct {
    ptr: ?[*]const u8,
    len: usize,

    pub fn slice(self: Bytes) ?[]const u8 {
        if (self.len == 0) return "";
        const p = self.ptr orelse return null;
        return p[0..self.len];
    }
};

pub const ByteRange = extern struct {
    start: u64,
    end: u64,
};

pub const Utf16Range = extern struct {
    location: u64,
    length: u64,
};

pub const Edit = extern struct {
    expected_revision: u64,
    start_byte: u64,
    old_end_byte: u64,
    replacement: Bytes,
};

pub const document_explicit_extensions: u32 = 1 << 0;

pub const extension_table: u32 = 1 << 0;
pub const extension_strikethrough: u32 = 1 << 1;
pub const extension_autolink: u32 = 1 << 2;
pub const extension_tagfilter: u32 = 1 << 3;
pub const extension_tasklist: u32 = 1 << 4;
pub const extension_all: u32 = extension_table |
    extension_strikethrough |
    extension_autolink |
    extension_tagfilter |
    extension_tasklist;

pub const DocumentOptions = extern struct {
    struct_size: u32,
    flags: u32,
    max_document_bytes: u64,
    extension_flags: u32,
    reserved: u32,
};

pub const NodeKind = enum(u16) {
    document = 1,
    block_quote,
    list,
    list_item,
    task_list_item,
    paragraph,
    heading,
    thematic_break,
    code_block,
    html_block,
    table,
    table_head,
    table_body,
    table_row,
    table_cell,
    text,
    soft_break,
    hard_break,
    code_span,
    emphasis,
    strong,
    strikethrough,
    link,
    image,
    autolink,
    html_inline,
    custom_block,
    custom_inline,
    unknown = 65535,
};

pub const node_flag_range_approximate: u16 = 1 << 0;
pub const node_flag_checked: u16 = 1 << 1;
pub const node_flag_table_header: u16 = 1 << 2;

pub const SemanticNode = extern struct {
    id: u64,
    parent_index: u32,
    first_child_index: u32,
    child_count: u32,
    kind: u16,
    flags: u16,
    source_start_byte: u64,
    source_end_byte: u64,
    content_start_byte: u64,
    content_end_byte: u64,
    metadata_index: u32,
    reserved: u32,
};

pub const SpanRole = enum(u16) {
    body = 1,
    heading_1,
    heading_2,
    heading_3,
    heading_4,
    heading_5,
    heading_6,
    emphasis,
    strong,
    strikethrough,
    code,
    code_fence,
    code_language,
    link_label,
    link_destination,
    image_label,
    image_destination,
    block_quote_marker,
    list_marker,
    task_marker,
    table_delimiter,
    html,
    syntax_marker,
    math_block,
    math_content,
    math_delimiter,
};

pub const span_dim_when_inactive: u16 = 1 << 0;
pub const span_reveal_at_caret: u16 = 1 << 1;
pub const span_interactive: u16 = 1 << 2;
pub const span_monospaced: u16 = 1 << 3;
pub const span_no_spellcheck: u16 = 1 << 4;
pub const span_preserve_foreground: u16 = 1 << 5;
pub const span_provisional: u16 = 1 << 15;

pub const DecorationSpan = extern struct {
    node_id: u64,
    start_byte: u64,
    end_byte: u64,
    role: u16,
    behavior: u16,
    metadata_index: u32,
};

pub const RangeView = extern struct {
    ptr: ?[*]const ByteRange,
    len: usize,
};

pub const NodeView = extern struct {
    ptr: ?[*]const SemanticNode,
    len: usize,
};

pub const SpanView = extern struct {
    ptr: ?[*]const DecorationSpan,
    len: usize,
};

pub const CommandKind = enum(c_int) {
    toggle_emphasis = 1,
    toggle_strong = 2,
    toggle_strikethrough = 3,
    inline_code = 4,
    insert_link = 5,
    set_heading = 6,
    toggle_block_quote = 7,
    toggle_task_item = 8,
    indent_list_item = 9,
    outdent_list_item = 10,
};

pub const CommandOptions = extern struct {
    struct_size: u32,
    flags: u32,
    value: u32,
    reserved: u32,
    argument: Bytes,
};

pub const PlannedEdit = extern struct {
    start_byte: u64,
    old_end_byte: u64,
    replacement: Bytes,
};

pub const PlannedEditView = extern struct {
    ptr: ?[*]const PlannedEdit,
    len: usize,
};

pub fn emptyPlannedEditView() PlannedEditView {
    return .{ .ptr = null, .len = 0 };
}

pub const RenderFormat = enum(u32) {
    html = 1,
    plaintext = 2,
};

pub const RenderOptions = extern struct {
    struct_size: u32,
    flags: u32,
    format: u32,
    reserved: u32,
};

pub const render_unsafe: u32 = 1 << 0;
pub const render_sourcepos: u32 = 1 << 1;
pub const render_hardbreaks: u32 = 1 << 2;
pub const render_nobreaks: u32 = 1 << 3;
pub const render_table_style_align: u32 = 1 << 4;
pub const render_full_info_string: u32 = 1 << 5;
pub const render_all: u32 = render_unsafe | render_sourcepos | render_hardbreaks | render_nobreaks | render_table_style_align | render_full_info_string;

pub fn emptyRangeView() RangeView {
    return .{ .ptr = null, .len = 0 };
}

pub fn emptyNodeView() NodeView {
    return .{ .ptr = null, .len = 0 };
}

pub fn emptySpanView() SpanView {
    return .{ .ptr = null, .len = 0 };
}

comptime {
    std.debug.assert(@sizeOf(Bytes) == @sizeOf(usize) * 2);
    std.debug.assert(@sizeOf(ByteRange) == 16);
    std.debug.assert(@sizeOf(Utf16Range) == 16);
    std.debug.assert(@sizeOf(Edit) == 40);
    std.debug.assert(@sizeOf(DocumentOptions) == 24);
    std.debug.assert(@sizeOf(SemanticNode) == 64);
    std.debug.assert(@sizeOf(DecorationSpan) == 32);
    std.debug.assert(@sizeOf(CommandOptions) == 32);
    std.debug.assert(@sizeOf(PlannedEdit) == 32);
    std.debug.assert(@sizeOf(RenderOptions) == 16);
}
