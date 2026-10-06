import SwiftUI
import AppKit
import Carbon
import UniformTypeIdentifiers

extension Notification.Name {
    static let launcherFloatingVisibilityChanged = Notification.Name("launcherFloatingVisibilityChanged")
    static let launcherOpenSettings = Notification.Name("launcherOpenSettings")
}

struct SettingsView: View {
    @ObservedObject private var language = LanguageManager.shared
    @EnvironmentObject private var store: LaunchStore
    @StateObject private var loginItem = LoginItemManager()
    @AppStorage("floatingLauncherVisible") private var floatingVisible = true
    @AppStorage("categorySwipeEnabled") private var categorySwipeEnabled = true
    @State private var shortcut = LauncherShortcut.saved
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var message = ""
    @State private var restoreSource: URL?
    @State private var confirmingRestore = false
    @State private var isExporting = false
    var body: some View {
        Form {
            Section(L10n.tr("语言")) {
                Picker(L10n.tr("界面语言"), selection: $language.selection) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Text(L10n.tr("切换后立即生效，不修改分类名称、应用名称或备注。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.tr("启动设置")) {
                Toggle(L10n.tr("登录时启动 Nest Launcher"), isOn: Binding(
                    get: { loginItem.isRequested },
                    set: { loginItem.setEnabled($0) }
                ))
                Text(loginItem.statusMessage)
                    .font(.caption).foregroundStyle(.secondary)
                if let error = loginItem.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                Button(L10n.tr("打开系统登录项设置…")) { loginItem.openSystemSettings() }
                    .controlSize(.small)
            }
            Section(L10n.tr("桌面入口")) {
                Toggle(L10n.tr("显示桌面悬浮球"), isOn: $floatingVisible)
                    .onChange(of: floatingVisible) { _, _ in
                        NotificationCenter.default.post(name: .launcherFloatingVisibilityChanged, object: nil)
                    }
            }
            Section(L10n.tr("全局快捷键")) {
                HStack {
                    Text(L10n.tr("显示／隐藏主界面"))
                    Spacer()
                    Text(shortcut.display).font(.body.monospaced())
                }
                HStack {
                    Button(isRecording ? L10n.tr("取消录制") : L10n.tr("录制快捷键")) {
                        if isRecording { stopRecording() } else { startRecording() }
                    }
                    Button(L10n.tr("恢复默认")) { apply(.defaultShortcut) }.disabled(isRecording)
                }
                Text(isRecording ? L10n.tr("请按快捷键，需包含 ⌘、⌥ 或 ⌃；Esc 取消。") : (message.isEmpty ? L10n.tr("快捷键在其他应用中也可使用，更改后立即生效。") : message))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.tr("触控板手势")) {
                Toggle(L10n.tr("双指左右滑动切换分类"), isOn: $categorySwipeEnabled)
                Text(L10n.tr("左滑下一个，右滑上一个；按分类栏顺序切换，上下滚动不受影响。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.tr("数据备份与恢复")) {
                VStack(alignment: .leading, spacing: 8) {
                    Button(L10n.tr("导出数据…")) { exportData() }.disabled(isExporting)
                    Button(L10n.tr("恢复上次备份")) {
                        restoreSource = nil
                        confirmingRestore = true
                    }
                    Button(L10n.tr("从文件恢复…")) { chooseRestoreFile() }
                }
                .disabled(store.isRestoringData)
                Text(L10n.tr("自动保留上一份有效数据。恢复前也会保留当前文件，不修改应用图标、主题或快捷键设置。"))
                    .font(.caption).foregroundStyle(.secondary)
                if let message = store.dataOperationMessage {
                    Text(message).font(.caption).textSelection(.enabled)
                }
                if store.isRestoringData { ProgressView(L10n.tr("正在恢复…")).controlSize(.small) }
            }
            Section {
                Text("Nest Launcher \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L10n.tr("开发版"))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .environment(\.locale, language.locale)
        .frame(width: 440, height: 640)
        .alert(L10n.tr("恢复应用数据？"), isPresented: $confirmingRestore) {
            Button(L10n.tr("取消"), role: .cancel) { }
            Button(L10n.tr("恢复"), role: .destructive) {
                Task { await store.restoreData(from: restoreSource) }
            }
        } message: {
            Text(L10n.tr("当前分类和启动项将被替换。恢复前的文件会另外保留，以便撤回。"))
        }
        .onAppear { loginItem.refresh() }
        .onDisappear { stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            stopRecording()
        }
    }

    private func exportData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Nest-Launcher-Backup.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isExporting = true
        Task {
            await store.exportData(to: url)
            isExporting = false
        }
    }

    private func chooseRestoreFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        restoreSource = url
        confirmingRestore = true
    }

    private func apply(_ candidate: LauncherShortcut) {
        if HotKeyManager.shared.register(candidate) {
            candidate.save()
            shortcut = candidate
            message = L10n.tr("快捷键已更新。")
        } else {
            let restored = HotKeyManager.shared.register(shortcut)
            message = restored ? L10n.tr("该快捷键无法注册，可能已被占用，请换一个组合。") : L10n.tr("新旧快捷键均无法注册，请换一个组合。仍可通过菜单栏或悬浮球打开主界面。")
        }
    }
    private func startRecording() {
        isRecording = true
        message = ""
        HotKeyManager.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) { stopRecording(); return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
            var modifiers: UInt32 = 0
            if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
            if flags.contains(.option) { modifiers |= UInt32(optionKey) }
            if flags.contains(.control) { modifiers |= UInt32(controlKey) }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            let labels: [UInt16: String] = [49: "Space", 36: "↩", 48: "Tab", 51: "⌫", 123: "←", 124: "→", 125: "↓", 126: "↑"]
            let label = labels[event.keyCode] ?? event.characters(byApplyingModifiers: [])?.uppercased() ?? "Key \(event.keyCode)"
            stopRecording()
            apply(LauncherShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: label))
            return nil
        }
    }
    private func stopRecording() {
        guard isRecording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        if !HotKeyManager.shared.register(shortcut) {
            message = L10n.tr("原快捷键无法重新注册，请换一个组合。仍可通过菜单栏或悬浮球打开主界面。")
        }
    }
}
