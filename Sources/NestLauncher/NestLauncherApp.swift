import SwiftUI

@main
struct NestLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = LaunchStore()
    @StateObject private var language = LanguageManager.shared

    var body: some Scene {
        Window("Nest Launcher", id: "main") {
            ContentView()
                .environmentObject(store)
                .environment(\.locale, language.locale)
                .onAppear { appDelegate.launchStore = store }
                .frame(minWidth: 1080, minHeight: 540)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.tr("设置…")) {
                    NotificationCenter.default.post(name: .launcherOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            CommandGroup(replacing: .newItem) {
                Button(L10n.tr("新建启动项")) {
                    store.isPresentingAddItem = true
                }
                .disabled(store.isRestoringData)
                .keyboardShortcut("n", modifiers: [.command])

                Button(L10n.tr("新建分类")) {
                    store.isPresentingAddCategory = true
                }
                .disabled(store.isRestoringData)
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }

            CommandMenu(L10n.tr("启动器")) {
                Button(L10n.tr("启动选中项")) {
                    store.launchSelectedItems()
                }
                .disabled(store.isRestoringData)
                .keyboardShortcut(.return, modifiers: [.command])

                Button(L10n.tr("收藏选中项")) {
                    store.toggleFavoriteSelectedItems()
                }
                .disabled(store.isRestoringData)
                .keyboardShortcut("f", modifiers: [.command])
            }
        }

    }
}

extension LaunchStore {
    func launchSelectedItems() {
        withBatchUpdates {
            for item in selectedItems { launch(item) }
        }
    }

    func toggleFavoriteSelectedItems() {
        withBatchUpdates {
            for item in selectedItems { toggleFavorite(item) }
        }
    }

}
