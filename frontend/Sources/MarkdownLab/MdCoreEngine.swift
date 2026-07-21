#if os(macOS) && canImport(CMdCore)
import CMdCore
import Foundation

struct MdCoreFailure: Error, CustomStringConvertible {
    let operation: String
    let status: MdStatus

    var description: String {
        "\(operation) failed with MdStatus(rawValue: \(status.rawValue))"
    }
}

enum MarkdownCommand {
    case emphasis
    case strong
    case strikethrough
    case inlineCode
    case insertLink(destination: String)
    case heading(level: UInt32)
    case blockQuote
    case taskItem
    case indentListItem
    case outdentListItem

    var cKind: MdCommandKind {
        switch self {
        case .emphasis: return MD_COMMAND_TOGGLE_EMPHASIS
        case .strong: return MD_COMMAND_TOGGLE_STRONG
        case .strikethrough: return MD_COMMAND_TOGGLE_STRIKETHROUGH
        case .inlineCode: return MD_COMMAND_INLINE_CODE
        case .insertLink: return MD_COMMAND_INSERT_LINK
        case .heading: return MD_COMMAND_SET_HEADING
        case .blockQuote: return MD_COMMAND_TOGGLE_BLOCK_QUOTE
        case .taskItem: return MD_COMMAND_TOGGLE_TASK_ITEM
        case .indentListItem: return MD_COMMAND_INDENT_LIST_ITEM
        case .outdentListItem: return MD_COMMAND_OUTDENT_LIST_ITEM
        }
    }

    var value: UInt32 {
        if case let .heading(level) = self { return level }
        return 0
    }

    var argument: String {
        if case let .insertLink(destination) = self { return destination }
        return ""
    }
}

struct PlannedSourceEdit {
    let byteRange: MdByteRange
    let replacement: String
}

struct PlannedCommand {
    let edits: [PlannedSourceEdit]
    let resultSelection: MdByteRange
}

struct CanonicalSnapshot {
    let revision: UInt64
    let nodes: [MdSemanticNode]
    let spans: [MdDecorationSpan]
}

final class MdCoreEngine {
    private var document: OpaquePointer?

    init(source: String) throws {
        var options = MdDocumentOptions()
        options.struct_size = UInt32(MemoryLayout<MdDocumentOptions>.size)
        options.flags = 0
        options.max_document_bytes = 64 * 1024 * 1024
        options.extension_flags = UInt32(MD_EXTENSION_ALL)
        options.reserved = 0

        var created: OpaquePointer?
        let status = source.withUTF8Bytes { bytes in
            md_document_create(bytes, &options, &created)
        }
        try Self.requireOK(status, operation: "md_document_create")
        guard created != nil else {
            throw MdCoreFailure(operation: "md_document_create(null result)", status: MD_STATUS_INTERNAL_ERROR)
        }
        document = created
    }

    deinit {
        if let document {
            md_document_destroy(document)
        }
    }

    var revision: UInt64 {
        guard let document else { return 0 }
        return md_document_revision(document)
    }

    var versionSummary: String {
        let core = mdcore_version_string().map(String.init(cString:)) ?? "unknown"
        let cmark = mdcore_cmark_version_string().map(String.init(cString:)) ?? "unknown"
        return "MdCore \(core) · cmark-gfm \(cmark)"
    }

    /// Applies a source edit and returns the byte ranges the fast patch marked as
    /// invalidated, so the caller can restyle only the affected region.
    @discardableResult
    func applyEdit(utf16Range: NSRange, replacement: String) throws -> [MdByteRange] {
        guard let document else { throw invalidDocument() }
        let lower = try byteOffset(forUTF16: UInt64(utf16Range.location))
        let upper = try byteOffset(forUTF16: UInt64(utf16Range.location + utf16Range.length))

        var fastPatch: OpaquePointer?
        let status = replacement.withUTF8Bytes { replacementBytes in
            var edit = MdEdit(
                expected_revision: revision,
                start_byte: lower,
                old_end_byte: upper,
                replacement: replacementBytes
            )
            return md_document_apply_edit(document, &edit, &fastPatch)
        }

        defer {
            if let fastPatch { md_patch_release(fastPatch) }
        }
        try Self.requireOK(status, operation: "md_document_apply_edit")

        guard let fastPatch else { return [] }
        let view = md_patch_invalidated_ranges(fastPatch)
        return Self.copyView(pointer: view.ptr, count: view.len)
    }

