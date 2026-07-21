#if os(macOS) && canImport(AppKit) && canImport(CMdCore)
  import AppKit
  import CMdCore
  import UniformTypeIdentifiers

  final class EditorViewController: NSViewController, NSTextViewDelegate {
    private struct PendingNativeEdit {
      let range: NSRange
      let replacement: String
    }

    private let initialText: String
    private var currentURL: URL?
    private var session: MarkdownDocumentSession?
    private let renderer = MarkdownRenderer()
    private var latestPlan: MarkdownRenderPlan?
    private var refreshWorkItem: DispatchWorkItem?
    private var pendingNativeEdits: [PendingNativeEdit] = []
    private var pendingInvalidatedRange: NSRange?
    private var sourceGeneration: UInt64 = 0
    private var activeEditingRange = NSRange(location: 0, length: 0)
    private var isApplyingPresentation = false
    private var imageImportPanel: ImageImportPanelController?

    private let editorScrollView = NSScrollView()
    private lazy var textView = MarkdownTextView(usingTextLayoutManager: true)
    private var textContainer: NSTextContainer { textView.textContainer! }
    private let statusLabel = NSTextField(labelWithString: "Starting MdCore…")

    init(initialText: String, url: URL? = nil) {
      self.initialText = initialText
      currentURL = url
      super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
      let root = NSView()
      root.translatesAutoresizingMaskIntoConstraints = false
      configureTextView()

      editorScrollView.documentView = textView
      editorScrollView.hasVerticalScroller = true
      editorScrollView.hasHorizontalScroller = false
      editorScrollView.autohidesScrollers = true
      editorScrollView.translatesAutoresizingMaskIntoConstraints = false

      statusLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
      statusLabel.textColor = .secondaryLabelColor
      statusLabel.lineBreakMode = .byTruncatingMiddle
      statusLabel.translatesAutoresizingMaskIntoConstraints = false

      root.addSubview(editorScrollView)
      root.addSubview(statusLabel)
      NSLayoutConstraint.activate([
        editorScrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
        editorScrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        editorScrollView.topAnchor.constraint(equalTo: root.topAnchor),
        editorScrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor),
        statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
        statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
        statusLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -5),
        statusLabel.heightAnchor.constraint(equalToConstant: 18),
      ])
      view = root
    }

    override func viewDidLoad() {
      super.viewDidLoad()
      load(text: initialText, from: currentURL)
    }

    override func viewDidAppear() {
      super.viewDidAppear()
      view.window?.makeFirstResponder(textView)
    }

    private func configureTextView() {
      textView.delegate = self
      textView.imageDropHandler = { [weak self] url, insertion in
        self?.configureDroppedImage(at: url, insertionLocation: insertion)
      }
      textView.imageLoadHandler = { [weak self] url, size in
        self?.imageDidLoad(at: url, size: size)
      }
      textView.imageClickHandler = { [weak self] range in
        self?.editImage(in: range)
      }
      textView.isRichText = false
      textView.importsGraphics = false
      textView.allowsUndo = true
      textView.isAutomaticQuoteSubstitutionEnabled = false
      textView.isAutomaticDashSubstitutionEnabled = false
      textView.isAutomaticTextReplacementEnabled = false
      textView.isAutomaticSpellingCorrectionEnabled = false
      textView.isContinuousSpellCheckingEnabled = true
      textView.usesFindBar = true
      textView.isIncrementalSearchingEnabled = true
      textView.isVerticallyResizable = true
      textView.isHorizontallyResizable = false
      textView.autoresizingMask = [.width]
      textView.maximumReadingWidth = Theme.readingWidth
      textView.minimumHorizontalInset = Theme.minimumHorizontalInset
      textView.textContainerInset = NSSize(width: Theme.minimumHorizontalInset, height: Theme.verticalInset)
      textView.minSize = .zero
      textView.maxSize = NSSize(
        width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude
      )
      textContainer.widthTracksTextView = false
      textContainer.lineFragmentPadding = 0
      textContainer.size = NSSize(width: Theme.readingWidth, height: .greatestFiniteMagnitude)

      textView.appearance = NSAppearance(named: .aqua)
      textView.backgroundColor = Theme.paper
      // MarkdownTextView paints the paper and semantic surfaces before asking
      // TextKit 2 to draw glyphs and selections.
      textView.drawsBackground = false
      textView.insertionPointColor = Theme.accent
      textView.selectedTextAttributes = [.backgroundColor: Theme.accentSoft]
      editorScrollView.backgroundColor = Theme.paper
      editorScrollView.drawsBackground = true
    }

    // MARK: - Native source editing

    func textView(
      _ textView: NSTextView,
      shouldChangeTextIn affectedCharRange: NSRange,
      replacementString: String?
    ) -> Bool {
      pendingNativeEdits.append(
        PendingNativeEdit(range: affectedCharRange, replacement: replacementString ?? "")
      )
      return true
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
      guard let plan = latestPlan, plan.source == textView.string,
        let target = Self.imageNavigationTarget(
          for: commandSelector,
          selection: textView.selectedRange(),
          plan: plan
        )
      else { return false }

      let previous = activeEditingRange
      isApplyingPresentation = true
      textView.setSelectedRange(NSRange(location: target, length: 0))
      isApplyingPresentation = false
      let next = target == (plan.source as NSString).length
        ? NSRange(location: target, length: 0)
        : renderer.editingRange(containing: target, in: plan)
      activeEditingRange = next
      applyPresentation(plan: plan, invalidatedRange: NSUnionRange(previous, next))
      textView.scrollRangeToVisible(NSRange(location: target, length: 0))
      return true
    }

    static func imageNavigationTarget(
      for commandSelector: Selector,
      selection: NSRange,
      plan: MarkdownRenderPlan
    ) -> Int? {
      guard selection.length == 0,
        commandSelector == #selector(NSResponder.moveDown(_:))
          || commandSelector == #selector(NSResponder.moveUp(_:))
      else { return nil }
      let source = plan.source as NSString
      let probe = min(selection.location, max(source.length - 1, 0))
      guard let image = plan.nodes.first(where: { node in
        node.kind == Int(MD_NODE_IMAGE.rawValue)
          && (NSLocationInRange(probe, node.range)
            || selection.location == NSMaxRange(node.range))
      }) else { return nil }
      let paragraph = source.paragraphRange(for: image.range)
      if commandSelector == #selector(NSResponder.moveDown(_:)) {
        return min(NSMaxRange(paragraph), source.length)
      }
      guard paragraph.location > 0 else { return nil }
      let previous = source.paragraphRange(
        for: NSRange(location: paragraph.location - 1, length: 0)
      )
      return previous.location
    }

    func textDidChange(_ notification: Notification) {
      guard !isApplyingPresentation, !pendingNativeEdits.isEmpty, let session else { return }
      let edits = pendingNativeEdits
      pendingNativeEdits.removeAll(keepingCapacity: true)
      for edit in edits {
        sourceGeneration &+= 1
        session.applyEdit(utf16Range: edit.range, replacement: edit.replacement) { [weak self] result in
          guard let self else { return }
          switch result {
          case .success(let acknowledgement):
            self.accumulate(invalidatedRange: acknowledgement.invalidatedRange)
            self.scheduleSemanticRefresh()
          case .failure(let error):
            self.show(error: error)
          }
        }
      }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      guard !isApplyingPresentation, !textView.hasMarkedText() else { return }
      guard let plan = latestPlan, plan.source == textView.string else {
        activeEditingRange = paragraphRange(containing: textView.selectedRange().location)
        return
      }
      let next = renderer.editingRange(
        containing: textView.selectedRange().location, in: plan
      )
      guard next != activeEditingRange else { return }
      let changed = NSUnionRange(activeEditingRange, next)
      activeEditingRange = next
      applyPresentation(plan: plan, invalidatedRange: changed)
    }

    private func accumulate(invalidatedRange: NSRange?) {
      guard let invalidatedRange else { return }
      pendingInvalidatedRange = pendingInvalidatedRange.map {
        NSUnionRange($0, invalidatedRange)
      } ?? invalidatedRange
    }

    private func scheduleSemanticRefresh(immediate: Bool = false) {
      refreshWorkItem?.cancel()
      let item = DispatchWorkItem { [weak self] in self?.refreshSemanticSnapshot() }
      refreshWorkItem = item
      DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0 : 0.014), execute: item)
    }

    private func refreshSemanticSnapshot() {
      guard let session, !textView.hasMarkedText() else { return }
      let requestedGeneration = sourceGeneration
      let started = ContinuousClock().now
      session.renderPlan { [weak self] result in
        guard let self else { return }
        do {
          let plan = try result.get()
          guard plan.source == self.textView.string else {
            if requestedGeneration != self.sourceGeneration { self.scheduleSemanticRefresh() }
            return
          }
          self.latestPlan = plan
          let previousEditingRange = self.activeEditingRange
          let nextEditingRange = self.renderer.editingRange(
            containing: self.textView.selectedRange().location, in: plan
          )
          self.activeEditingRange = nextEditingRange
          var target = self.pendingInvalidatedRange
          if previousEditingRange != nextEditingRange {
            let activationChange = NSUnionRange(previousEditingRange, nextEditingRange)
            target = target.map { NSUnionRange($0, activationChange) } ?? activationChange
          }
          self.pendingInvalidatedRange = nil
          self.applyPresentation(plan: plan, invalidatedRange: target)
          let elapsed = started.duration(to: ContinuousClock().now)
          self.statusLabel.stringValue = String(
            format: "render %.2f ms · rev %llu · %d nodes · %d spans · %@",
            elapsed.inMilliseconds, plan.revision, plan.nodes.count, plan.spans.count,
            plan.versionSummary
          )
        } catch {
          self.show(error: error)
        }
      }
    }

    private func applyPresentation(plan: MarkdownRenderPlan, invalidatedRange: NSRange?) {
      let selection = textView.selectedRange()
      isApplyingPresentation = true
      renderer.apply(
        plan: plan,
        invalidatedRange: invalidatedRange,
        activeEditingRange: activeEditingRange,
        to: textView
      )
      isApplyingPresentation = false
      assert(textView.selectedRange() == selection, "Attribute-only rendering moved the native selection")
    }

    private func paragraphRange(containing offset: Int) -> NSRange {
      let source = textView.string as NSString
      guard source.length > 0 else { return NSRange(location: 0, length: 0) }
      let safe = min(max(offset, 0), source.length)
      return source.paragraphRange(for: NSRange(location: safe, length: 0))
    }

    // MARK: - File menu

    private func configureDroppedImage(at sourceURL: URL, insertionLocation: Int) {
      guard let window = view.window, NSImage(contentsOf: sourceURL) != nil else {
        NSSound.beep()
        return
      }
      let panel = ImageImportPanelController(
        imageURL: sourceURL,
        figureNumber: nextFigureNumber()
      ) { [weak self] configuration in
        guard let self else { return }
        self.imageImportPanel = nil
        guard let configuration else { return }
        do {
          let destination = try ImageAssetImporter.destination(
            for: sourceURL, documentURL: self.currentURL
          )
          let imageMarkdown = MarkdownImageDescriptor.markdown(
            caption: configuration.caption,
            destination: destination,
            width: configuration.width
          )
          let insertion = min(max(insertionLocation, 0), self.textView.string.utf16.count)
          let replacement = self.blockInsertion(imageMarkdown, at: insertion)
          self.textView.insertText(
            replacement, replacementRange: NSRange(location: insertion, length: 0)
          )
          let selection = NSRange(location: insertion + (replacement as NSString).length, length: 0)
          self.textView.setSelectedRange(selection)
          self.textView.scrollRangeToVisible(selection)
        } catch {
          self.show(error: error)
        }
      }
      imageImportPanel = panel
      panel.present(asSheetFor: window)
    }

    private func imageDidLoad(at url: URL, size: NSSize) {
      renderer.updateIntrinsicImageSize(size, for: url)
      guard let plan = latestPlan, plan.source == textView.string else { return }
      let source = plan.source as NSString
      let affected = plan.nodes.compactMap { node -> NSRange? in
        guard node.kind == Int(MD_NODE_IMAGE.rawValue),
          let descriptor = MarkdownImageDescriptor.parse(range: node.range, source: source),
          descriptor.resolvedURL(relativeTo: renderer.documentURL) == url
        else { return nil }
        return node.range
      }.reduce(nil as NSRange?) { result, range in
        result.map { NSUnionRange($0, range) } ?? range
      }
      guard let affected else { return }
      applyPresentation(plan: plan, invalidatedRange: affected)
    }

    private func editImage(in range: NSRange) {
      guard imageImportPanel == nil,
        let window = view.window,
        let plan = latestPlan, plan.source == textView.string
      else { return }
      let source = plan.source as NSString
      guard let node = plan.nodes.first(where: {
        $0.kind == Int(MD_NODE_IMAGE.rawValue) && $0.range.intersection(range) != nil
      }), let descriptor = MarkdownImageDescriptor.parse(range: node.range, source: source),
        let url = descriptor.resolvedURL(relativeTo: renderer.documentURL)
      else { return }

      let panel = ImageImportPanelController(
        imageURL: url,
        configuration: ImageImportConfiguration(
          width: descriptor.width,
          caption: descriptor.caption.isEmpty ? nil : descriptor.caption
        ),
        isEditing: true,
        previewImage: textView.cachedImageForPresentation(at: url)
      ) { [weak self] configuration in
        guard let self else { return }
        self.imageImportPanel = nil
        guard let configuration else { return }
        let replacement = MarkdownImageDescriptor.markdown(
          caption: configuration.caption,
          destination: descriptor.destination,
          width: configuration.width
        )
        let replacementLength = (replacement as NSString).length
        let oldEnd = NSMaxRange(node.range)
        let followedByNewline = oldEnd < source.length && source.character(at: oldEnd) == 0x0A
        self.textView.undoManager?.beginUndoGrouping()
        self.textView.insertText(replacement, replacementRange: node.range)
        self.textView.undoManager?.endUndoGrouping()
        let afterImage = node.range.location + replacementLength + (followedByNewline ? 1 : 0)
        let target = min(afterImage, (self.textView.string as NSString).length)
        self.textView.setSelectedRange(NSRange(location: target, length: 0))
        self.textView.scrollRangeToVisible(NSRange(location: node.range.location, length: replacementLength))
      }
      imageImportPanel = panel
      panel.present(asSheetFor: window)
    }

    private func nextFigureNumber() -> Int {
      if let latestPlan, latestPlan.source == textView.string {
        return latestPlan.nodes.filter { $0.kind == Int(MD_NODE_IMAGE.rawValue) }.count + 1
      }
      let expression = try? NSRegularExpression(
        pattern: #"!\[[^\]]*\]\("#, options: []
      )
      let source = textView.string
      let range = NSRange(location: 0, length: (source as NSString).length)
      return (expression?.numberOfMatches(in: source, range: range) ?? 0) + 1
    }

    private func blockInsertion(_ markdown: String, at location: Int) -> String {
      let source = textView.string as NSString
      let needsLeadingBreak = location > 0 && source.character(at: location - 1) != 0x0A
      let trailingBreak = location == source.length
        ? "\n\n"
        : (source.character(at: location) == 0x0A ? "\n" : "\n\n")
      return (needsLeadingBreak ? "\n\n" : "") + markdown + trailingBreak
    }

    @objc func openDocument(_ sender: Any?) {
      let panel = NSOpenPanel()
      panel.allowedContentTypes = [.plainText]
      panel.allowsMultipleSelection = false
      guard panel.runModal() == .OK, let url = panel.url else { return }
      do {
        load(text: try String(contentsOf: url, encoding: .utf8), from: url)
      } catch {
        show(error: error)
      }
    }

    @objc func saveDocument(_ sender: Any?) {
      do {
        let destination: URL
        if let currentURL {
          destination = currentURL
        } else {
          let panel = NSSavePanel()
          panel.nameFieldStringValue = "document.md"
          guard panel.runModal() == .OK, let url = panel.url else { return }
          destination = url
          currentURL = url
          renderer.documentURL = url
        }
        try textView.string.write(to: destination, atomically: true, encoding: .utf8)
        statusLabel.stringValue = "Saved \(destination.path)"
        view.window?.title = destination.lastPathComponent
      } catch {
        show(error: error)
      }
    }

    // MARK: - Format menu

    @objc func toggleStrong(_ sender: Any?) { apply(.strong) }
    @objc func toggleEmphasis(_ sender: Any?) { apply(.emphasis) }
    @objc func toggleStrikethrough(_ sender: Any?) { apply(.strikethrough) }
    @objc func insertInlineCode(_ sender: Any?) { apply(.inlineCode) }
    @objc func setHeadingOne(_ sender: Any?) { apply(.heading(level: 1)) }
    @objc func toggleBlockQuote(_ sender: Any?) { apply(.blockQuote) }
    @objc func toggleTaskItem(_ sender: Any?) { apply(.taskItem) }
    @objc func indentListItem(_ sender: Any?) { apply(.indentListItem) }
    @objc func outdentListItem(_ sender: Any?) { apply(.outdentListItem) }

    @objc func insertLink(_ sender: Any?) {
      let field = NSTextField(string: "https://")
      field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
      let alert = NSAlert()
      alert.messageText = "Insert Link"
      alert.informativeText = "Enter the destination URL."
      alert.accessoryView = field
      alert.addButton(withTitle: "Insert")
      alert.addButton(withTitle: "Cancel")
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      apply(.insertLink(destination: field.stringValue))
    }

    private func apply(_ command: MarkdownCommand) {
      guard let session else { return }
      session.plan(command, selection: textView.selectedRange()) { [weak self] result in
        guard let self else { return }
        do {
          let commandPlan = try result.get()
          self.textView.undoManager?.beginUndoGrouping()
          defer { self.textView.undoManager?.endUndoGrouping() }
          for edit in commandPlan.edits {
            self.textView.insertText(edit.replacement, replacementRange: edit.range)
          }
          self.textView.setSelectedRange(commandPlan.selection)
          self.textView.scrollRangeToVisible(commandPlan.selection)
        } catch {
          self.show(error: error)
        }
      }
    }

    // MARK: - Document lifecycle

    private func load(text: String, from url: URL?) {
      do {
        let replacementSession = try MarkdownDocumentSession(source: text)
        refreshWorkItem?.cancel()
        textView.delegate = nil
        textView.string = text
        textView.delegate = self
        session = replacementSession
        latestPlan = nil
        pendingNativeEdits.removeAll(keepingCapacity: true)
        pendingInvalidatedRange = nil
        sourceGeneration = 0
        currentURL = url
        renderer.documentURL = url
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        activeEditingRange = paragraphRange(containing: 0)
        view.window?.title = url?.lastPathComponent ?? "MarkdownLab"
        scheduleSemanticRefresh(immediate: true)
      } catch {
        show(error: error)
      }
    }

    private func show(error: Error) {
      statusLabel.stringValue = String(describing: error)
      NSSound.beep()
    }
  }
#endif
