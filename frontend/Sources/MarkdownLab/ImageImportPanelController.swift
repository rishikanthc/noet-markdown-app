#if os(macOS) && canImport(AppKit)
  import AppKit

  struct ImageImportConfiguration {
    let width: CGFloat
    let caption: String?
  }

  /// A compact native inspector shown as a sheet after an image drop.
  final class ImageImportPanelController: NSWindowController {
    private let imageURL: URL
    private let completion: (ImageImportConfiguration?) -> Void
    private let initialConfiguration: ImageImportConfiguration
    private let isEditing: Bool
    private let providedPreview: NSImage?
    private let preview = NSImageView()
    private let widthSlider = NSSlider(
      value: 512, minValue: 128, maxValue: Double(Theme.readingWidth), target: nil, action: nil)
    private let widthField = NSTextField(string: "512")
    private let captionToggle = NSButton(checkboxWithTitle: "Caption", target: nil, action: nil)
    private let captionField: NSTextField

    convenience init(
      imageURL: URL,
      figureNumber: Int,
      completion: @escaping (ImageImportConfiguration?) -> Void
    ) {
      self.init(
        imageURL: imageURL,
        configuration: ImageImportConfiguration(
          width: MarkdownImageDescriptor.defaultWidth,
          caption: "Figure \(figureNumber)."
        ),
        isEditing: false,
        previewImage: nil,
        completion: completion
      )
    }

    init(
      imageURL: URL,
      configuration: ImageImportConfiguration,
      isEditing: Bool,
      previewImage: NSImage?,
      completion: @escaping (ImageImportConfiguration?) -> Void
    ) {
      self.imageURL = imageURL
      self.completion = completion
      initialConfiguration = configuration
      self.isEditing = isEditing
      providedPreview = previewImage
      captionField = NSTextField(string: configuration.caption ?? "")
      let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 470, height: 340),
        styleMask: [.titled, .fullSizeContentView],
        backing: .buffered,
        defer: false
      )
      panel.title = isEditing ? "Edit Image" : "Add Image"
      panel.titleVisibility = .hidden
      panel.titlebarAppearsTransparent = true
      panel.isMovable = false
      panel.isOpaque = false
      panel.backgroundColor = .clear
      super.init(window: panel)
      widthSlider.doubleValue = Double(configuration.width)
      widthField.integerValue = Int(configuration.width.rounded())
      buildInterface()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present(asSheetFor parent: NSWindow) {
      guard let window else { return }
      parent.beginSheet(window)
      window.makeFirstResponder(initialConfiguration.caption == nil ? widthField : captionField)
    }

    private func buildInterface() {
      guard let window else { return }
      let (host, content) = glassSurface()
      window.contentView = host

      let image = providedPreview ?? NSImage(contentsOf: imageURL)
      preview.image = image
      preview.imageScaling = .scaleProportionallyUpOrDown
      preview.imageAlignment = .alignCenter
      preview.wantsLayer = true
      preview.layer?.cornerRadius = 10
      preview.layer?.masksToBounds = true
      preview.layer?.backgroundColor = Theme.surfaceSubtle.withAlphaComponent(0.72).cgColor
      preview.layer?.borderColor = Theme.hairline.cgColor
      preview.layer?.borderWidth = 1
      preview.translatesAutoresizingMaskIntoConstraints = false

      let title = NSTextField(labelWithString: isEditing ? "Edit Image" : "Add Image")
      title.font = Theme.sans(19, weight: .semibold)
      title.textColor = .labelColor
      let filename = NSTextField(labelWithString: imageURL.lastPathComponent)
      filename.font = Theme.sans(12.5, weight: .medium)
      filename.textColor = .secondaryLabelColor
      filename.lineBreakMode = .byTruncatingMiddle
      let dimensions = image.map {
        "\(Int($0.size.width.rounded())) × \(Int($0.size.height.rounded()))  ·  Aspect ratio preserved"
      } ?? "Aspect ratio preserved"
      let detail = NSTextField(labelWithString: dimensions)
      detail.font = Theme.sans(11.5)
      detail.textColor = .tertiaryLabelColor
      let heading = NSStackView(views: [title, filename, detail])
      heading.orientation = .vertical
      heading.alignment = .leading
      heading.spacing = 2
      let header = NSStackView(views: [preview, heading])
      header.orientation = .horizontal
      header.alignment = .centerY
      header.spacing = 14

      widthSlider.target = self
      widthSlider.action = #selector(sliderChanged(_:))
      widthSlider.isContinuous = true
      widthSlider.controlSize = .small
      widthSlider.setAccessibilityLabel("Image width")
      widthField.alignment = .right
      widthField.font = Theme.mono(12.5, weight: .semibold)
      widthField.formatter = integerFormatter()
      widthField.target = self
      widthField.action = #selector(widthFieldChanged(_:))
      widthField.translatesAutoresizingMaskIntoConstraints = false
      let px = NSTextField(labelWithString: "px")
      px.font = Theme.sans(11.5)
      px.textColor = .tertiaryLabelColor
      let widthValue = NSStackView(views: [widthField, px])
      widthValue.orientation = .horizontal
      widthValue.alignment = .centerY
      widthValue.spacing = 4
      let widthHeader = NSStackView(views: [sectionTitle("Rendered width"), flexibleSpacer(), widthValue])
      widthHeader.orientation = .horizontal
      widthHeader.alignment = .centerY
      let widthControls = NSStackView(views: [widthHeader, widthSlider])
      widthControls.orientation = .vertical
      widthControls.alignment = .leading
      widthControls.spacing = 8
      let widthCard = card(containing: widthControls)

      captionToggle.state = initialConfiguration.caption == nil ? .off : .on
      captionToggle.target = self
      captionToggle.action = #selector(captionToggled(_:))
      captionToggle.font = Theme.sans(13, weight: .medium)
      captionField.placeholderString = "Optional figure caption"
      captionField.font = Theme.serif(13.5)
      captionField.focusRingType = .exterior
      captionField.isEnabled = captionToggle.state == .on
      captionField.alphaValue = captionField.isEnabled ? 1 : 0.45
      let captionControls = NSStackView(views: [captionToggle, captionField])
      captionControls.orientation = .vertical
      captionControls.alignment = .leading
      captionControls.spacing = 7
      let captionCard = card(containing: captionControls)

      let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
      cancel.bezelStyle = .rounded
      cancel.controlSize = .regular
      cancel.keyEquivalent = "\u{1b}"
      let insert = NSButton(
        title: isEditing ? "Update" : "Add Image", target: self, action: #selector(confirm(_:)))
      insert.bezelStyle = .rounded
      insert.controlSize = .regular
      insert.keyEquivalent = "\r"
      let buttons = NSStackView(views: [flexibleSpacer(), cancel, insert])
      buttons.orientation = .horizontal
      buttons.alignment = .centerY
      buttons.spacing = 8

      let controls = NSStackView(views: [header, widthCard, captionCard, buttons])
      controls.orientation = .vertical
      controls.alignment = .leading
      controls.spacing = 12
      controls.setCustomSpacing(16, after: header)
      controls.setCustomSpacing(16, after: captionCard)
      controls.translatesAutoresizingMaskIntoConstraints = false
      content.addSubview(controls)

      NSLayoutConstraint.activate([
        preview.widthAnchor.constraint(equalToConstant: 82),
        preview.heightAnchor.constraint(equalToConstant: 62),
        header.widthAnchor.constraint(equalTo: controls.widthAnchor),
        widthCard.widthAnchor.constraint(equalTo: controls.widthAnchor),
        widthCard.heightAnchor.constraint(equalToConstant: 70),
        captionCard.widthAnchor.constraint(equalTo: controls.widthAnchor),
        captionCard.heightAnchor.constraint(equalToConstant: 70),
        widthControls.widthAnchor.constraint(equalTo: widthCard.widthAnchor, constant: -24),
        widthSlider.widthAnchor.constraint(equalTo: widthControls.widthAnchor),
        widthField.widthAnchor.constraint(equalToConstant: 52),
        captionControls.widthAnchor.constraint(equalTo: captionCard.widthAnchor, constant: -24),
        captionField.widthAnchor.constraint(equalTo: captionControls.widthAnchor),
        buttons.widthAnchor.constraint(equalTo: controls.widthAnchor),
        controls.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
        controls.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
        controls.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
        controls.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18),
      ])
    }

    private func glassSurface() -> (NSView, NSView) {
      if #available(macOS 26.0, *) {
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = 18
        glass.tintColor = Theme.paper.withAlphaComponent(0.14)
        let content = NSView()
        glass.contentView = content
        return (glass, content)
      }
      let glass = NSVisualEffectView()
      glass.material = .popover
      glass.blendingMode = .behindWindow
      glass.state = .active
      glass.wantsLayer = true
      glass.layer?.cornerRadius = 18
      glass.layer?.masksToBounds = true
      return (glass, glass)
    }

    private func card(containing controls: NSView) -> NSView {
      let card = NSView()
      card.wantsLayer = true
      card.layer?.cornerRadius = 11
      card.layer?.backgroundColor = Theme.paper.withAlphaComponent(0.42).cgColor
      card.layer?.borderColor = Theme.hairline.cgColor
      card.layer?.borderWidth = 1
      controls.translatesAutoresizingMaskIntoConstraints = false
      card.addSubview(controls)
      NSLayoutConstraint.activate([
        controls.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
        controls.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
        controls.centerYAnchor.constraint(equalTo: card.centerYAnchor),
      ])
      return card
    }

    private func sectionTitle(_ value: String) -> NSTextField {
      let label = NSTextField(labelWithString: value)
      label.font = Theme.sans(12.5, weight: .medium)
      label.textColor = .labelColor
      return label
    }

    private func flexibleSpacer() -> NSView {
      let view = NSView()
      view.setContentHuggingPriority(.defaultLow, for: .horizontal)
      view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      return view
    }

    private func integerFormatter() -> NumberFormatter {
      let formatter = NumberFormatter()
      formatter.allowsFloats = false
      formatter.minimum = 128
      formatter.maximum = NSNumber(value: Double(Theme.readingWidth))
      return formatter
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
      let value = (sender.doubleValue / 16).rounded() * 16
      synchronizeWidth(value)
    }

    @objc private func widthFieldChanged(_ sender: NSTextField) {
      synchronizeWidth(sender.doubleValue)
    }

    private func synchronizeWidth(_ proposed: Double) {
      let value = min(max(proposed, 128), Double(Theme.readingWidth))
      widthSlider.doubleValue = value
      widthField.integerValue = Int(value.rounded())
    }

    @objc private func captionToggled(_ sender: NSButton) {
      captionField.isEnabled = sender.state == .on
      captionField.alphaValue = captionField.isEnabled ? 1 : 0.45
      if captionField.isEnabled { window?.makeFirstResponder(captionField) }
    }

    @objc private func cancel(_ sender: Any?) { finish(nil) }

    @objc private func confirm(_ sender: Any?) {
      let caption = captionToggle.state == .on
        ? captionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        : nil
      finish(ImageImportConfiguration(
        width: CGFloat(widthSlider.doubleValue),
        caption: caption?.isEmpty == true ? nil : caption
      ))
    }

    private func finish(_ configuration: ImageImportConfiguration?) {
      guard let window, let parent = window.sheetParent else {
        completion(configuration)
        return
      }
      parent.endSheet(window)
      completion(configuration)
    }
  }
#endif
