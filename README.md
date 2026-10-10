# ToreScan

Steady card scanning for iOS. Hold a trading card up to the camera, read the number printed on it,
and get a result you can put a button next to.

VisionKit's live text scanner reports what it sees many times a second, and what it sees comes and
goes with every shake of the hand: a number is read, lost, misread for one frame, read again. Wire
that straight into a UI and the "Add" button jumps away as you reach for it, a misread adds the wrong
card, and one card is counted twice. ToreScan sits between the scanner and your UI and deals with it.

- **Settle** – a number is only offered after it has stayed readable for a moment (0.4 s by default),
  so a single misread frame is ignored.
- **Hold** – the last card read stays selectable for a few seconds (6 s) after it leaves the frame.
- **No double counting** – a card you already added is not reported again until it has really been
  taken away (3 s out of view), however much the tracking flickers.
- **Tolerant matching** – finds your known card numbers in OCR output despite full-width characters,
  odd dashes, wrong case and stray spaces.

It is not limited to cards: anything with a known set of printed identifiers works the same way
(serial numbers, shelf labels, tickets).

日本語: トレーディングカードの番号をカメラで読み取るときの「候補がすぐ外れる」「読み違いで別のカードが入る」
「同じカードを二重に数える」を防ぐための Swift パッケージです。

## Requirements

- iOS 16 or later for the camera view (`DataScannerViewController` needs an A12 chip or later)
- Swift 6 / Xcode 16 or later
- `ToreScanCore` has no UI dependency and also builds for macOS and visionOS

## Installation

Add the package in Xcode (**File ▸ Add Package Dependencies…**) or in `Package.swift`:

```swift
.package(url: "https://github.com/touyou/ToreScan.git", from: "0.1.0")
```

Add `NSCameraUsageDescription` to your app's Info.plist.

## Usage

```swift
import SwiftUI
import ToreScan
import ToreScanCore

struct ScannerView: View {
    let matcher: IdentifierMatcher<Card>          // built once from your card list
    @StateObject private var session = ScanSession<Card>()
    @State private var addsAutomatically = false

    var body: some View {
        ZStack(alignment: .bottom) {
            LiveTextScanner(languages: ["en-US", "ja-JP"]) { texts in
                session.observe(matcher.matches(in: texts))
            }

            if let card = session.focused {
                Button("Add \(card.name)") { add(card) }
                    .opacity(session.isFocusedVisible ? 1 : 0.7)   // held after leaving the frame
            }
        }
        .onAppear {
            session.onSettle = { card in
                if addsAutomatically { add(card) }
            }
        }
        .onDisappear { session.stop() }
    }

    private func add(_ card: Card) {
        collection.add(card)
        session.markHandled(card)     // don't report it again while it stays in view
    }
}

let matcher = IdentifierMatcher(cards, identifier: \.number)
```

### The pieces

| Type | Module | What it does |
| --- | --- | --- |
| `LiveTextScanner` | ToreScan | SwiftUI camera view; reports every string in view |
| `ScanSession` | ToreScan | `ObservableObject` that steadies the stream and runs its own timer |
| `ScanStabilizer` | ToreScanCore | The logic behind `ScanSession` as a plain value type, with no timers and no clock |
| `IdentifierMatcher` | ToreScanCore | Finds known identifiers in OCR text |

`ScanStabilizer` takes the current time as a parameter, so its behaviour is deterministic and you can
unit-test your own scanning flow against it without a camera. Use it directly if you drive the scanner
from something other than SwiftUI.

### Tuning

```swift
ScanSession<Card>(configuration: .init(settleDelay: 0.4, holdDuration: 6, repeatInterval: 3))
```

### What the matcher accepts

`IdentifierMatcher` normalizes both your identifiers and the text (upper case, half-width, every kind
of dash turned into `-`, whitespace ignored) and then looks for the identifiers it knows. A match has
to stand on its own: `E1-01` is found in `ｅ１ － ０１ PR` but not inside `SE1-01` or `E1-012`. When
two known identifiers overlap (`SC1-01` and `SC1-01a`), the longer one wins.

## License

MIT
