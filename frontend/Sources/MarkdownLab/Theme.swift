#if os(macOS) && canImport(AppKit)
  import AppKit

  /// Screen design tokens ported from `typst-template/template.typ`.
  ///
  /// The Typst source is print-oriented, so sizes are scaled consistently for a
  /// Retina display instead of being copied point-for-point. Ratios, color values,
  /// spacing cadence, rail widths, and radii remain faithful to the template.
  enum Theme {
    // MARK: - Palette

    static let paper = NSColor(hex: 0xFBFAF8)
    static let surfaceSubtle = NSColor(hex: 0xF5F3EF)
    static let surfaceMuted = NSColor(hex: 0xEBE8E2)

    static let ink = NSColor(hex: 0x0F172A)
    static let inkSoft = NSColor(hex: 0x1E293B)
    static let textCol = NSColor(hex: 0x334155)
    static let muted = NSColor(hex: 0x64748B)
    static let faint = NSColor(hex: 0x94A3B8)

    static let accent = NSColor(hex: 0x4F46E5)
    static let accentStrong = NSColor(hex: 0x4338CA)
    static let accentSoft = NSColor(hex: 0xEEF2FF)
    static let accentLine = NSColor(hex: 0x4F46E5, alpha: 0.12)
    static let orange = NSColor(hex: 0xC2410C)
    static let warningSurface = NSColor(hex: 0xFFFAF0)
    static let highlight = NSColor(hex: 0xFEF3C7, alpha: 0.82)

    static let codeInk = NSColor(hex: 0x3730A3)
    static let codeChip = NSColor(hex: 0xF1EEE9)

    static let hairline = NSColor(hex: 0x0F172A, alpha: 0.08)
    static let hairlineMedium = NSColor(hex: 0x0F172A, alpha: 0.14)
    static let tableRule = NSColor(hex: 0x0F172A, alpha: 0.10)
    static let tableRuleStrong = NSColor(hex: 0x0F172A, alpha: 0.33)

    // Syntax colors from rr-code-theme.tmTheme.
    static let synKeyword = NSColor(hex: 0x9F1239)
    static let synString = NSColor(hex: 0x15803D)
    static let synComment = NSColor(hex: 0x64748B)
    static let synNumber = NSColor(hex: 0xB45309)
    static let synType = NSColor(hex: 0x4338CA)
    static let synFunction = NSColor(hex: 0x2563EB)

    // MARK: - Type

    static func serif(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
      font(["Iosevka Etoile", "Charter", "Georgia"], size: size, weight: weight)
        ?? NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func sans(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
      font(["Iosevka Aile", "Avenir Next"], size: size, weight: weight)
        ?? NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
      font(["Iosevka Term Extended", "SF Mono", "Menlo"], size: size, weight: weight)
        ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func applying(
      bold: Bool? = nil,
      italic: Bool? = nil,
      to font: NSFont
    ) -> NSFont {
      var traits = font.fontDescriptor.symbolicTraits
      if let bold {
        if bold { traits.insert(.bold) } else { traits.remove(.bold) }
      }
      if let italic {
        if italic { traits.insert(.italic) } else { traits.remove(.italic) }
      }
      let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
      guard let converted = NSFont(descriptor: descriptor, size: font.pointSize)
      else {
        var fallback = font
        if bold == true {
          fallback = NSFontManager.shared.convert(fallback, toHaveTrait: .boldFontMask)
        }
        if italic == true {
          fallback = NSFontManager.shared.convert(fallback, toHaveTrait: .italicFontMask)
        }
        return fallback
      }
      return converted
    }

    private static func font(
      _ families: [String],
      size: CGFloat,
      weight: NSFont.Weight
    ) -> NSFont? {
      for family in families {
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
          .addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]])
        if let font = NSFont(descriptor: descriptor, size: size),
          font.familyName?.localizedCaseInsensitiveContains(family) == true
        {
          return font
        }
        if let base = NSFont(name: family, size: size) {
          return weight >= .semibold
            ? NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
            : base
        }
      }
      return nil
    }

    // Typst 8.5pt body scaled by ~1.88 for a comfortable native editor.
    static let sizeBody: CGFloat = 16
    static let sizeBodySmall: CGFloat = 15.5
    static let sizeCode: CGFloat = 15
    static let sizeCaption: CGFloat = 13.5
    static let sizeMicro: CGFloat = 12.5
    static let sizeEquation: CGFloat = 21
    static let equationScriptScale: CGFloat = 0.72
    static let equationMargin: CGFloat = 15
    static let headingSizes: [CGFloat] = [25, 20.5, 18, 16.8, 16, 16]

    // MARK: - Rhythm

    static let space1: CGFloat = 5.5
    static let space2: CGFloat = 11
    static let space3: CGFloat = 16
    static let space4: CGFloat = 22
    static let space5: CGFloat = 29
    static let space6: CGFloat = 36
    static let space7: CGFloat = 48
    static let space8: CGFloat = 40
    static let space9: CGFloat = 58

    static let radiusSmall: CGFloat = 7
    static let radiusMedium: CGFloat = 13
    static let railInset: CGFloat = 25
    static let railWidth: CGFloat = 2

    static let readingWidth: CGFloat = 780
    static let minimumHorizontalInset: CGFloat = 42
    static let verticalInset: CGFloat = 42
    static let listIndent: CGFloat = 25
    static let bodyLineSpacing: CGFloat = 4.5
    static let paragraphSpacing: CGFloat = 13
  }

  extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
      let red = CGFloat((hex >> 16) & 0xFF) / 255
      let green = CGFloat((hex >> 8) & 0xFF) / 255
      let blue = CGFloat(hex & 0xFF) / 255
      self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
  }
#endif
