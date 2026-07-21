import Foundation

public struct TextEditDiff: Equatable {
    public let oldRange: NSRange
    public let replacement: String

    public static func between(old: String, new: String) -> TextEditDiff? {
        if old == new { return nil }

        let oldUnits = Array(old.utf16)
        let newUnits = Array(new.utf16)
        let commonCount = min(oldUnits.count, newUnits.count)

        var prefix = 0
        while prefix < commonCount && oldUnits[prefix] == newUnits[prefix] {
            prefix += 1
        }

        var oldSuffix = oldUnits.count
        var newSuffix = newUnits.count
        while oldSuffix > prefix,
              newSuffix > prefix,
              oldUnits[oldSuffix - 1] == newUnits[newSuffix - 1] {
            oldSuffix -= 1
            newSuffix -= 1
        }

        let replacementRange = NSRange(location: prefix, length: newSuffix - prefix)
        let oldRange = NSRange(location: prefix, length: oldSuffix - prefix)
        // `Range(NSRange, in:)` accepts some UTF-16 offsets that land between
        // the surrogate halves of a Unicode scalar on current Foundation
        // runtimes. MdCore edits are defined on real UTF-16 character
        // boundaries, so validate both ends explicitly before emitting a
        // minimal patch. Falling back to a full replacement is rare and keeps
        // emoji edits correct rather than splitting a scalar in two.
        guard isCharacterBoundary(oldRange.location, in: old),
              isCharacterBoundary(NSMaxRange(oldRange), in: old),
              isCharacterBoundary(replacementRange.location, in: new),
              isCharacterBoundary(NSMaxRange(replacementRange), in: new),
              let swiftRange = Range(replacementRange, in: new) else {
            return TextEditDiff(
                oldRange: NSRange(location: 0, length: oldUnits.count),
                replacement: new
            )
        }

        return TextEditDiff(
            oldRange: oldRange,
            replacement: String(new[swiftRange])
        )
    }

    private static func isCharacterBoundary(_ utf16Offset: Int, in string: String) -> Bool {
        guard utf16Offset >= 0, utf16Offset <= string.utf16.count else { return false }
        let index = String.UTF16View.Index(utf16Offset: utf16Offset, in: string)
        return String.Index(index, within: string) != nil
    }
}
