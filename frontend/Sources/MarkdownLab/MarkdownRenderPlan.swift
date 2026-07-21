#if os(macOS) && canImport(CMdCore)
  import Foundation

  /// Value-only output of the engine session. It crosses onto the main thread
  /// without exposing MdCore handles or requiring the renderer to call Zig.
  struct MarkdownRenderPlan {
    struct Node {
      let kind: Int
      let flags: UInt16
      let range: NSRange
    }

    struct Span {
      let role: Int
      let range: NSRange
    }

    let revision: UInt64
    let source: String
    let nodes: [Node]
    let spans: [Span]
    let versionSummary: String
  }

  struct MarkdownEditAcknowledgement {
    let revision: UInt64
    let invalidatedRange: NSRange?
  }

  struct MarkdownCommandPlan {
    struct Edit {
      let range: NSRange
      let replacement: String
    }

    let edits: [Edit]
    let selection: NSRange
  }
#endif
