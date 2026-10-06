import XCTest
import ServiceManagement
@testable import NestLauncher

@MainActor
private final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var registrationStatus: SMAppService.Status = .enabled
    var failure: Error?
    var registrations = 0
    var unregistrations = 0

    func register() throws {
        registrations += 1
        if let failure { throw failure }
        status = registrationStatus
    }

    func unregister() throws {
        unregistrations += 1
        if let failure { throw failure }
        status = .notRegistered
    }
}

final class LoginItemManagerTests: XCTestCase {
    @MainActor func testDefaultDoesNotRegisterAndToggleUpdatesSystem() async {
        let service = FakeLoginItemService()
        let manager = LoginItemManager(service: service)
        XCTAssertFalse(manager.isRequested)
        XCTAssertEqual(service.registrations, 0)
        manager.setEnabled(true)
        XCTAssertTrue(manager.isRequested)
        XCTAssertEqual(manager.status, .enabled)
        manager.setEnabled(true)
        XCTAssertEqual(service.registrations, 1)
        manager.setEnabled(false)
        XCTAssertFalse(manager.isRequested)
        XCTAssertEqual(service.unregistrations, 1)
    }

    @MainActor func testApprovalIsShownAndCanBeCancelled() async {
        let service = FakeLoginItemService()
        service.registrationStatus = .requiresApproval
        let manager = LoginItemManager(service: service)
        manager.setEnabled(true)
        XCTAssertTrue(manager.isRequested)
        XCTAssertEqual(manager.status, .requiresApproval)
        XCTAssertEqual(manager.statusMessage, L10n.tr("等待系统允许，请在“系统设置 → 通用 → 登录项”中开启 Nest Launcher。"))
        manager.setEnabled(false)
        XCTAssertFalse(manager.isRequested)
    }

    @MainActor func testExternalSystemChangesAreReflected() async {
        let service = FakeLoginItemService()
        let manager = LoginItemManager(service: service)
        service.status = .enabled
        manager.refresh()
        XCTAssertTrue(manager.isRequested)
        service.status = .notRegistered
        manager.refresh()
        XCTAssertFalse(manager.isRequested)
    }

    @MainActor func testFailuresDoNotInventEnabledOrDisabledState() async {
        let service = FakeLoginItemService()
        service.failure = NSError(domain: "LoginItemTests", code: 1)
        let manager = LoginItemManager(service: service)
        manager.setEnabled(true)
        XCTAssertFalse(manager.isRequested)
        XCTAssertNotNil(manager.errorMessage)
        service.status = .enabled
        manager.setEnabled(false)
        XCTAssertTrue(manager.isRequested)
        XCTAssertNotNil(manager.errorMessage)
        service.failure = nil
        manager.setEnabled(false)
        XCTAssertFalse(manager.isRequested)
        XCTAssertNil(manager.errorMessage)
    }

    @MainActor func testMissingItemHasInstallationGuidance() async {
        let service = FakeLoginItemService()
        service.status = .notFound
        let manager = LoginItemManager(service: service)
        XCTAssertFalse(manager.isRequested)
        XCTAssertEqual(manager.statusMessage, L10n.tr("系统未找到登录项，请先将应用安装到应用程序目录，再重新开启。"))
    }
}
