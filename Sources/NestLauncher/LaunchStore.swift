import AppKit
import Combine
import Foundation

@MainActor
final class LaunchStore: ObservableObject {
    static let allFilterID = "all"
    static let favoritesFilterID = "favorites"
    static let uncategorizedFilterID = "uncategorized"

    @Published var categories: [Category] = [] {
        didSet { cachedCategoryIndex = nil }
    }
    @Published var items: [LaunchItem] = []
    @Published private(set) var installedApps: [LaunchItem] = []
    @Published private(set) var isRefreshingApps = false
    @Published private(set) var isRestoringData = false
    @Published var dataOperationMessage: String?
    @Published var selectedFilterID = LaunchStore.allFilterID {
        didSet { if oldValue != selectedFilterID { selectedItemIDs.removeAll() } }
    }
    @Published var selectedItemIDs: Set<UUID> = []
    @Published var searchText = "" {
        didSet { if oldValue != searchText { selectedItemIDs.removeAll() } }
    }
    @Published var persistenceError: String?
    @Published var launchError: String?
    @Published var sortOrder: ItemSortOrder = .manual
    @Published var appIconSize: Double {
        didSet {
            UserDefaults.standard.set(appIconSize, forKey: Self.appIconSizeKey)
        }
    }
    @Published var appGridSpacing: Double {
        didSet {
            UserDefaults.standard.set(appGridSpacing, forKey: Self.appGridSpacingKey)
        }
    }
    @Published var isPresentingAddItem = false
    @Published var isPresentingAddCategory = false
    @Published var editingItem: LaunchItem?
    @Published var editingCategory: Category?
    @Published var preselectedParentCategoryID: UUID?

    private let fileURL: URL
    private let persistence: LauncherPersistence
    private let scanQueue = DispatchQueue(label: "com.nestlauncher.scan", qos: .utility)
    private var cachedCategoryIndex: CategoryIndex?
    private var categoryIndex: CategoryIndex {
        if let cachedCategoryIndex { return cachedCategoryIndex }
        let index = CategoryIndex(categories)
        cachedCategoryIndex = index
        return index
    }
    private let applicationOpener: (URL) -> Bool
    private var savingBlocked = false
    private var batchDepth = 0
    private var needsSave = false
    private static let appIconSizeKey = "appIconSize"
    private static let appGridSpacingKey = "appGridSpacing"

    init(fileURL: URL? = nil, scansOnInit: Bool = true, applicationOpener: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        let destination = fileURL ?? Self.defaultFileURL()
        self.fileURL = destination
        self.persistence = LauncherPersistence(fileURL: destination)
        self.applicationOpener = applicationOpener
        self.appIconSize = Self.loadAppIconSize()
        self.appGridSpacing = Self.loadAppGridSpacing()
        load()
        if scansOnInit { refreshInstalledApps() }
    }

