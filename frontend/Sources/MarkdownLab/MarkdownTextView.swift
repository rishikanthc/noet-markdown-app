#if os(macOS) && canImport(AppKit)
  import AppKit

  /// TextKit 2 editor surface with a centered editorial reading column.
  final class MarkdownTextView: NSTextView {
    struct Decoration: Equatable {
      enum Shape: Equatable {
        case inline(horizontalOutset: CGFloat, verticalOutset: CGFloat)
        case block(verticalInset: CGFloat)
      }

      let range: NSRange
      let color: NSColor
      let radius: CGFloat
      let shape: Shape
    }

    var maximumReadingWidth: CGFloat = Theme.readingWidth
    var minimumHorizontalInset: CGFloat = Theme.minimumHorizontalInset
    var markdownDecorations: [Decoration] = [] {
      didSet {
        guard oldValue != markdownDecorations else { return }
        needsDisplay = true
      }
    }

    private var isUpdatingReadingGeometry = false

    override func setFrameSize(_ newSize: NSSize) {
      super.setFrameSize(newSize)
      updateReadingGeometry(for: newSize.width)
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      updateReadingGeometry(for: bounds.width)
    }

    override func draw(_ dirtyRect: NSRect) {
      Theme.paper.setFill()
      dirtyRect.fill()
      drawMarkdownDecorations(in: dirtyRect)
      super.draw(dirtyRect)
    }

    private func drawMarkdownDecorations(in rect: NSRect) {
      guard !markdownDecorations.isEmpty,
        let contentManager = textContentStorage,
        let layoutManager = textLayoutManager
      else { return }

      let visibleRange = sourceRange(
        for: layoutManager.textViewportLayoutController.viewportRange,
        contentManager: contentManager
      )
      let visibleDecorations = markdownDecorations.filter { decoration in
        guard let visibleRange else { return true }
        return decoration.range.intersection(visibleRange) != nil
      }

      // Block surfaces must sit below inline chips when ranges overlap. Only
      // viewport components request geometry, keeping draw cost independent of
      // total document length.
      for decoration in visibleDecorations.sorted(by: { $0.isBlock && !$1.isBlock }) {
        guard let textRange = textRange(for: decoration.range, contentManager: contentManager)
        else { continue }
        layoutManager.ensureLayout(for: textRange)

        var segmentRects: [CGRect] = []
        layoutManager.enumerateTextSegments(
          in: textRange, type: .standard, options: [.rangeNotRequired]
        ) { _, frame, _, _ in
          guard !frame.isNull, !frame.isInfinite, frame.width >= 0, frame.height > 0 else {
            return true
          }
          segmentRects.append(frame.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y))
          return true
        }
        guard !segmentRects.isEmpty else { continue }

        decoration.color.setFill()
        switch decoration.shape {
        case .inline(let horizontalOutset, let verticalOutset):
          for segment in segmentRects {
            let surface = segment.insetBy(dx: -horizontalOutset, dy: -verticalOutset)
            guard surface.intersects(rect) else { continue }
            NSBezierPath(roundedRect: surface, xRadius: decoration.radius, yRadius: decoration.radius)
              .fill()
          }
        case .block(let verticalInset):
          let union = segmentRects.dropFirst().reduce(segmentRects[0]) { $0.union($1) }
          guard let textContainer else { continue }
          let surface = CGRect(
            x: textContainerOrigin.x,
            y: union.minY - verticalInset,
            width: textContainer.containerSize.width,
            height: union.height + verticalInset * 2
          )
          guard surface.intersects(rect) else { continue }
          NSBezierPath(roundedRect: surface, xRadius: decoration.radius, yRadius: decoration.radius)
            .fill()
        }
      }
    }

    private func updateReadingGeometry(for viewWidth: CGFloat) {
      guard !isUpdatingReadingGeometry, let textContainer else { return }
      isUpdatingReadingGeometry = true
      defer { isUpdatingReadingGeometry = false }

      let available = max(viewWidth - minimumHorizontalInset * 2, 320)
      let readingWidth = min(maximumReadingWidth, available)
      let horizontalInset = max((viewWidth - readingWidth) / 2, minimumHorizontalInset)

      textContainer.widthTracksTextView = false
      textContainer.containerSize = NSSize(
        width: readingWidth,
        height: CGFloat.greatestFiniteMagnitude
      )
      let desiredInset = NSSize(width: horizontalInset, height: Theme.verticalInset)
      if textContainerInset != desiredInset {
        textContainerInset = desiredInset
      }
    }

    private func textRange(
      for range: NSRange,
      contentManager: NSTextContentManager
    ) -> NSTextRange? {
      let document = contentManager.documentRange
      guard range.location >= 0, range.length >= 0,
        let start = contentManager.location(document.location, offsetBy: range.location),
        let end = contentManager.location(start, offsetBy: range.length)
      else { return nil }
      return NSTextRange(location: start, end: end)
    }

    private func sourceRange(
      for textRange: NSTextRange?,
      contentManager: NSTextContentManager
    ) -> NSRange? {
      guard let textRange else { return nil }
      let documentStart = contentManager.documentRange.location
      let location = contentManager.offset(from: documentStart, to: textRange.location)
      let length = contentManager.offset(from: textRange.location, to: textRange.endLocation)
      guard location != NSNotFound, length != NSNotFound else { return nil }
      return NSRange(location: location, length: length)
    }

  }

  private extension MarkdownTextView.Decoration {
    var isBlock: Bool {
      if case .block = shape { return true }
      return false
    }
  }
#endif
