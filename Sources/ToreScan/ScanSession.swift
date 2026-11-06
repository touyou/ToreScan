import Foundation
import Observation
import ToreScanCore

/// Drives a ``ScanStabilizer`` for a SwiftUI scanner screen: feed it what the camera reads and
/// observe ``focused`` to know what to offer.
///
/// ```swift
/// @State private var session = ScanSession<Card>()
///
/// LiveTextScanner { texts in session.observe(matcher.matches(in: texts)) }
///
/// if let card = session.focused {
///     Button("Add") { add(card); session.markHandled(card) }
/// }
/// ```
///
/// Set ``onSettle`` to act on items the moment they have been read reliably, for example to add them
/// automatically. The session keeps its own timer, so held items expire and items settle even while
/// the scanner reports nothing new.
@MainActor
@Observable
public final class ScanSession<Item: Hashable & Sendable> {
    /// The item to offer in the UI, or nil when nothing has been read recently.
    public private(set) var focused: Item?
    /// Everything the camera sees right now, in the order it was reported.
    public private(set) var visible: [Item] = []
    /// Whether ``focused`` is in view right now rather than being held after the camera lost it.
    public private(set) var isFocusedVisible = false

    /// Called once for each item when it has stayed in view long enough to be trusted and isn't a
    /// repeat of something handled a moment ago. Call ``markHandled(_:)`` if you act on it.
    @ObservationIgnored public var onSettle: ((Item) -> Void)?

    public var configuration: ScanStabilizer<Item>.Configuration {
        get { stabilizer.configuration }
        set { stabilizer.configuration = newValue }
    }

    // 毎フレーム書き換わるので追跡しない。画面に出す値は publish で差分があるときだけ写す
    @ObservationIgnored private var stabilizer: ScanStabilizer<Item>
    @ObservationIgnored private var wakeUp: Task<Void, Never>?
    private let now: @MainActor () -> Date

    public init(configuration: ScanStabilizer<Item>.Configuration = .init()) {
        self.stabilizer = ScanStabilizer(configuration: configuration)
        self.now = { Date.now }
    }

    /// For tests: a session that reads the time from `now` instead of the system clock.
    init(configuration: ScanStabilizer<Item>.Configuration = .init(), now: @escaping @MainActor () -> Date) {
        self.stabilizer = ScanStabilizer(configuration: configuration)
        self.now = now
    }

    deinit {
        wakeUp?.cancel()
    }

    /// Reports everything the camera sees now. Pass an empty array when it sees nothing.
    public func observe(_ items: [Item]) {
        publish(settled: stabilizer.observe(items, at: now()))
    }

    /// Tells the session an item was acted on, so it isn't reported again while it stays in view.
    public func markHandled(_ item: Item) {
        stabilizer.markHandled(item, at: now())
    }

    /// Stops offering the focused item without waiting for it to time out.
    public func clearFocus() {
        stabilizer.clearFocus()
        publish(settled: [])
    }

    /// Stops the timer. Call when the scanner screen goes away; observing again restarts it.
    public func stop() {
        wakeUp?.cancel()
        wakeUp = nil
    }

    /// Applies what is due now. The session calls this itself; it is exposed for tests.
    func advance() {
        publish(settled: stabilizer.advance(to: now()))
    }

    private func publish(settled: [Item]) {
        if focused != stabilizer.focused { focused = stabilizer.focused }
        if visible != stabilizer.visible { visible = stabilizer.visible }
        if isFocusedVisible != stabilizer.isFocusedVisible { isFocusedVisible = stabilizer.isFocusedVisible }
        for item in settled {
            onSettle?(item)
        }
        scheduleWakeUp()
    }

    private func scheduleWakeUp() {
        wakeUp?.cancel()
        guard let deadline = stabilizer.nextDeadline else {
            wakeUp = nil
            return
        }
        wakeUp = Task { [weak self] in
            let delay = max(0, deadline.timeIntervalSinceNow)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000) + 5_000_000)
            guard !Task.isCancelled else { return }
            self?.advance()
        }
    }
}
