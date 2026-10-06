import Foundation

enum LaunchTargetKind: String, Codable, CaseIterable, Identifiable {
    case application

    var id: String { rawValue }

    var displayName: String {
        L10n.tr("应用")
    }

    var symbol: String {
        "app"
    }
}

struct LaunchItem: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var target: String
    var kind: LaunchTargetKind
    var categoryID: UUID?
    var keywords: [String]
    var notes: String
    var hotkey: String?
    var isFavorite: Bool
    var launchCount: Int
    var lastLaunchedAt: Date?
    var sortIndex: Int
    var createdAt: Date
    var isManaged: Bool
    var managedSourceCategoryID: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        target: String,
        kind: LaunchTargetKind,
        categoryID: UUID? = nil,
        keywords: [String] = [],
        notes: String = "",
        hotkey: String? = nil,
        isFavorite: Bool = false,
        launchCount: Int = 0,
        lastLaunchedAt: Date? = nil,
        sortIndex: Int = 0,
        createdAt: Date = Date(),
        isManaged: Bool = false,
        managedSourceCategoryID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.target = target
        self.kind = kind
        self.categoryID = categoryID
        self.keywords = keywords
        self.notes = notes
        self.hotkey = hotkey
        self.isFavorite = isFavorite
        self.launchCount = launchCount
        self.lastLaunchedAt = lastLaunchedAt
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.isManaged = isManaged
        self.managedSourceCategoryID = managedSourceCategoryID
    }

    var launchURL: URL? {
        let expanded = (target as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    func matches(query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }

        let haystacks = [
            name,
            target,
            kind.displayName,
            keywords.joined(separator: " "),
            notes
        ]

        return haystacks.contains {
            $0.localizedCaseInsensitiveContains(needle)
        }
    }
}

struct Category: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var symbol: String
    var parentID: UUID?
    var sortIndex: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String = "folder",
        parentID: UUID? = nil,
        sortIndex: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.parentID = parentID
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}

struct StorePayload: Codable {
    var categories: [Category]
    var items: [LaunchItem]
}

enum ItemSortOrder: String, CaseIterable, Identifiable {
    case manual = "手动"
    case name = "名称"
    case launchCount = "使用次数"
    case lastLaunched = "最近使用"

    var id: String { rawValue }
    var displayName: String { L10n.tr(rawValue) }
}
