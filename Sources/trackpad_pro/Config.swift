import Foundation

/// 手势判定参数。坐标均为触摸板归一化坐标：x 0(左)~1(右)，y 0(下)~1(上)。
struct Config: Codable, Equatable {
    // ---- 功能开关 ----
    var closeEnabled = true
    var minimizeEnabled = true
    var moveEnabled = true
    var resizeEnabled = true

    /// 右上角（调整大小）区的宽度（占触摸板比例）：x > 1 - cornerSize。
    /// 上沿各区（含右上角）的高度统一用 topEdgeHeight。
    var cornerSize: Float = 0.10

    /// 关闭区宽度（占触摸板比例），贴左边缘：x < closeZoneWidth。手指摸到左上角边缘即可触发。
    var closeZoneWidth: Float = 0.10

    /// 最小化区宽度（占触摸板比例），紧挨关闭区右侧：closeZoneWidth <= x < closeZoneWidth + minimizeZoneWidth。
    /// 对应红绿灯里关闭按钮右边的黄色按钮。
    var minimizeZoneWidth: Float = 0.10

    /// 上沿功能区（关闭/最小化/拖窗/调整大小）的统一高度（占触摸板比例）。
    /// y > 1 - topEdgeHeight 视为上沿。
    var topEdgeHeight: Float = 0.10

    /// 触发时是否要求触摸板上只有一根手指（避免和多指手势冲突）。
    var requireSingleFinger = true

    /// 轻点（tap-to-click）时手指已离开触摸板，允许回溯多久以内抬起的手指位置。
    var tapFallbackInterval: TimeInterval = 0.25

    /// 左上角（关闭）/ 最小化区按下后，指针累计移动超过多少像素视为误操作、取消。
    var closeCancelDistance: CGFloat = 10

    /// 单指从触摸板右边缘起手向内滑动时放大指针，抬起还原。
    var cursorZoomEnabled = true
    /// 右边缘判定宽度（占触摸板比例）。
    var rightEdgeWidth: Float = 0.06
    /// 从边缘向内滑动多少（归一化距离）后触发放大。
    var edgeSwipeActivationDistance: Float = 0.04
    /// 指针放大倍率（1–4）。
    var cursorZoomScale: Float = 3.0

    /// 下沿左右滑动切换窗口。
    var switcherEnabled = true
    /// 下沿判定带高度（占触摸板比例）：y < bottomEdgeHeight 视为下沿。
    var bottomEdgeHeight: Float = 0.09
    /// 每滑动多少（归一化距离）切换到下一个窗口。
    var switcherStepDistance: Float = 0.055

    /// 向右滑动切换到下一个（层叠里更靠后的）窗口；false 则向左滑。
    var switcherRightToNext = true

    /// 选定窗口后把指针移到该窗口中心（指针已在窗口内则不动）。
    var switcherMovesPointer = true

    /// 打印手指坐标，用于调阈值（命令行参数，不持久化）。
    var debug = false

    /// 是否已完成引导教学。
    var hasCompletedOnboarding = false

    /// 是否已做过开机自启的默认设置（首次以 .app 运行时注册一次，之后尊重用户选择）。
    var hasSetupLaunchAtLogin = false

    private enum CodingKeys: String, CodingKey {
        case closeEnabled, minimizeEnabled, moveEnabled, resizeEnabled
        case cornerSize, closeZoneWidth, minimizeZoneWidth, topEdgeHeight
        case requireSingleFinger, tapFallbackInterval, closeCancelDistance
        case cursorZoomEnabled, rightEdgeWidth, edgeSwipeActivationDistance, cursorZoomScale
        case switcherEnabled, bottomEdgeHeight, switcherStepDistance, switcherRightToNext, switcherMovesPointer
        case hasCompletedOnboarding, hasSetupLaunchAtLogin
    }

    init() {}

