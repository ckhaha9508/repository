import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum EditItemMode {
    case new
    case edit(LaunchItem)
}

struct EditItemView: View {
    @ObservedObject private var language = LanguageManager.shared
    @EnvironmentObject private var store: LaunchStore
    @Environment(\.dismiss) private var dismiss

    let mode: EditItemMode

    @State private var name: String
    @State private var target: String
    @State private var categoryID: UUID?
    @State private var keywordsText: String
    @State private var notes: String
    @State private var hotkey: String
    @State private var isFavorite: Bool

    init(mode: EditItemMode, initialCategoryID: UUID? = nil) {
        self.mode = mode
        switch mode {
        case .new:
            _name = State(initialValue: "")
            _target = State(initialValue: "")
            _categoryID = State(initialValue: initialCategoryID)
            _keywordsText = State(initialValue: "")
            _notes = State(initialValue: "")
            _hotkey = State(initialValue: "")
            _isFavorite = State(initialValue: false)
        case .edit(let item):
            _name = State(initialValue: item.name)
            _target = State(initialValue: item.target)
            _categoryID = State(initialValue: item.categoryID)
            _keywordsText = State(initialValue: item.keywords.joined(separator: ", "))
            _notes = State(initialValue: item.notes)
            _hotkey = State(initialValue: item.hotkey ?? "")
            _isFavorite = State(initialValue: item.isFavorite)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(mode.isEditing ? L10n.tr("编辑启动项") : L10n.tr("新建启动项"))
                .font(.headline)
                .padding(.top, 18)

            Form {
                TextField(L10n.tr("名称"), text: $name)

                HStack {
                    TextField(L10n.tr("应用程序路径"), text: $target)
                    Button(L10n.tr("选择")) {
                        chooseTarget()
                    }
                }

                Picker(L10n.tr("分类"), selection: $categoryID) {
                    Text(L10n.tr("未分类")).tag(UUID?.none)
                    ForEach(store.categoriesInDisplayOrder) { category in
                        Text(store.indentedName(for: category)).tag(Optional(category.id))
                    }
                }

                TextField(L10n.tr("关键词（用逗号分隔）"), text: $keywordsText)
                TextField(L10n.tr("快捷键备注（仅记录，不触发启动）"), text: $hotkey)

                TextField(L10n.tr("备注"), text: $notes, axis: .vertical)
                    .lineLimit(3...6)

                Toggle(L10n.tr("收藏"), isOn: $isFavorite)
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button(L10n.tr("取消")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(L10n.tr("保存")) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty || trimmedTarget.isEmpty)
            }
            .padding(14)
        }
        .frame(width: 520, height: 430)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedTarget: String {
        target.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func chooseTarget() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "app") ?? .applicationBundle
        ]
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = L10n.tr("选择")

        if panel.runModal() == .OK, let url = panel.url {
            guard url.pathExtension == "app" else {
                NSSound.beep()
                return
            }
            target = url.path
            if name.isEmpty {
                name = url.deletingPathExtension().lastPathComponent
            }
        }
    }

    private func save() {
        let keywords = keywordsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        switch mode {
        case .new:
            store.addItem(
                name: trimmedName,
                target: trimmedTarget,
                kind: .application,
                categoryID: categoryID,
                keywords: keywords,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                hotkey: hotkey.isEmpty ? nil : hotkey,
                isFavorite: isFavorite
            )
        case .edit(let original):
            var updated = original
            updated.name = trimmedName
            updated.target = trimmedTarget
            updated.kind = .application
            updated.categoryID = categoryID
            updated.keywords = keywords
            updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.hotkey = hotkey.isEmpty ? nil : hotkey
            updated.isFavorite = isFavorite
            store.updateItem(updated)
        }

        dismiss()
    }
}

private extension EditItemMode {
    var isEditing: Bool {
        if case .edit = self { return true }
        return false
    }
}
