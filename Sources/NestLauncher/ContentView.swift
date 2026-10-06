import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum AppLayoutMode: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { rawValue }
}

private enum LauncherAppearance: String {
    case light, system, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .system: return nil
        case .dark: return .dark
        }
    }

    func apply() {
        switch self {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .system: NSApp.appearance = nil
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

private let dockPersistentAppType = UTType("com.apple.dock.persistent-app") ?? .item

private let appDropTypes: [UTType] = [
    .fileURL,
    .applicationBundle,
    .application,
    dockPersistentAppType,
    .item
]

struct ContentView: View {
    @ObservedObject private var language = LanguageManager.shared
    @EnvironmentObject private var store: LaunchStore
    @AppStorage("appLibraryExpanded") private var isAppLibraryExpanded = true
    @AppStorage("launcherAppearance") private var appearance = LauncherAppearance.system.rawValue
    @AppStorage("categorySwipeEnabled") private var categorySwipeEnabled = true

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 220)

            DetailView()

            Divider()

            AppLibraryPanel(isExpanded: $isAppLibraryExpanded)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(store.isRestoringData)
        .foregroundStyle(Color(nsColor: .labelColor).opacity(1))
        .background(Color.clear)
        .background(CategorySwipeGesture(enabled: categorySwipeEnabled) { direction in
            withAnimation(.easeInOut(duration: 0.18)) {
                store.switchCategory(direction: direction)
            }
        })
        .onDrop(of: appDropTypes, isTargeted: nil) { providers in
            importProviders(
                providers,
                into: store.selectedCategoryIDForImport,
                store: store
            )
            return true
        }
        .toolbar(.hidden, for: .windowToolbar)
        .sheet(isPresented: $store.isPresentingAddItem) {
            EditItemView(
                mode: .new,
                initialCategoryID: store.selectedCategoryIDForImport
            )
                .environmentObject(store)
        }
        .sheet(item: $store.editingItem) { item in
            EditItemView(mode: .edit(item))
                .environmentObject(store)
        }
        .sheet(isPresented: $store.isPresentingAddCategory) {
            EditCategoryView(parentID: store.preselectedParentCategoryID)
                .environmentObject(store)
        }
        .sheet(item: $store.editingCategory) { category in
            EditCategoryView(category: category)
                .environmentObject(store)
        }
        .preferredColorScheme((LauncherAppearance(rawValue: appearance) ?? .system).colorScheme)
        .alert(L10n.tr("操作未完成"), isPresented: Binding(
            get: { store.persistenceError != nil || store.launchError != nil },
            set: { if !$0 { store.persistenceError = nil; store.launchError = nil } }
        )) {
            Button(L10n.tr("知道了"), role: .cancel) { store.persistenceError = nil; store.launchError = nil }
        } message: {
            Text(store.persistenceError ?? store.launchError ?? "")
        }
        .onAppear { (LauncherAppearance(rawValue: appearance) ?? .system).apply() }
        .onChange(of: appearance) { _, value in
            (LauncherAppearance(rawValue: value) ?? .system).apply()
        }
    }
}

struct SidebarView: View {
    @ObservedObject private var language = LanguageManager.shared
    @EnvironmentObject private var store: LaunchStore

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.tr("分类"))
                        .font(.headline)
                        .opaqueForeground()
                        .padding(.horizontal, 10)
                        .padding(.top, 4)

                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(store.rootCategories) { category in
                                CategorySidebarRow(category: category)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .scrollIndicators(.hidden)
                    .frame(height: min(
                        CGFloat(store.categoriesInDisplayOrder.count) * 44,
                        max(0, geometry.size.height - 206)
                    ))

                    Divider().padding(.horizontal, 8)

                    Button {
                        store.isPresentingAddCategory = true
                    } label: {
                        Label(L10n.tr("新建分类"), systemImage: "folder.badge.plus")
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.tr("新建分类"))
                }
                .padding(10)
                .macPanel(cornerRadius: 22)
                .padding(12)
                Spacer()
                AppearanceModeToggle()
                    .frame(width: 126)
                    .padding(6)
                    .macPanel(cornerRadius: 14)
                    .padding(12)
            }
        }
    }
}

private struct CategorySidebarRow: View {
    @ObservedObject private var language = LanguageManager.shared
    @EnvironmentObject private var store: LaunchStore
    @State private var isDropTargeted = false
    @State private var isHovered = false
    let category: Category
    var depth: Int = 0

