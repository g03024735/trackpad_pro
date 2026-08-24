import AppKit
import ApplicationServices

/// 手势的操作目标：其他应用的窗口走 Accessibility；自己的窗口直接操作 NSWindow
/// （从主线程用 AX 操作自己进程会阻塞/超时）。坐标统一用 AX 坐标系（主屏左上角原点，y 向下）。
enum TargetWindow {
    case ax(AXUIElement)
    case own(NSWindow)

    var pid: pid_t {
        switch self {
        case .ax(let el): return WindowControl.pid(of: el)
        case .own: return ProcessInfo.processInfo.processIdentifier
        }
    }

    var title: String {
        switch self {
        case .ax(let el): return WindowControl.title(of: el)
        case .own(let w): return w.title
        }
    }

    func frame() -> CGRect? {
        switch self {
        case .ax(let el): return WindowControl.frame(of: el)
        case .own(let w): return WindowControl.toAX(w.frame)
        }
    }

    func setPosition(_ pt: CGPoint) {
        switch self {
        case .ax(let el): WindowControl.setPosition(el, pt)
        case .own(let w):
            let h = w.frame.height
            w.setFrameOrigin(NSPoint(x: pt.x, y: WindowControl.primaryHeight - pt.y - h))
        }
    }

    func setSize(_ size: CGSize) {
        switch self {
        case .ax(let el): WindowControl.setSize(el, size)
        case .own(let w):
            // 不小于窗口内容的最小尺寸，避免内容被剪；保持左上角不动。
            let minFrame = w.frameRect(forContentRect: NSRect(origin: .zero, size: w.contentMinSize)).size
            var s = size
            s.width = max(s.width, minFrame.width)
            s.height = max(s.height, minFrame.height)
            let top = w.frame.maxY
            w.setFrame(NSRect(x: w.frame.minX, y: top - s.height, width: s.width, height: s.height), display: true)
        }
    }

    func close() {
        switch self {
        case .ax(let el): WindowControl.close(el)
        case .own(let w): w.performClose(nil)
        }
    }

    func minimize() {
        switch self {
        case .ax(let el): WindowControl.minimize(el)
        case .own(let w): w.miniaturize(nil)
        }
    }
}

/// 通过 Accessibility API 操作其他应用的窗口。需要"辅助功能"权限。
enum WindowControl {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// AppKit 坐标（主屏左下原点）→ AX 坐标（主屏左上原点）。
    static func toAX(_ r: NSRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// 手势的目标窗口：鼠标指针下方的窗口。
    static func targetWindow(at point: CGPoint) -> TargetWindow? {
        let target = windowUnderCursor(at: point)
        // 拖动期间会高频调用 set，缩短超时防止某个应用卡住时拖死主线程。
        if case .ax(let el)? = target { AXUIElementSetMessagingTimeout(el, 0.1) }
        return target
    }

    /// 指针下方的窗口（屏幕坐标，左上原点）。指针下没有普通窗口（桌面、菜单栏、Dock 等）时返回 nil。
    static func windowUnderCursor(at point: CGPoint) -> TargetWindow? {
        // 以窗口服务器的窗口列表为准判断"指针下有没有真实窗口"：只看普通窗口层，排除桌面元素和自己的提示层。
        // 这样在桌面上按下时不会把 Finder 的桌面窗口当成目标。
        guard let top = topmostWindowInfo(at: point) else { return nil }

        // 自己的窗口：直接用 NSWindow。
        if top.pid == ProcessInfo.processInfo.processIdentifier {
            return NSApp.windows.first { $0.windowNumber == top.windowNumber }.map { .own($0) }
        }

        // 1. AX 命中测试：拿到指针下最深的元素，再向上找窗口；必须和窗口列表里的那个窗口吻合。
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        var hit: AXUIElement?
        if AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
           let hit, let win = windowAncestor(of: hit),
           pid(of: win) == top.pid, let f = frame(of: win), approximatelyEqual(f, top.bounds) {
            return .ax(win)
        }

        // 2. 退路：在该应用的 AX 窗口里按 frame 匹配。
        let axApp = AXUIElementCreateApplication(top.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.first { w in frame(of: w).map { approximatelyEqual($0, top.bounds) } ?? false }.map { .ax($0) }
    }

    private struct WindowInfo {
        let pid: pid_t
        let windowNumber: Int
        let bounds: CGRect
    }

    /// 窗口列表中位于 point 之下、最靠前的普通窗口（layer 0）。
    private static func topmostWindowInfo(at point: CGPoint) -> WindowInfo? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        // 自己的提示层在更高的 layer，会被 layer == 0 过滤掉；设置/教学窗口是普通窗口，允许成为目标。
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.contains(point) else { continue }
            return WindowInfo(pid: pid, windowNumber: info[kCGWindowNumber as String] as? Int ?? 0, bounds: bounds)
        }
        return nil
    }

