#if os(macOS) && canImport(CMdCore)
  import CMdCore
  import Foundation

  /// The sole Swift owner of an MdCore document. Its serial queue preserves the
  /// ABI's one-mutator rule and keeps parsing/range conversion off AppKit's
  /// input path. Every public result is immutable and safe for the main thread.
  final class MarkdownDocumentSession {
    private let queue = DispatchQueue(label: "com.markdownlab.document-session", qos: .userInitiated)
    private var engine: MdCoreEngine

    init(source: String) throws {
      engine = try MdCoreEngine(source: source)
    }

    func applyEdit(
      utf16Range: NSRange,
      replacement: String,
      completion: @escaping (Result<MarkdownEditAcknowledgement, Error>) -> Void
    ) {
      queue.async { [self] in
        do {
          let invalidated = try engine.applyEdit(utf16Range: utf16Range, replacement: replacement)
          let merged = merge(invalidated)
          let renderedRange = try merged.map { try engine.utf16Range(for: $0) }
          let acknowledgement = MarkdownEditAcknowledgement(
            revision: engine.revision,
            invalidatedRange: renderedRange
          )
          DispatchQueue.main.async { completion(.success(acknowledgement)) }
        } catch {
          DispatchQueue.main.async { completion(.failure(error)) }
        }
      }
    }

    func renderPlan(completion: @escaping (Result<MarkdownRenderPlan, Error>) -> Void) {
      queue.async { [self] in
        do {
          let snapshot = try engine.canonicalSnapshot()
          let source = try engine.source()
          let nodeRanges = try engine.utf16Ranges(for: snapshot.nodes.map {
            MdByteRange(start: $0.source_start_byte, end: $0.source_end_byte)
          })
          let spanRanges = try engine.utf16Ranges(for: snapshot.spans.map {
            MdByteRange(start: $0.start_byte, end: $0.end_byte)
          })
          let plan = MarkdownRenderPlan(
            revision: snapshot.revision,
            source: source,
            nodes: zip(snapshot.nodes, nodeRanges).map {
              MarkdownRenderPlan.Node(kind: Int($0.0.kind), flags: $0.0.flags, range: $0.1)
            },
            spans: zip(snapshot.spans, spanRanges).map {
              MarkdownRenderPlan.Span(role: Int($0.0.role), range: $0.1)
            },
            versionSummary: engine.versionSummary
          )
          DispatchQueue.main.async { completion(.success(plan)) }
        } catch {
          DispatchQueue.main.async { completion(.failure(error)) }
        }
      }
    }

    func plan(
      _ command: MarkdownCommand,
      selection: NSRange,
      completion: @escaping (Result<MarkdownCommandPlan, Error>) -> Void
    ) {
      queue.async { [self] in
        do {
          let planned = try engine.plan(command, selection: selection)
          let ranges = try engine.utf16Ranges(for: planned.edits.map(\.byteRange))
          let selection = try engine.utf16Range(for: planned.resultSelection)
          let result = MarkdownCommandPlan(
            edits: zip(planned.edits, ranges).map {
              MarkdownCommandPlan.Edit(range: $0.1, replacement: $0.0.replacement)
            },
            selection: selection
          )
          DispatchQueue.main.async { completion(.success(result)) }
        } catch {
          DispatchQueue.main.async { completion(.failure(error)) }
        }
      }
    }

    private func merge(_ ranges: [MdByteRange]) -> MdByteRange? {
      guard var result = ranges.first else { return nil }
      for range in ranges.dropFirst() {
        result.start = min(result.start, range.start)
        result.end = max(result.end, range.end)
      }
      return result
    }
  }
#endif