    var visibleItems: [LaunchItem] {
        var result: [LaunchItem]

        switch selectedFilterID {
        case Self.favoritesFilterID:
            result = items.filter(\.isFavorite)
        case Self.uncategorizedFilterID:
            result = items.filter { $0.categoryID == nil }
        case Self.allFilterID:
            result = items
        default:
            result = items.filter { $0.categoryID?.uuidString == selectedFilterID }
        }

        if !searchText.isEmpty {
            result = result.filter { $0.matches(query: searchText) }
        }

        switch sortOrder {
        case .manual:
            result.sort {
                if $0.sortIndex == $1.sortIndex {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.sortIndex < $1.sortIndex
            }
        case .name:
            result.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .launchCount:
            result.sort {
                if $0.launchCount == $1.launchCount {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.launchCount > $1.launchCount
            }
        case .lastLaunched:
            result.sort {
                ($0.lastLaunchedAt ?? .distantPast) > ($1.lastLaunchedAt ?? .distantPast)
            }
        }

        return result
    }

    func category(for item: LaunchItem) -> Category? {
        guard let id = item.categoryID else { return nil }
        return categoryIndex.byID[id]
    }

    var rootCategories: [Category] {
        categoryIndex.roots
    }

    func switchCategory(direction: Int) {
        // Match the sidebar's depth-first order, including nested categories.
        let ordered = categoriesInDisplayOrder.map { $0.id.uuidString }
        guard !ordered.isEmpty else { return }
        let next: Int
        if let current = ordered.firstIndex(of: selectedFilterID) {
            next = min(max(current + (direction > 0 ? 1 : -1), 0), ordered.count - 1)
        } else {
            next = direction > 0 ? 0 : ordered.count - 1
        }
        guard selectedFilterID != ordered[next] else { return }
        selectedItemIDs.removeAll()
        selectedFilterID = ordered[next]
    }

    func subcategories(of category: Category) -> [Category] {
        categoryIndex.children[category.id] ?? []
    }

    func depth(of category: Category) -> Int {
        categoryIndex.depths[category.id] ?? 0
    }

    func indentedName(for category: Category) -> String {
        String(repeating: "    ", count: depth(of: category)) + category.name
    }

    func canSetParent(_ parentID: UUID?, for categoryID: UUID) -> Bool {
        let indexed = self.categoryIndex.byID
        var next = parentID
        var visited = Set<UUID>()
        while let id = next {
            guard id != categoryID, visited.insert(id).inserted,
                  let parent = indexed[id] else { return false }
            next = parent.parentID
        }
        return true
    }

    var selectedItems: [LaunchItem] {
        visibleItems.filter { selectedItemIDs.contains($0.id) }
    }

    func withBatchUpdates(_ changes: () -> Void) {
        batchDepth += 1
        changes()
        batchDepth -= 1
        if batchDepth == 0, needsSave { needsSave = false; save() }
    }

    var categoriesInDisplayOrder: [Category] {
        categoryIndex.displayOrder
    }

    @discardableResult
    func addItem(
        name: String,
        target: String,
        kind: LaunchTargetKind,
        categoryID: UUID?,
        keywords: [String],
        notes: String,
        hotkey: String?,
        isFavorite: Bool
    ) -> LaunchItem {
        let item = LaunchItem(
            name: name,
            target: target,
            kind: kind,
            categoryID: existingCategoryID(categoryID),
            keywords: keywords,
            notes: notes,
            hotkey: hotkey,
            isFavorite: isFavorite,
            sortIndex: nextSortIndex()
        )
        items.append(item)
        save()
        return item
    }

    func updateItem(_ item: LaunchItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        updated.categoryID = existingCategoryID(item.categoryID)
        items[index] = updated
        save()
    }

    func deleteItems(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        selectedItemIDs.subtract(ids)
        save()
    }

    func toggleFavorite(_ item: LaunchItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isFavorite.toggle()
        save()
    }

    func moveItems(_ ids: Set<UUID>, to categoryID: UUID?) {
        for id in ids {
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            items[index].categoryID = existingCategoryID(categoryID)
        }
        save()
    }

    func importURLs(_ urls: [URL]) {
        importURLs(urls, into: selectedCategoryIDForImport)
    }

    func importURLs(_ urls: [URL], into categoryID: UUID?) {
        guard !isRestoringData else { return }
        let destination = existingCategoryID(categoryID)
        var knownPaths = Set(items.map { Self.normalizedPath($0.target) })
        var additions: [LaunchItem] = []
        let firstSortIndex = nextSortIndex()
        for url in urls {
            guard url.isFileURL, url.pathExtension.lowercased() == "app" else { continue }
            let path = Self.normalizedPath(url.path)
            guard knownPaths.insert(path).inserted else { continue }
            let name = url.deletingPathExtension().lastPathComponent

            additions.append(LaunchItem(
                name: name,
                target: path,
                kind: .application,
                categoryID: destination,
                keywords: [name],
                notes: "",
                hotkey: nil,
                isFavorite: false,
                sortIndex: firstSortIndex + additions.count
            ))
        }
        guard !additions.isEmpty else { return }
        items.append(contentsOf: additions)
        save()
        if categoryID != nil {
            selectedFilterID = destination?.uuidString ?? Self.uncategorizedFilterID
        }
    }

    private func existingCategoryID(_ id: UUID?) -> UUID? {
        guard let id, categoryIndex.byID[id] != nil else { return nil }
        return id
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL.resolvingSymlinksInPath().path
    }

    func refreshInstalledApps() { refreshInstalledApps(importing: false, into: nil) }

    private func refreshInstalledApps(importing: Bool, into categoryID: UUID?) {
        guard !isRefreshingApps else { return }
        isRefreshingApps = true
        scanQueue.async { [weak self] in
            let discovered = ApplicationScanner.discover(in: ApplicationScanner.defaultDirectories)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let previous = Dictionary(self.installedApps.map { ($0.target, $0) }, uniquingKeysWith: { first, _ in first })
                self.installedApps = discovered.enumerated().map { index, app in
                    LaunchItem(id: previous[app.path]?.id ?? UUID(), name: app.name, target: app.path,
                               kind: .application, keywords: [app.name], sortIndex: index,
                               createdAt: previous[app.path]?.createdAt ?? Date())
                }
                self.isRefreshingApps = false
                if importing { self.importURLs(self.installedApps.compactMap(\.launchURL), into: categoryID) }
            }
        }
    }

    func scanApplications() {
        refreshInstalledApps(importing: true, into: selectedCategoryIDForImport)
    }

    @discardableResult
    func addCategory(
        name: String,
        symbol: String,
        parentID: UUID? = nil
    ) -> Category {
        let categoryID = UUID()
        let category = Category(
            id: categoryID,
            name: name,
            symbol: symbol,
            parentID: canSetParent(parentID, for: categoryID) ? parentID : nil,
            sortIndex: (categories.map(\.sortIndex).max() ?? -1) + 1
        )
        categories.append(category)
        save()
        return category
    }

    func updateCategory(
        _ category: Category,
        name: String,
        symbol: String,
        parentID: UUID?
    ) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        guard canSetParent(parentID, for: category.id) else { return }
        categories[index].name = name
        categories[index].symbol = symbol
        categories[index].parentID = parentID
        save()
    }