    private var isSelected: Bool {
        store.selectedFilterID == category.id.uuidString
    }

    var body: some View {
        Button {
            store.selectedFilterID = category.id.uuidString
        } label: {
            Label(category.name, systemImage: category.symbol)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, CGFloat(depth) * 12)
                .padding(.horizontal, 10)
                .frame(height: 40)
        }
            .buttonStyle(.plain)
            .opaqueForeground()
            .background(
                isDropTargeted || isSelected
                    ? Color.accentColor.opacity(0.20)
                    : Color.white.opacity(isHovered ? 0.16 : 0),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.16), value: isHovered)
            .onDrop(of: appDropTypes, isTargeted: $isDropTargeted) { providers in
                importProviders(providers, into: category.id, store: store)
                return true
            }
            .help(L10n.tr("拖入 App 加入此分类"))
            .tag(category.id.uuidString)
            .contextMenu {
                Button(L10n.tr("新建子分类")) {
                    store.preselectedParentCategoryID = category.id
                    store.isPresentingAddCategory = true
                }
                Button(L10n.tr("重命名")) {
                    store.editingCategory = category
                }
                Button(L10n.tr("删除"), role: .destructive) {
                    store.deleteCategory(category)
                }
            }

        let children = store.subcategories(of: category)
        if !children.isEmpty {
            ForEach(children) { child in
                CategorySidebarRow(category: child, depth: depth + 1)
            }
        }
    }
}

struct DetailView: View {
    @ObservedObject private var language = LanguageManager.shared
    @EnvironmentObject private var store: LaunchStore
    @State private var layoutMode: AppLayoutMode = .list

