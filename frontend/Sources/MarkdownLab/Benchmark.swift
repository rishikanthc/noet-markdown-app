#if os(macOS) && canImport(CMdCore)
import CMdCore
import Foundation

/// Headless rendering benchmark. Runs from the CLI via `MarkdownLab --benchmark`
/// (no window is created), timing the MdCore operations that drive the editor
/// across representative document sizes. Print output only; nothing is mutated.
enum Benchmark {
    /// One representative GFM block: heading, prose with inline styles, a list,
    /// a table, and a fenced code block. Repeated to reach each target size.
    private static let block = """
    # Section heading

    A paragraph with **bold**, *emphasis*, ~~strike~~, `inline code`, and a
    [link](https://example.com/path) plus an extended autolink https://github.com.

    - [x] finished task item
    - [ ] pending task item
    - nested bullet with `code`

    | Column A | Column B | Column C |
    | --- | --- | --- |
    | value 1 | value 2 | value 3 |

    ```swift
    let greeting = "hello"
    print(greeting)
    ```

    > A block quote closing the section.

    """

    private static let sizes: [(label: String, bytes: Int)] = [
        ("10 KiB", 10 * 1024),
        ("100 KiB", 100 * 1024),
        ("1 MiB", 1024 * 1024),
    ]

    static func run() {
        print("MdCore rendering benchmark")
        if let version = mdcore_version_string().map(String.init(cString:)) {
            print("engine: \(version)")
        }
        print("")
        print(row("document", "create", "canonical", "renderHTML", "span→utf16", "edit+reparse"))
        print(String(repeating: "-", count: 84))

        for size in sizes {
            do {
                try benchmark(size: size)
            } catch {
                print("\(size.label): FAILED — \(error)")
            }
        }
    }

    private static func benchmark(size: (label: String, bytes: Int)) throws {
        let source = document(ofAtLeast: size.bytes)

        var engine: MdCoreEngine!
        let createMs = try measure { engine = try MdCoreEngine(source: source) }

        var snapshot: CanonicalSnapshot!
        let canonicalMs = try measure { snapshot = try engine.canonicalSnapshot() }

        let renderMs = try measure { _ = try engine.renderHTML() }

        let byteRanges = snapshot.spans.map { MdByteRange(start: $0.start_byte, end: $0.end_byte) }
        let convertMs = try measure { _ = try engine.utf16Ranges(for: byteRanges) }

        // Simulate typing one character at the end, then a canonical reparse —
        // the hot path the editor runs on every debounce.
        let end = utf16Length(of: source)
        let editReparseMs = try measure {
            try engine.applyEdit(utf16Range: NSRange(location: end, length: 0), replacement: "x")
            _ = try engine.canonicalSnapshot()
        }

        let bytes = source.utf8.count
        print(row(
            "\(size.label) (\(bytes / 1024) KiB, \(snapshot.spans.count) spans)",
            fmt(createMs), fmt(canonicalMs), fmt(renderMs), fmt(convertMs), fmt(editReparseMs)
        ))
    }

    private static func document(ofAtLeast bytes: Int) -> String {
        let unit = block.utf8.count
        let repeats = max(1, (bytes + unit - 1) / unit)
        return String(repeating: block, count: repeats)
    }

    private static func utf16Length(of source: String) -> Int {
        source.utf16.count
    }

    private static func measure(_ body: () throws -> Void) rethrows -> Double {
        let clock = ContinuousClock()
        let start = clock.now
        try body()
        return start.duration(to: clock.now).inMilliseconds
    }

    private static func fmt(_ ms: Double) -> String {
        String(format: "%8.2f ms", ms)
    }

    private static func row(_ columns: String...) -> String {
        let widths = [34, 12, 12, 12, 12, 14]
        return zip(columns, widths)
            .map { text, width in text.padding(toLength: max(width, text.count), withPad: " ", startingAt: 0) }
            .joined(separator: " ")
    }
}
#endif
