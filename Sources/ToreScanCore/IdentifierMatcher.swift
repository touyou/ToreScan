import Foundation

/// Finds known identifiers, such as card numbers, inside text read by OCR.
///
/// OCR rarely returns an identifier exactly as printed: hyphens come back as full-width or as one of
/// several dash characters, letters change case, digits arrive full-width, and stray spaces appear
/// around the hyphen or between characters. Because the set of valid identifiers is known up front,
/// the matcher doesn't guess at a format. It normalizes both sides the same way and looks for the
/// known identifiers in the text.
///
/// ```swift
/// let matcher = IdentifierMatcher(cards, identifier: \.number)
/// matcher.matches(in: "ｅ１ － ０１ PR")   // the card numbered "E1-01"
/// ```
///
/// A match has to stand on its own: `E1-01` is not found inside `SE1-01` or `E1-012`. When two known
/// identifiers overlap, such as `SC1-01` and `SC1-01a`, the longer one wins.
public struct IdentifierMatcher<Value> {
    private let valuesByKey: [String: Value]
    /// Keys as character arrays, longest first, so the longest identifier at a position is found first.
    private let keys: [(key: String, characters: [Character])]

    /// - Parameter entries: The known identifiers and what each one stands for. If two identifiers
    ///   normalize to the same key, the first one is kept.
    public init(_ entries: some Sequence<(identifier: String, value: Value)>) {
        var valuesByKey: [String: Value] = [:]
        for entry in entries {
            let key = Self.normalize(entry.identifier).filter { !$0.isWhitespace }
            guard !key.isEmpty, valuesByKey[key] == nil else { continue }
            valuesByKey[key] = entry.value
        }
        self.valuesByKey = valuesByKey
        self.keys = valuesByKey.keys
            .map { (key: $0, characters: Array($0)) }
            .sorted { ($0.characters.count, $0.key) > ($1.characters.count, $1.key) }
    }

    public init(_ values: some Sequence<Value>, identifier: (Value) -> String) {
        self.init(values.map { (identifier: identifier($0), value: $0) })
    }

    /// The values whose identifiers appear in `text`, in the order they appear. Lines are searched
    /// separately; an identifier never spans a line break.
    public func matches(in text: String) -> [Value] {
        var found: [Value] = []
        for line in text.split(whereSeparator: \.isNewline) {
            for key in keys(in: String(line)) {
                if let value = valuesByKey[key] { found.append(value) }
            }
        }
        return found
    }

    /// Convenience for scanners that report one string per recognized item.
    public func matches(in texts: some Sequence<String>) -> [Value] {
        texts.flatMap { matches(in: $0) }
    }

    // MARK: Matching

    private func keys(in line: String) -> [String] {
        // Compare without whitespace, but remember where it was: a space is a word boundary even
        // though it may also be OCR noise in the middle of an identifier.
        var characters: [Character] = []
        var followsSpace: [Bool] = []
        var pendingSpace = false
        for character in Self.normalize(line) {
            if character.isWhitespace {
                pendingSpace = true
            } else {
                characters.append(character)
                followsSpace.append(pendingSpace)
                pendingSpace = false
            }
        }

        var matches: [(start: Int, end: Int, key: String)] = []
        for (key, keyCharacters) in keys where keyCharacters.count <= characters.count {
            var start = 0
            while start + keyCharacters.count <= characters.count {
                let end = start + keyCharacters.count
                if characters[start..<end].elementsEqual(keyCharacters),
                   isBoundary(before: start, in: characters, followsSpace: followsSpace),
                   isBoundary(after: end, in: characters, followsSpace: followsSpace),
                   !matches.contains(where: { $0.start < end && start < $0.end }) {
                    matches.append((start, end, key))
                    start = end
                } else {
                    start += 1
                }
            }
        }
        return matches.sorted { $0.start < $1.start }.map(\.key)
    }

    /// An identifier may not continue a word or number to its left.
    private func isBoundary(before index: Int, in characters: [Character], followsSpace: [Bool]) -> Bool {
        guard index > 0, !followsSpace[index] else { return true }
        let previous = characters[index - 1]
        return !(previous.isLetter || previous.isNumber)
    }

    /// An identifier may be followed by letters (a rarity printed right after it), but not by more
    /// digits, which would make it a different number.
    private func isBoundary(after index: Int, in characters: [Character], followsSpace: [Bool]) -> Bool {
        guard index < characters.count, !followsSpace[index] else { return true }
        return !characters[index].isNumber
    }

    /// Upper case, half-width, with every kind of dash turned into `-`.
    private static func normalize(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            result.append(dashes.contains(character) ? "-" : character)
        }
        return (result.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? result).uppercased()
    }
}

/// Characters OCR returns in place of a hyphen, including the katakana long vowel mark.
private let dashes: Set<Character> = ["－", "‐", "‑", "‒", "–", "—", "―", "−", "ー", "ｰ", "﹣"]

extension IdentifierMatcher: Sendable where Value: Sendable {}
