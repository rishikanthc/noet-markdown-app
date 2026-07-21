#ifndef MDCORE_H
#define MDCORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MDCORE_ABI_VERSION_MAJOR 1u
#define MDCORE_ABI_VERSION_MINOR 1u
#define MDCORE_ABI_VERSION_PATCH 0u
#define MDCORE_ABI_VERSION ((MDCORE_ABI_VERSION_MAJOR << 16u) | (MDCORE_ABI_VERSION_MINOR << 8u) | MDCORE_ABI_VERSION_PATCH)
#define MDCORE_INDEX_NONE UINT32_MAX
#define MDCORE_DOCUMENT_DEFAULT_MAX_BYTES (64u * 1024u * 1024u)

typedef struct MdDocument MdDocument;
typedef struct MdPatch MdPatch;
typedef struct MdBuffer MdBuffer;
typedef struct MdEditList MdEditList;

typedef enum MdStatus {
    MD_STATUS_OK = 0,
    MD_STATUS_INVALID_ARGUMENT = 1,
    MD_STATUS_OUT_OF_MEMORY = 2,
    MD_STATUS_INVALID_UTF8 = 3,
    MD_STATUS_STALE_REVISION = 4,
    MD_STATUS_PARSE_FAILED = 5,
    MD_STATUS_UNSUPPORTED = 6,
    MD_STATUS_INTERNAL_ERROR = 255
} MdStatus;

typedef struct MdBytes {
    const uint8_t *ptr;
    size_t len;
} MdBytes;

typedef struct MdByteRange {
    uint64_t start;
    uint64_t end;
} MdByteRange;

typedef struct MdUtf16Range {
    uint64_t location;
    uint64_t length;
} MdUtf16Range;

typedef struct MdEdit {
    uint64_t expected_revision;
    uint64_t start_byte;
    uint64_t old_end_byte;
    MdBytes replacement;
} MdEdit;

enum {
    MD_DOCUMENT_FLAG_EXPLICIT_EXTENSIONS = 1u << 0
};

enum {
    MD_EXTENSION_TABLE = 1u << 0,
    MD_EXTENSION_STRIKETHROUGH = 1u << 1,
    MD_EXTENSION_AUTOLINK = 1u << 2,
    MD_EXTENSION_TAGFILTER = 1u << 3,
    MD_EXTENSION_TASKLIST = 1u << 4,
    MD_EXTENSION_ALL = MD_EXTENSION_TABLE |
                       MD_EXTENSION_STRIKETHROUGH |
                       MD_EXTENSION_AUTOLINK |
                       MD_EXTENSION_TAGFILTER |
                       MD_EXTENSION_TASKLIST
};

typedef struct MdDocumentOptions {
    uint32_t struct_size;
    uint32_t flags;
    uint64_t max_document_bytes;
    uint32_t extension_flags;
    uint32_t reserved;
} MdDocumentOptions;

typedef enum MdNodeKind {
    MD_NODE_DOCUMENT = 1,
    MD_NODE_BLOCK_QUOTE,
    MD_NODE_LIST,
    MD_NODE_LIST_ITEM,
    MD_NODE_TASK_LIST_ITEM,
    MD_NODE_PARAGRAPH,
    MD_NODE_HEADING,
    MD_NODE_THEMATIC_BREAK,
    MD_NODE_CODE_BLOCK,
    MD_NODE_HTML_BLOCK,
    MD_NODE_TABLE,
    MD_NODE_TABLE_HEAD,
    MD_NODE_TABLE_BODY,
    MD_NODE_TABLE_ROW,
    MD_NODE_TABLE_CELL,
    MD_NODE_TEXT,
    MD_NODE_SOFT_BREAK,
    MD_NODE_HARD_BREAK,
    MD_NODE_CODE_SPAN,
    MD_NODE_EMPHASIS,
    MD_NODE_STRONG,
    MD_NODE_STRIKETHROUGH,
    MD_NODE_LINK,
    MD_NODE_IMAGE,
    MD_NODE_AUTOLINK,
    MD_NODE_HTML_INLINE,
    MD_NODE_CUSTOM_BLOCK,
    MD_NODE_CUSTOM_INLINE,
    MD_NODE_UNKNOWN = 65535
} MdNodeKind;

enum {
    MD_NODE_FLAG_RANGE_APPROXIMATE = 1u << 0,
    MD_NODE_FLAG_CHECKED = 1u << 1,
    MD_NODE_FLAG_TABLE_HEADER = 1u << 2
};

