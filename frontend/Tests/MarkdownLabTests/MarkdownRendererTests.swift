#if os(macOS) && canImport(AppKit) && canImport(CMdCore)
  import AppKit
  import CMdCore
  @testable import MarkdownLab
  import XCTest

  final class MarkdownRendererTests: XCTestCase {
    func testConcealmentPreservesSourceAndSelection() throws {
      let source = "# Title\n\nBody with **strong** and ==highlight==.\n"
      let plan = try renderPlan(source)
      let textView = MarkdownTextView(usingTextLayoutManager: true)
      textView.string = source
      let selection = NSRange(location: (source as NSString).range(of: "Title").location, length: 0)
      textView.setSelectedRange(selection)
      let active = (source as NSString).paragraphRange(for: selection)

      MarkdownRenderer().apply(
        plan: plan, invalidatedRange: nil, activeParagraphRange: active, to: textView
      )

      XCTAssertEqual(textView.string, source)
      XCTAssertEqual(textView.textStorage?.length, source.utf16.count)
      XCTAssertEqual(textView.selectedRange(), selection)
    }

    func testMarkersAreConcealedOnlyOutsideActiveParagraph() throws {
      let source = "# Title\n\nBody with **strong**.\n"
      let plan = try renderPlan(source)
      let text = source as NSString
      let textView = MarkdownTextView(usingTextLayoutManager: true)
      textView.string = source
      let heading = text.paragraphRange(for: text.range(of: "Title"))
      let bodyMarker = text.range(of: "**")
      let renderer = MarkdownRenderer()

      renderer.apply(
        plan: plan, invalidatedRange: nil, activeParagraphRange: heading, to: textView
      )
      let concealedColor = textView.textStorage?.attribute(
        .foregroundColor, at: bodyMarker.location, effectiveRange: nil
      ) as? NSColor
      let concealedFont = textView.textStorage?.attribute(
        .font, at: bodyMarker.location, effectiveRange: nil
      ) as? NSFont
      XCTAssertEqual(concealedColor, .clear)
      XCTAssertLessThanOrEqual(concealedFont?.pointSize ?? 100, 0.1)

      let body = text.paragraphRange(for: bodyMarker)
      renderer.apply(
        plan: plan, invalidatedRange: NSUnionRange(heading, body),
        activeParagraphRange: body, to: textView
      )
      let revealedColor = textView.textStorage?.attribute(
        .foregroundColor, at: bodyMarker.location, effectiveRange: nil
      ) as? NSColor
      XCTAssertNotEqual(revealedColor, .clear)
      XCTAssertEqual(textView.string, source)
    }

    func testSemanticRestyleDoesNotMoveCaretAfterTyping() throws {
      let source = "Body with **strong** text.\n"
      let textView = MarkdownTextView(usingTextLayoutManager: true)
      textView.string = source
      let insertion = (source as NSString).range(of: " text").location
      textView.setSelectedRange(NSRange(location: insertion, length: 0))
      textView.insertText("!", replacementRange: textView.selectedRange())
      let selectionAfterTyping = textView.selectedRange()
      let updatedPlan = try renderPlan(textView.string)
      let active = (textView.string as NSString).paragraphRange(for: selectionAfterTyping)

      MarkdownRenderer().apply(
        plan: updatedPlan, invalidatedRange: active,
        activeParagraphRange: active, to: textView
      )

      XCTAssertEqual(textView.selectedRange(), selectionAfterTyping)
      XCTAssertEqual(textView.string, "Body with **strong**! text.\n")
    }

    func testHeadingTypingUsesHeadingStyleBeforeEngineRefresh() throws {
      let source = "# Heading\n"
      let textView = MarkdownTextView(usingTextLayoutManager: true)
      textView.string = source
      let insertion = (source as NSString).range(of: "Heading").upperBound
      textView.setSelectedRange(NSRange(location: insertion, length: 0))
      let active = (source as NSString).paragraphRange(for: textView.selectedRange())
      MarkdownRenderer().apply(
        plan: try renderPlan(source), invalidatedRange: nil,
        activeParagraphRange: active, to: textView
      )

      let expectedFont = textView.typingAttributes[.font] as? NSFont
      textView.insertText("!", replacementRange: textView.selectedRange())
      let insertedFont = textView.textStorage?.attribute(
        .font, at: insertion, effectiveRange: nil
      ) as? NSFont

      XCTAssertEqual(insertedFont?.pointSize, expectedFont?.pointSize)
      XCTAssertEqual(insertedFont?.familyName, expectedFont?.familyName)
    }

    private func renderPlan(_ source: String) throws -> MarkdownRenderPlan {
      let engine = try MdCoreEngine(source: source)
      let snapshot = try engine.canonicalSnapshot()
      let nodeRanges = try engine.utf16Ranges(for: snapshot.nodes.map {
        MdByteRange(start: $0.source_start_byte, end: $0.source_end_byte)
      })
      let spanRanges = try engine.utf16Ranges(for: snapshot.spans.map {
        MdByteRange(start: $0.start_byte, end: $0.end_byte)
      })
      return MarkdownRenderPlan(
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
    }
  }
#endif