    private var itemGridItem: GridItem {
        let minimum = max(CGFloat(store.appIconSize) + 78, 104)
        let maximum = max(CGFloat(store.appIconSize) + 88, 136)
        return GridItem(
            .adaptive(minimum: minimum, maximum: maximum),
            spacing: CGFloat(store.appGridSpacing)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                SearchField(text: $store.searchText)

                Picker(L10n.tr("排序"), selection: $store.sortOrder) {
                    ForEach(ItemSortOrder.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }
                .labelsHidden()
                .frame(width: 120)

                LayoutModeToggle(mode: $layoutMode)
                AppearanceControlsButton()

                Button {
                    store.isPresentingAddItem = true
                } label: {
                    Image(systemName: "plus")
                }
                .help(L10n.tr("新建启动项"))

                Menu {
                    Button(L10n.tr("扫描应用程序")) {
                        store.scanApplications()
                    }
                    .disabled(store.isRefreshingApps)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L10n.tr("更多操作"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .macPanel(cornerRadius: 20)
            .padding(12)

            itemList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
                .macPanel(cornerRadius: 24)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
    }

    private var itemList: some View {
        Group {
            if store.visibleItems.isEmpty {
                ContentUnavailableView(
                    L10n.tr("没有启动项"),
                    systemImage: "tray",
                    description: Text(L10n.tr("拖入 App，也可以点击右上角加号新建。"))
                )
            } else {
                switch layoutMode {
                case .list:
                    List(selection: $store.selectedItemIDs) {
                        ForEach(store.visibleItems) { item in
                            ItemRow(item: item)
                                .tag(item.id)
                        }
                    }
                    .listStyle(.plain)
                    .listRowBackground(Color.clear)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .contextMenu(forSelectionType: UUID.self) { ids in
                        itemSelectionMenu(for: ids)
                    }
                case .grid:
                    ScrollView {
                        LazyVGrid(
                            columns: [itemGridItem],
                            alignment: .leading,
                            spacing: CGFloat(store.appGridSpacing)
                        ) {
                            ForEach(store.visibleItems) { item in
                                ItemTile(item: item)
                            }
                        }
                        .padding(12)
                    }
                    .background(Color.clear)
                }
            }
        }
        .onDrop(of: appDropTypes, isTargeted: nil) { providers in
            importProviders(
                providers,
                into: store.selectedCategoryIDForImport,
                store: store
            )
            return true
        }
    }

    @ViewBuilder
    private func itemSelectionMenu(for ids: Set<UUID>) -> some View {
        if !ids.isEmpty {
            Button(L10n.tr("启动")) {
                store.withBatchUpdates {
                    store.visibleItems.filter { ids.contains($0.id) }.forEach { store.launch($0) }
                }
            }
            Button(L10n.tr("收藏")) {
                store.withBatchUpdates {
                    store.visibleItems.filter { ids.contains($0.id) }.forEach { store.toggleFavorite($0) }
                }
            }
            Divider()
            Menu(L10n.tr("移动到")) {
                Button(L10n.tr("未分类")) {
                    store.moveItems(ids, to: nil)
                }
                ForEach(store.categoriesInDisplayOrder) { category in
                    Button(store.indentedName(for: category)) {
                        store.moveItems(ids, to: category.id)
                    }
                }
            }
            Divider()
            Button(L10n.tr("删除"), role: .destructive) {
                store.deleteItems(ids)
            }
        }
    }
}

struct SearchField: View {
    @ObservedObject private var language = LanguageManager.shared
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L10n.tr("搜索应用名称或路径"), text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(
            Color(nsColor: .textBackgroundColor),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}

struct ItemRow: View {
    @ObservedObject private var language = LanguageManager.shared
    @EnvironmentObject private var store: LaunchStore
    let item: LaunchItem

    private var iconSize: CGFloat {
        max(20, min(CGFloat(store.appIconSize) * 0.58, 44))
    }

    var body: some View {
        HStack(spacing: 10) {
            AppIconBadge(item: item, size: iconSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                    .opaqueForeground()
                    .opacity(1.0)
            }

            Spacer(minLength: 12)

            if item.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }
            if item.hotkey?.isEmpty == false {
                Text(item.hotkey ?? "")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .help(L10n.tr("快捷键备注，仅记录，不触发启动"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .listRowSeparator(.hidden)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                store.launch(item)
            }
        )
        .contextMenu {
            Button(L10n.tr("启动")) {
                store.launch(item)
            }
            Button(L10n.tr("编辑")) {
                store.editingItem = item
            }
            Divider()
            Button(item.isFavorite ? L10n.tr("取消收藏") : L10n.tr("收藏")) {
                store.toggleFavorite(item)
            }
            Divider()
            Button(L10n.tr("删除"), role: .destructive) {
                store.deleteItems([item.id])
            }
        }
    }
}

private struct ItemTile: View {
    @ObservedObject private var language = LanguageManager.shared
    @EnvironmentObject private var store: LaunchStore
    let item: LaunchItem

    private var iconSize: CGFloat {
        CGFloat(store.appIconSize)
    }

    private var tileWidth: CGFloat {
        max(iconSize + 78, 112)
    }

    private var tileHeight: CGFloat {
        max(iconSize + 82, 128)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                AppIconBadge(item: item, size: iconSize)

                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .offset(x: 8, y: -5)
                }
            }

            Text(item.name)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .opaqueForeground()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: tileWidth, height: tileHeight)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .help(item.target)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                store.launch(item)
            }
        )
        .contextMenu {
            Button(L10n.tr("启动")) {
                store.launch(item)
            }
            Button(L10n.tr("编辑")) {
                store.editingItem = item
            }
            Divider()
            Button(item.isFavorite ? L10n.tr("取消收藏") : L10n.tr("收藏")) {
                store.toggleFavorite(item)
            }
            Divider()
            Button(L10n.tr("删除"), role: .destructive) {
                store.deleteItems([item.id])
            }
        }
    }
}

private struct AppLibraryPanel: View {
    @ObservedObject private var language = LanguageManager.shared
    @EnvironmentObject private var store: LaunchStore
    @Binding var isExpanded: Bool
    @State private var layoutMode: AppLayoutMode = .list

    private var appGridItem: GridItem {
        let minimum = max(CGFloat(store.appIconSize) + 62, 92)
        let maximum = max(CGFloat(store.appIconSize) + 72, 112)
        return GridItem(
            .adaptive(minimum: minimum, maximum: maximum),
            spacing: CGFloat(store.appGridSpacing)
        )
    }