typedef struct MdSemanticNode {
    uint64_t id;
    uint32_t parent_index;
    uint32_t first_child_index;
    uint32_t child_count;
    uint16_t kind;
    uint16_t flags;
    uint64_t source_start_byte;
    uint64_t source_end_byte;
    uint64_t content_start_byte;
    uint64_t content_end_byte;
    uint32_t metadata_index;
    uint32_t reserved;
} MdSemanticNode;

typedef enum MdSpanRole {
    MD_SPAN_BODY = 1,
    MD_SPAN_HEADING_1,
    MD_SPAN_HEADING_2,
    MD_SPAN_HEADING_3,
    MD_SPAN_HEADING_4,
    MD_SPAN_HEADING_5,
    MD_SPAN_HEADING_6,
    MD_SPAN_EMPHASIS,
    MD_SPAN_STRONG,
    MD_SPAN_STRIKETHROUGH,
    MD_SPAN_CODE,
    MD_SPAN_CODE_FENCE,
    MD_SPAN_CODE_LANGUAGE,
    MD_SPAN_LINK_LABEL,
    MD_SPAN_LINK_DESTINATION,
    MD_SPAN_IMAGE_LABEL,
    MD_SPAN_IMAGE_DESTINATION,
    MD_SPAN_BLOCK_QUOTE_MARKER,
    MD_SPAN_LIST_MARKER,
    MD_SPAN_TASK_MARKER,
    MD_SPAN_TABLE_DELIMITER,
    MD_SPAN_HTML,
    MD_SPAN_SYNTAX_MARKER
} MdSpanRole;

enum {
    MD_SPAN_BEHAVIOR_DIM_WHEN_INACTIVE = 1u << 0,
    MD_SPAN_BEHAVIOR_REVEAL_AT_CARET = 1u << 1,
    MD_SPAN_BEHAVIOR_INTERACTIVE = 1u << 2,
    MD_SPAN_BEHAVIOR_MONOSPACED = 1u << 3,
    MD_SPAN_BEHAVIOR_NO_SPELLCHECK = 1u << 4,
    MD_SPAN_BEHAVIOR_PRESERVE_FOREGROUND = 1u << 5,
    MD_SPAN_BEHAVIOR_PROVISIONAL = 1u << 15
};

typedef struct MdDecorationSpan {
    uint64_t node_id;
    uint64_t start_byte;
    uint64_t end_byte;
    uint16_t role;
    uint16_t behavior;
    uint32_t metadata_index;
} MdDecorationSpan;

typedef struct MdRangeView {
    const MdByteRange *ptr;
    size_t len;
} MdRangeView;

typedef struct MdNodeView {
    const MdSemanticNode *ptr;
    size_t len;
} MdNodeView;

typedef struct MdSpanView {
    const MdDecorationSpan *ptr;
    size_t len;
} MdSpanView;

typedef enum MdCommandKind {
    MD_COMMAND_TOGGLE_EMPHASIS = 1,
    MD_COMMAND_TOGGLE_STRONG = 2,
    MD_COMMAND_TOGGLE_STRIKETHROUGH = 3,
    MD_COMMAND_INLINE_CODE = 4,
    MD_COMMAND_INSERT_LINK = 5,
    MD_COMMAND_SET_HEADING = 6,
    MD_COMMAND_TOGGLE_BLOCK_QUOTE = 7,
    MD_COMMAND_TOGGLE_TASK_ITEM = 8,
    MD_COMMAND_INDENT_LIST_ITEM = 9,
    MD_COMMAND_OUTDENT_LIST_ITEM = 10
} MdCommandKind;

typedef struct MdCommandOptions {
    uint32_t struct_size;
    uint32_t flags;
    uint32_t value;
    uint32_t reserved;
    MdBytes argument;
} MdCommandOptions;

typedef struct MdPlannedEdit {
    uint64_t start_byte;
    uint64_t old_end_byte;
    MdBytes replacement;
} MdPlannedEdit;

typedef struct MdPlannedEditView {
    const MdPlannedEdit *ptr;
    size_t len;
} MdPlannedEditView;

typedef enum MdRenderFormat {
    MD_RENDER_HTML = 1,
    MD_RENDER_PLAINTEXT = 2
} MdRenderFormat;

typedef struct MdRenderOptions {
    uint32_t struct_size;
    uint32_t flags;
    uint32_t format;
    uint32_t reserved;
} MdRenderOptions;

enum {
    MD_RENDER_FLAG_UNSAFE = 1u << 0,
    MD_RENDER_FLAG_SOURCEPOS = 1u << 1,
    MD_RENDER_FLAG_HARDBREAKS = 1u << 2,
    MD_RENDER_FLAG_NOBREAKS = 1u << 3,
    MD_RENDER_FLAG_TABLE_STYLE_ALIGN = 1u << 4,
    MD_RENDER_FLAG_FULL_INFO_STRING = 1u << 5
};

