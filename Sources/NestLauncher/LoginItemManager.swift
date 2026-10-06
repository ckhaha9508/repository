import Combine
import ServiceManagement

@MainActor
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

@MainActor
private struct SystemLoginItemService: LoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var errorMessage: String?
    private let service: any LoginItemService

    init(service: (any LoginItemService)? = nil) {
        self.service = service ?? SystemLoginItemService()
        refresh()
    }

    // Pending approval is a registration request, not a successfully enabled item.
    var isRequested: Bool { status == .enabled || status == .requiresApproval }

    var statusMessage: String {
        switch status {
        case .enabled:
            return L10n.tr("已开启，下次登录 macOS 时自动启动。")
        case .requiresApproval:
            return L10n.tr("等待系统允许，请在“系统设置 → 通用 → 登录项”中开启 Nest Launcher。")
        case .notFound:
            return L10n.tr("系统未找到登录项，请先将应用安装到应用程序目录，再重新开启。")
        case .notRegistered:
            return L10n.tr("默认关闭。开启后，登录 macOS 时自动启动 Nest Launcher。")
        @unknown default:
            return L10n.tr("无法识别登录项状态，请在系统设置中检查。")
        }
    }

    func refresh() {
        status = service.status
    }

    func setEnabled(_ enabled: Bool) {
        refresh()
        errorMessage = nil
        guard enabled != isRequested else { return }
        do {
            if enabled { try service.register() } else { try service.unregister() }
        } catch {
            errorMessage = L10n.tr(enabled ? "开启登录时启动失败：%@" : "关闭登录时启动失败：%@", error.localizedDescription)
        }
        // Never persist a separate Boolean: macOS owns the actual setting.
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
