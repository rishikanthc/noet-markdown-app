#if os(macOS) && canImport(AppKit) && canImport(CMdCore)
  import AppKit
  import CMdCore

  /// Headless contract check for the typography renderer. It intentionally
  /// covers only the stable first slice: headings and inline text semantics.
  enum StyleCheck {
    private static let fixture = """
      # Heading **Strong**

      Body with *emphasis*, ~~strike~~, and ==highlight==.
      """

    static func run(path: String?) {
      let source = path.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? fixture
      do {
        let engine = try MdCoreEngine(source: source)
        let textView = MarkdownTextView(usingTextLayoutManager: true)
        textView.string = source
        let snapshot = try engine.canonicalSnapshot()
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
        MarkdownRenderer().apply(plan: plan, invalidatedRange: nil, to: textView)
        guard let storage = textView.textStorage else { return }

        if path == nil {
          try verify(source: source, storage: storage)
          print("STYLECHECK PASS (heading + inline typography)")
        } else {
          print("length=\(storage.length) nodes=\(snapshot.nodes.count) spans=\(snapshot.spans.count)")
        }
      } catch {
        print("stylecheck failed: \(error)")
      }
    }

    private static func verify(source: String, storage: NSTextStorage) throws {
      let text = source as NSString
      func index(_ needle: String) -> Int { text.range(of: needle).location }
      func font(_ needle: String) -> NSFont? {
        let location = index(needle)
        return location == NSNotFound ? nil : storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
      }
      guard let heading = font("Heading"), let strong = font("Strong"),
        heading.pointSize == strong.pointSize,
        strong.fontDescriptor.symbolicTraits.contains(.bold),
        font("emphasis")?.fontDescriptor.symbolicTraits.contains(.italic) == true,
        storage.attribute(.strikethroughStyle, at: index("strike"), effectiveRange: nil) != nil,
        storage.attribute(.backgroundColor, at: index("highlight"), effectiveRange: nil) != nil
      else { throw StyleCheckFailure() }
    }

    private struct StyleCheckFailure: Error {}
  }
#endif
