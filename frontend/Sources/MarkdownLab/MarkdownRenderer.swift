#if os(macOS) && canImport(AppKit) && canImport(CMdCore)
  import AppKit
  import CMdCore
  import Foundation

  /// A source-preserving renderer. It changes attributes only: every UTF-16
  /// code unit in MdCore remains present at the same NSTextStorage offset.
  final class MarkdownRenderer {
    func baseAttributes() -> [NSAttributedString.Key: Any] {
      [
        .font: Theme.serif(Theme.sizeBody),
        .foregroundColor: Theme.textCol,
        .paragraphStyle: bodyParagraphStyle(),
        .ligature: 1,
      ]
    }

    /// Applies only the paragraphs MdCore marked invalid. This method is purely
    /// presentational and therefore has no Zig dependency.
    @discardableResult
    func apply(
      plan: MarkdownRenderPlan,
      invalidatedRange: NSRange?,
      activeParagraphRange: NSRange? = nil,
      to textView: NSTextView
    ) -> NSRange {
      guard let storage = textView.textStorage else { return NSRange(location: 0, length: 0) }
      let documentRange = NSRange(location: 0, length: storage.length)
      guard documentRange.length > 0 else {
        textView.typingAttributes = baseAttributes()
        return documentRange
      }

      let targetRange: NSRange
      if let invalidatedRange {
        targetRange = paragraphEnvelope(for: invalidatedRange, in: storage.string as NSString)
          .intersection(documentRange) ?? documentRange
      } else {
        targetRange = documentRange
      }

      let nodes = plan.nodes.filter { node in
        node.range.intersection(targetRange) != nil
      }
      let spans = plan.spans.filter { span in
        span.range.intersection(targetRange) != nil
      }

      storage.beginEditing()
      applyAttributes(
        plan: plan, nodes: nodes, spans: spans, in: targetRange,
        activeParagraphRange: activeParagraphRange, to: storage
      )
      storage.endEditing()
      synchronizeTypingAttributes(in: textView, storage: storage)
      return targetRange
    }

    private func applyAttributes(
      plan: MarkdownRenderPlan,
      nodes: [MarkdownRenderPlan.Node],
      spans: [MarkdownRenderPlan.Span],
      in range: NSRange,
      activeParagraphRange: NSRange?,
      to storage: NSTextStorage
    ) {
      storage.setAttributes(baseAttributes(), range: range)

      // Block role establishes the type scale and paragraph rhythm first.
      for node in nodes {
        guard let nodeRange = node.range.intersection(range), nodeRange.length > 0 else { continue }
        applyBlockRole(node, range: nodeRange, source: storage.string as NSString, storage: storage)
      }

      // Inline roles are layered over the block font, preserving a heading's
      // family and size when it contains strong or emphasis.
      for node in nodes {
        guard let nodeRange = node.range.intersection(range), nodeRange.length > 0 else { continue }
        applyInlineRole(node, range: nodeRange, storage: storage)
      }

      for span in spans {
        guard let spanRange = span.range.intersection(range), spanRange.length > 0,
          isSyntaxMarker(span)
        else { continue }
        storage.addAttributes(
          markerAttributes(for: spanRange, activeParagraphRange: activeParagraphRange),
          range: spanRange
        )
      }

      applyHighlightSyntax(
        in: range, text: storage.string as NSString,
        activeParagraphRange: activeParagraphRange, storage: storage
      )
    }

    private func applyBlockRole(
      _ node: MarkdownRenderPlan.Node,
      range: NSRange,
      source: NSString,
      storage: NSTextStorage
    ) {
      guard node.kind == Int(MD_NODE_HEADING.rawValue) else { return }
      let level = headingLevel(in: range, source: source)
      storage.addAttributes([
        .font: Theme.sans(Theme.headingSizes[level - 1], weight: .semibold),
        .foregroundColor: level == 1 ? Theme.ink : Theme.inkSoft,
        .paragraphStyle: headingParagraphStyle(level: level),
        .kern: level <= 2 ? -0.22 : 0,
      ], range: range)
    }

    private func applyInlineRole(_ node: MarkdownRenderPlan.Node, range: NSRange, storage: NSTextStorage) {
      switch node.kind {
      case Int(MD_NODE_STRONG.rawValue):
        applyFontTrait(bold: true, italic: nil, range: range, storage: storage)
        storage.addAttribute(.foregroundColor, value: Theme.ink, range: range)
      case Int(MD_NODE_EMPHASIS.rawValue):
        applyFontTrait(bold: nil, italic: true, range: range, storage: storage)
      case Int(MD_NODE_STRIKETHROUGH.rawValue):
        storage.addAttributes([
          .strikethroughStyle: NSUnderlineStyle.single.rawValue,
          .strikethroughColor: Theme.muted,
        ], range: range)
      default:
        break
      }
    }

    private func applyHighlightSyntax(
      in range: NSRange,
      text: NSString,
      activeParagraphRange: NSRange?,
      storage: NSTextStorage
    ) {
      guard let expression = try? NSRegularExpression(pattern: #"==([^=\n](?:.*?[^=\n])?)=="#) else {
        return
      }
      expression.enumerateMatches(in: text as String, range: range) { match, _, _ in
        guard let match, match.numberOfRanges > 1 else { return }
        storage.addAttribute(.backgroundColor, value: Theme.highlight, range: match.range(at: 1))
        let opening = NSRange(location: match.range.location, length: 2)
        let closing = NSRange(location: NSMaxRange(match.range) - 2, length: 2)
        storage.addAttributes(
          self.markerAttributes(for: opening, activeParagraphRange: activeParagraphRange),
          range: opening
        )
        storage.addAttributes(
          self.markerAttributes(for: closing, activeParagraphRange: activeParagraphRange),
          range: closing
        )
      }
    }

    private func applyFontTrait(
      bold: Bool?, italic: Bool?, range: NSRange, storage: NSTextStorage
    ) {
      var replacements: [(NSRange, NSFont)] = []
      storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
        let font = value as? NSFont ?? Theme.serif(Theme.sizeBody)
        replacements.append((subrange, Theme.applying(bold: bold, italic: italic, to: font)))
      }
      for (subrange, font) in replacements {
        storage.addAttribute(.font, value: font, range: subrange)
      }
    }

    private func isSyntaxMarker(_ span: MarkdownRenderPlan.Span) -> Bool {
      switch span.role {
      case Int(MD_SPAN_SYNTAX_MARKER.rawValue),
        Int(MD_SPAN_CODE_FENCE.rawValue),
        Int(MD_SPAN_CODE_LANGUAGE.rawValue),
        Int(MD_SPAN_LINK_DESTINATION.rawValue),
        Int(MD_SPAN_IMAGE_DESTINATION.rawValue),
        Int(MD_SPAN_BLOCK_QUOTE_MARKER.rawValue),
        Int(MD_SPAN_LIST_MARKER.rawValue),
        Int(MD_SPAN_TASK_MARKER.rawValue),
        Int(MD_SPAN_TABLE_DELIMITER.rawValue):
        return true
      default:
        return false
      }
    }

    private func markerAttributes() -> [NSAttributedString.Key: Any] {
      [
        .font: Theme.mono(Theme.sizeMicro),
        .foregroundColor: Theme.faint,
        .kern: 0,
      ]
    }

    private func markerAttributes(
      for range: NSRange,
      activeParagraphRange: NSRange?
    ) -> [NSAttributedString.Key: Any] {
      guard let activeParagraphRange, range.intersection(activeParagraphRange) != nil else {
        return concealedMarkerAttributes()
      }
      return markerAttributes()
    }

    /// Marker characters remain in storage for native caret geometry, but
    /// consume virtually no visual width outside the active paragraph.
    private func concealedMarkerAttributes() -> [NSAttributedString.Key: Any] {
      [
        .font: Theme.mono(0.1),
        .foregroundColor: NSColor.clear,
        .backgroundColor: NSColor.clear,
        .kern: -0.04,
        .ligature: 0,
        .underlineStyle: 0,
        .strikethroughStyle: 0,
      ]
    }

    private func synchronizeTypingAttributes(in textView: NSTextView, storage: NSTextStorage) {
      let selection = textView.selectedRange()
      guard selection.length == 0, storage.length > 0 else {
        textView.typingAttributes = baseAttributes()
        return
      }
      let location = min(selection.location, storage.length - 1)
      var attributes = storage.attributes(at: location, effectiveRange: nil)
      // Selection and spelling are transient presentation concerns, never
      // attributes that newly inserted source characters should inherit.
      attributes.removeValue(forKey: .backgroundColor)
      attributes.removeValue(forKey: .underlineColor)
      textView.typingAttributes = attributes
    }

    private func bodyParagraphStyle() -> NSParagraphStyle {
      let style = NSMutableParagraphStyle()
      style.lineSpacing = Theme.bodyLineSpacing
      style.paragraphSpacing = Theme.paragraphSpacing
      style.lineBreakMode = .byWordWrapping
      style.hyphenationFactor = 0
      return style
    }

    private func headingParagraphStyle(level: Int) -> NSParagraphStyle {
      let style = NSMutableParagraphStyle()
      style.firstLineHeadIndent = 0
      style.headIndent = 0
      style.lineSpacing = level <= 2 ? 1.5 : 2
      switch level {
      case 1:
        style.paragraphSpacingBefore = Theme.space9
        style.paragraphSpacing = Theme.space4
      case 2:
        style.paragraphSpacingBefore = Theme.space8
        style.paragraphSpacing = Theme.space3
      default:
        style.paragraphSpacingBefore = Theme.space5
        style.paragraphSpacing = Theme.space2
      }
      return style
    }

    private func headingLevel(in range: NSRange, source: NSString) -> Int {
      var offset = range.location
      let end = min(NSMaxRange(range), source.length)
      var level = 0
      while offset < end, level < 6,
        source.character(at: offset) == UInt16(UnicodeScalar("#").value)
      {
        level += 1
        offset += 1
      }
      return max(level, 1)
    }

    private func paragraphEnvelope(for range: NSRange, in source: NSString) -> NSRange {
      guard source.length > 0 else { return NSRange(location: 0, length: 0) }
      let start = min(range.location, source.length - 1)
      let end = min(max(NSMaxRange(range) - 1, start), source.length - 1)
      return NSUnionRange(
        source.paragraphRange(for: NSRange(location: start, length: 0)),
        source.paragraphRange(for: NSRange(location: end, length: 0))
      )
    }

  }
#endif
