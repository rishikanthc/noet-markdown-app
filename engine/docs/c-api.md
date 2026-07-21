# MdCore C ABI contract

## Ownership

| Value | Owner | Lifetime |
| --- | --- | --- |
| `MdDocument *` | caller | Until `md_document_destroy` |
| `MdPatch *` | caller | Until `md_patch_release` |
| Patch views | patch | Invalid after patch release |
| `MdBuffer *` | caller | Until `md_buffer_release` |
| `MdBytes` from a buffer | buffer | Invalid after buffer release |
| `MdEditList *` | caller | Until `md_edit_list_release` |
| Planned-edit views and replacement bytes | edit list | Invalid after edit-list release |

Every `out_*` handle is set to null before validation. A failed call never transfers ownership.

## Revisions

- Documents begin at revision 1.
- Each accepted source edit increments the revision exactly once.
- `expected_revision` prevents edits against stale source.
- Canonical parsing, rendering, source copying, and command planning require the exact current revision.
- Fast patches span the old and new revisions. Canonical patches have equal base/result revisions because they are immutable snapshots of one revision.

## Coordinates

- All ABI source ranges are half-open UTF-8 byte ranges: `[start, end)`.
- Edit endpoints must be Unicode scalar boundaries.
- UTF-16 offsets that split a surrogate pair are rejected.
- Conversion functions do not scan or modify caller memory after reporting an invalid input.
- Batch conversion validates every input before writing outputs.

## Options structs

Each public options struct begins with `struct_size`. Callers initialize it to `sizeof(the_struct)` and zero all reserved fields. MdCore accepts larger structs for forward compatibility and rejects smaller structs, unknown flag bits, or non-zero reserved fields.

## Rendering safety

HTML rendering is safe by default. Raw HTML and unsafe links are suppressed by cmark-gfm unless `MD_RENDER_FLAG_UNSAFE` is explicitly passed. The GFM tag-filter extension remains active when enabled, including in unsafe mode.

## Threading

A single `MdDocument` must be mutated on one serialized queue. Immutable patch, buffer, and edit-list views may be read on another thread while their owner remains alive. MdCore does not call back into Swift and does not retain caller-provided source or replacement pointers after a function returns.

## ABI evolution

`mdcore_abi_version()` returns `(major << 16) | (minor << 8) | patch`. Additive functions and enum values increment the minor version. Layout or ownership-breaking changes increment the major version.
