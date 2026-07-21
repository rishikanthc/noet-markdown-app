#if os(macOS) && canImport(AppKit)
  import AppKit

  struct ImageImportConfiguration {
    let width: CGFloat
    let caption: String?
  }

  final class ImageImportPanelController: NSWindowController {
    private let imageURL: URL
    private let completion: (ImageImportConfiguration?) -> Void
    private let preview = NSImageView()
    private let widthSlider = NSSlider(
      value: 512, minValue: 128, maxValue: Double(Theme.readingWidth), target: nil, action: nil)
    private let widthField = NSTextField(string: "512")
    private let widthStepper = NSStepper()
    private let captionToggle = NSButton(checkboxWithTitle: "Include caption", target: nil, action: nil)
    private let captionField: NSTextField

    init(imageURL: URL, figureNumber: Int, completion: @escaping (ImageImportConfiguration?) -> Void) {
      self.imageURL = imageURL
      self.completion = completion
      captionField = NSTextField(string: "Figure \(figureNumber).")
      let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 560, height: 430),
        styleMask: [.titled, .fullSizeContentView],
        backing: .buffered,
        defer: false
      )
      panel.title = "Add Image"
      panel.titleVisibility = .hidden
      panel.titlebarAppearsTransparent = true
      panel.isMovable = false
      panel.isOpaque = false
      panel.backgroundColor = .clear
      super.init(window: panel)
      buildInterface()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present(asSheetFor parent: NSWindow) {
      guard let window else { return }
      parent.beginSheet(window)
      window.makeFirstResponder(captionField)
    }

    private func buildInterface() {
      guard let window else { return }
      let host: NSView
      let content: NSView
      if #available(macOS 26.0, *) {
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = Theme.radiusMedium
        glass.tintColor = Theme.paper.withAlphaComponent(0.2)
        let embedded = NSView()
        glass.contentView = embedded
        host = glass
        content = embedded
      } else {
        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = Theme.radiusMedium
        glass.layer?.masksToBounds = true
        host = glass
        content = glass
      }
      window.contentView = host

      let title = NSTextField(labelWithString: "Add image")
      title.font = Theme.sans(22, weight: .semibold)
      title.textColor = .labelColor
      let subtitle = NSTextField(
        wrappingLabelWithString: "Choose the rendered width and optional Typst-style figure caption. The original aspect ratio is always preserved."
      )
      subtitle.font = Theme.serif(14)
      subtitle.textColor = .secondaryLabelColor

      preview.image = NSImage(contentsOf: imageURL)
      preview.imageScaling = .scaleProportionallyUpOrDown
      preview.imageAlignment = .alignCenter
      preview.wantsLayer = true
      preview.layer?.cornerRadius = Theme.radiusSmall
      preview.layer?.masksToBounds = true
      preview.layer?.backgroundColor = Theme.surfaceSubtle.cgColor
      preview.translatesAutoresizingMaskIntoConstraints = false

      let widthLabel = sectionLabel("WIDTH")
      widthSlider.target = self
      widthSlider.action = #selector(sliderChanged(_:))
      widthSlider.isContinuous = true
      widthField.alignment = .right
      widthField.font = Theme.mono(13, weight: .semibold)
      widthField.formatter = integerFormatter()
      widthField.target = self
      widthField.action = #selector(widthFieldChanged(_:))
      widthField.translatesAutoresizingMaskIntoConstraints = false
      widthStepper.minValue = 128
      widthStepper.maxValue = Double(Theme.readingWidth)
      widthStepper.increment = 16
      widthStepper.valueWraps = false
      widthStepper.integerValue = 512
      widthStepper.target = self
      widthStepper.action = #selector(stepperChanged(_:))

      let px = NSTextField(labelWithString: "px")
      px.font = Theme.mono(12)
      px.textColor = .secondaryLabelColor
      let widthValue = NSStackView(views: [widthField, px, widthStepper])
      widthValue.orientation = .horizontal
      widthValue.alignment = .centerY
      widthValue.spacing = 6

      let widthRow = NSStackView(views: [widthSlider, widthValue])
      widthRow.orientation = .horizontal
      widthRow.alignment = .centerY
      widthRow.spacing = 14

      captionToggle.state = .on
      captionToggle.target = self
      captionToggle.action = #selector(captionToggled(_:))
      captionToggle.font = Theme.sans(13, weight: .medium)
      captionField.placeholderString = "Figure caption"
      captionField.font = Theme.serif(14)

      let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
      cancel.bezelStyle = .rounded
      cancel.keyEquivalent = "\u{1b}"
      let insert = NSButton(title: "Insert Image", target: self, action: #selector(confirm(_:)))
      insert.bezelStyle = .rounded
      insert.keyEquivalent = "\r"
      insert.contentTintColor = Theme.accent
      let buttons = NSStackView(views: [NSView(), cancel, insert])
      buttons.orientation = .horizontal
      buttons.spacing = 10

      let controls = NSStackView(views: [
        title, subtitle, preview, widthLabel, widthRow, captionToggle, captionField, buttons,
      ])
      controls.orientation = .vertical
      controls.alignment = .leading
      controls.spacing = 12
      controls.setCustomSpacing(4, after: title)
      controls.setCustomSpacing(18, after: subtitle)
      controls.setCustomSpacing(18, after: preview)
      controls.setCustomSpacing(6, after: widthLabel)
      controls.setCustomSpacing(8, after: captionToggle)
      controls.setCustomSpacing(20, after: captionField)
      controls.translatesAutoresizingMaskIntoConstraints = false
      content.addSubview(controls)

      widthRow.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
      widthSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
      widthField.widthAnchor.constraint(equalToConstant: 54).isActive = true
      preview.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
      preview.heightAnchor.constraint(equalToConstant: 120).isActive = true
      captionField.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
      buttons.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
      NSLayoutConstraint.activate([
        controls.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
        controls.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
        controls.topAnchor.constraint(equalTo: content.topAnchor, constant: 26),
        controls.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
      ])
    }

    private func sectionLabel(_ value: String) -> NSTextField {
      let label = NSTextField(labelWithString: value)
      label.font = Theme.mono(11, weight: .bold)
      label.textColor = Theme.muted
      return label
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

    @objc private func stepperChanged(_ sender: NSStepper) {
      synchronizeWidth(sender.doubleValue)
    }

    @objc private func widthFieldChanged(_ sender: NSTextField) {
      synchronizeWidth(sender.doubleValue)
    }

    private func synchronizeWidth(_ proposed: Double) {
      let value = min(max(proposed, 128), Double(Theme.readingWidth))
      widthSlider.doubleValue = value
      widthField.integerValue = Int(value.rounded())
      widthStepper.doubleValue = value
    }

    @objc private func captionToggled(_ sender: NSButton) {
      captionField.isEnabled = sender.state == .on
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
