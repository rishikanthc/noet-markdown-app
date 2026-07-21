#if os(macOS) && canImport(AppKit)
  import AppKit

  final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
      let inputURL = commandLineInputURL()
      let initialText: String
      if let inputURL, let loaded = try? String(contentsOf: inputURL, encoding: .utf8) {
        initialText = loaded
      } else {
        initialText = Self.sampleMarkdown
      }

      let editor = EditorViewController(initialText: initialText, url: inputURL)
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
      )
      window.title = inputURL?.lastPathComponent ?? "MarkdownLab"
      window.backgroundColor = Theme.paper
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
      window.isMovableByWindowBackground = true
      if #available(macOS 11.0, *) {
        window.toolbarStyle = .unifiedCompact
      }
      window.center()
      window.minSize = NSSize(width: 760, height: 480)
      window.contentViewController = editor

      let controller = NSWindowController(window: window)
      windowController = controller
      installMainMenu(editor: editor)
      controller.showWindow(nil)
      NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
      true
    }

    private func commandLineInputURL() -> URL? {
      for argument in CommandLine.arguments.dropFirst() where !argument.hasPrefix("-") {
        let url = URL(fileURLWithPath: argument).standardizedFileURL
        if FileManager.default.fileExists(atPath: url.path) { return url }
      }
      return nil
    }

    private func installMainMenu(editor: EditorViewController) {
      let main = NSMenu()

      let applicationItem = NSMenuItem()
      main.addItem(applicationItem)
      let applicationMenu = NSMenu()
      applicationItem.submenu = applicationMenu
      applicationMenu.addItem(
        withTitle: "About MarkdownLab",
        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
      applicationMenu.addItem(.separator())
      applicationMenu.addItem(
        withTitle: "Quit MarkdownLab", action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q")

      let fileItem = NSMenuItem()
      main.addItem(fileItem)
      let fileMenu = NSMenu(title: "File")
      fileItem.submenu = fileMenu
      addItem(
        to: fileMenu, title: "Open…", key: "o",
        action: #selector(EditorViewController.openDocument(_:)), target: editor)
      addItem(
        to: fileMenu, title: "Save", key: "s",
        action: #selector(EditorViewController.saveDocument(_:)), target: editor)

      let editItem = NSMenuItem()
      main.addItem(editItem)
      let editMenu = NSMenu(title: "Edit")
      editItem.submenu = editMenu
      editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
      editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
      editMenu.addItem(.separator())
      editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
      editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
      editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
      editMenu.addItem(
        withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

      let formatItem = NSMenuItem()
      main.addItem(formatItem)
      let formatMenu = NSMenu(title: "Markdown")
      formatItem.submenu = formatMenu
      addItem(
        to: formatMenu, title: "Strong", key: "b",
        action: #selector(EditorViewController.toggleStrong(_:)), target: editor)
      addItem(
        to: formatMenu, title: "Emphasis", key: "i",
        action: #selector(EditorViewController.toggleEmphasis(_:)), target: editor)
      addItem(
        to: formatMenu, title: "Strikethrough", key: "",
        action: #selector(EditorViewController.toggleStrikethrough(_:)), target: editor)
      addItem(
        to: formatMenu, title: "Inline Code", key: "`",
        action: #selector(EditorViewController.insertInlineCode(_:)), target: editor)
      addItem(
        to: formatMenu, title: "Insert Link…", key: "k",
        action: #selector(EditorViewController.insertLink(_:)), target: editor)
      formatMenu.addItem(.separator())
      addItem(
        to: formatMenu, title: "Heading 1", key: "1",
        action: #selector(EditorViewController.setHeadingOne(_:)), target: editor,
        modifiers: [.command, .option])
      addItem(
        to: formatMenu, title: "Block Quote", key: ">",
        action: #selector(EditorViewController.toggleBlockQuote(_:)), target: editor)
      addItem(
        to: formatMenu, title: "Task Item", key: "",
        action: #selector(EditorViewController.toggleTaskItem(_:)), target: editor)
      addItem(
        to: formatMenu, title: "Indent List Item", key: "]",
        action: #selector(EditorViewController.indentListItem(_:)), target: editor)
      addItem(
        to: formatMenu, title: "Outdent List Item", key: "[",
        action: #selector(EditorViewController.outdentListItem(_:)), target: editor)

      NSApp.mainMenu = main
    }

    private func addItem(
      to menu: NSMenu,
      title: String,
      key: String,
      action: Selector,
      target: AnyObject,
      modifiers: NSEvent.ModifierFlags = [.command]
    ) {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
      item.target = target
      item.keyEquivalentModifierMask = modifiers
      menu.addItem(item)
    }

    private static let sampleMarkdown = """
      # MarkdownLab

      This is a **native AppKit editor** backed by the Zig MdCore library, styled to match the Typst editorial system with a quiet paper surface and a focused reading measure.

      ## Core presentation

      Strong text stays **strong inside headings and links**, emphasis remains *family-aware*, and ==highlighted text== uses a rounded warm marker treatment. Links such as [the project site](https://example.com) are command-clickable.

      > [!NOTE]
      > Callouts use the same compact label, inset, radius, and indigo surface as the report template.

      Inline code such as `revision + 1` uses the warm chip treatment without changing line height.

      ```swift
      struct RenderSnapshot {
          let revision: UInt64
          let elapsedMilliseconds: Double
      }
      ```

      A display equation is centered and becomes editable source when its paragraph is active:

      $$
      E = mc^2
      $$

      ![A rendered image card](https://picsum.photos/1200/640)
      """
  }
#endif
