import AppKit
import SwiftUI

/// The shared player owns position; AppKit supplies explicit numeric AX writes.
struct MacSeekSlider: View {
    let playback: PlaybackService
    var title = "播放进度"
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        MacSeekSliderControl(value: playback.elapsed, duration: playback.duration,
                             trackID: playback.queue.current?.musicID, title: title,
                             onEditingChanged: onEditingChanged) { value, trackID in
            Task { @MainActor in
                guard playback.queue.current?.musicID == trackID else { return }
                await playback.seek(to: value)
            }
        }.frame(maxWidth: .infinity).frame(height: 18)
    }
}

private struct MacSeekSliderControl: NSViewRepresentable {
    let value: Double
    let duration: Double
    let trackID: String?
    let title: String
    let onEditingChanged: (Bool) -> Void
    let onCommit: (Double, String) -> Void

    func makeNSView(context: Context) -> NativeSeekSlider {
        let slider = NativeSeekSlider()
        slider.controlSize = .small
        slider.isContinuous = false
        slider.target = slider
        slider.action = #selector(NativeSeekSlider.commitAction(_:))
        return slider
    }

    func updateNSView(_ slider: NativeSeekSlider, context: Context) {
        slider.onCommit = onCommit
        slider.onEditingChanged = onEditingChanged
        slider.setAccessibilityLabel(title)
        slider.configure(value: value, duration: duration, trackID: trackID)
    }
}

/// A single native control. No playback or persistent state lives here.
@MainActor
final class NativeSeekSlider: NSSlider {
    var onCommit: ((Double, String) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?
    private(set) var representedTrackID: String?
    private(set) var isTrackingSeek = false
    private var trackingTrackID: String?
    private var trackingCancelled = false

    func configure(value: Double, duration: Double, trackID: String?) {
        if isTrackingSeek, representedTrackID != trackID { trackingCancelled = true }
        representedTrackID = trackID
        minValue = 0
        maxValue = duration.isFinite ? max(1, duration) : 1
        isEnabled = trackID != nil && duration.isFinite && duration > 0
        if !isTrackingSeek || trackingCancelled {
            doubleValue = value.isFinite ? min(maxValue, max(minValue, value)) : minValue
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        beginSeekTracking()
        defer { endSeekTracking() }
        super.mouseDown(with: event)
    }

    func beginSeekTracking() {
        isTrackingSeek = true
        trackingTrackID = representedTrackID
        trackingCancelled = false
        onEditingChanged?(true)
    }

    func endSeekTracking() {
        isTrackingSeek = false
        trackingTrackID = nil
        trackingCancelled = false
        onEditingChanged?(false)
    }

    @objc func commitAction(_ sender: NSSlider) {
        let identity = isTrackingSeek ? trackingTrackID : representedTrackID
        guard isEnabled, !trackingCancelled, let identity, identity == representedTrackID else { return }
        onCommit?(doubleValue, identity)
    }

    override func setAccessibilityValue(_ value: Any?) {
        let number: Double?
        if let value = value as? NSNumber { number = value.doubleValue }
        else if let value = value as? String { number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        else { number = nil }
        guard isEnabled, !isTrackingSeek, let number, number.isFinite else { return }
        doubleValue = min(maxValue, max(minValue, number))
        commitAction(self)
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    override func accessibilityPerformIncrement() -> Bool { adjust(by: 5) }
    override func accessibilityPerformDecrement() -> Bool { adjust(by: -5) }

    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        if selector == NSSelectorFromString("setAccessibilityValue:") { return isEnabled }
        return super.isAccessibilitySelectorAllowed(selector)
    }

    private func adjust(by amount: Double) -> Bool {
        guard isEnabled, !isTrackingSeek else { return false }
        setAccessibilityValue(NSNumber(value: doubleValue + amount))
        return true
    }
}
