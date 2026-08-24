import AppKit
import ApplicationServices

/// 全局拦截鼠标事件，结合触摸板手指位置实现自定义手势。
final class GestureController {
    static let shared = GestureController()

    private enum Mode {
        case idle
        /// 已消费了一次 mouseDown，后续 drag/up 也要吞掉，直到 mouseUp。
        case swallowUntilUp
        /// 按下后等待松开再执行的动作；期间移动超过阈值则取消。
        case armed(action: ArmedAction, window: TargetWindow, moved: CGFloat)
        /// 正在拖动窗口。
        case dragging(window: TargetWindow, frame: CGRect)
        /// 正在调整窗口大小（拖动映射到窗口右下角）。
        case resizing(window: TargetWindow, frame: CGRect)
    }

    /// "松开才执行"的动作。
    private enum ArmedAction {
        case close
        case minimize

        var overlayStyle: FeedbackOverlay.Style {
            switch self {
            case .close: return .close
            case .minimize: return .minimize
            }
        }

        var name: String {
            switch self {
            case .close: return "关闭"
            case .minimize: return "最小化"
            }
        }

        func perform(on win: TargetWindow) {
            switch self {
            case .close: win.close()
            case .minimize: win.minimize()
            }
        }
    }

    var config = Config()
    private var mode: Mode = .idle

    /// 是否正在进行按下类手势（拖动/调整大小/待执行）。主线程读写。
    var isMidGesture: Bool {
        if case .idle = mode { return false }
        return true
    }
    private var tap: CFMachPort?

    private init() {}

    func start() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: nil
        ) else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // 系统在回调太慢时会禁用 tap，重新打开。
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)

        case .leftMouseDown:
            return handleMouseDown(event)

        case .leftMouseDragged:
            return handleMouseDragged(event)

        case .leftMouseUp:
            return handleMouseUp(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - 按下

    private func handleMouseDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        mode = .idle
        if SettingsStore.shared.isPaused { return Unmanaged.passUnretained(event) }
        guard let finger = TouchTracker.shared.fingerForClick(config: config) else {
            return Unmanaged.passUnretained(event)
        }
        if config.debug {
            log(String(format: "mouseDown 屏幕(%.0f, %.0f) 手指(x=%.2f y=%.2f)", event.location.x, event.location.y, finger.x, finger.y))
        }

        let armedAction: ArmedAction? = config.isTopLeftCorner(finger) ? .close
            : config.isMinimizeZone(finger) ? .minimize
            : nil
        if let action = armedAction {
            guard let win = WindowControl.targetWindow(at: event.location),
                  let frame = win.frame() else {
                log("\(action.name)区按下，但指针下没有窗口，忽略")
                return Unmanaged.passUnretained(event)
            }
            // 教学进行中：关闭/最小化只对教学窗口生效。练习时指针常忘了挪过来，
            // 别把用户的真实窗口收进 Dock 或关掉；放行事件当普通点击。
            if OnboardingWindowController.shared.isTeaching,
               win.pid != ProcessInfo.processInfo.processIdentifier {
                log("教学进行中，指针不在教学窗口上，忽略\(action.name)")
                return Unmanaged.passUnretained(event)
            }
            log(String(format: "%@区按下 (x=%.2f y=%.2f) → 待%@「%@」，松开执行",
                       action.name, finger.x, finger.y, action.name, win.title))
            FeedbackOverlay.shared.show(axFrame: frame, style: action.overlayStyle)
            mode = .armed(action: action, window: win, moved: 0)
            return nil
        }

        if config.isTopRightCorner(finger) {
            guard let win = WindowControl.targetWindow(at: event.location),
                  let frame = win.frame() else {
                log("右上角按下，但指针下没有窗口，忽略")
                return Unmanaged.passUnretained(event)
            }
            log(String(format: "右上角按下 (x=%.2f y=%.2f) → 开始调整「%@」大小", finger.x, finger.y, win.title))
            FeedbackOverlay.shared.show(axFrame: frame, style: .resize)
            mode = .resizing(window: win, frame: frame)
            return nil
        }

        if config.isTopEdge(finger) {
            guard let win = WindowControl.targetWindow(at: event.location),
                  let frame = win.frame() else {
                log("上沿按下，但指针下没有窗口，忽略")
                return Unmanaged.passUnretained(event)
            }
            log(String(format: "上沿按下 (x=%.2f y=%.2f) → 开始拖动「%@」", finger.x, finger.y, win.title))
            FeedbackOverlay.shared.show(axFrame: frame, style: .drag)
            mode = .dragging(window: win, frame: frame)
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - 拖动

    private func handleMouseDragged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let dx = CGFloat(event.getIntegerValueField(.mouseEventDeltaX))
        let dy = CGFloat(event.getIntegerValueField(.mouseEventDeltaY))

        switch mode {
        case .idle:
            return Unmanaged.passUnretained(event)

        case .swallowUntilUp:
            return nil

        case .armed(let action, let win, let moved):
            let total = moved + hypot(dx, dy)
            if total > config.closeCancelDistance {
                log("移动超过阈值 → 取消\(action.name)")
                FeedbackOverlay.shared.hide()
                mode = .swallowUntilUp
            } else {
                mode = .armed(action: action, window: win, moved: total)
            }
            return nil

        case .dragging(let win, var frame):
            frame.origin.x += dx
            frame.origin.y += dy
            win.setPosition(frame.origin)
            FeedbackOverlay.shared.move(axFrame: frame)
            mode = .dragging(window: win, frame: frame)
            return nil

        case .resizing(let win, var frame):
            frame.size.width = max(1, frame.size.width + dx)
            frame.size.height = max(1, frame.size.height + dy)
            win.setSize(frame.size)
            // 应用可能有最小尺寸限制，用实际生效的 frame 画提示层。
            let actual = win.frame() ?? frame
            FeedbackOverlay.shared.move(axFrame: actual)
            mode = .resizing(window: win, frame: frame)
            return nil
        }
    }

    // MARK: - 抬起

    private func handleMouseUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch mode {
        case .idle:
            return Unmanaged.passUnretained(event)

        case .swallowUntilUp:
            mode = .idle
            return nil

        case .armed(let action, let win, _):
            log("松开 → \(action.name)窗口")
            FeedbackOverlay.shared.hide()
            action.perform(on: win)
            GestureEvents.post(action == .close ? .close : .minimize, targetPid: win.pid)
            mode = .idle
            return nil

        case .dragging(let win, _):
            log("松开 → 结束拖动")
            FeedbackOverlay.shared.hide()
            GestureEvents.post(.move, targetPid: win.pid)
            mode = .idle
            return nil

        case .resizing(let win, _):
            log("松开 → 结束调整大小")
            FeedbackOverlay.shared.hide()
            GestureEvents.post(.resize, targetPid: win.pid)
            mode = .idle
            return nil
        }
    }

    private func log(_ msg: String) {
        if config.debug { print("[gesture] \(msg)") }
    }
}

/// C 回调：无捕获全局函数。
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    GestureController.shared.handle(type: type, event: event)
}
