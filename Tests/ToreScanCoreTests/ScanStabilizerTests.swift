import Foundation
import Testing
@testable import ToreScanCore

@Suite struct ScanStabilizerTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)
    func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    @Test func offersAnIdentifierOnlyAfterItStaysInView() {
        var stabilizer = ScanStabilizer<String>()
        #expect(stabilizer.observe(["E1-01"], at: at(0)).isEmpty)
        #expect(stabilizer.focused == nil)
        #expect(stabilizer.nextDeadline == at(0.4))

        #expect(stabilizer.advance(to: at(0.39)).isEmpty)
        #expect(stabilizer.advance(to: at(0.4)) == ["E1-01"])
        #expect(stabilizer.focused == "E1-01")
        #expect(stabilizer.isFocusedVisible)
        #expect(stabilizer.nextDeadline == nil)
    }

    @Test func ignoresASingleMisreadFrame() {
        var stabilizer = ScanStabilizer<String>()
        stabilizer.observe(["E1-07"], at: at(0))
        stabilizer.observe([], at: at(0.1))
        #expect(stabilizer.advance(to: at(1)).isEmpty)
        #expect(stabilizer.focused == nil)
    }

    @Test func aRunInterruptedByFlickerStartsOver() {
        var stabilizer = ScanStabilizer<String>()
        stabilizer.observe(["A"], at: at(0))
        stabilizer.observe([], at: at(0.3))
        stabilizer.observe(["A"], at: at(0.35))
        #expect(stabilizer.advance(to: at(0.5)).isEmpty)
        #expect(stabilizer.advance(to: at(0.75)) == ["A"])
    }

    @Test func holdsTheFocusedIdentifierAfterItLeavesTheView() {
        var stabilizer = ScanStabilizer<String>()
        stabilizer.observe(["A"], at: at(0))
        stabilizer.advance(to: at(0.4))

        stabilizer.observe([], at: at(1))
        #expect(stabilizer.focused == "A")
        #expect(!stabilizer.isFocusedVisible)
        #expect(stabilizer.nextDeadline == at(7))

        stabilizer.advance(to: at(6.9))
        #expect(stabilizer.focused == "A")
        stabilizer.advance(to: at(7))
        #expect(stabilizer.focused == nil)
        #expect(stabilizer.nextDeadline == nil)
    }

    @Test func comingBackIntoViewCancelsTheRelease() {
        var stabilizer = ScanStabilizer<String>()
        stabilizer.observe(["A"], at: at(0))
        stabilizer.advance(to: at(0.4))
        stabilizer.observe([], at: at(1))
        stabilizer.observe(["A"], at: at(3))
        stabilizer.observe([], at: at(5))
        stabilizer.advance(to: at(10.9))
        #expect(stabilizer.focused == "A")
        stabilizer.advance(to: at(11))
        #expect(stabilizer.focused == nil)
    }

    @Test func staysOnTheFocusedIdentifierWhenAnotherAppearsNextToIt() {
        var stabilizer = ScanStabilizer<String>()
        stabilizer.observe(["A"], at: at(0))
        stabilizer.advance(to: at(0.4))
        stabilizer.observe(["B", "A"], at: at(1))
        #expect(stabilizer.advance(to: at(2)) == ["B"])
        #expect(stabilizer.focused == "A")
    }

    @Test func aHeldIdentifierIsReplacedByTheNextOneThatSettles() {
        var stabilizer = ScanStabilizer<String>()
        stabilizer.observe(["A"], at: at(0))
        stabilizer.advance(to: at(0.4))
        stabilizer.observe(["B"], at: at(1))
        #expect(stabilizer.focused == "A")
        stabilizer.advance(to: at(1.4))
        #expect(stabilizer.focused == "B")
    }

    @Test func reportsEachRunInViewOnlyOnce() {
        var stabilizer = ScanStabilizer<String>()
        stabilizer.observe(["A"], at: at(0))
        #expect(stabilizer.advance(to: at(0.4)) == ["A"])
        #expect(stabilizer.observe(["A"], at: at(1)).isEmpty)
        #expect(stabilizer.advance(to: at(30)).isEmpty)
    }

    @Test func aHandledIdentifierIsNotReportedAgainUntilItHasBeenAwayLongEnough() {
        var stabilizer = ScanStabilizer<String>()
        stabilizer.observe(["A"], at: at(0))
        #expect(stabilizer.advance(to: at(0.4)) == ["A"])
        stabilizer.markHandled("A", at: at(0.4))

        // Tracking flicker long after it was handled: gone for a second, then back.
        stabilizer.observe([], at: at(10))
        stabilizer.observe(["A"], at: at(11))
        #expect(stabilizer.advance(to: at(11.4)).isEmpty)

        // Each short disappearance keeps the window open.
        stabilizer.observe([], at: at(20))
        stabilizer.observe(["A"], at: at(22))
        #expect(stabilizer.advance(to: at(22.4)).isEmpty)

        // Away for longer than the repeat interval: it counts as another copy.
        stabilizer.observe([], at: at(30))
        stabilizer.observe(["A"], at: at(33.5))
        #expect(stabilizer.advance(to: at(33.9)) == ["A"])
    }

    @Test func handlingByHandAlsoSuppressesTheRepeat() {
        var stabilizer = ScanStabilizer<String>()
        stabilizer.observe(["A"], at: at(0))
        stabilizer.advance(to: at(0.4))
        stabilizer.observe([], at: at(1))
        // Added from the held panel after the card left the frame.
        stabilizer.markHandled("A", at: at(2))
        stabilizer.observe(["A"], at: at(3))
        #expect(stabilizer.advance(to: at(3.4)).isEmpty)
    }

    @Test func anIdentifierThatWasNotHandledIsReportedOnItsNextRun() {
        var stabilizer = ScanStabilizer<String>()
        stabilizer.observe(["A"], at: at(0))
        #expect(stabilizer.advance(to: at(0.4)) == ["A"])
        stabilizer.observe([], at: at(1))
        stabilizer.observe(["A"], at: at(1.5))
        #expect(stabilizer.advance(to: at(1.9)) == ["A"])
    }

    @Test func duplicateIdentifiersInOneReportAreCollapsed() {
        var stabilizer = ScanStabilizer<String>()
        stabilizer.observe(["A", "B", "A"], at: at(0))
        #expect(stabilizer.visible == ["A", "B"])
        #expect(stabilizer.advance(to: at(0.4)) == ["A", "B"])
    }

    @Test func clearFocusDropsTheHeldIdentifier() {
        var stabilizer = ScanStabilizer<String>()
        stabilizer.observe(["A"], at: at(0))
        stabilizer.advance(to: at(0.4))
        stabilizer.observe([], at: at(1))
        stabilizer.clearFocus()
        #expect(stabilizer.focused == nil)
        #expect(stabilizer.nextDeadline == nil)
    }

    @Test func respectsACustomConfiguration() {
        var stabilizer = ScanStabilizer<Int>(configuration: .init(settleDelay: 0, holdDuration: 1, repeatInterval: 0))
        #expect(stabilizer.observe([7], at: at(0)) == [7])
        stabilizer.markHandled(7, at: at(0))
        stabilizer.observe([], at: at(0.5))
        #expect(stabilizer.observe([7], at: at(0.6)) == [7])
        stabilizer.observe([], at: at(1))
        stabilizer.advance(to: at(2))
        #expect(stabilizer.focused == nil)
    }
}
