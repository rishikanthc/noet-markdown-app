#if os(macOS) && canImport(AppKit) && canImport(CMdCore)
import AppKit

@main
struct MarkdownLabMain {
    static func main() {
        if CommandLine.arguments.contains("--benchmark") {
            Benchmark.run()
            return
        }
        if CommandLine.arguments.contains("--stylecheck") {
            let path = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("-") }
            StyleCheck.run(path: path)
            return
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}
#else
import Foundation

@main
struct MarkdownLabMain {
    static func main() {
        fputs("MarkdownLab is a macOS AppKit application. Build it on macOS with `make app`.\n", stderr)
    }
}
#endif