    var body: some View {
        Group {
            if isExpanded {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text(L10n.tr("全部应用"))
                            .font(.headline)
                        Text("\(store.installedApps.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            store.refreshInstalledApps()
                        } label: {
                            if store.isRefreshingApps {
                                ProgressView().controlSize(.small).frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(store.isRefreshingApps)
                        .help(L10n.tr("刷新应用列表，不导入分类"))
                        LayoutModeToggle(mode: $layoutMode)
                        AppearanceControlsButton()
                        Button {
                            isExpanded = false
                        } label: {
                            Image(systemName: "sidebar.right")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.tr("折叠全部应用栏"))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .macPanel(cornerRadius: 20)
                    .padding(12)

                    Group {
                    switch layoutMode {
                    case .list:
                        List(store.installedApps) { app in
                            AppLibraryRow(item: app)
                        }
                        .listStyle(.plain)
                        .listRowBackground(Color.clear)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                    case .grid:
                        ScrollView {
                            LazyVGrid(
                                columns: [appGridItem],
                                alignment: .leading,
                                spacing: CGFloat(store.appGridSpacing)
                            ) {
                                ForEach(store.installedApps) { app in
                                    AppLibraryTile(item: app)
                                }
                            }
                            .padding(10)
                        }
                        .background(Color.clear)
                    }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)
                    .macPanel(cornerRadius: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .background(Color.clear)
                .frame(width: 300)
            } else {
                VStack {
                    Button {
                        isExpanded = true
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 10)
                    .help(L10n.tr("展开全部应用栏"))

                    Spacer()
                }
                .frame(width: 32)
            }
        }
    }
}

private struct AppLibraryRow: View {
    @ObservedObject private var language = LanguageManager.shared
    @EnvironmentObject private var store: LaunchStore
    let item: LaunchItem

    private var iconSize: CGFloat {
        max(18, min(CGFloat(store.appIconSize) * 0.52, 40))
    }

    var body: some View {
        HStack(spacing: 8) {
            AppIconBadge(item: item, size: iconSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                    .opaqueForeground()
                    .opacity(1.0)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
        .contentShape(Rectangle())
        .onDrag {
            guard let url = item.launchURL else { return NSItemProvider() }
            return NSItemProvider(object: url as NSURL)
        }
        .help(L10n.tr("拖到左侧分类"))
        .contextMenu {
            Button(L10n.tr("添加到当前分类")) {
                guard let url = item.launchURL else { return }
                store.importURLs([url], into: store.selectedCategoryIDForImport)
            }

            Menu(L10n.tr("添加到分类")) {
                ForEach(store.categoriesInDisplayOrder) { category in
                    Button(store.indentedName(for: category)) {
                        guard let url = item.launchURL else { return }
                        store.importURLs([url], into: category.id)
                    }
                }
            }
        }
    }
}

private struct AppLibraryTile: View {
    @ObservedObject private var language = LanguageManager.shared
    @EnvironmentObject private var store: LaunchStore
    let item: LaunchItem

    private var iconSize: CGFloat {
        CGFloat(store.appIconSize)
    }

    private var tileWidth: CGFloat {
        max(iconSize + 62, 108)
    }

    private var tileHeight: CGFloat {
        max(iconSize + 66, 112)
    }

    var body: some View {
        VStack(spacing: 5) {
            AppIconBadge(item: item, size: iconSize)

            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .opaqueForeground()
                .padding(.horizontal, 6)
                .padding(.vertical, 4)

            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(width: tileWidth, height: tileHeight)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onDrag {
            guard let url = item.launchURL else { return NSItemProvider() }
            return NSItemProvider(object: url as NSURL)
        }
        .help(L10n.tr("拖到左侧分类"))
        .contextMenu {
            Button(L10n.tr("添加到当前分类")) {
                guard let url = item.launchURL else { return }
                store.importURLs([url], into: store.selectedCategoryIDForImport)
            }

            Menu(L10n.tr("添加到分类")) {
                ForEach(store.categoriesInDisplayOrder) { category in
                    Button(store.indentedName(for: category)) {
                        guard let url = item.launchURL else { return }
                        store.importURLs([url], into: category.id)
                    }
                }
            }
        }
    }
}

private struct LayoutModeToggle: View {
    @ObservedObject private var language = LanguageManager.shared
    @Binding var mode: AppLayoutMode

    var body: some View {
        Picker(L10n.tr("显示方式"), selection: $mode) {
            Image(systemName: "list.bullet")
                .tag(AppLayoutMode.list)
            Image(systemName: "square.grid.2x2")
                .tag(AppLayoutMode.grid)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 74)
        .help(L10n.tr("切换列表或图标显示"))
    }
}

private struct MacPanelBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(in: .rect(cornerRadius: cornerRadius))
        } else {
            content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.13) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.05), radius: 8, y: 3)
        }
    }
}

private struct AppIconBadge: View {
    @ObservedObject private var language = LanguageManager.shared
    let item: LaunchItem
    let size: CGFloat

