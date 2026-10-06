import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var launchStore: LaunchStore?
    private var hotKeyManager: HotKeyManager?
    private weak var backgroundEffectView: NSVisualEffectView?
    private var mainWindow: NSWindow?
    private var floatingLauncher: FloatingLauncherController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var floatingVisible: Bool { UserDefaults.standard.bool(forKey: "floatingLauncherVisible") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        UserDefaults.standard.register(defaults: ["floatingLauncherVisible": true])
        hotKeyManager = HotKeyManager.shared
        hotKeyManager?.onTrigger = { [weak self] in
            self?.toggleMainWindow()
        }
        let shortcutRegistered = hotKeyManager?.register() == true
        configureStatusItem()
        NotificationCenter.default.addObserver(self, selector: #selector(updateFloatingVisibility), name: .launcherFloatingVisibilityChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings), name: .launcherOpenSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateLanguage), name: .launcherLanguageChanged, object: nil)

        DispatchQueue.main.async { [weak self] in
            self?.configureMainWindowForTransparency()
            self?.floatingLauncher = FloatingLauncherController(
                onToggle: { [weak self] in self?.toggleMainWindow() },
                onShow: { [weak self] in self?.showMainWindow() },
                onHide: { [weak self] in self?.toggleFloatingVisibility() },
                onSettings: { [weak self] in self?.openSettings() }
            )
            self?.updateFloatingVisibility()
            if !shortcutRegistered { self?.reportShortcutFailure() }
        }
    }

    private func reportShortcutFailure() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("全局快捷键无法启用")
        alert.informativeText = L10n.tr("%@ 注册失败，可能已被系统或其他应用占用。你仍可通过菜单栏图标和悬浮球打开主界面，请在设置中更换快捷键。", LauncherShortcut.saved.display)
        alert.addButton(withTitle: L10n.tr("打开设置"))
        alert.addButton(withTitle: L10n.tr("稍后"))
        if let window = resolveMainWindow() {
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn { self?.openSettings() }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            openSettings()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let launchStore else { return .terminateNow }
        Task {
            await launchStore.flushSaves()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "Nest Launcher")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = L10n.tr("Nest Launcher · 点击显示/隐藏 · 右键菜单")
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp, let item = statusItem {
            let menu = NSMenu()
            let show = NSMenuItem(title: L10n.tr("打开 Nest Launcher"), action: #selector(statusShowMainWindow), keyEquivalent: "")
            show.target = self
            menu.addItem(show)
            let floating = NSMenuItem(title: floatingVisible ? L10n.tr("隐藏桌面悬浮球") : L10n.tr("显示桌面悬浮球"), action: #selector(toggleFloatingVisibility), keyEquivalent: "")
            floating.target = self
            menu.addItem(floating)
            let settings = NSMenuItem(title: L10n.tr("设置…"), action: #selector(openSettings), keyEquivalent: ",")
            settings.target = self
            menu.addItem(settings)
            menu.addItem(.separator())
            let quit = NSMenuItem(title: L10n.tr("退出 Nest Launcher"), action: #selector(statusQuit), keyEquivalent: "")
            quit.target = self
            menu.addItem(quit)
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            toggleMainWindow()
        }
    }

    @objc private func statusShowMainWindow() { showMainWindow() }
    @objc private func updateLanguage() {
        statusItem?.button?.toolTip = L10n.tr("Nest Launcher · 点击显示/隐藏 · 右键菜单")
        settingsWindow?.title = L10n.tr("Nest Launcher 设置")
        floatingLauncher?.updateLocalizedText()
    }
    @objc private func statusQuit() { NSApp.terminate(nil) }

    @objc private func toggleFloatingVisibility() {
        UserDefaults.standard.set(!floatingVisible, forKey: "floatingLauncherVisible")
        NotificationCenter.default.post(name: .launcherFloatingVisibilityChanged, object: nil)
    }
    @objc private func updateFloatingVisibility() {
        if floatingVisible { floatingLauncher?.show() } else { floatingLauncher?.hide() }
    }
    @objc private func openSettings() {
        guard let launchStore else { return }
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 640),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = L10n.tr("Nest Launcher 设置")
            window.contentView = NSHostingView(rootView: SettingsView().environmentObject(launchStore))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.unhide(nil)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        configureMainWindowForTransparency()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === mainWindow else { return true }
        sender.orderOut(nil)
        return false
    }

    private func resolveMainWindow() -> NSWindow? {
        if let mainWindow { return mainWindow }
        guard let window = NSApp.windows.first(where: {
            !($0 is NSPanel) && ($0.identifier?.rawValue == "main" || $0.title == "Nest Launcher")
        }) else { return nil }
        mainWindow = window
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    private func showMainWindow() {
        guard let window = resolveMainWindow() else { return }
        NSApp.unhide(nil)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func toggleMainWindow() {
        guard let window = resolveMainWindow() else { return }

        if window.isVisible && !window.isMiniaturized {
            window.orderOut(nil)
        } else {
            showMainWindow()
        }
    }

    private func configureMainWindowForTransparency() {
        guard let window = resolveMainWindow() else { return }

        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)

        for view in [window.contentView, window.contentView?.superview] {
            guard let view else { continue }
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.clear.cgColor
            view.layer?.isOpaque = false
        }

        guard let contentView = window.contentView,
              let backdropContainer = contentView.superview else { return }

        let visualEffectView: NSVisualEffectView
        if let existing = backgroundEffectView {
            visualEffectView = existing
        } else {
            visualEffectView = NSVisualEffectView(frame: contentView.bounds)
            visualEffectView.autoresizingMask = [.width, .height]
            // A sibling below the hosting view cannot wash out SwiftUI's
            // layer-rendered text and images, unlike a hosting-view subview.
            backdropContainer.addSubview(visualEffectView, positioned: .below, relativeTo: contentView)
            backgroundEffectView = visualEffectView
        }

        visualEffectView.frame = contentView.frame
        visualEffectView.material = .sidebar
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        // Transparency belongs to the backdrop, never to the foreground content.
        // Keep the glass backdrop light while foreground content stays opaque.
        visualEffectView.alphaValue = 0.55

        clearOpaqueBackgrounds(in: contentView)
    }

    private func clearOpaqueBackgrounds(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            scrollView.drawsBackground = false
            scrollView.backgroundColor = .clear
            scrollView.contentView.drawsBackground = false
            scrollView.contentView.backgroundColor = .clear
        }
        if let tableView = view as? NSTableView {
            tableView.backgroundColor = .clear
            tableView.enclosingScrollView?.drawsBackground = false
            tableView.enclosingScrollView?.backgroundColor = .clear
        }

        for subview in view.subviews {
            clearOpaqueBackgrounds(in: subview)
        }
    }
}
