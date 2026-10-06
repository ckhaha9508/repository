import SwiftUI

struct EditCategoryView: View {
    @ObservedObject private var language = LanguageManager.shared
    @EnvironmentObject private var store: LaunchStore
    @Environment(\.dismiss) private var dismiss

    private let category: Category?

    @State private var name: String
    @State private var symbol: String
    @State private var parentID: UUID?

    init(category: Category? = nil, parentID: UUID? = nil) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _symbol = State(initialValue: category?.symbol ?? "folder")
        _parentID = State(initialValue: category?.parentID ?? parentID)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(category == nil ? L10n.tr("新建分类") : L10n.tr("编辑分类"))
                .font(.headline)
                .padding(.top, 18)

            Form {
                TextField(L10n.tr("名称"), text: $name)
                TextField("SF Symbol", text: $symbol)

                Picker(L10n.tr("上级分类"), selection: $parentID) {
                    Text(L10n.tr("无")).tag(UUID?.none)
                    ForEach(availableParentCategories) { parent in
                        Text(store.indentedName(for: parent)).tag(Optional(parent.id))
                    }
                }

            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button(L10n.tr("取消")) {
                    if category == nil {
                        store.preselectedParentCategoryID = nil
                    }
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(L10n.tr("保存")) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
        }
        .frame(width: 400, height: 235)
        .onDisappear {
            if category == nil {
                store.preselectedParentCategoryID = nil
            }
        }
    }

    private var availableParentCategories: [Category] {
        guard let category else { return store.categoriesInDisplayOrder }
        return store.categoriesInDisplayOrder.filter { store.canSetParent($0.id, for: category.id) }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let category {
            store.updateCategory(
                category,
                name: trimmed,
                symbol: symbol.isEmpty ? "folder" : symbol,
                parentID: parentID
            )
        } else {
            store.addCategory(
                name: trimmed,
                symbol: symbol.isEmpty ? "folder" : symbol,
                parentID: parentID
            )
            store.preselectedParentCategoryID = nil
        }
        dismiss()
    }
}
