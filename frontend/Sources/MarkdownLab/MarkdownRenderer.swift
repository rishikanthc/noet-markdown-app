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
      activeEditingRange: NSRange? = nil,
      to textView: NSTextView
    ) -> NSRange {
      guard let storage = textView.textStorage else { return NSRange(location: 0, length: 0) }
      let documentRange = NSRange(location: 0, length: storage.length)
      guard documentRange.length > 0 else {
        (textView as? MarkdownTextView)?.markdownDecorations = []
        textView.typingAttributes = baseAttributes()
        return documentRange
      }

      var targetRange: NSRange
      if let invalidatedRange {
        targetRange = paragraphEnvelope(for: invalidatedRange, in: storage.string as NSString)
          .intersection(documentRange) ?? documentRange
      } else {
        targetRange = documentRange
      }
      targetRange = compoundEnvelope(
        for: targetRange, plan: plan, source: storage.string as NSString
      ).intersection(documentRange) ?? documentRange
      if let activeEditingRange {
        targetRange = NSUnionRange(targetRange, activeEditingRange)
          .intersection(documentRange) ?? documentRange
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
        activeEditingRange: activeEditingRange, to: storage
      )
      storage.endEditing()
      if let markdownTextView = textView as? MarkdownTextView {
        markdownTextView.markdownDecorations = decorations(
          for: plan, source: storage.string as NSString
        )
      }
      synchronizeTypingAttributes(in: textView, storage: storage)
      return targetRange
    }

    private func compoundEnvelope(
      for range: NSRange,
      plan: MarkdownRenderPlan,
      source: NSString
    ) -> NSRange {
      plan.nodes.reduce(range) { result, node in
        guard node.range.intersection(result) != nil else { return result }
        let isCodeBlock = node.kind == Int(MD_NODE_CODE_BLOCK.rawValue)
        let isCallout = node.kind == Int(MD_NODE_BLOCK_QUOTE.rawValue)
          && callout(in: node.range, source: source) != nil
        return isCodeBlock || isCallout ? NSUnionRange(result, node.range) : result
      }
    }

    /// Resolves the source unit that enters edit mode at a caret position.
    /// Compound blocks are atomic editing objects; all other Markdown keeps
    /// the familiar line/paragraph activation behavior.
    func editingRange(containing offset: Int, in plan: MarkdownRenderPlan) -> NSRange {
      let source = plan.source as NSString
      guard source.length > 0 else { return NSRange(location: 0, length: 0) }
      let caret = min(max(offset, 0), source.length)
      let probe = min(caret, source.length - 1)

      let compound = plan.nodes
        .filter { node in
          let containsCaret = NSLocationInRange(probe, node.range)
            || caret == NSMaxRange(node.range)
          guard containsCaret else { return false }
          if node.kind == Int(MD_NODE_CODE_BLOCK.rawValue) { return true }
          return node.kind == Int(MD_NODE_BLOCK_QUOTE.rawValue)
            && callout(in: node.range, source: source) != nil
        }
        .min { $0.range.length < $1.range.length }
      if let compound { return compound.range }
      return source.paragraphRange(for: NSRange(location: caret, length: 0))
    }

    private func applyAttributes(
      plan: MarkdownRenderPlan,
      nodes: [MarkdownRenderPlan.Node],
      spans: [MarkdownRenderPlan.Span],
      in range: NSRange,
      activeEditingRange: NSRange?,
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

      applyCodeSyntax(nodes: nodes, in: range, source: storage.string as NSString, storage: storage)

      applyCalloutLabels(
        nodes: nodes, in: range, source: storage.string as NSString,
        activeEditingRange: activeEditingRange, storage: storage
      )

      // Syntax concealment is the final semantic layer, so highlighter colors
      // can never make a fence or delimiter visible again.
      for span in spans {
        let displayRange = concealableRange(for: span, source: storage.string as NSString)
        guard let spanRange = displayRange.intersection(range), spanRange.length > 0,
          isSyntaxMarker(span)
        else { continue }
        applyMarker(
          to: spanRange, activeEditingRange: activeEditingRange,
          source: storage.string as NSString, storage: storage
        )
        if span.role == Int(MD_SPAN_CODE_FENCE.rawValue),
          activeEditingRange?.intersection(spanRange) == nil
        {
          collapseFenceParagraph(containing: spanRange, storage: storage)
        }
      }

      applyHighlightSyntax(
        in: range, text: storage.string as NSString,
        activeEditingRange: activeEditingRange, storage: storage
      )

      collapseStructuralBlankParagraphs(
        in: range, nodes: nodes, source: storage.string as NSString, storage: storage
      )
    }

    private func applyBlockRole(
      _ node: MarkdownRenderPlan.Node,
      range: NSRange,
      source: NSString,
      storage: NSTextStorage
    ) {
      switch node.kind {
      case Int(MD_NODE_HEADING.rawValue):
        let level = headingLevel(in: range, source: source)
        storage.addAttributes([
          .font: Theme.sans(Theme.headingSizes[level - 1], weight: .semibold),
          .foregroundColor: level == 1 ? Theme.ink : Theme.inkSoft,
          .paragraphStyle: headingParagraphStyle(
            level: level,
            precedingSpacing: precedingContentSpacing(
              before: range, source: source, storage: storage
            )
          ),
          .kern: level <= 2 ? -0.22 : 0,
        ], range: range)
      case Int(MD_NODE_CODE_BLOCK.rawValue):
        storage.addAttributes([
          .font: Theme.mono(Theme.sizeBodySmall),
          .foregroundColor: Theme.textCol,
          .ligature: 0,
        ], range: range)
        applyComponentParagraphStyles(
          range: range, kind: .code, source: source, storage: storage
        )
      case Int(MD_NODE_BLOCK_QUOTE.rawValue):
        guard callout(in: range, source: source) != nil else { return }
        storage.addAttributes([
          .font: Theme.serif(Theme.sizeBodySmall),
          .foregroundColor: Theme.textCol,
        ], range: range)
        applyComponentParagraphStyles(
          range: range, kind: .callout, source: source, storage: storage
        )
      default:
        break
      }
    }

    private func applyInlineRole(_ node: MarkdownRenderPlan.Node, range: NSRange, storage: NSTextStorage) {
      switch node.kind {
      case Int(MD_NODE_CODE_SPAN.rawValue):
        storage.addAttributes([
          .font: Theme.mono(Theme.sizeBodySmall),
          .foregroundColor: Theme.codeInk,
          .ligature: 0,
        ], range: range)
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
      activeEditingRange: NSRange?,
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
        self.applyMarker(
          to: opening, activeEditingRange: activeEditingRange,
          source: text, storage: storage
        )
        self.applyMarker(
          to: closing, activeEditingRange: activeEditingRange,
          source: text, storage: storage
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

    /// Source characters stay one-to-one with MdCore offsets. Outside the
    /// active paragraph, negative per-glyph tracking cancels their exact
    /// advance so the rendered content starts at its real visual origin.
    private func applyMarker(
      to range: NSRange,
      activeEditingRange: NSRange?,
      source: NSString,
      storage: NSTextStorage
    ) {
      guard let activeEditingRange, range.intersection(activeEditingRange) != nil else {
        let font = Theme.mono(Theme.sizeMicro)
        for location in range.location..<NSMaxRange(range) {
          let character = source.substring(with: NSRange(location: location, length: 1)) as NSString
          let advance = character.size(withAttributes: [.font: font]).width
          storage.addAttributes([
            .font: font,
            .foregroundColor: NSColor.clear,
            .backgroundColor: NSColor.clear,
            .kern: -advance,
            .ligature: 0,
            .underlineStyle: 0,
            .strikethroughStyle: 0,
          ], range: NSRange(location: location, length: 1))
        }
        return
      }
      storage.addAttributes(markerAttributes(), range: range)
    }

    private struct Callout {
      let label: String
      let labelRange: NSRange
      let openingRange: NSRange
      let closingRange: NSRange

      var isWarning: Bool {
        label == "WARNING" || label == "CAUTION"
      }
    }

    private func decorations(
      for plan: MarkdownRenderPlan,
      source: NSString
    ) -> [MarkdownTextView.Decoration] {
      var result: [MarkdownTextView.Decoration] = []
      for node in plan.nodes {
        switch node.kind {
        case Int(MD_NODE_CODE_SPAN.rawValue):
          let content = codeSpanContentRange(node.range, source: source)
          guard content.length > 0 else { continue }
          result.append(.init(
            range: content,
            color: Theme.codeChip,
            radius: Theme.radiusSmall,
            shape: .inline(horizontalOutset: 5, verticalOutset: 3.5)
          ))
        case Int(MD_NODE_CODE_BLOCK.rawValue):
          result.append(.init(
            range: node.range,
            color: Theme.surfaceSubtle,
            radius: Theme.radiusSmall,
            shape: .block(verticalInset: Theme.space3)
          ))
        case Int(MD_NODE_BLOCK_QUOTE.rawValue):
          guard let callout = callout(in: node.range, source: source) else { continue }
          result.append(.init(
            range: node.range,
            color: callout.isWarning ? Theme.warningSurface : Theme.accentSoft,
            radius: Theme.radiusSmall,
            shape: .block(verticalInset: Theme.space3)
          ))
        default:
          break
        }
      }
      return result
    }

    private func applyCalloutLabels(
      nodes: [MarkdownRenderPlan.Node],
      in targetRange: NSRange,
      source: NSString,
      activeEditingRange: NSRange?,
      storage: NSTextStorage
    ) {
      for node in nodes where node.kind == Int(MD_NODE_BLOCK_QUOTE.rawValue) {
        guard let callout = callout(in: node.range, source: source),
          let labelRange = callout.labelRange.intersection(targetRange)
        else { continue }
        storage.addAttributes([
          .font: Theme.mono(Theme.sizeMicro, weight: .bold),
          .foregroundColor: callout.isWarning ? Theme.orange : Theme.accent,
          .kern: 0.6,
        ], range: labelRange)
        for markerRange in [callout.openingRange, callout.closingRange] {
          guard let clipped = markerRange.intersection(targetRange) else { continue }
          applyMarker(
            to: clipped, activeEditingRange: activeEditingRange,
            source: source, storage: storage
          )
        }
      }
    }

    private func callout(in range: NSRange, source: NSString) -> Callout? {
      guard let expression = try? NSRegularExpression(
        pattern: #"(?m)^\h*>\h*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]"#
      ), let match = expression.firstMatch(in: source as String, range: range),
        match.numberOfRanges > 1
      else { return nil }
      let labelRange = match.range(at: 1)
      return Callout(
        label: source.substring(with: labelRange).uppercased(),
        labelRange: labelRange,
        openingRange: NSRange(location: labelRange.location - 2, length: 2),
        closingRange: NSRange(location: NSMaxRange(labelRange), length: 1)
      )
    }

    private func applyCodeSyntax(
      nodes: [MarkdownRenderPlan.Node],
      in targetRange: NSRange,
      source: NSString,
      storage: NSTextStorage
    ) {
      for node in nodes {
        if node.kind == Int(MD_NODE_CODE_SPAN.rawValue) {
          guard let range = codeSpanContentRange(node.range, source: source).intersection(targetRange)
          else { continue }
          applyRegex(#"\b(?:0x[0-9A-Fa-f]+|\d+(?:\.\d+)?)\b"#, color: Theme.orange,
                     in: range, source: source, storage: storage)
        } else if node.kind == Int(MD_NODE_CODE_BLOCK.rawValue) {
          guard let range = node.range.intersection(targetRange) else { continue }
          highlightCodeBlock(in: range, source: source, storage: storage)
        }
      }
    }

    private func highlightCodeBlock(
      in range: NSRange,
      source: NSString,
      storage: NSTextStorage
    ) {
      var claimed: [NSRange] = []
      let rules: [(String, NSColor, NSFont?)] = [
        (#"(?s:/\*.*?\*/)|(?m://[^\n]*$)|(?m:(?<!\S)#(?![A-Fa-f0-9]{3,8}\b)[^\n]*$)"#,
         Theme.synComment, Theme.mono(Theme.sizeBodySmall, weight: .regular)),
        (#"\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'"#, Theme.synString, nil),
        (#"\b(?:true|false|null|nil|None|undefined|[0-9]+(?:\.[0-9]+)?)\b"#,
         Theme.synNumber, nil),
        (#"\b(?:actor|async|await|break|case|catch|class|const|continue|defer|do|else|enum|export|extension|false|for|func|function|guard|if|import|in|interface|let|mut|protocol|return|self|static|struct|switch|throws|try|typealias|var|while)\b"#,
         Theme.synKeyword, Theme.mono(Theme.sizeBodySmall, weight: .bold)),
        (#"\b[A-Z][A-Za-z0-9_]*\b"#, Theme.synType, nil),
        (#"\b[A-Za-z_][A-Za-z0-9_]*(?=\s*\()"#, Theme.synFunction, nil),
      ]
      for (pattern, color, font) in rules {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
        expression.enumerateMatches(in: source as String, range: range) { match, _, _ in
          guard let token = match?.range, token.length > 0,
            !claimed.contains(where: { $0.intersection(token) != nil })
          else { return }
          var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color]
          if let font { attributes[.font] = font }
          if color == Theme.synComment { attributes[.obliqueness] = 0.12 }
          storage.addAttributes(attributes, range: token)
          claimed.append(token)
        }
      }
    }

    private func applyRegex(
      _ pattern: String,
      color: NSColor,
      in range: NSRange,
      source: NSString,
      storage: NSTextStorage
    ) {
      guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
      expression.enumerateMatches(in: source as String, range: range) { match, _, _ in
        guard let match else { return }
        storage.addAttribute(.foregroundColor, value: color, range: match.range)
      }
    }

    private func codeSpanContentRange(_ range: NSRange, source: NSString) -> NSRange {
      guard range.length >= 2 else { return range }
      var openingLength = 0
      while openingLength < range.length,
        source.character(at: range.location + openingLength) == 0x60
      { openingLength += 1 }
      guard openingLength > 0, range.length >= openingLength * 2 else { return range }
      return NSRange(
        location: range.location + openingLength,
        length: range.length - openingLength * 2
      )
    }

    private func concealableRange(
      for span: MarkdownRenderPlan.Span,
      source: NSString
    ) -> NSRange {
      var range = span.range
      let expandsWhitespace = span.role == Int(MD_SPAN_BLOCK_QUOTE_MARKER.rawValue)
        || (span.role == Int(MD_SPAN_SYNTAX_MARKER.rawValue)
          && range.location == source.paragraphRange(for: range).location)
      if expandsWhitespace {
        while NSMaxRange(range) < source.length {
          let character = source.character(at: NSMaxRange(range))
          guard character == 0x20 || character == 0x09 else { break }
          range.length += 1
        }
      }
      return range
    }

    private func collapseFenceParagraph(
      containing range: NSRange,
      storage: NSTextStorage
    ) {
      let paragraph = (storage.string as NSString).paragraphRange(for: range)
      let existing = storage.attribute(
        .paragraphStyle, at: paragraph.location, effectiveRange: nil
      ) as? NSParagraphStyle
      let style = (existing?.mutableCopy() as? NSMutableParagraphStyle)
        ?? NSMutableParagraphStyle()
      style.minimumLineHeight = 0.1
      style.maximumLineHeight = 0.1
      style.lineSpacing = 0
      storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
    }

    private func synchronizeTypingAttributes(in textView: NSTextView, storage: NSTextStorage) {
      let selection = textView.selectedRange()
      guard selection.length == 0, storage.length > 0 else {
        textView.typingAttributes = baseAttributes()
        return
      }
      let location = min(selection.location, storage.length - 1)
      var attributes = storage.attributes(at: location, effectiveRange: nil)
      if let style = attributes[.paragraphStyle] as? NSParagraphStyle,
        style.maximumLineHeight > 0, style.maximumLineHeight <= 0.1
      {
        textView.typingAttributes = baseAttributes()
        return
      }
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

    private func headingParagraphStyle(
      level: Int,
      precedingSpacing: CGFloat
    ) -> NSParagraphStyle {
      let style = NSMutableParagraphStyle()
      style.firstLineHeadIndent = 0
      style.headIndent = 0
      style.lineSpacing = level <= 2 ? 1.5 : 2
      switch level {
      case 1:
        style.paragraphSpacingBefore = max(Theme.space9 - precedingSpacing, 0)
        style.paragraphSpacing = Theme.space4
      case 2:
        style.paragraphSpacingBefore = max(Theme.space8 - precedingSpacing, 0)
        style.paragraphSpacing = Theme.space3
      default:
        style.paragraphSpacingBefore = max(Theme.space5 - precedingSpacing, 0)
        style.paragraphSpacing = Theme.space2
      }
      return style
    }

    private enum ComponentKind {
      case code
      case callout
    }

    private func applyComponentParagraphStyles(
      range: NSRange,
      kind: ComponentKind,
      source: NSString,
      storage: NSTextStorage
    ) {
      var paragraphs: [NSRange] = []
      var location = range.location
      while location < NSMaxRange(range) {
        let paragraph = source.paragraphRange(for: NSRange(location: location, length: 0))
        guard let clipped = paragraph.intersection(range), clipped.length > 0 else { break }
        paragraphs.append(clipped)
        location = NSMaxRange(paragraph)
      }
      let precedingSpacing = precedingContentSpacing(
        before: range, source: source, storage: storage
      )
      for (index, paragraph) in paragraphs.enumerated() {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = Theme.space4
        style.headIndent = Theme.space4
        style.tailIndent = -Theme.space4
        style.lineSpacing = Theme.bodyLineSpacing
        style.paragraphSpacingBefore = index == 0
          ? max(Theme.space6 + Theme.space3 - precedingSpacing, 0)
          : 0
        if index == paragraphs.count - 1 {
          style.paragraphSpacing = Theme.space6 + Theme.space3
        } else if kind == .callout, index == 0 {
          style.paragraphSpacing = Theme.space1
        } else {
          style.paragraphSpacing = 0
        }
        style.lineBreakMode = .byWordWrapping
        storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
      }
    }

    private func precedingContentSpacing(
      before range: NSRange,
      source: NSString,
      storage: NSTextStorage
    ) -> CGFloat {
      guard range.location > 0 else { return 0 }
      var location = range.location - 1
      while location > 0 {
        let scalar = source.character(at: location)
        if scalar != 0x20, scalar != 0x09, scalar != 0x0A, scalar != 0x0D { break }
        location -= 1
      }
      let style = storage.attribute(
        .paragraphStyle, at: location, effectiveRange: nil
      ) as? NSParagraphStyle
      let spacing = style?.paragraphSpacing ?? 0
      // Component margins deliberately accumulate with other component
      // margins. Only ordinary prose/heading after-spacing is compensated.
      return spacing < Theme.space6 ? spacing : 0
    }

    private func collapseStructuralBlankParagraphs(
      in range: NSRange,
      nodes: [MarkdownRenderPlan.Node],
      source: NSString,
      storage: NSTextStorage
    ) {
      let compoundRanges = nodes.compactMap { node -> NSRange? in
        if node.kind == Int(MD_NODE_CODE_BLOCK.rawValue) { return node.range }
        if node.kind == Int(MD_NODE_BLOCK_QUOTE.rawValue),
          callout(in: node.range, source: source) != nil
        { return node.range }
        return nil
      }
      var location = range.location
      while location < NSMaxRange(range) {
        let paragraph = source.paragraphRange(for: NSRange(location: location, length: 0))
        guard let clipped = paragraph.intersection(range), clipped.length > 0 else { break }
        let content = source.substring(with: clipped)
          .trimmingCharacters(in: .whitespacesAndNewlines)
        let belongsToComponent = compoundRanges.contains { $0.intersection(clipped) != nil }
        if content.isEmpty, !belongsToComponent {
          let style = NSMutableParagraphStyle()
          style.minimumLineHeight = 0.1
          style.maximumLineHeight = 0.1
          style.lineSpacing = 0
          style.paragraphSpacing = 0
          style.paragraphSpacingBefore = 0
          storage.addAttribute(.paragraphStyle, value: style, range: clipped)
        }
        location = NSMaxRange(paragraph)
      }
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
