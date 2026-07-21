#if os(macOS) && canImport(AppKit)
  import AppKit
  import Foundation

  struct MarkdownImageDescriptor: Equatable {
    static let defaultWidth: CGFloat = 512

    let sourceRange: NSRange
    let caption: String
    let destination: String
    let width: CGFloat

    static func parse(range: NSRange, source: NSString) -> MarkdownImageDescriptor? {
      guard range.location >= 0, NSMaxRange(range) <= source.length else { return nil }
      let markdown = source.substring(with: range) as NSString
      guard markdown.hasPrefix("!["),
        let labelEnd = firstUnescaped("]", in: markdown, after: 2),
        labelEnd + 1 < markdown.length,
        markdown.substring(with: NSRange(location: labelEnd + 1, length: 1)) == "("
      else { return nil }

      let close = markdown.length - 1
      guard close > labelEnd + 1,
        markdown.substring(with: NSRange(location: close, length: 1)) == ")"
      else { return nil }

      let caption = unescape(
        markdown.substring(with: NSRange(location: 2, length: labelEnd - 2)))
      let body = markdown.substring(
        with: NSRange(location: labelEnd + 2, length: close - labelEnd - 2)) as NSString
      let parsed = parseDestinationAndTitle(body)
      guard !parsed.destination.isEmpty else { return nil }
      return MarkdownImageDescriptor(
        sourceRange: range,
        caption: caption,
        destination: parsed.destination,
        width: parsed.width ?? defaultWidth
      )
    }

    func resolvedURL(relativeTo documentURL: URL?) -> URL? {
      if let absolute = URL(string: destination), absolute.scheme != nil { return absolute }
      let decoded = destination.removingPercentEncoding ?? destination
      if decoded.hasPrefix("/") { return URL(fileURLWithPath: decoded) }
      let base = documentURL?.deletingLastPathComponent()
        ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
      return URL(fileURLWithPath: decoded, relativeTo: base).standardizedFileURL
    }

    static func markdown(caption: String?, destination: String, width: CGFloat) -> String {
      let safeCaption = escapeLabel(caption ?? "")
      let pixels = max(Int(width.rounded()), 1)
      return "![\(safeCaption)](<\(destination)> \"width=\(pixels)\")"
    }

    private static func parseDestinationAndTitle(
      _ body: NSString
    ) -> (destination: String, width: CGFloat?) {
      var cursor = 0
      while cursor < body.length, CharacterSet.whitespacesAndNewlines.contains(
        UnicodeScalar(body.character(at: cursor))!
      ) { cursor += 1 }
      guard cursor < body.length else { return ("", nil) }

      let destination: String
      if body.character(at: cursor) == 0x3C,
        let end = firstUnescaped(">", in: body, after: cursor + 1)
      {
        destination = body.substring(
          with: NSRange(location: cursor + 1, length: end - cursor - 1))
        cursor = end + 1
      } else {
        let start = cursor
        while cursor < body.length {
          let scalar = UnicodeScalar(body.character(at: cursor))!
          if CharacterSet.whitespacesAndNewlines.contains(scalar) { break }
          cursor += 1
        }
        destination = body.substring(with: NSRange(location: start, length: cursor - start))
      }

      let remainder = body.substring(from: cursor)
      let expression = try? NSRegularExpression(
        pattern: #"width\s*=\s*([0-9]+(?:\.[0-9]+)?)"#,
        options: [.caseInsensitive]
      )
      let full = NSRange(location: 0, length: (remainder as NSString).length)
      let match = expression?.firstMatch(in: remainder, range: full)
      let width = match.flatMap { result -> CGFloat? in
        guard result.numberOfRanges > 1 else { return nil }
        return Double((remainder as NSString).substring(with: result.range(at: 1))).map { CGFloat($0) }
      }
      return (unescape(destination), width)
    }

    private static func firstUnescaped(
      _ character: Character, in source: NSString, after start: Int
    ) -> Int? {
      let needle = String(character).utf16.first!
      var location = start
      while location < source.length {
        guard source.character(at: location) == needle else {
          location += 1
          continue
        }
        var slashes = 0
        var previous = location
        while previous > start, source.character(at: previous - 1) == 0x5C {
          slashes += 1
          previous -= 1
        }
        if slashes.isMultiple(of: 2) { return location }
        location += 1
      }
      return nil
    }

    private static func escapeLabel(_ value: String) -> String {
      value.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "]", with: "\\]")
        .replacingOccurrences(of: "\n", with: " ")
    }

    private static func unescape(_ value: String) -> String {
      value.replacingOccurrences(of: "\\]", with: "]")
        .replacingOccurrences(of: "\\\\", with: "\\")
    }
  }

  enum ImageAssetImporter {
    static func destination(
      for sourceURL: URL,
      documentURL: URL?,
      fileManager: FileManager = .default
    ) throws -> String {
      guard let documentURL else { return sourceURL.absoluteString }
      let assets = documentURL.deletingLastPathComponent()
        .appendingPathComponent("assets", isDirectory: true)
      try fileManager.createDirectory(at: assets, withIntermediateDirectories: true)

      let safeStem = sanitizedStem(sourceURL.deletingPathExtension().lastPathComponent)
      let fileExtension = sourceURL.pathExtension.lowercased()
      var candidate = assets.appendingPathComponent(
        fileExtension.isEmpty ? safeStem : "\(safeStem).\(fileExtension)")
      var suffix = 2
      while fileManager.fileExists(atPath: candidate.path) {
        if candidate.standardizedFileURL == sourceURL.standardizedFileURL { break }
        let name = "\(safeStem)-\(suffix)"
        candidate = assets.appendingPathComponent(
          fileExtension.isEmpty ? name : "\(name).\(fileExtension)")
        suffix += 1
      }
      if candidate.standardizedFileURL != sourceURL.standardizedFileURL {
        try fileManager.copyItem(at: sourceURL, to: candidate)
      }
      return "assets/\(candidate.lastPathComponent)"
    }

    private static func sanitizedStem(_ value: String) -> String {
      let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
      let mapped = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
      let result = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
      return result.isEmpty ? "image" : result
    }
  }
#endif
