#include "mdcore.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static int contains(MdBytes bytes, const char *needle) {
    const size_t needle_len = strlen(needle);
    if (needle_len == 0) return 1;
    if (bytes.ptr == NULL || bytes.len < needle_len) return 0;
    for (size_t i = 0; i <= bytes.len - needle_len; ++i) {
        if (memcmp(bytes.ptr + i, needle, needle_len) == 0) return 1;
    }
    return 0;
}

int main(void) {
    const char *markdown =
        "# Title\n\n"
        "| A | B |\n| - | - |\n| 1 | 2 |\n\n"
        "- [x] done\n\n"
        "~~gone~~ www.example.com 😀\n\n"
        "<script>alert(1)</script>\n";

    MdDocument *doc = NULL;
    const MdBytes initial = {(const uint8_t *)markdown, strlen(markdown)};
    assert(mdcore_abi_version() == MDCORE_ABI_VERSION);
    assert(mdcore_version_string() != NULL);
    assert(mdcore_cmark_version_string() != NULL);
    assert(md_document_create(initial, NULL, &doc) == MD_STATUS_OK);
    assert(doc != NULL);
    assert(md_document_revision(doc) == 1);
    assert(md_document_utf8_length(doc) == initial.len);

    const MdRenderOptions options = {
        sizeof(options), MD_RENDER_FLAG_UNSAFE, MD_RENDER_HTML, 0
    };
    MdBuffer *buffer = NULL;
    assert(md_document_render(doc, 1, &options, &buffer) == MD_STATUS_OK);
    const MdBytes html = md_buffer_bytes(buffer);
    assert(contains(html, "<table>"));
    assert(contains(html, "type=\"checkbox\""));
    assert(contains(html, "<del>gone</del>"));
    assert(contains(html, "href=\"http://www.example.com\""));
    assert(contains(html, "&lt;script>"));
    md_buffer_release(buffer);

    uint64_t utf16_end = 0;
    uint64_t byte_end = 0;
    assert(md_document_byte_to_utf16(doc, initial.len, &utf16_end) == MD_STATUS_OK);
    assert(md_document_utf16_to_byte(doc, utf16_end, &byte_end) == MD_STATUS_OK);
    assert(byte_end == initial.len);

    const uint64_t byte_offsets[] = {0, 2, (uint64_t)initial.len};
    uint64_t utf16_offsets[3] = {UINT64_MAX, UINT64_MAX, UINT64_MAX};
    assert(md_document_byte_offsets_to_utf16(doc, byte_offsets, 3, utf16_offsets) == MD_STATUS_OK);
    assert(utf16_offsets[0] == 0);
    assert(utf16_offsets[1] == 2);
    assert(utf16_offsets[2] == utf16_end);

    const MdByteRange byte_ranges[] = {{0, 7}, {2, 7}};
    MdUtf16Range utf16_ranges[2] = {{0, 0}, {0, 0}};
    assert(md_document_byte_ranges_to_utf16(doc, byte_ranges, 2, utf16_ranges) == MD_STATUS_OK);
    assert(utf16_ranges[0].location == 0 && utf16_ranges[0].length == 7);
    assert(utf16_ranges[1].location == 2 && utf16_ranges[1].length == 5);

    MdPatch *canonical = NULL;
    assert(md_document_build_canonical_patch(doc, 1, &canonical) == MD_STATUS_OK);
    const MdNodeView nodes = md_patch_semantic_nodes(canonical);
    const MdSpanView spans = md_patch_decoration_spans(canonical);
    assert(nodes.len > 0);
    assert(spans.len > 0);
    for (size_t i = 0; i < nodes.len; ++i) {
        assert(nodes.ptr[i].source_start_byte <= nodes.ptr[i].source_end_byte);
        assert(nodes.ptr[i].source_end_byte <= initial.len);
        assert(nodes.ptr[i].content_start_byte <= nodes.ptr[i].content_end_byte);
        assert(nodes.ptr[i].content_end_byte <= nodes.ptr[i].source_end_byte);
    }
    for (size_t i = 0; i < spans.len; ++i) {
        assert(spans.ptr[i].start_byte < spans.ptr[i].end_byte);
        assert(spans.ptr[i].end_byte <= initial.len);
    }
    md_patch_release(canonical);

    MdEditList *edit_list = NULL;
    assert(md_document_plan_command(doc,
                                    1,
                                    MD_COMMAND_TOGGLE_STRONG,
                                    (MdByteRange){2, 7},
                                    NULL,
                                    &edit_list) == MD_STATUS_OK);
    const MdPlannedEditView planned = md_edit_list_edits(edit_list);
    assert(planned.len == 1);
    assert(planned.ptr[0].start_byte == 2);
    assert(planned.ptr[0].old_end_byte == 7);
    assert(contains(planned.ptr[0].replacement, "**Title**"));
    const MdByteRange result_selection = md_edit_list_result_selection(edit_list);
    assert(result_selection.start == 4 && result_selection.end == 9);

    const MdEdit command_edit = {
        1,
        planned.ptr[0].start_byte,
        planned.ptr[0].old_end_byte,
        planned.ptr[0].replacement
    };
    MdPatch *fast = NULL;
    assert(md_document_apply_edit(doc, &command_edit, &fast) == MD_STATUS_OK);
    assert(md_patch_base_revision(fast) == 1);
    assert(md_patch_result_revision(fast) == 2);
    assert(md_patch_invalidated_ranges(fast).len == 1);
    md_patch_release(fast);
    md_edit_list_release(edit_list);

    buffer = NULL;
    assert(md_document_copy_source(doc, 2, &buffer) == MD_STATUS_OK);
    assert(contains(md_buffer_bytes(buffer), "# **Title**"));
    md_buffer_release(buffer);

    canonical = (MdPatch *)(uintptr_t)1;
    assert(md_document_build_canonical_patch(doc, 1, &canonical) == MD_STATUS_STALE_REVISION);
    assert(canonical == NULL);

    edit_list = (MdEditList *)(uintptr_t)1;
    assert(md_document_plan_command(doc,
                                    1,
                                    MD_COMMAND_TOGGLE_STRONG,
                                    (MdByteRange){0, 0},
                                    NULL,
                                    &edit_list) == MD_STATUS_STALE_REVISION);
    assert(edit_list == NULL);

    md_document_destroy(doc);
    puts("C ABI smoke test passed");
    return 0;
}
