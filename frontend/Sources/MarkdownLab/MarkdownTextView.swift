#if os(macOS) && canImport(AppKit)
  import AppKit

  /// TextKit 2 editor surface with a centered editorial reading column.
  final class MarkdownTextView: NSTextView {
    struct ImageDecoration: Equatable {
      let range: NSRange
      let url: URL
      let width: CGFloat
      let intrinsicSize: NSSize
      let caption: String
    }

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
    var markdownImages: [ImageDecoration] = [] {
      didSet {
        guard oldValue != markdownImages else { return }
        if markdownImages.isEmpty { imageHitRegions = [] }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
      }
    }
    var imageDropHandler: ((URL, Int) -> Void)?
    var imageLoadHandler: ((URL, NSSize) -> Void)?
    var imageClickHandler: ((NSRange) -> Void)?

    private var isUpdatingReadingGeometry = false
    private var imageCache: [URL: NSImage] = [:]
    private var pendingImageLoads: Set<URL> = []
    private var failedImageURLs: Set<URL> = []
    private var imageHitRegions: [(range: NSRange, rect: NSRect)] = []

    override func setFrameSize(_ newSize: NSSize) {
      super.setFrameSize(newSize)
      updateReadingGeometry(for: newSize.width)
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      registerForDraggedTypes([.fileURL])
      updateReadingGeometry(for: bounds.width)
    }

    override func draw(_ dirtyRect: NSRect) {
      Theme.paper.setFill()
      dirtyRect.fill()
      drawMarkdownDecorations(in: dirtyRect)
      super.draw(dirtyRect)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
      imageURLs(from: sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
      !imageURLs(from: sender.draggingPasteboard).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
      guard let url = imageURLs(from: sender.draggingPasteboard).first else { return false }
      let point = convert(sender.draggingLocation, from: nil)
      let insertion = characterIndexForInsertion(at: point)
      imageDropHandler?(url, insertion)
      return true
    }

    override func mouseDown(with event: NSEvent) {
      let point = convert(event.locationInWindow, from: nil)
      if let hit = imageHitRegions.first(where: { $0.rect.contains(point) }) {
        imageClickHandler?(hit.range)
        return
      }
      super.mouseDown(with: event)
    }

    override func resetCursorRects() {
      super.resetCursorRects()
      for hit in imageHitRegions { addCursorRect(hit.rect, cursor: .pointingHand) }
    }

    private func drawMarkdownDecorations(in rect: NSRect) {
      guard (!markdownDecorations.isEmpty || !markdownImages.isEmpty),
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

      drawImages(in: rect, visibleRange: visibleRange, contentManager: contentManager, layoutManager: layoutManager)
    }

    private func drawImages(
      in dirtyRect: NSRect,
      visibleRange: NSRange?,
      contentManager: NSTextContentManager,
      layoutManager: NSTextLayoutManager
    ) {
      var hitRegions: [(range: NSRange, rect: NSRect)] = []
      for decoration in markdownImages where visibleRange?.intersection(decoration.range) != nil || visibleRange == nil {
        guard let textRange = textRange(for: decoration.range, contentManager: contentManager)
        else { continue }
        layoutManager.ensureLayout(for: textRange)
        var union = CGRect.null
        layoutManager.enumerateTextSegments(
          in: textRange, type: .standard, options: [.rangeNotRequired]
        ) { _, frame, _, _ in
          guard !frame.isNull, !frame.isInfinite, frame.height > 0 else { return true }
          union = union.union(frame.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y))
          return true
        }
        guard !union.isNull, let textContainer else { continue }
        let availableWidth = textContainer.containerSize.width
        let imageWidth = min(decoration.width, availableWidth)
        let ratio = decoration.intrinsicSize.width / max(decoration.intrinsicSize.height, 1)
        let imageHeight = imageWidth / max(ratio, 0.01)
        let imageRect = CGRect(
          x: textContainerOrigin.x + (availableWidth - imageWidth) / 2,
          y: union.minY,
          width: imageWidth,
          height: imageHeight
        )
        hitRegions.append((decoration.range, imageRect))
        guard imageRect.union(union).intersects(dirtyRect) else { continue }
        if let image = cachedImage(at: decoration.url) {
          NSGraphicsContext.saveGraphicsState()
          NSBezierPath(
            roundedRect: imageRect, xRadius: Theme.radiusSmall, yRadius: Theme.radiusSmall
          ).addClip()
          image.draw(
            in: imageRect, from: .zero, operation: .sourceOver, fraction: 1,
            respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high]
          )
          NSGraphicsContext.restoreGraphicsState()
          Theme.hairline.setStroke()
          let border = NSBezierPath(
            roundedRect: imageRect, xRadius: Theme.radiusSmall, yRadius: Theme.radiusSmall
          )
          border.lineWidth = 1
          border.stroke()
        } else if failedImageURLs.contains(decoration.url) {
          drawImageFailure(in: imageRect)
        }
        if !decoration.caption.isEmpty {
          drawCaption(
            decoration.caption,
            in: CGRect(
              x: textContainerOrigin.x,
              y: imageRect.maxY + Theme.space3,
              width: availableWidth,
              height: Theme.sizeCaption + 8
            )
          )
        }
      }
      imageHitRegions = hitRegions
      window?.invalidateCursorRects(for: self)
    }

    private func drawImageFailure(in rect: NSRect) {
      Theme.surfaceSubtle.setFill()
      NSBezierPath(roundedRect: rect, xRadius: Theme.radiusSmall, yRadius: Theme.radiusSmall).fill()
      let message = NSMutableAttributedString(
        string: "Image unavailable\nClick to edit the source or try again",
        attributes: [
          .font: Theme.sans(Theme.sizeCaption, weight: .medium),
          .foregroundColor: Theme.muted,
        ]
      )
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .center
      paragraph.lineSpacing = 4
      message.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: message.length))
      let size = message.boundingRect(
        with: NSSize(width: max(rect.width - 40, 1), height: rect.height),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
      ).size
      message.draw(
        in: NSRect(
          x: rect.midX - size.width / 2,
          y: rect.midY - size.height / 2,
          width: size.width,
          height: size.height
        )
      )
    }

    private func drawCaption(_ caption: String, in rect: CGRect) {
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .center
      let attributed = NSMutableAttributedString(
        string: caption,
        attributes: [
          .font: Theme.serif(Theme.sizeCaption),
          .foregroundColor: Theme.inkSoft,
          .paragraphStyle: paragraph,
        ]
      )
      if let expression = try? NSRegularExpression(
        pattern: #"^Figure\s+[0-9]+\."#, options: [.caseInsensitive]
      ), let match = expression.firstMatch(
        in: caption, range: NSRange(location: 0, length: (caption as NSString).length)
      ) {
        attributed.addAttributes([
          .font: Theme.mono(Theme.sizeMicro, weight: .bold),
          .foregroundColor: Theme.orange,
          .kern: 0.75,
        ], range: match.range)
      }
      attributed.draw(
        with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
      )
    }

    private func cachedImage(at url: URL) -> NSImage? {
      if let cached = imageCache[url] { return cached }
      guard pendingImageLoads.insert(url).inserted else { return nil }
      if url.isFileURL {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
          let image = NSImage(contentsOf: url)
          DispatchQueue.main.async { self?.completeImageLoad(image, from: url) }
        }
      } else if url.scheme == "https" || url.scheme == "http" {
        var request = URLRequest(
          url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30
        )
        request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
          let http = response as? HTTPURLResponse
          let isSuccessful = error == nil
            && (http.map { (200...299).contains($0.statusCode) } ?? false)
            && (http?.mimeType?.hasPrefix("image/") ?? false)
          let image = isSuccessful ? data.flatMap(NSImage.init(data:)) : nil
          DispatchQueue.main.async { self?.completeImageLoad(image, from: url) }
        }.resume()
      } else {
        pendingImageLoads.remove(url)
      }
      return nil
    }

    private func completeImageLoad(_ image: NSImage?, from url: URL) {
      pendingImageLoads.remove(url)
      if let image {
        failedImageURLs.remove(url)
        imageCache[url] = image
        imageLoadHandler?(url, image.size)
      } else {
        failedImageURLs.insert(url)
      }
      needsDisplay = true
    }

    func cachedImageForPresentation(at url: URL) -> NSImage? {
      imageCache[url]
    }

    private func imageURLs(from pasteboard: NSPasteboard) -> [URL] {
      let options: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: ["public.image"],
      ]
      return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
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
