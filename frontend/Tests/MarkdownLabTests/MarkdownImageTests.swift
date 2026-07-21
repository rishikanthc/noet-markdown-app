#if os(macOS) && canImport(AppKit) && canImport(CMdCore)
  import AppKit
  import CMdCore
  @testable import MarkdownLab
  import XCTest

  final class MarkdownImageTests: XCTestCase {
    func testImageMarkdownRoundTripsCaptionDestinationAndDefaultWidth() throws {
      let markdown = MarkdownImageDescriptor.markdown(
        caption: "Figure 3. Compact pipeline.",
        destination: "assets/pipeline plot.png",
        width: 512
      )
      let text = markdown as NSString
      let descriptor = try XCTUnwrap(
        MarkdownImageDescriptor.parse(
          range: NSRange(location: 0, length: text.length), source: text
        )
      )

      XCTAssertEqual(descriptor.caption, "Figure 3. Compact pipeline.")
      XCTAssertEqual(descriptor.destination, "assets/pipeline plot.png")
      XCTAssertEqual(descriptor.width, 512)
      XCTAssertTrue(markdown.contains("\"width=512\""))
    }

    func testImporterCopiesAssetsBesideSavedDocument() throws {
      let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: root) }
      let source = root.appendingPathComponent("Source Plot.png")
      try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)
      let document = root.appendingPathComponent("report.md")

      let destination = try ImageAssetImporter.destination(
        for: source, documentURL: document
      )

      XCTAssertEqual(destination, "assets/Source-Plot.png")
      XCTAssertTrue(FileManager.default.fileExists(
        atPath: root.appendingPathComponent(destination).path
      ))
    }

    func testRendererCentersLocalImageAsSourcePreservingFigure() throws {
      let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      let assets = root.appendingPathComponent("assets", isDirectory: true)
      try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: root) }
      let imageURL = assets.appendingPathComponent("plot.png")
      try makeImage(width: 200, height: 100).write(to: imageURL)
      let documentURL = root.appendingPathComponent("report.md")
      let source = "![Figure 1. Pipeline overview.](<assets/plot.png> \"width=512\")\n"
      let text = source as NSString
      let plan = try renderPlan(source)
      let renderer = MarkdownRenderer()
      renderer.documentURL = documentURL
      let textView = MarkdownTextView(usingTextLayoutManager: true)
      textView.string = source

      renderer.apply(plan: plan, invalidatedRange: nil, to: textView)

      let figure = try XCTUnwrap(textView.markdownImages.first)
      XCTAssertEqual(figure.width, 512)
      XCTAssertEqual(figure.intrinsicSize.width / figure.intrinsicSize.height, 2, accuracy: 0.01)
      XCTAssertEqual(figure.caption, "Figure 1. Pipeline overview.")
      let style = textView.textStorage?.attribute(
        .paragraphStyle, at: 0, effectiveRange: nil
      ) as? NSParagraphStyle
      XCTAssertEqual(
        style?.minimumLineHeight ?? 0,
        256 + Theme.space3 + Theme.sizeCaption + 8,
        accuracy: 0.5
      )
      let color = textView.textStorage?.attribute(
        .foregroundColor, at: 0, effectiveRange: nil
      ) as? NSColor
      XCTAssertEqual(color, .clear)
      XCTAssertEqual(textView.string, source)

      let active = text.paragraphRange(for: NSRange(location: 0, length: 0))
      renderer.apply(
        plan: plan, invalidatedRange: nil,
        activeEditingRange: active, to: textView
      )
      XCTAssertTrue(textView.markdownImages.isEmpty)
      XCTAssertEqual(textView.string, source)
    }

    func testRemoteImageUsesNonblockingProvisionalAspectRatio() throws {
      let source = "![Figure 1. Remote.](<https://example.com/plot.png> \"width=512\")\n"
      let plan = try renderPlan(source)
      let textView = MarkdownTextView(usingTextLayoutManager: true)
      textView.string = source

      MarkdownRenderer().apply(plan: plan, invalidatedRange: nil, to: textView)

      let figure = try XCTUnwrap(textView.markdownImages.first)
      XCTAssertEqual(figure.url.absoluteString, "https://example.com/plot.png")
      XCTAssertEqual(figure.intrinsicSize.width / figure.intrinsicSize.height, 16.0 / 9.0)
      XCTAssertEqual(textView.string, source)
    }

    private func makeImage(width: Int, height: Int) throws -> Data {
      let bitmap = try XCTUnwrap(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      ))
      return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
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
