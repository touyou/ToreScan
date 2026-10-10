import Testing
@testable import ToreScanCore

@Suite struct IdentifierMatcherTests {
    let matcher = IdentifierMatcher(
        ["E1-01", "E1-02", "E1-12", "EP-001", "SC1-01", "SC1-01a", "PR-004", "001/165", "OP01-001"],
        identifier: { $0 }
    )

    @Test func findsAnIdentifierAsPrinted() {
        #expect(matcher.matches(in: "E1-01 PR") == ["E1-01"])
        #expect(matcher.matches(in: "No. EP-001") == ["EP-001"])
        #expect(matcher.matches(in: "001/165 C") == ["001/165"])
    }

    @Test func toleratesWhatOCRDoesToHyphensCaseAndWidth() {
        #expect(matcher.matches(in: "e1-01") == ["E1-01"])
        #expect(matcher.matches(in: "E1－01") == ["E1-01"])
        #expect(matcher.matches(in: "E1ー01") == ["E1-01"])
        #expect(matcher.matches(in: "E1–01") == ["E1-01"])
        #expect(matcher.matches(in: "Ｅ１－０１") == ["E1-01"])
    }

    @Test func toleratesStraySpaces() {
        #expect(matcher.matches(in: "E1 - 01") == ["E1-01"])
        #expect(matcher.matches(in: "E 1-01") == ["E1-01"])
        #expect(matcher.matches(in: "OP01 －001") == ["OP01-001"])
    }

    @Test func doesNotMatchInsideALongerWordOrNumber() {
        #expect(matcher.matches(in: "SE1-01").isEmpty)
        #expect(matcher.matches(in: "E1-012").isEmpty)
        #expect(matcher.matches(in: "E1-0").isEmpty)
        #expect(matcher.matches(in: "2E1-01").isEmpty)
    }

    @Test func aSpaceIsABoundaryEvenNextToADigit() {
        #expect(matcher.matches(in: "12 E1-01 34") == ["E1-01"])
    }

    @Test func allowsLettersRightAfterTheIdentifier() {
        #expect(matcher.matches(in: "E1-01PR") == ["E1-01"])
    }

    @Test func prefersTheLongestKnownIdentifier() {
        #expect(matcher.matches(in: "SC1-01a") == ["SC1-01a"])
        #expect(matcher.matches(in: "SC1-01A") == ["SC1-01a"])
        #expect(matcher.matches(in: "SC1-01") == ["SC1-01"])
        #expect(matcher.matches(in: "SC1-01b") == ["SC1-01"])
    }

    @Test func returnsMatchesInReadingOrder() {
        #expect(matcher.matches(in: "PR-004 and E1-02, then E1-12") == ["PR-004", "E1-02", "E1-12"])
        #expect(matcher.matches(in: ["E1-02 R", "Angely Sugar", "E1-01 PR"]) == ["E1-02", "E1-01"])
    }

    @Test func neverMatchesAcrossLines() {
        #expect(matcher.matches(in: "E1-\n01").isEmpty)
        #expect(matcher.matches(in: "foo E1-02\nbar EP-001") == ["E1-02", "EP-001"])
    }

    @Test func ignoresUnknownIdentifiersAndEmptyInput() {
        #expect(matcher.matches(in: "E9-99").isEmpty)
        #expect(matcher.matches(in: "").isEmpty)
        #expect(IdentifierMatcher<String>([], identifier: { $0 }).matches(in: "E1-01").isEmpty)
    }

    @Test func mapsIdentifiersToValuesAndKeepsTheFirstOfADuplicate() {
        struct Card: Equatable { let number: String; let name: String }
        let cards = [Card(number: "E1-01", name: "first"), Card(number: "e1－01", name: "second")]
        let matcher = IdentifierMatcher(cards, identifier: \.number)
        #expect(matcher.matches(in: "E1-01") == [cards[0]])
    }
}
