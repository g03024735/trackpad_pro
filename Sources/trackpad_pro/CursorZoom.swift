import Foundation

/// 通过 SkyLight 私有接口 CGSSetCursorScale 临时放大系统指针。
/// 放大期间把原始倍率记到 UserDefaults，万一程序异常退出，下次启动时据此还原。
final class CursorZoom {
    static let shared = CursorZoom()

    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias GetScaleFn = @convention(c) (Int32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetScaleFn = @convention(c) (Int32, Float) -> Int32

    private let connection: Int32
    private let getScale: GetScaleFn
    private let setScale: SetScaleFn
    private let available: Bool
    private var baseScale: Float = 1
    private(set) var isZoomed = false

    private static let savedBaseKey = "cursorZoom.savedBaseScale"

    private init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
        if let handle,
           let pMain = dlsym(handle, "CGSMainConnectionID"),
           let pGet = dlsym(handle, "CGSGetCursorScale"),
           let pSet = dlsym(handle, "CGSSetCursorScale") {
            connection = unsafeBitCast(pMain, to: MainConnectionFn.self)()
            getScale = unsafeBitCast(pGet, to: GetScaleFn.self)
            setScale = unsafeBitCast(pSet, to: SetScaleFn.self)
            available = true
        } else {
            connection = 0
            getScale = { _, _ in -1 }
            setScale = { _, _ in -1 }
            available = false
        }
    }

    /// 启动时调用：若上次异常退出时指针处于放大状态，先还原。
    func recoverIfNeeded() {
        guard available else { return }
        let defaults = UserDefaults.standard
        if let saved = defaults.object(forKey: Self.savedBaseKey) as? Float {
            _ = setScale(connection, saved)
            defaults.removeObject(forKey: Self.savedBaseKey)
        }
    }

    func zoom(to scale: Float) {
        guard available, !isZoomed else { return }
        var current: Float = 1
        if getScale(connection, &current) != 0 { current = 1 }
        baseScale = current
        UserDefaults.standard.set(baseScale, forKey: Self.savedBaseKey)
        // 不小于用户在辅助功能里设置的倍率的 1.5 倍，上限 4（系统指针大小滑块的最大值）。
        let target = min(4, max(scale, baseScale * 1.5))
        _ = setScale(connection, target)
        isZoomed = true
    }

    func restore() {
        guard available, isZoomed else { return }
        _ = setScale(connection, baseScale)
        UserDefaults.standard.removeObject(forKey: Self.savedBaseKey)
        isZoomed = false
    }
}
