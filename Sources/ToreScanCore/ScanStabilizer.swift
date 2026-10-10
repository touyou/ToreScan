import Foundation

/// Turns the flickering stream of things a live camera recognizes into something a person can act on.
///
/// A live text or barcode scanner reports what it sees many times a second, and what it sees comes
/// and goes with every shake of the hand: an identifier is read, lost, misread for a frame, read
/// again. `ScanStabilizer` sits between that stream and your UI and answers three questions:
///
/// - **What should be offered right now?** ``focused`` sticks to one identifier while it is in view
///   and is kept for ``Configuration/holdDuration`` after the camera loses it, so the button next to
///   it doesn't run away.
/// - **Is this read real?** An identifier is only offered, and only reported as settled, after it has
///   been in view without interruption for ``Configuration/settleDelay``.
/// - **Is this the same physical thing as before?** Once you ``markHandled(_:at:)`` an identifier it is
///   not reported again until it has been out of view for ``Configuration/repeatInterval``, so
///   tracking flicker doesn't count one card twice.
///
/// The type is a plain value with no timers and no clock of its own: you tell it what is in view and
/// what time it is, which makes it deterministic and easy to test. Call ``observe(_:at:)`` whenever
/// the scanner reports, and ``advance(to:)`` at ``nextDeadline`` so time-based changes happen even
/// when the scanner is quiet. `ScanSession` in the `ToreScan` module does both for you.
public struct ScanStabilizer<ID: Hashable & Sendable>: Sendable {
    public struct Configuration: Sendable, Equatable {
        /// How long an identifier has to stay in view before it is offered or reported as settled.
        /// A single misread frame while the camera is moving usually doesn't last this long.
        public var settleDelay: TimeInterval
        /// How long the focused identifier is kept after it leaves the view.
        public var holdDuration: TimeInterval
        /// How long a handled identifier has to be out of view before it is reported as settled again.
        public var repeatInterval: TimeInterval

        public init(settleDelay: TimeInterval = 0.4, holdDuration: TimeInterval = 6, repeatInterval: TimeInterval = 3) {
            self.settleDelay = settleDelay
            self.holdDuration = holdDuration
            self.repeatInterval = repeatInterval
        }
    }

    public var configuration: Configuration

    /// What the scanner reported last, in its order, without duplicates.
    public private(set) var visible: [ID] = []

    /// The identifier to offer in the UI: the first one that settled, kept while it stays in view and
    /// for ``Configuration/holdDuration`` afterwards.
    public private(set) var focused: ID?

    /// When each visible identifier entered the view in its current uninterrupted run.
    private var firstSeen: [ID: Date] = [:]
    /// Visible identifiers already reported as settled during their current run.
    private var reported: Set<ID> = []
    /// Visible identifiers that were handled, or suppressed as repeats, during their current run.
    private var handledWhileVisible: Set<ID> = []
    /// When each identifier was last handled or, if it was handled while in view, last seen.
    private var lastHandled: [ID: Date] = [:]
    /// When the focused identifier left the view.
    private var focusLostAt: Date?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Whether ``focused`` is in view right now rather than being held after the camera lost it.
    public var isFocusedVisible: Bool {
        focused.map(visible.contains) ?? false
    }

    /// Records what the scanner sees now. Pass everything currently in view, not just what changed.
    ///
    /// - Returns: Identifiers that just settled; see ``advance(to:)``.
    @discardableResult
    public mutating func observe(_ ids: [ID], at now: Date = .now) -> [ID] {
        var seen = Set<ID>()
        let unique = ids.filter { seen.insert($0).inserted }

        // The repeat window of something handled while in view starts when it leaves the view.
        for id in handledWhileVisible.subtracting(seen) {
            lastHandled[id] = now
        }
        handledWhileVisible.formIntersection(seen)
        reported.formIntersection(seen)
        firstSeen = Dictionary(uniqueKeysWithValues: unique.map { ($0, firstSeen[$0] ?? now) })
        visible = unique
        return advance(to: now)
    }

    /// Applies everything that depends on time alone: identifiers settling and the hold running out.
    ///
    /// - Returns: Identifiers that just settled and are not repeats of something recently handled, in
    ///   view order. Each identifier is returned at most once per uninterrupted run in view. Act on
    ///   them if you add automatically, and call ``markHandled(_:at:)`` for each one you act on.
    @discardableResult
    public mutating func advance(to now: Date = .now) -> [ID] {
        let settled = visible.filter { hasSettled($0, at: now) }

        if isFocusedVisible {
            // Stay on the current identifier even if another one shows up next to it.
            focusLostAt = nil
        } else if let next = settled.first {
            focused = next
            focusLostAt = nil
        } else if focused != nil {
            if let lostAt = focusLostAt {
                if now >= lostAt.addingTimeInterval(configuration.holdDuration) {
                    focused = nil
                    focusLostAt = nil
                }
            } else {
                focusLostAt = now
            }
        }

        var fresh: [ID] = []
        for id in settled where reported.insert(id).inserted {
            if handledWhileVisible.contains(id) { continue }
            if let last = lastHandled[id], now < last.addingTimeInterval(configuration.repeatInterval) {
                // Still the same physical thing flickering; keep its window open until it really leaves.
                handledWhileVisible.insert(id)
                continue
            }
            fresh.append(id)
        }
        return fresh
    }

    /// Tells the stabilizer you acted on `id` (for example added the card), whether automatically or
    /// because the person tapped. It won't be reported as settled again until it has been out of view
    /// for ``Configuration/repeatInterval``.
    public mutating func markHandled(_ id: ID, at now: Date = .now) {
        lastHandled[id] = now
        if visible.contains(id) {
            handledWhileVisible.insert(id)
        }
    }

    /// Drops the focused identifier without waiting for the hold to run out.
    public mutating func clearFocus() {
        focused = nil
        focusLostAt = nil
    }

    /// The next moment at which ``advance(to:)`` would change something, or nil if nothing is pending.
    public var nextDeadline: Date? {
        var deadlines = visible
            .filter { !reported.contains($0) }
            .compactMap { firstSeen[$0]?.addingTimeInterval(configuration.settleDelay) }
        if focused != nil, let focusLostAt {
            deadlines.append(focusLostAt.addingTimeInterval(configuration.holdDuration))
        }
        return deadlines.min()
    }

    private func hasSettled(_ id: ID, at now: Date) -> Bool {
        guard let since = firstSeen[id] else { return false }
        return now >= since.addingTimeInterval(configuration.settleDelay)
    }
}
