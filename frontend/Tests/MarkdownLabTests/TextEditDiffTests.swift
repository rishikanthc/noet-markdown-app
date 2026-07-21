import Foundation
@testable import MarkdownLabSupport
import XCTest

final class TextEditDiffTests: XCTestCase {
    func testInsertion() {
        let diff = TextEditDiff.between(old: "hello", new: "hello world")
        XCTAssertEqual(diff?.oldRange, NSRange(location: 5, length: 0))
        XCTAssertEqual(diff?.replacement, " world")
    }

    func testReplacement() {
        let diff = TextEditDiff.between(old: "alpha beta", new: "alpha gamma")
        XCTAssertEqual(diff?.oldRange, NSRange(location: 6, length: 3))
        XCTAssertEqual(diff?.replacement, "gamm")
    }

    func testDeletion() {
        let diff = TextEditDiff.between(old: "one two", new: "one")
        XCTAssertEqual(diff?.oldRange, NSRange(location: 3, length: 4))
        XCTAssertEqual(diff?.replacement, "")
    }

    func testNoChange() {
        XCTAssertNil(TextEditDiff.between(old: "same", new: "same"))
    }

    func testSurrogatePairBoundaryFallsBackToSafeWholeDocumentEdit() {
        let old = "😀"
        let new = "😁"
        let diff = TextEditDiff.between(old: old, new: new)
        XCTAssertEqual(diff?.oldRange, NSRange(location: 0, length: old.utf16.count))
        XCTAssertEqual(diff?.replacement, new)
    }

    func testHTMLWrapperProvidesDocumentAndFragment() {
        let html = HTMLDocument.wrap(fragment: "<h1>Title</h1>")
        XCTAssertTrue(html.contains("<!doctype html>"))
        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("color-scheme"))
    }
}
