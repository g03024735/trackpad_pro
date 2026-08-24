import Combine
import Foundation
import ServiceManagement

/// 配置的唯一来源：持久化到 UserDefaults，变更时通知各模块。
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private static let key = "config"

    @Published var config: Config {
        didSet { save() }
    }

    /// 暂停所有手势（菜单栏切换）。不持久化。
    @Published var isPaused = false

    /// 是否已获得辅助功能权限（由 main 设置）。
    @Published var isTrusted = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(Config.self, from: data) {
            config = decoded
        } else {
            config = Config()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    // MARK: - 开机自启（仅 .app 形式有效）

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                print("开机自启设置失败: \(error)")
            }
            objectWillChange.send()
        }
    }

    var canLaunchAtLogin: Bool { Bundle.main.bundleURL.pathExtension == "app" }
}