    func deleteCategory(_ category: Category) {
        let parentID = category.parentID
        for index in categories.indices where categories[index].parentID == category.id {
            categories[index].parentID = parentID
        }
        categories.removeAll { $0.id == category.id }
        for index in items.indices where items[index].categoryID == category.id {
            items[index].categoryID = nil
            items[index].managedSourceCategoryID = nil
            items[index].isManaged = false
        }
        if selectedFilterID == category.id.uuidString {
            selectedFilterID = Self.allFilterID
        }
        save()
    }

    func launch(_ item: LaunchItem) {
        guard let url = item.launchURL else { return }
        guard applicationOpener(url) else {
            launchError = L10n.tr("无法打开“%@”。应用可能已被移动、删除，或被系统阻止。请检查启动项路径。\n%@", item.name, url.path)
            return
        }

        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].launchCount += 1
        items[index].lastLaunchedAt = Date()
        save()
    }

    var selectedCategoryIDForImport: UUID? {
        guard !selectedFilterID.hasPrefix("all"),
              !selectedFilterID.hasPrefix("favorites"),
              !selectedFilterID.hasPrefix("uncategorized"),
              let id = UUID(uuidString: selectedFilterID) else {
            return nil
        }
        return id
    }

    private func nextSortIndex() -> Int {
        (items.map(\.sortIndex).max() ?? -1) + 1
    }

    private static func defaultFileURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["NEST_LAUNCHER_DATA_FILE"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }

        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let directory = base.appendingPathComponent("NestLauncher", isDirectory: true)
        return directory.appendingPathComponent("data.json")
    }

    private static func loadAppIconSize() -> Double {
        let value = UserDefaults.standard.object(forKey: appIconSizeKey) as? Double ?? 46
        return min(max(value, 28), 88)
    }

    private static func loadAppGridSpacing() -> Double {
        let value = UserDefaults.standard.object(forKey: appGridSpacingKey) as? Double ?? 12
        return min(max(value, 4), 40)
    }

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            apply(try LauncherPersistence.decode(data))
        } catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain && failure.code == NSFileReadNoSuchFileError {
                seedDefaults()
            } else {
                savingBlocked = true
                persistenceError = L10n.tr("无法读取应用数据，原文件已保留。本次更改不会保存，请备份并修复数据文件后重新打开应用。\n%@\n%@", fileURL.path, error.localizedDescription)
            }
        }
    }

    private func save() {
        guard !savingBlocked, !isRestoringData else { return }
        if batchDepth > 0 { needsSave = true; return }
        let payload = StorePayload(categories: categories, items: items)
        persistence.save(payload) { [weak self] error in
            if let error { self?.persistenceError = L10n.tr("应用数据保存失败，请检查磁盘空间和文件权限。\n%@", error) }
        }
    }

    private func apply(_ payload: StorePayload) {
        categories = payload.categories.sorted { $0.sortIndex < $1.sortIndex }
        items = payload.items
        for index in items.indices {
            items[index].categoryID = existingCategoryID(items[index].categoryID)
            if let source = items[index].managedSourceCategoryID, existingCategoryID(source) == nil {
                items[index].managedSourceCategoryID = nil
                items[index].isManaged = false
            }
        }
        for index in categories.indices {
            if !canSetParent(categories[index].parentID, for: categories[index].id) { categories[index].parentID = nil }
        }
    }

    func flushSaves() async { await persistence.flush() }

    func exportData(to destination: URL) async {
        do {
            try await persistence.export(StorePayload(categories: categories, items: items), to: destination)
            dataOperationMessage = L10n.tr("数据已导出。")
        } catch { dataOperationMessage = L10n.tr("导出失败：%@", error.localizedDescription) }
    }

    func restoreData(from source: URL? = nil) async {
        guard !isRestoringData else { return }
        isRestoringData = true
        defer { isRestoringData = false }
        do {
            let payload = try await persistence.restore(from: source ?? persistence.backupURL)
            apply(payload)
            savingBlocked = false
            persistenceError = nil
            selectedItemIDs.removeAll()
            selectedFilterID = Self.allFilterID
            dataOperationMessage = L10n.tr("数据已恢复。恢复前的文件已另存到数据目录，便于撤回。")
        } catch { dataOperationMessage = L10n.tr("恢复失败，当前数据未替换：%@", error.localizedDescription) }
    }

    private func seedDefaults() {
        if categories.isEmpty {
            let category = addCategory(name: L10n.tr("未命名"), symbol: "folder")
            selectedFilterID = category.id.uuidString
        } else {
            selectedFilterID = Self.allFilterID
        }
    }
}