    private static func approximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.origin.x - b.origin.x) < tolerance && abs(a.origin.y - b.origin.y) < tolerance &&
        abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }

    static func pid(of element: AXUIElement) -> pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(element, &p)
        return p
    }

    private static func windowAncestor(of element: AXUIElement) -> AXUIElement? {
        if role(of: element) == kAXWindowRole { return element }
        if let win = copyElement(element, kAXWindowAttribute) { return win }
        var current = element
        for _ in 0..<30 {
            guard let parent = copyElement(current, kAXParentAttribute) else { return nil }
            if role(of: parent) == kAXWindowRole { return parent }
            current = parent
        }
        return nil
    }

    static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func title(of win: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }

    /// 关闭窗口：优先按标题栏的关闭按钮，没有的话退回发送 ⌘W。
    static func close(_ win: AXUIElement) {
        if let btn = copyElement(win, kAXCloseButtonAttribute),
           AXUIElementPerformAction(btn, kAXPressAction as CFString) == .success {
            return
        }
        postCommandW()
    }

    /// 最小化窗口：优先设置 AXMinimized 属性，失败则按标题栏的最小化按钮。
    static func minimize(_ win: AXUIElement) {
        if AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success {
            return
        }
        if let btn = copyElement(win, kAXMinimizeButtonAttribute) {
            AXUIElementPerformAction(btn, kAXPressAction as CFString)
        }
    }

    static func position(of win: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(v, to: AXValue.self)
        var pt = CGPoint.zero
        guard AXValueGetType(axValue) == .cgPoint, AXValueGetValue(axValue, .cgPoint, &pt) else { return nil }
        return pt
    }

    static func size(of win: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(v, to: AXValue.self)
        var sz = CGSize.zero
        guard AXValueGetType(axValue) == .cgSize, AXValueGetValue(axValue, .cgSize, &sz) else { return nil }
        return sz
    }

    /// 窗口在 AX 坐标系（主屏左上角为原点，y 向下）中的 frame。
    static func frame(of win: AXUIElement) -> CGRect? {
        guard let p = position(of: win), let s = size(of: win) else { return nil }
        return CGRect(origin: p, size: s)
    }

    static func setSize(_ win: AXUIElement, _ size: CGSize) {
        var sz = size
        guard let v = AXValueCreate(.cgSize, &sz) else { return }
        AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, v)
    }

    static func setPosition(_ win: AXUIElement, _ pt: CGPoint) {
        var p = pt
        guard let v = AXValueCreate(.cgPoint, &p) else { return }
        AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v)
    }

    // MARK: - helpers

    private static func copyElement(_ parent: AXUIElement, _ attr: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attr as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(v, to: AXUIElement.self)
    }

    private static func postCommandW() {
        let src = CGEventSource(stateID: .hidSystemState)
        let keyW: CGKeyCode = 13
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: keyW, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: keyW, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