    var body: some View {
        Image(nsImage: IconProvider.shared.icon(for: item))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

private struct AppearanceModeToggle: View {
    @ObservedObject private var language = LanguageManager.shared
    @AppStorage("launcherAppearance") private var appearance = LauncherAppearance.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 3) {
            segment(.light, label: L10n.tr("浅色")) {
                Image(systemName: "sun.max.fill").resizable().scaledToFit()
            }
            segment(.system, label: L10n.tr("跟随系统")) {
                Image(systemName: "circle.lefthalf.filled").resizable().scaledToFit()
            }
            segment(.dark, label: L10n.tr("深色")) {
                Image(systemName: "moon.fill").resizable().scaledToFit()
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
        .help(L10n.tr("外观：左侧浅色，中间跟随系统，右侧深色"))
    }

    private func segment<Symbol: View>(_ mode: LauncherAppearance, label: String, @ViewBuilder symbol: () -> Symbol) -> some View {
        Button {
            appearance = mode.rawValue
        } label: {
            symbol()
                .frame(width: 12, height: 12)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(
                    appearance == mode.rawValue
                        ? (colorScheme == .dark ? Color.white.opacity(0.16) : Color.white)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(appearance == mode.rawValue ? .isSelected : [])
        .help(label)
    }
}

private struct OpaqueForeground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
    }
}

private extension View {
    func opaqueForeground() -> some View {
        modifier(OpaqueForeground())
    }
    func macPanel(cornerRadius: CGFloat = 10) -> some View {
        modifier(MacPanelBackground(cornerRadius: cornerRadius))
    }
}

private struct AppearanceControlsButton: View {
    @ObservedObject private var language = LanguageManager.shared
    @EnvironmentObject private var store: LaunchStore
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .buttonStyle(.borderless)
        .help(L10n.tr("调整图标大小和间距"))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(L10n.tr("图标大小"))
                    Spacer()
                    Text("\(Int(store.appIconSize))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $store.appIconSize, in: 28...88, step: 2)

                HStack {
                    Text(L10n.tr("网格间距"))
                    Spacer()
                    Text("\(Int(store.appGridSpacing))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $store.appGridSpacing, in: 4...40, step: 2)
            }
            .padding(16)
            .frame(width: 250)
        }
    }
}

@MainActor private func importProviders(
    _ providers: [NSItemProvider],
    into categoryID: UUID?,
    store: LaunchStore
) {
    let candidates = providers.compactMap { provider -> (NSItemProvider, UTType)? in
        guard let type = appDropTypes.first(where: {
            provider.hasItemConformingToTypeIdentifier($0.identifier)
        }) else { return nil }
        return (provider, type)
    }
    guard !candidates.isEmpty else { return }
    let batch = DropImportBatch(count: candidates.count) { urls in
        store.importURLs(urls, into: categoryID)
    }
    for (index, candidate) in candidates.enumerated() {
        let (provider, type) = candidate
        provider.loadItem(
            forTypeIdentifier: type.identifier,
            options: nil
        ) { item, _ in
            let url = droppedURL(from: item)
            DispatchQueue.main.async {
                batch.accept(url, at: index)
            }
        }
    }
}

private func droppedURL(from item: NSSecureCoding?) -> URL? {
    urlFromDroppedValue(item)
}

private func urlFromDroppedValue(_ value: Any?) -> URL? {
    guard let value else { return nil }

    if let url = value as? URL {
        return url
    }
    if let url = value as? NSURL {
        return url as URL
    }
    if let data = value as? Data {
        return URL(dataRepresentation: data, relativeTo: nil)
    }
    if let string = value as? String {
        return urlFromDroppedString(string)
    }
    if let string = value as? NSString {
        return urlFromDroppedString(string as String)
    }
    if let dictionary = value as? NSDictionary {
        return urlFromDroppedDictionary(dictionary)
    }
    if let array = value as? NSArray {
        return array.compactMap { urlFromDroppedValue($0) }.first
    }

    return nil
}

private func urlFromDroppedString(_ string: String) -> URL? {
    if let url = URL(string: string), url.isFileURL {
        return url
    }
    return URL(fileURLWithPath: string)
}

private func urlFromDroppedDictionary(_ dictionary: NSDictionary) -> URL? {
    for key in ["tile-data", "file-data", "_CFURLString"] {
        if let value = dictionary[key],
           let url = urlFromDroppedValue(value) {
            return url
        }
    }

    for value in dictionary.allValues where
        value is NSDictionary ||
        value is NSArray ||
        value is URL ||
        value is NSURL ||
        value is Data
    {
        if let url = urlFromDroppedValue(value) {
            return url
        }
    }

    return nil
}
