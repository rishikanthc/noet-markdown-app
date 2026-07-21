pub const Node = opaque {};
pub const Parser = opaque {};
pub const Iterator = opaque {};
pub const SyntaxExtension = opaque {};
pub const LList = opaque {};

pub const EventType = enum(c_int) {
    none = 0,
    done = 1,
    enter = 2,
    exit = 3,
};

pub const opt_default: c_int = 0;
pub const opt_sourcepos: c_int = 1 << 1;
pub const opt_hardbreaks: c_int = 1 << 2;
pub const opt_nobreaks: c_int = 1 << 4;
pub const opt_table_style_attributes: c_int = 1 << 15;
pub const opt_full_info_string: c_int = 1 << 16;
pub const opt_unsafe: c_int = 1 << 17;

pub extern fn cmark_gfm_core_extensions_ensure_registered() void;
pub extern fn cmark_find_syntax_extension(name: [*:0]const u8) ?*SyntaxExtension;
pub extern fn cmark_parser_attach_syntax_extension(parser: *Parser, extension: *SyntaxExtension) c_int;
pub extern fn cmark_parser_get_syntax_extensions(parser: *Parser) ?*LList;
pub extern fn cmark_gfm_extensions_get_tasklist_item_checked(node: *Node) bool;
pub extern fn cmark_gfm_extensions_get_table_row_is_header(node: *Node) c_int;

pub extern fn cmark_parser_new(options: c_int) ?*Parser;
pub extern fn cmark_parser_free(parser: *Parser) void;
pub extern fn cmark_parser_feed(parser: *Parser, buffer: [*]const u8, len: usize) void;
pub extern fn cmark_parser_finish(parser: *Parser) ?*Node;

pub extern fn cmark_node_free(node: *Node) void;
pub extern fn cmark_node_get_type_string(node: *Node) [*:0]const u8;
pub extern fn cmark_node_get_start_line(node: *Node) c_int;
pub extern fn cmark_node_get_start_column(node: *Node) c_int;
pub extern fn cmark_node_get_end_line(node: *Node) c_int;
pub extern fn cmark_node_get_end_column(node: *Node) c_int;
pub extern fn cmark_node_get_heading_level(node: *Node) c_int;
pub extern fn cmark_node_parent(node: *Node) ?*Node;
pub extern fn cmark_node_first_child(node: *Node) ?*Node;
pub extern fn cmark_node_next(node: *Node) ?*Node;

pub extern fn cmark_iter_new(root: *Node) ?*Iterator;
pub extern fn cmark_iter_free(iter: *Iterator) void;
pub extern fn cmark_iter_next(iter: *Iterator) EventType;
pub extern fn cmark_iter_get_node(iter: *Iterator) *Node;

pub extern fn cmark_render_html(root: *Node, options: c_int, extensions: ?*LList) ?[*:0]u8;
pub extern fn cmark_render_plaintext(root: *Node, options: c_int, width: c_int) ?[*:0]u8;
pub extern fn cmark_version_string() [*:0]const u8;
pub extern fn free(ptr: ?*anyopaque) void;
