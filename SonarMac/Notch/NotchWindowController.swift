import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class NotchWindowController {
    private(set) var expanded = false
    private(set) var pinned = false
    private(set) var geometry = NotchGeometry(screen: .zero, safeTop: 0, hardwareWidth: 0)
    @ObservationIgnored private weak var model: MacAppModel?
    @ObservationIgnored private var panel: NotchPanel?
    @ObservationIgnored private var closeTask: Task<Void, Never>?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var localClickMonitor: Any?
    @ObservationIgnored private var globalClickMonitor: Any?
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var interacting = false
    @ObservationIgnored private var pointerInside = false
    @ObservationIgnored private var keyboardOpen = false

    init(model: MacAppModel) {
        self.model = model
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated {
                if let self, self.expanded { self.collapse() }
            }
        }
    }

    deinit {
        closeTask?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        guard enabled else {
            closeTask?.cancel()
            stopOutsideClickMonitoring()
            expanded = false
            pinned = false
            interacting = false
            pointerInside = false
            keyboardOpen = false
            panel?.orderOut(nil)
            return
        }
        if panel == nil, let model {
            let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Sonar 刘海播放器"
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.isReleasedWhenClosed = false
            panel.closePlayer = { [weak self] in self?.collapse() }
            panel.focusLost = { [weak self] in
                if let self, self.expanded { self.collapse() }
            }
            panel.contentView = NotchHostingView(rootView: NotchPlayerView(model: model, controller: self))
            self.panel = panel
        }
        reposition()
        panel?.orderFrontRegardless()
    }

    func expand(keyboard: Bool = false) {
        guard enabled else { return }
        closeTask?.cancel()
        keyboardOpen = keyboard
        expanded = true
        reposition()
        panel?.orderFrontRegardless()
        if keyboard { panel?.makeKey() }
        startOutsideClickMonitoring()
    }

    func toggleExpanded() {
        if expanded { collapse() } else { expand(keyboard: true) }
    }

    func collapse() {
        closeTask?.cancel()
        stopOutsideClickMonitoring()
        pinned = false
        expanded = false
        interacting = false
        keyboardOpen = false
        panel?.resignKey()
        reposition()
    }

    func togglePinned() { pinned.toggle() }

    func hover(_ inside: Bool) {
        guard enabled else { return }
        pointerInside = inside
        closeTask?.cancel()
        if inside {
            keyboardOpen = false
            guard !expanded else { return }
            closeTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(170))
                guard !Task.isCancelled else { return }
                self?.expand()
            }
        } else if expanded && !pinned && !interacting && !keyboardOpen {
            closeTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                self?.collapse()
            }
        }
    }

    func interactionChanged(_ active: Bool) {
        interacting = active
        closeTask?.cancel()
        if !active && !pointerInside { hover(false) }
    }

    // Hover opens a nonactivating panel, so it can lose focus without ever being key.
    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            MainActor.assumeIsolated { self?.dismissIfOutside(event) }
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self, self.expanded { self.collapse() }
            }
        }
    }

    private func stopOutsideClickMonitoring() {
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        localClickMonitor = nil
        globalClickMonitor = nil
    }

    private func dismissIfOutside(_ event: NSEvent) {
        guard expanded, let panel, event.window !== panel,
              !panel.frame.contains(NSEvent.mouseLocation) else { return }
        collapse()
    }

    private func reposition() {
        guard enabled, let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first,
              screen.frame.width > 100, screen.frame.height > 100 else { return }
        let hardwareWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            hardwareWidth = max(0, right.minX - left.maxX)
        } else { hardwareWidth = 0 }
        geometry = NotchGeometry(screen: screen.frame, safeTop: screen.safeAreaInsets.top, hardwareWidth: hardwareWidth)
        panel?.setFrame(geometry.frame(expanded: expanded), display: true)
    }
}

private final class NotchPanel: NSPanel {
    var closePlayer: (() -> Void)?
    var focusLost: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func resignKey() {
        super.resignKey()
        focusLost?()
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { closePlayer?() }
        else { super.keyDown(with: event) }
    }
}

private final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }
}
