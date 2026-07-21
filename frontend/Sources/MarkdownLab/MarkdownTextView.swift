#if os(macOS) && canImport(AppKit)
  import AppKit

  /// TextKit 2 editor surface with a centered editorial reading column.
  final class MarkdownTextView: NSTextView {
    var maximumReadingWidth: CGFloat = Theme.readingWidth
    var minimumHorizontalInset: CGFloat = Theme.minimumHorizontalInset

    private var isUpdatingReadingGeometry = false

    override func setFrameSize(_ newSize: NSSize) {
      super.setFrameSize(newSize)
      updateReadingGeometry(for: newSize.width)
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      updateReadingGeometry(for: bounds.width)
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

  }
#endif