/* Version and dependency metadata. */
uint32_t mdcore_abi_version(void);
const char *mdcore_version_string(void);
const char *mdcore_cmark_version_string(void);

/* Document lifetime and revisioned source edits. */
MdStatus md_document_create(MdBytes initial_utf8,
                            const MdDocumentOptions *options,
                            MdDocument **out_document);
void md_document_destroy(MdDocument *document);
uint64_t md_document_revision(const MdDocument *document);
uint64_t md_document_utf8_length(const MdDocument *document);
uint64_t md_document_utf16_length(const MdDocument *document);
MdStatus md_document_copy_source(const MdDocument *document,
                                 uint64_t revision,
                                 MdBuffer **out_buffer);
MdStatus md_document_apply_edit(MdDocument *document,
                                const MdEdit *edit,
                                MdPatch **out_fast_patch);
MdStatus md_document_build_canonical_patch(const MdDocument *document,
                                           uint64_t revision,
                                           MdPatch **out_patch);

/* Patch views remain valid until md_patch_release. */
uint64_t md_patch_base_revision(const MdPatch *patch);
uint64_t md_patch_result_revision(const MdPatch *patch);
MdRangeView md_patch_invalidated_ranges(const MdPatch *patch);
MdNodeView md_patch_semantic_nodes(const MdPatch *patch);
MdSpanView md_patch_decoration_spans(const MdPatch *patch);
void md_patch_release(MdPatch *patch);

/* Markdown-aware commands produce source edits; they do not mutate the document. */
MdStatus md_document_plan_command(const MdDocument *document,
                                  uint64_t revision,
                                  MdCommandKind command,
                                  MdByteRange selection,
                                  const MdCommandOptions *options,
                                  MdEditList **out_edits);
MdPlannedEditView md_edit_list_edits(const MdEditList *edit_list);
MdByteRange md_edit_list_result_selection(const MdEditList *edit_list);
void md_edit_list_release(MdEditList *edit_list);

/* Explicit UTF-8-byte to UTF-16 conversions for Cocoa. */
MdStatus md_document_byte_to_utf16(const MdDocument *document,
                                   uint64_t byte_offset,
                                   uint64_t *out_utf16_offset);
MdStatus md_document_utf16_to_byte(const MdDocument *document,
                                   uint64_t utf16_offset,
                                   uint64_t *out_byte_offset);
MdStatus md_document_byte_range_to_utf16(const MdDocument *document,
                                         MdByteRange byte_range,
                                         MdUtf16Range *out_range);
MdStatus md_document_byte_offsets_to_utf16(const MdDocument *document,
                                           const uint64_t *byte_offsets,
                                           size_t count,
                                           uint64_t *out_utf16_offsets);
MdStatus md_document_byte_ranges_to_utf16(const MdDocument *document,
                                          const MdByteRange *byte_ranges,
                                          size_t count,
                                          MdUtf16Range *out_ranges);

/* Canonical cmark-gfm rendering. Safe HTML is the default; UNSAFE is explicit. */
MdStatus md_document_render(const MdDocument *document,
                            uint64_t revision,
                            const MdRenderOptions *options,
                            MdBuffer **out_buffer);
MdBytes md_buffer_bytes(const MdBuffer *buffer);
void md_buffer_release(MdBuffer *buffer);

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(MdBytes) == sizeof(void *) + sizeof(size_t), "MdBytes ABI mismatch");
_Static_assert(sizeof(MdByteRange) == 16, "MdByteRange ABI mismatch");
_Static_assert(sizeof(MdUtf16Range) == 16, "MdUtf16Range ABI mismatch");
_Static_assert(sizeof(MdEdit) == 40, "MdEdit ABI mismatch");
_Static_assert(sizeof(MdDocumentOptions) == 24, "MdDocumentOptions ABI mismatch");
_Static_assert(sizeof(MdSemanticNode) == 64, "MdSemanticNode ABI mismatch");
_Static_assert(sizeof(MdDecorationSpan) == 32, "MdDecorationSpan ABI mismatch");
_Static_assert(sizeof(MdCommandOptions) == 32, "MdCommandOptions ABI mismatch");
_Static_assert(sizeof(MdPlannedEdit) == 32, "MdPlannedEdit ABI mismatch");
_Static_assert(sizeof(MdRenderOptions) == 16, "MdRenderOptions ABI mismatch");
#endif

#ifdef __cplusplus
}
#endif

#endif
