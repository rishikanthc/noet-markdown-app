#if os(macOS) && canImport(CMdCore)
import Foundation
@testable import MarkdownLab
import XCTest

final class MdCoreIntegrationTests: XCTestCase {
    func testGFMTableRenderingAndSemanticSnapshot() throws {
        let source = """
        | A | B |
        | --- | --- |
        | 1 | 2 |
        """
        let engine = try MdCoreEngine(source: source)
        let html = try engine.renderHTML()
        let snapshot = try engine.canonicalSnapshot()

        XCTAssertTrue(html.contains("<table>"))
        XCTAssertEqual(snapshot.revision, 1)
        XCTAssertFalse(snapshot.nodes.isEmpty)
        XCTAssertFalse(snapshot.spans.isEmpty)
    }

    func testRevisionAdvancesAfterUTF16Edit() throws {
        let engine = try MdCoreEngine(source: "Hi 😀")
        XCTAssertEqual(engine.revision, 1)

        try engine.applyEdit(
            utf16Range: NSRange(location: 3, length: 2),
            replacement: "Markdown"
        )

        XCTAssertEqual(engine.revision, 2)
        XCTAssertTrue(try engine.renderHTML().contains("Hi Markdown"))
    }

    func testStrongCommandProducesSourceEdits() throws {
        let engine = try MdCoreEngine(source: "hello")
        let plan = try engine.plan(.strong, selection: NSRange(location: 0, length: 5))

        XCTAssertFalse(plan.edits.isEmpty)
        XCTAssertGreaterThanOrEqual(plan.resultSelection.end, plan.resultSelection.start)
    }
}
#endif
