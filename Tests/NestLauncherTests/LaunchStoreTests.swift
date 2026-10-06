import XCTest
@testable import NestLauncher

final class LaunchStoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nest-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor func testDropBatchCompletesOnceInOrderIncludingFailures() async {
        var deliveries: [[URL]] = []
        let first = URL(fileURLWithPath: "/tmp/First.app"), last = URL(fileURLWithPath: "/tmp/Last.app")
        let batch = DropImportBatch(count: 3) { deliveries.append($0) }
        batch.accept(last, at: 2)
        batch.accept(nil, at: 1)
        XCTAssertTrue(deliveries.isEmpty)
        batch.accept(first, at: 0)
        batch.accept(first, at: 0)
        XCTAssertEqual(deliveries, [[first, last]])
    }

    @MainActor func testDeletedImportDestinationFallsBackAndSurvivesReload() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("data.json")
        let store = LaunchStore(fileURL: file, scansOnInit: false)
        let category = store.addCategory(name: "Deleted", symbol: "folder")
        store.deleteCategory(category)
        store.importURLs([directory.appendingPathComponent("Late.app")], into: category.id)
        XCTAssertNil(store.items[0].categoryID)
        XCTAssertEqual(store.selectedFilterID, LaunchStore.uncategorizedFilterID)
        XCTAssertEqual(store.visibleItems.count, 1)
        await store.flushSaves()
        let reloaded = LaunchStore(fileURL: file, scansOnInit: false)
        reloaded.selectedFilterID = LaunchStore.uncategorizedFilterID
        XCTAssertEqual(reloaded.visibleItems.count, 1)
    }

    @MainActor func testLoadedOrphanIsUncategorized() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = LaunchItem(name: "Orphan", target: "/tmp/Orphan.app", kind: .application, categoryID: UUID())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let file = directory.appendingPathComponent("data.json")
        try encoder.encode(StorePayload(categories: [], items: [item])).write(to: file)
        let store = LaunchStore(fileURL: file, scansOnInit: false)
        store.selectedFilterID = LaunchStore.uncategorizedFilterID
        XCTAssertEqual(store.visibleItems.count, 1)
    }

    @MainActor func testFailedLaunchDoesNotCountAndSuccessPersists() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("data.json")
        var succeeds = false
        let store = LaunchStore(fileURL: file, scansOnInit: false, applicationOpener: { _ in succeeds })
        store.importURLs([directory.appendingPathComponent("Example.app")])
        let item = store.items[0]
        store.launch(item)
        XCTAssertEqual(store.items[0].launchCount, 0)
        XCTAssertNil(store.items[0].lastLaunchedAt)
        XCTAssertNotNil(store.launchError)
        succeeds = true
        store.launch(item)
        XCTAssertEqual(store.items[0].launchCount, 1)
        await store.flushSaves()
        XCTAssertEqual(LaunchStore(fileURL: file, scansOnInit: false).items[0].launchCount, 1)
    }

    @MainActor func testCorruptFileIsPreservedEvenAfterMutation() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("data.json")
        let original = Data("{invalid-json".utf8)
        try original.write(to: file)
        let store = LaunchStore(fileURL: file, scansOnInit: false)
        XCTAssertNotNil(store.persistenceError)
        store.addCategory(name: "Do not overwrite", symbol: "folder")
        await store.flushSaves()
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    @MainActor func testMissingFileSeedsAndPersists() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("data.json")
        let store = LaunchStore(fileURL: file, scansOnInit: false)
        XCTAssertNil(store.persistenceError)
        XCTAssertEqual(store.categories.count, 1)
        await store.flushSaves()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(LaunchStore(fileURL: file, scansOnInit: false).categories.map(\.id), store.categories.map(\.id))
    }

    @MainActor func testParentCannotBeSelfOrDescendant() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LaunchStore(fileURL: directory.appendingPathComponent("data.json"), scansOnInit: false)
        let parent = store.addCategory(name: "Parent", symbol: "folder")
        let child = store.addCategory(name: "Child", symbol: "folder", parentID: parent.id)
        let grandchild = store.addCategory(name: "Grandchild", symbol: "folder", parentID: child.id)
        XCTAssertFalse(store.canSetParent(parent.id, for: parent.id))
        XCTAssertFalse(store.canSetParent(grandchild.id, for: parent.id))
        store.updateCategory(parent, name: parent.name, symbol: parent.symbol, parentID: child.id)
        XCTAssertNil(store.categories.first { $0.id == parent.id }?.parentID)
        XCTAssertEqual(store.depth(of: grandchild), 2)
        store.categories = [Category(id: parent.id, name: "A", parentID: child.id), Category(id: child.id, name: "B", parentID: parent.id)]
        XCTAssertLessThanOrEqual(store.depth(of: store.categories[0]), 2)
        await store.flushSaves()
    }

    @MainActor func testLoadedCycleIsRepairedWithoutImmediateWrite() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = UUID(), b = UUID()
        let payload = StorePayload(categories: [Category(id: a, name: "A", parentID: b), Category(id: b, name: "B", parentID: a)], items: [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let original = try encoder.encode(payload)
        let file = directory.appendingPathComponent("data.json")
        try original.write(to: file)
        let store = LaunchStore(fileURL: file, scansOnInit: false)
        XCTAssertEqual(store.rootCategories.count, 1)
        XCTAssertEqual(store.categoriesInDisplayOrder.count, 2)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    @MainActor func testBulkImportDeduplicatesAndPersists() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("data.json")
        let store = LaunchStore(fileURL: file, scansOnInit: false)
        let urls = (0..<500).map { directory.appendingPathComponent("Test-\($0).app") }
        store.importURLs(urls + urls)
        store.importURLs([urls[0], directory.appendingPathComponent("./Test-0.app")])
        XCTAssertEqual(store.items.count, 500)
        XCTAssertEqual(Set(store.items.map(\.sortIndex)).count, 500)
        await store.flushSaves()
        XCTAssertEqual(LaunchStore(fileURL: file, scansOnInit: false).items.count, 500)
    }

    @MainActor func testChangingFilterOrSearchClearsSelection() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LaunchStore(fileURL: directory.appendingPathComponent("data.json"), scansOnInit: false)
        store.importURLs([directory.appendingPathComponent("Example.app")])
        let item = store.items[0]
        store.selectedItemIDs = [item.id]
        store.selectedFilterID = LaunchStore.favoritesFilterID
        XCTAssertTrue(store.selectedItemIDs.isEmpty)
        store.selectedItemIDs = [item.id]
        XCTAssertTrue(store.selectedItems.isEmpty)
        store.searchText = "hidden"
        XCTAssertTrue(store.selectedItemIDs.isEmpty)
        await store.flushSaves()
    }

    @MainActor func testCategoryIndexInvalidatesAndMatchesDepthFirstOrder() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LaunchStore(fileURL: directory.appendingPathComponent("data.json"), scansOnInit: false)
        let parent = store.addCategory(name: "A", symbol: "folder")
        let other = store.addCategory(name: "B", symbol: "folder")
        let child = store.addCategory(name: "A1", symbol: "folder", parentID: parent.id)
        let displayed = store.categoriesInDisplayOrder.map(\.id)
        XCTAssertLessThan(displayed.firstIndex(of: child.id)!, displayed.firstIndex(of: other.id)!)
        XCTAssertEqual(store.depth(of: child), 1)
        store.updateCategory(child, name: "A1", symbol: "folder", parentID: nil)
        XCTAssertEqual(store.depth(of: child), 0)
        XCTAssertTrue(store.subcategories(of: parent).isEmpty)
        await store.flushSaves()
    }

    func testScannerFindsNestedAppsButSkipsBundleInternalsAndSymlinkDirectories() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in ["Folder/Nested.app", "Outer.app/Contents/Hidden.app", ".Hidden/Invisible.app"] {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("Loop"), withDestinationURL: directory)
        let names = ApplicationScanner.discover(in: [directory, directory]).map(\.name)
        XCTAssertEqual(names.sorted(), ["Nested", "Outer"])
    }

    @MainActor func testSerialSavesKeepLatestAndBackupRestoresPrevious() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("data.json")
        let store = LaunchStore(fileURL: file, scansOnInit: false)
        store.importURLs([directory.appendingPathComponent("First.app")])
        store.importURLs([directory.appendingPathComponent("Second.app")])
        await store.flushSaves()
        XCTAssertEqual(try LauncherPersistence.decode(Data(contentsOf: file)).items.count, 2)
        XCTAssertEqual(try LauncherPersistence.decode(Data(contentsOf: file.appendingPathExtension("backup"))).items.count, 1)
        await store.restoreData()
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(try LauncherPersistence.decode(Data(contentsOf: file)).items.count, 1)
        let preserved = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains("before-restore") }
        XCTAssertEqual(preserved.count, 1)
    }

    @MainActor func testExportAndInvalidRestoreDoNotReplaceData() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("data.json")
        let store = LaunchStore(fileURL: file, scansOnInit: false)
        store.importURLs([directory.appendingPathComponent("Example.app")])
        let exported = directory.appendingPathComponent("export.json")
        await store.exportData(to: exported)
        XCTAssertEqual(try LauncherPersistence.decode(Data(contentsOf: exported)).items.count, 1)
        await store.flushSaves()
        let original = try Data(contentsOf: file)
        let invalid = directory.appendingPathComponent("invalid.json")
        try Data("{bad".utf8).write(to: invalid)
        await store.restoreData(from: invalid)
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(store.items.count, 1)
    }

    @MainActor func testRestoreUnblocksCorruptDataFile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("good.json")
        let good = LaunchStore(fileURL: source, scansOnInit: false)
        good.importURLs([directory.appendingPathComponent("Example.app")])
        await good.flushSaves()
        let file = directory.appendingPathComponent("corrupt.json")
        try Data("{bad".utf8).write(to: file)
        let store = LaunchStore(fileURL: file, scansOnInit: false)
        await store.restoreData(from: source)
        XCTAssertNil(store.persistenceError)
        store.importURLs([directory.appendingPathComponent("New.app")])
        await store.flushSaves()
        XCTAssertEqual(try LauncherPersistence.decode(Data(contentsOf: file)).items.count, 2)
    }
}
