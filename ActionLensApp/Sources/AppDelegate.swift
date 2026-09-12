import AppKit
import Carbon
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = AnalysisViewModel()

    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var hotKeyManager: HotKeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainWindow()
        configureStatusItem()
        configureHotKey()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    private func configureMainWindow() {
        let contentView = ContentView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "ActionLens"
        window.setContentSize(NSSize(width: 1080, height: 760))
        window.minSize = NSSize(width: 980, height: 700)
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ActionLens")
            button.imagePosition = .imageOnly
            button.toolTip = "ActionLens"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open ActionLens", action: #selector(openMainWindowFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Capture Screenshot", action: #selector(captureScreenshotFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Choose Image…", action: #selector(chooseImageFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Analyze Current Image", action: #selector(analyzeCurrentImageFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reset", action: #selector(resetFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let hotkeyItem = NSMenuItem(title: "Global Shortcut: Control + Option + A", action: nil, keyEquivalent: "")
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit ActionLens", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func configureHotKey() {
        hotKeyManager = HotKeyManager(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            Task { @MainActor in
                await self?.captureScreenshotAndAnalyze()
            }
        }
    }

    private func showMainWindow() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func captureScreenshotAndAnalyze() async {
        showMainWindow()
        await viewModel.captureScreenshot(autoAnalyze: true)
    }

    @objc private func openMainWindowFromMenu() {
        showMainWindow()
    }

    @objc private func captureScreenshotFromMenu() {
        Task { @MainActor in
            await captureScreenshotAndAnalyze()
        }
    }

    @objc private func chooseImageFromMenu() {
        showMainWindow()
        viewModel.chooseImage()
    }

    @objc private func analyzeCurrentImageFromMenu() {
        showMainWindow()
        Task { @MainActor in
            await viewModel.analyze()
        }
    }

    @objc private func resetFromMenu() {
        viewModel.reset()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
