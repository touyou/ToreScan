#if canImport(VisionKit) && os(iOS)
import SwiftUI
import VisionKit

/// A camera view that reads text continuously and reports every string in view whenever that changes.
///
/// It is a thin SwiftUI wrapper around VisionKit's `DataScannerViewController`. Pair it with
/// `IdentifierMatcher` to turn the strings into your own values and with ``ScanSession`` to steady
/// the result:
///
/// ```swift
/// LiveTextScanner(languages: ["en-US", "ja-JP"]) { texts in
///     session.observe(matcher.matches(in: texts))
/// }
/// ```
///
/// Check ``isAvailable`` first and add `NSCameraUsageDescription` to your Info.plist.
public struct LiveTextScanner: UIViewControllerRepresentable {
    private let languages: [String]
    private let qualityLevel: DataScannerViewController.QualityLevel
    private let isHighlightingEnabled: Bool
    private let isPinchToZoomEnabled: Bool
    private let onRecognized: @MainActor ([String]) -> Void

    /// Whether the device has the hardware for live scanning (an A12 chip or later).
    @MainActor public static var isSupported: Bool { DataScannerViewController.isSupported }

    /// Whether scanning can start now: the device supports it and camera access is granted.
    @MainActor public static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    /// - Parameters:
    ///   - languages: Language identifiers to recognize, most likely first. Empty uses the person's
    ///     preferred languages.
    ///   - onRecognized: Called with the transcript of every text item currently in view, each time
    ///     an item appears, changes or disappears.
    public init(
        languages: [String] = [],
        qualityLevel: DataScannerViewController.QualityLevel = .accurate,
        isHighlightingEnabled: Bool = true,
        isPinchToZoomEnabled: Bool = true,
        onRecognized: @escaping @MainActor ([String]) -> Void
    ) {
        self.languages = languages
        self.qualityLevel = qualityLevel
        self.isHighlightingEnabled = isHighlightingEnabled
        self.isPinchToZoomEnabled = isPinchToZoomEnabled
        self.onRecognized = onRecognized
    }

    public func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.text(languages: languages)],
            qualityLevel: qualityLevel,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: isPinchToZoomEnabled,
            isGuidanceEnabled: false,
            isHighlightingEnabled: isHighlightingEnabled
        )
        controller.delegate = context.coordinator
        return controller
    }

    public func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onRecognized = onRecognized
        if !controller.isScanning {
            try? controller.startScanning()
        }
    }

    public static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onRecognized: onRecognized)
    }

    @MainActor
    public final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onRecognized: @MainActor ([String]) -> Void

        init(onRecognized: @escaping @MainActor ([String]) -> Void) {
            self.onRecognized = onRecognized
        }

        public func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }

        public func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }

        public func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }

        private func report(_ items: [RecognizedItem]) {
            onRecognized(items.compactMap { item in
                if case .text(let text) = item { return text.transcript }
                return nil
            })
        }
    }
}
#endif
