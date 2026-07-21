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
        plan: plan, invalidatedRange: nil, activeEditingRange: active, to: textView
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
        plan: plan, invalidatedRange: nil, activeEditingRange: heading, to: textView
      )
      let concealedColor = textView.textStorage?.attribute(
        .foregroundColor, at: bodyMarker.location, effectiveRange: nil
      ) as? NSColor
      let concealedFont = textView.textStorage?.attribute(
        .font, at: bodyMarker.location, effectiveRange: nil
      ) as? NSFont
      let concealedKern = textView.textStorage?.attribute(
        .kern, at: bodyMarker.location, effectiveRange: nil
      ) as? CGFloat
      XCTAssertEqual(concealedColor, .clear)
      XCTAssertEqual(concealedFont?.pointSize, Theme.sizeMicro)
      XCTAssertLessThan(concealedKern ?? 0, 0)

      let body = text.paragraphRange(for: bodyMarker)
      renderer.apply(
        plan: plan, invalidatedRange: NSUnionRange(heading, body),
        activeEditingRange: body, to: textView
      )
      let revealedColor = textView.textStorage?.attribute(
        .foregroundColor, at: bodyMarker.location, effectiveRange: nil
      ) as? NSColor
      XCTAssertNotEqual(revealedColor, .clear)
      XCTAssertEqual(textView.string, source)
    }

    func testHeadingPrefixHasZeroVisualAdvanceWhenInactive() throws {
      let source = "## Heading\n\nBody\n"
      let text = source as NSString
      let textView = MarkdownTextView(usingTextLayoutManager: true)
      textView.string = source
      let body = text.paragraphRange(for: text.range(of: "Body"))
      MarkdownRenderer().apply(
        plan: try renderPlan(source), invalidatedRange: nil,
        activeEditingRange: body, to: textView
      )

      let prefix = text.range(of: "## ")
      var visualAdvance: CGFloat = 0
      for location in prefix.location..<NSMaxRange(prefix) {
        let attributes = textView.textStorage?.attributes(at: location, effectiveRange: nil) ?? [:]
        let font = attributes[.font] as? NSFont ?? Theme.mono(Theme.sizeMicro)
        let glyph = text.substring(with: NSRange(location: location, length: 1)) as NSString
        visualAdvance += glyph.size(withAttributes: [.font: font]).width
        visualAdvance += attributes[.kern] as? CGFloat ?? 0
      }
      XCTAssertEqual(visualAdvance, 0, accuracy: 0.01)
    }

    func testCalloutsAndCodeUseTypstPresentationWithoutChangingSource() throws {
      let source = """
        > [!NOTE]
        > Callout body.

        Inline `revision + 1` value.

        ```swift
        struct RenderSnapshot {
          let revision: UInt64
        }
        ```
        """
      let text = source as NSString
      let textView = MarkdownTextView(usingTextLayoutManager: true)
      textView.string = source
      let selection = NSRange(location: text.range(of: "Callout body").location, length: 0)
      textView.setSelectedRange(selection)
      let active = text.paragraphRange(for: selection)

      MarkdownRenderer().apply(
        plan: try renderPlan(source), invalidatedRange: nil,
        activeEditingRange: active, to: textView
      )

      XCTAssertEqual(textView.string, source)
      XCTAssertEqual(textView.selectedRange(), selection)
      XCTAssertTrue(textView.markdownDecorations.contains { $0.color == Theme.accentSoft })
      XCTAssertTrue(textView.markdownDecorations.contains { $0.color == Theme.codeChip })
      XCTAssertTrue(textView.markdownDecorations.contains { $0.color == Theme.surfaceSubtle })

      let label = text.range(of: "NOTE")
      let labelColor = textView.textStorage?.attribute(
        .foregroundColor, at: label.location, effectiveRange: nil
      ) as? NSColor
      XCTAssertEqual(labelColor, Theme.accent)

      let inlineNumber = text.range(of: "1")
      let inlineNumberColor = textView.textStorage?.attribute(
        .foregroundColor, at: inlineNumber.location, effectiveRange: nil
      ) as? NSColor
      XCTAssertEqual(inlineNumberColor, Theme.orange)

      let keyword = text.range(of: "struct")
      let keywordColor = textView.textStorage?.attribute(
        .foregroundColor, at: keyword.location, effectiveRange: nil
      ) as? NSColor
      XCTAssertEqual(keywordColor, Theme.synKeyword)
    }

    func testCompoundBlocksResolveToOneEditingObject() throws {
      let source = """
        > [!NOTE]
        > First callout line.
        > Second callout line.

        Between blocks.

        ```swift
        struct Snapshot {
          let revision: UInt64
        }
        ```
        """
      let text = source as NSString
      let plan = try renderPlan(source)
      let renderer = MarkdownRenderer()

      let calloutFromLabel = renderer.editingRange(
        containing: text.range(of: "NOTE").location, in: plan
      )
      let calloutFromLastLine = renderer.editingRange(
        containing: text.range(of: "Second callout").location, in: plan
      )
      XCTAssertEqual(calloutFromLabel, calloutFromLastLine)
      XCTAssertTrue(calloutFromLabel.length > text.paragraphRange(for: text.range(of: "NOTE")).length)

      let codeFromFirstLine = renderer.editingRange(
        containing: text.range(of: "struct Snapshot").location, in: plan
      )
      let codeFromLastLine = renderer.editingRange(
        containing: text.range(of: "revision").location, in: plan
      )
      XCTAssertEqual(codeFromFirstLine, codeFromLastLine)
      XCTAssertTrue(codeFromFirstLine.length > text.paragraphRange(for: text.range(of: "revision")).length)

      let ordinary = renderer.editingRange(
        containing: text.range(of: "Between blocks").location, in: plan
      )
      XCTAssertEqual(ordinary, text.paragraphRange(for: text.range(of: "Between blocks")))
    }

    func testActivatingCompoundBlockRevealsAllOfItsSourceMarkers() throws {
      let source = """
        > [!NOTE]
        > First line.
        > Second line.

        ```swift
        let first = 1
        let second = 2
        ```
        """
      let text = source as NSString
      let plan = try renderPlan(source)
      let renderer = MarkdownRenderer()
      let textView = MarkdownTextView(usingTextLayoutManager: true)
      textView.string = source

      let calloutRange = renderer.editingRange(
        containing: text.range(of: "Second line").location, in: plan
      )
      renderer.apply(
        plan: plan, invalidatedRange: nil,
        activeEditingRange: calloutRange, to: textView
      )
      let quoteMarkers = plan.spans.filter {
        $0.role == Int(MD_SPAN_BLOCK_QUOTE_MARKER.rawValue)
          && $0.range.intersection(calloutRange) != nil
      }
      XCTAssertGreaterThanOrEqual(quoteMarkers.count, 3)
      for marker in quoteMarkers {
        let color = textView.textStorage?.attribute(
          .foregroundColor, at: marker.range.location, effectiveRange: nil
        ) as? NSColor
        XCTAssertNotEqual(color, .clear)
      }

      let codeRange = renderer.editingRange(
        containing: text.range(of: "second = 2").location, in: plan
      )
      renderer.apply(
        plan: plan, invalidatedRange: NSUnionRange(calloutRange, codeRange),
        activeEditingRange: codeRange, to: textView
      )
      let fences = plan.spans.filter {
        $0.role == Int(MD_SPAN_CODE_FENCE.rawValue)
          && $0.range.intersection(codeRange) != nil
      }
      XCTAssertEqual(fences.count, 2)
      for fence in fences {
        let color = textView.textStorage?.attribute(
          .foregroundColor, at: fence.range.location, effectiveRange: nil
        ) as? NSColor
        XCTAssertNotEqual(color, .clear)
      }
    }

    func testPartialRefreshStylesCodeBlockAsOneSpacingUnit() throws {
      let source = """
        Before.

        ```swift
        struct RenderSnapshot {
          let revision: UInt64
          let elapsedMilliseconds: Double
        }
        ```

        After.
        """
      let text = source as NSString
      let plan = try renderPlan(source)
      let renderer = MarkdownRenderer()
      let textView = MarkdownTextView(usingTextLayoutManager: true)
      textView.string = source
      let caretLine = text.paragraphRange(for: text.range(of: "elapsedMilliseconds"))
      let codeRange = renderer.editingRange(
        containing: text.range(of: "elapsedMilliseconds").location, in: plan
      )

      let applied = renderer.apply(
        plan: plan, invalidatedRange: caretLine,
        activeEditingRange: codeRange, to: textView
      )

      XCTAssertTrue(NSEqualRanges(applied.intersection(codeRange) ?? .init(), codeRange))
      for token in ["struct RenderSnapshot", "revision", "elapsedMilliseconds"] {
        let style = textView.textStorage?.attribute(
          .paragraphStyle, at: text.range(of: token).location, effectiveRange: nil
        ) as? NSParagraphStyle
        XCTAssertEqual(style?.paragraphSpacingBefore, 0)
        XCTAssertEqual(style?.paragraphSpacing, 0)
      }
    }

    func testStructuralBlankLinesDoNotAddLayoutHeightToTypstMargins() throws {
      let source = """
        Intro paragraph.

        ## Section

        Body paragraph.

        > [!NOTE]
        > Compact body.

        After callout.
        """
      let text = source as NSString
      let plan = try renderPlan(source)
      let textView = MarkdownTextView(usingTextLayoutManager: true)
      textView.string = source
      MarkdownRenderer().apply(plan: plan, invalidatedRange: nil, to: textView)

      var searchLocation = 0
      var blankCount = 0
      while searchLocation < text.length {
        let paragraph = text.paragraphRange(
          for: NSRange(location: searchLocation, length: 0)
        )
        let content = text.substring(with: paragraph)
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
          blankCount += 1
          let style = textView.textStorage?.attribute(
            .paragraphStyle, at: paragraph.location, effectiveRange: nil
          ) as? NSParagraphStyle
          XCTAssertEqual(style?.maximumLineHeight, 0.1)
          XCTAssertEqual(style?.paragraphSpacing, 0)
        }
        searchLocation = NSMaxRange(paragraph)
      }
      XCTAssertEqual(blankCount, 4)

      let introStyle = textView.textStorage?.attribute(
        .paragraphStyle, at: text.range(of: "Intro paragraph").location, effectiveRange: nil
      ) as? NSParagraphStyle
      let headingStyle = textView.textStorage?.attribute(
        .paragraphStyle, at: text.range(of: "Section").location, effectiveRange: nil
      ) as? NSParagraphStyle
      XCTAssertEqual(
        (introStyle?.paragraphSpacing ?? 0) + (headingStyle?.paragraphSpacingBefore ?? 0),
        Theme.space8,
        accuracy: 0.01
      )

      let bodyStyle = textView.textStorage?.attribute(
        .paragraphStyle, at: text.range(of: "Body paragraph").location, effectiveRange: nil
      ) as? NSParagraphStyle
      let calloutStyle = textView.textStorage?.attribute(
        .paragraphStyle, at: text.range(of: "> [!NOTE]").location, effectiveRange: nil
      ) as? NSParagraphStyle
      XCTAssertEqual(
        (bodyStyle?.paragraphSpacing ?? 0) + (calloutStyle?.paragraphSpacingBefore ?? 0),
        Theme.space6 + Theme.space3,
        accuracy: 0.01
      )
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
        activeEditingRange: active, to: textView
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
        activeEditingRange: active, to: textView
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