    func canonicalSnapshot() throws -> CanonicalSnapshot {
        guard let document else { throw invalidDocument() }
        var patch: OpaquePointer?
        let currentRevision = revision
        let status = md_document_build_canonical_patch(document, currentRevision, &patch)
        try Self.requireOK(status, operation: "md_document_build_canonical_patch")
        guard let patch else {
            throw MdCoreFailure(operation: "canonical patch was null", status: MD_STATUS_INTERNAL_ERROR)
        }
        defer { md_patch_release(patch) }

        let nodeView = md_patch_semantic_nodes(patch)
        let spanView = md_patch_decoration_spans(patch)
        let nodes = Self.copyView(pointer: nodeView.ptr, count: nodeView.len)
        let spans = Self.copyView(pointer: spanView.ptr, count: spanView.len)

        return CanonicalSnapshot(
            revision: md_patch_result_revision(patch),
            nodes: nodes,
            spans: spans
        )
    }

    /// Copies the exact canonical source for a revision. The projection layer
    /// reads this rather than trusting an AppKit display string.
    func source() throws -> String {
        guard let document else { throw invalidDocument() }
        var buffer: OpaquePointer?
        let status = md_document_copy_source(document, revision, &buffer)
        try Self.requireOK(status, operation: "md_document_copy_source")
        guard let buffer else {
            throw MdCoreFailure(operation: "source buffer was null", status: MD_STATUS_INTERNAL_ERROR)
        }
        defer { md_buffer_release(buffer) }
        let bytes = md_buffer_bytes(buffer)
        return String(decoding: UnsafeBufferPointer(start: bytes.ptr, count: bytes.len), as: UTF8.self)
    }

    func renderHTML() throws -> String {
        guard let document else { throw invalidDocument() }
        var options = MdRenderOptions()
        options.struct_size = UInt32(MemoryLayout<MdRenderOptions>.size)
        options.flags = 0
        options.format = UInt32(MD_RENDER_HTML.rawValue)
        options.reserved = 0

        var buffer: OpaquePointer?
        let status = md_document_render(document, revision, &options, &buffer)
        try Self.requireOK(status, operation: "md_document_render")
        guard let buffer else {
            throw MdCoreFailure(operation: "render buffer was null", status: MD_STATUS_INTERNAL_ERROR)
        }
        defer { md_buffer_release(buffer) }

        let bytes = md_buffer_bytes(buffer)
        guard bytes.len == 0 || bytes.ptr != nil else {
            throw MdCoreFailure(operation: "render buffer contained a null pointer", status: MD_STATUS_INTERNAL_ERROR)
        }
        return String(decoding: UnsafeBufferPointer(start: bytes.ptr, count: bytes.len), as: UTF8.self)
    }

    /// Converts many byte ranges to UTF-16 `NSRange`s in a single FFI call.
    func utf16Ranges(for byteRanges: [MdByteRange]) throws -> [NSRange] {
        guard let document else { throw invalidDocument() }
        if byteRanges.isEmpty { return [] }

        var output = [MdUtf16Range](repeating: MdUtf16Range(), count: byteRanges.count)
        let status = byteRanges.withUnsafeBufferPointer { input in
            output.withUnsafeMutableBufferPointer { out in
                md_document_byte_ranges_to_utf16(
                    document,
                    input.baseAddress,
                    input.count,
                    out.baseAddress
                )
            }
        }
        try Self.requireOK(status, operation: "md_document_byte_ranges_to_utf16")

        return try output.map { converted in
            guard converted.location <= UInt64(Int.max), converted.length <= UInt64(Int.max) else {
                throw MdCoreFailure(operation: "UTF-16 range exceeded Int.max", status: MD_STATUS_UNSUPPORTED)
            }
            return NSRange(location: Int(converted.location), length: Int(converted.length))
        }
    }

