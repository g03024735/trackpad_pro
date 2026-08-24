import Foundation

/// 手势完成事件，供引导教学等 UI 订阅。
enum GestureKind: String {
    case move, resize, minimize, close, zoom
}

extension Notification.Name {
    static let gesturePerformed = Notification.Name("trackpad_pro.gesturePerformed")
}

enum GestureEvents {
    /// targetPid：被操作窗口所属进程（放大指针无目标时为 nil）。
    static func post(_ kind: GestureKind, targetPid: pid_t? = nil) {
        var info: [String: Any] = ["kind": kind.rawValue]
        if let targetPid { info["pid"] = targetPid }
        NotificationCenter.default.post(name: .gesturePerformed, object: nil, userInfo: info)
    }

    static func parse(_ n: Notification) -> (kind: GestureKind, pid: pid_t?)? {
        guard let raw = n.userInfo?["kind"] as? String, let kind = GestureKind(rawValue: raw) else { return nil }
        return (kind, n.userInfo?["pid"] as? pid_t)
    }
}
