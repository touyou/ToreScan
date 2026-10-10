import Foundation
import Testing
@testable import ToreScan

@MainActor
@Suite struct ScanSessionTests {
    final class Clock {
        var now = Date(timeIntervalSinceReferenceDate: 1_000)
    }

    @Test func publishesTheFocusedItemAndReportsSettledOnes() {
        let clock = Clock()
        let session = ScanSession<String>(now: { clock.now })
        var settled: [String] = []
        session.onSettle = { settled.append($0) }

        session.observe(["A"])
        #expect(session.visible == ["A"])
        #expect(session.focused == nil)

        clock.now += 0.5
        session.advance()
        #expect(session.focused == "A")
        #expect(session.isFocusedVisible)
        #expect(settled == ["A"])

        session.markHandled("A")
        clock.now += 1
        session.observe([])
        #expect(session.focused == "A")
        #expect(!session.isFocusedVisible)

        clock.now += 6
        session.advance()
        #expect(session.focused == nil)
        #expect(settled == ["A"])
        session.stop()
    }

    @Test func wakesItselfUpWhenAnItemSettles() async throws {
        let session = ScanSession<String>(configuration: .init(settleDelay: 0.05, holdDuration: 0.1, repeatInterval: 1))
        session.observe(["A"])
        #expect(session.focused == nil)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(session.focused == "A")

        session.observe([])
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(session.focused == nil)
    }

    @Test func clearFocusStopsOfferingTheHeldItem() {
        let clock = Clock()
        let session = ScanSession<String>(now: { clock.now })
        session.observe(["A"])
        clock.now += 0.5
        session.advance()
        session.observe([])
        session.clearFocus()
        #expect(session.focused == nil)
        session.stop()
    }
}
