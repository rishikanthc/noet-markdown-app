# Security policy

## Supported release

The `0.2.x` line receives security fixes while it is the current development
line.

## Parser safety defaults

- HTML rendering is safe by default.
- Raw HTML and unsafe URLs require the explicit `MD_RENDER_FLAG_UNSAFE` flag.
- The formal GFM tag-filter extension remains independently configurable.
- Input must be valid UTF-8 and is capped at 64 MiB by default.
- Every mutating operation is revision checked.
- Public result objects own their memory and require the matching release call.

## Reporting

Do not include confidential documents in a report. Provide a minimized Markdown
sample, MdCore version, cmark-gfm version, target architecture, and reproduction
steps.