    func utf16Range(for byteRange: MdByteRange) throws -> NSRange {
        guard let document else { throw invalidDocument() }
        var converted = MdUtf16Range()
        let status = md_document_byte_range_to_utf16(document, byteRange, &converted)
        try Self.requireOK(status, operation: "md_document_byte_range_to_utf16")
        guard converted.location <= UInt64(Int.max), converted.length <= UInt64(Int.max) else {
            throw MdCoreFailure(operation: "UTF-16 range exceeded Int.max", status: MD_STATUS_UNSUPPORTED)
        }
        return NSRange(location: Int(converted.location), length: Int(converted.length))
    }

    func byteRange(for utf16Range: NSRange) throws -> MdByteRange {
        let start = try byteOffset(forUTF16: UInt64(utf16Range.location))
        let end = try byteOffset(forUTF16: UInt64(utf16Range.location + utf16Range.length))
        return MdByteRange(start: start, end: end)
    }

    func plan(_ command: MarkdownCommand, selection: NSRange) throws -> PlannedCommand {
        guard let document else { throw invalidDocument() }
        let byteSelection = try byteRange(for: selection)
        var editList: OpaquePointer?

        let status = command.argument.withUTF8Bytes { argumentBytes in
            var options = MdCommandOptions()
            options.struct_size = UInt32(MemoryLayout<MdCommandOptions>.size)
            options.flags = 0
            options.value = command.value
            options.reserved = 0
            options.argument = argumentBytes
            return md_document_plan_command(
                document,
                revision,
                command.cKind,
                byteSelection,
                &options,
                &editList
            )
        }

        try Self.requireOK(status, operation: "md_document_plan_command")
        guard let editList else {
            throw MdCoreFailure(operation: "command edit list was null", status: MD_STATUS_INTERNAL_ERROR)
        }
        defer { md_edit_list_release(editList) }

        let view = md_edit_list_edits(editList)
        var edits: [PlannedSourceEdit] = []
        edits.reserveCapacity(view.len)
        if let pointer = view.ptr {
            for edit in UnsafeBufferPointer(start: pointer, count: view.len) {
                let replacement = String(
                    decoding: UnsafeBufferPointer(
                        start: edit.replacement.ptr,
                        count: edit.replacement.len
                    ),
                    as: UTF8.self
                )
                edits.append(
                    PlannedSourceEdit(
                        byteRange: MdByteRange(start: edit.start_byte, end: edit.old_end_byte),
                        replacement: replacement
                    )
                )
            }
        }

        return PlannedCommand(
            edits: edits.sorted { $0.byteRange.start > $1.byteRange.start },
            resultSelection: md_edit_list_result_selection(editList)
        )
    }

    private func byteOffset(forUTF16 offset: UInt64) throws -> UInt64 {
        guard let document else { throw invalidDocument() }
        var result: UInt64 = 0
        let status = md_document_utf16_to_byte(document, offset, &result)
        try Self.requireOK(status, operation: "md_document_utf16_to_byte")
        return result
    }

    private func invalidDocument() -> MdCoreFailure {
        MdCoreFailure(operation: "document is unavailable", status: MD_STATUS_INTERNAL_ERROR)
    }

    private static func requireOK(_ status: MdStatus, operation: String) throws {
        guard status == MD_STATUS_OK else {
            throw MdCoreFailure(operation: operation, status: status)
        }
    }

    private static func copyView<T>(pointer: UnsafePointer<T>?, count: Int) -> [T] {
        guard count > 0, let pointer else { return [] }
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }
}

private extension String {
    func withUTF8Bytes<Result>(_ body: (MdBytes) throws -> Result) rethrows -> Result {
        let bytes = Array(utf8)
        return try bytes.withUnsafeBufferPointer { buffer in
            try body(MdBytes(ptr: buffer.baseAddress, len: buffer.count))
        }
    }
}
#endif
