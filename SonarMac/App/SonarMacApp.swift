import AppKit
import SwiftUI

extension Notification.Name {
    static let sonarOpenStatusPanel = Notification.Name("sonarOpenStatusPanel")
    static let sonarStatusPanelDidClose = Notification.Name("sonarStatusPanelDidClose")
}

/// An accessory app: the status item and notch are its only persistent surfaces.
@main
@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = MacAppModel()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var observer: NSObjectProtocol?
    private var popoverFocusObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var outsideClickMonitor: Any?

    static func main() {
        let app = NSApplication.shared
        let delegate = MacAppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installEditingMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Sonar")
        item.button?.toolTip = "Sonar · 音乐与灵动岛"
        item.button?.target = self
        item.button?.action = #selector(toggleStatusPanel)
        statusItem = item
        popover.behavior = .transient
        popover.delegate = self
        let panelController = NSHostingController(rootView: MacStatusPanel(model: model))
        panelController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = panelController
        observer = NotificationCenter.default.addObserver(forName: .sonarOpenStatusPanel, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.showStatusPanel() }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.closeStatusPanel() }
        }
        model.start()
    }

    private func installEditingMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Sonar")
        appMenu.addItem(withTitle: "退出 Sonar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        for (title, selector, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"),
                                       ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: NSSelectorFromString(selector), keyEquivalent: key)
        }
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    @objc private func toggleStatusPanel() {
        if popover.isShown { popover.performClose(nil) }
        else { showStatusPanel() }
    }

    func popoverDidClose(_ notification: Notification) {
        if let popoverFocusObserver {
            NotificationCenter.default.removeObserver(popoverFocusObserver)
            self.popoverFocusObserver = nil
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        NotificationCenter.default.post(name: .sonarStatusPanelDidClose, object: nil)
    }

    private func showStatusPanel() {
        guard !popover.isShown, let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let window = popover.contentViewController?.view.window {
            window.makeKey()
            popoverFocusObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.closeStatusPanel() }
            }
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] _ in
                // Global monitors only receive clicks delivered to other applications.
                MainActor.assumeIsolated { self?.closeStatusPanel() }
            }
        }
    }

    private func closeStatusPanel() {
        if popover.isShown { popover.performClose(nil) }
    }

    func applicationDidResignActive(_ notification: Notification) {
        closeStatusPanel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        closeStatusPanel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showStatusPanel()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