    /// 缺失的键使用默认值，这样新增配置项不会让旧配置解析失败。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        closeEnabled = try c.decodeIfPresent(Bool.self, forKey: .closeEnabled) ?? d.closeEnabled
        minimizeEnabled = try c.decodeIfPresent(Bool.self, forKey: .minimizeEnabled) ?? d.minimizeEnabled
        moveEnabled = try c.decodeIfPresent(Bool.self, forKey: .moveEnabled) ?? d.moveEnabled
        resizeEnabled = try c.decodeIfPresent(Bool.self, forKey: .resizeEnabled) ?? d.resizeEnabled
        cornerSize = try c.decodeIfPresent(Float.self, forKey: .cornerSize) ?? d.cornerSize
        closeZoneWidth = try c.decodeIfPresent(Float.self, forKey: .closeZoneWidth) ?? d.closeZoneWidth
        minimizeZoneWidth = try c.decodeIfPresent(Float.self, forKey: .minimizeZoneWidth) ?? d.minimizeZoneWidth
        topEdgeHeight = try c.decodeIfPresent(Float.self, forKey: .topEdgeHeight) ?? d.topEdgeHeight
        requireSingleFinger = try c.decodeIfPresent(Bool.self, forKey: .requireSingleFinger) ?? d.requireSingleFinger
        tapFallbackInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .tapFallbackInterval) ?? d.tapFallbackInterval
        closeCancelDistance = try c.decodeIfPresent(CGFloat.self, forKey: .closeCancelDistance) ?? d.closeCancelDistance
        cursorZoomEnabled = try c.decodeIfPresent(Bool.self, forKey: .cursorZoomEnabled) ?? d.cursorZoomEnabled
        rightEdgeWidth = try c.decodeIfPresent(Float.self, forKey: .rightEdgeWidth) ?? d.rightEdgeWidth
        edgeSwipeActivationDistance = try c.decodeIfPresent(Float.self, forKey: .edgeSwipeActivationDistance) ?? d.edgeSwipeActivationDistance
        cursorZoomScale = try c.decodeIfPresent(Float.self, forKey: .cursorZoomScale) ?? d.cursorZoomScale
        switcherEnabled = try c.decodeIfPresent(Bool.self, forKey: .switcherEnabled) ?? d.switcherEnabled
        bottomEdgeHeight = try c.decodeIfPresent(Float.self, forKey: .bottomEdgeHeight) ?? d.bottomEdgeHeight
        switcherStepDistance = try c.decodeIfPresent(Float.self, forKey: .switcherStepDistance) ?? d.switcherStepDistance
        switcherRightToNext = try c.decodeIfPresent(Bool.self, forKey: .switcherRightToNext) ?? d.switcherRightToNext
        switcherMovesPointer = try c.decodeIfPresent(Bool.self, forKey: .switcherMovesPointer) ?? d.switcherMovesPointer
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? d.hasCompletedOnboarding
        hasSetupLaunchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .hasSetupLaunchAtLogin) ?? d.hasSetupLaunchAtLogin
    }

    func isTopLeftCorner(_ f: Finger) -> Bool {
        closeEnabled && f.x < closeZoneWidth && f.y > 1 - topEdgeHeight
    }

    func isMinimizeZone(_ f: Finger) -> Bool {
        minimizeEnabled && f.x >= minimizeZoneStart && f.x < minimizeZoneStart + minimizeZoneWidth && f.y > 1 - topEdgeHeight
    }

    func isTopRightCorner(_ f: Finger) -> Bool {
        resizeEnabled && f.x > 1 - cornerSize && f.y > 1 - topEdgeHeight
    }

    func isTopEdge(_ f: Finger) -> Bool {
        moveEnabled && f.y > 1 - topEdgeHeight
    }

    /// 最小化区起点：关闭区关闭时最小化区贴左边缘。
    var minimizeZoneStart: Float { closeEnabled ? closeZoneWidth : 0 }
}
