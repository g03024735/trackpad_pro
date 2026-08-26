import AppKit
import ApplicationServices
import QuartzCore
import SwiftUI

/// 下沿左右滑动切换窗口：起手激活后，按滑动距离在窗口层叠列表里滚动，
/// 每跨过一格就把对应窗口带到前台预览；抬起手指即选定当前前台窗口。
/// 屏幕下方同时显示 ⌘Tab 式指示条。update(_:) 在触摸数据线程调用，
/// 涉及 AppKit/AX 的操作都切回主线程。
final class WindowSwitcher {
    var enabled = true
    /// 下沿判定带高度（占触摸板比例）。
    var bandHeight: Float = 0.12
    /// 每滑动多少（归一化距离）切换一个窗口。
    var stepDistance: Float = 0.055
    /// 右侧排除宽度：右下角让给放大指针的边缘条。
    var rightExclusion: Float = 0.06
    /// 向右滑动切换到下一个（更靠后的）窗口；false 则向左滑。
    var rightToNext = true
    /// 选定窗口后把指针移到该窗口中心（指针已在窗口内则不动）。
    var movesPointer = true
    var debug = false

    struct WindowRef {
        let pid: pid_t
        let windowNumber: Int
        let bounds: CGRect
        let title: String
    }

    private enum State {
        case idle
        /// 手指在下沿带内起手，尚未超过激活距离。
        case tracking(id: Int32, startX: Float)
        case active
    }

    /// 激活中的滑动会话。
    private struct ActiveSession {
        let id: Int32
        let windows: [WindowRef]
        var index: Int
        /// 经速度增益累计的滑动进度（归一化距离），0 对应最前窗口。
        var progress: Float
        var lastX: Float
        var lastT: TimeInterval
    }

    private var state: State = .idle
    private var session: ActiveSession?

    /// 每根手指首次接触时的落点：只有“直接落在下沿”的手指才能起手，
    /// 从触摸板其他位置滑进下沿的手指是在正常移动指针，不触发切换。
    private var startPositions: [Int32: (x: Float, y: Float)] = [:]

    // 置前节流：滑得快时合并中间目标，按固定节奏只置前最新的，减少窗口猛跳。
    private var pendingRaise: WindowRef?
    private var raiseScheduled = false
    private var lastRaiseAt: CFTimeInterval = 0

    func update(_ fingers: [Finger]) {
        // 记录新手指的落点，清理已抬起的。
        let ids = Set(fingers.map { $0.id })
        for f in fingers where startPositions[f.id] == nil {
            startPositions[f.id] = (f.x, f.y)
        }
        startPositions = startPositions.filter { ids.contains($0.key) }

        guard enabled else { cancel(); return }
        // 鼠标按着（真实点击/拖拽）时不起手。只挡未激活阶段：
        // 已激活后滑动稍用力就可能压出物理点击，不能因此中断手势。
        let buttonDown = CGEventSource.buttonState(.combinedSessionState, button: .left)

        switch state {
        case .idle:
            guard !buttonDown else { return }
            // 候选起手：恰好一根手指在下沿带内，且它的落点也在带内（不含右缘条）——
            // 从别处滑进来的手指不算；搭在触摸板其他位置的手指不影响判定。
            let candidates = fingers.filter { f in
                guard let start = startPositions[f.id] else { return false }
                return f.y < bandHeight && start.y < bandHeight && start.x < 1 - rightExclusion
            }
            guard candidates.count == 1, let f = candidates.first else { return }
            state = .tracking(id: f.id, startX: f.x)

        case .tracking(let id, let startX):
            guard !buttonDown else { state = .idle; return }
            guard let f = fingers.first(where: { $0.id == id }), f.y < bandHeight * 2 else {
                state = .idle
                return
            }
            // 第二根手指进入下沿带（例如双指滚动）则放弃。
            if fingers.contains(where: { $0.id != id && $0.y < bandHeight * 1.5 }) {
                state = .idle
                return
            }
            guard abs(f.x - startX) > 0.03 else { return }
            let windows = Self.snapshotWindows()
            guard windows.count > 1 else { state = .idle; return }
            if debug { print("[switcher] 激活，可切换窗口 \(windows.count) 个") }
            session = ActiveSession(id: id, windows: windows, index: 0, progress: 0, lastX: f.x, lastT: f.timestamp)
            state = .active
            DispatchQueue.main.async { SwitcherHUD.shared.show(windows: windows) }

        case .active:
            guard var s = session else { state = .idle; return }
            // 起手手指抬起：结束，保持当前前台。其他手指的出现不打断。
            guard let f = fingers.first(where: { $0.id == s.id }) else {
                endActive()
                return
            }
            // 滑出下沿带太多视为结束（当前前台保持不变）。
            guard f.y < bandHeight * 2.5 else {
                endActive()
                return
            }

            // 速度增益：慢滑 1 倍精确逐格；快滑增益最高 4 倍，一次能扫过更多窗口。
            // 进度在两端截停，到头后反向滑立即响应。
            let dx = f.x - s.lastX
            let dt = Float(max(f.timestamp - s.lastT, 0.001))
            let speed = abs(dx) / dt  // 归一化宽度 / 秒
            let gain = min(1 + max(0, speed - 0.25) * 1.6, 4)
            let signed = (rightToNext ? dx : -dx) * gain
            let maxProgress = Float(s.windows.count - 1) * stepDistance
            s.progress = min(max(s.progress + signed, 0), maxProgress)
            s.lastX = f.x
            s.lastT = f.timestamp

            let newIndex = Int((s.progress / stepDistance).rounded())
            if newIndex != s.index {
                s.index = newIndex
                if debug { print("[switcher] 预览第 \(newIndex + 1)/\(s.windows.count) 个窗口") }
                DispatchQueue.main.async { SwitcherHUD.shared.select(newIndex) }
                requestRaise(s.windows[newIndex])
            }
            session = s
        }
    }

    private func cancel() {
        if case .active = state { endActive() } else { state = .idle }
    }

    private func endActive() {
        if let s = session {
            if debug { print("[switcher] 结束，停在第 \(s.index + 1)/\(s.windows.count) 个窗口") }
            // 真的切换了窗口才移指针；停在原前台（index 0）不动。
            if movesPointer, s.index > 0 {
                movePointer(toCenterOf: s.windows[s.index].bounds)
            }
        }
        session = nil
        state = .idle
        DispatchQueue.main.async { SwitcherHUD.shared.hideSoon() }
    }

    /// 把指针统一移到所选窗口正中，并脉冲一下反馈切换完成。
    private func movePointer(toCenterOf bounds: CGRect) {
        DispatchQueue.main.async {
            let target = CGPoint(x: bounds.midX, y: bounds.midY)
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                    mouseCursorPosition: target, mouseButton: .left)?.post(tap: .cghidEventTap)
            CursorZoom.shared.pulse()
        }
    }

    /// 层叠顺序（前台在先）的普通窗口快照。
    private static func snapshotWindows() -> [WindowRef] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var refs: [WindowRef] = []
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let num = info[kCGWindowNumber as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 120, bounds.height >= 80  // 过滤小浮窗
            else { continue }
            let title = (info[kCGWindowName as String] as? String) ?? ""
            refs.append(WindowRef(pid: pid, windowNumber: num, bounds: bounds, title: title))
            if refs.count >= 20 { break }
        }
        return refs
    }

    // MARK: - 置前（主线程，带节流）

    private func requestRaise(_ ref: WindowRef) {
        DispatchQueue.main.async {
            self.pendingRaise = ref
            self.flushRaise()
        }
    }

    private func flushRaise() {
        guard let ref = pendingRaise else { return }
        let interval: CFTimeInterval = 0.08
        let now = CACurrentMediaTime()
        if now - lastRaiseAt < interval {
            if !raiseScheduled {
                raiseScheduled = true
                DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
                    self?.raiseScheduled = false
                    self?.flushRaise()
                }
            }
            return
        }
        lastRaiseAt = now
        pendingRaise = nil
        performRaise(ref)
    }

    private func performRaise(_ ref: WindowRef) {
        // 教学窗口打开时不切前台，避免把教学窗盖掉。
        if OnboardingWindowController.shared.isTeaching { return }

        if ref.pid == ProcessInfo.processInfo.processIdentifier {
            NSApp.windows.first { $0.windowNumber == ref.windowNumber }?.orderFrontRegardless()
            return
        }
        NSRunningApplication(processIdentifier: ref.pid)?.activate()
        let axApp = AXUIElementCreateApplication(ref.pid)
        AXUIElementSetMessagingTimeout(axApp, 0.1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        let target = windows.first { w in
            guard let f = WindowControl.frame(of: w) else { return false }
            return abs(f.origin.x - ref.bounds.origin.x) < 2 && abs(f.origin.y - ref.bounds.origin.y) < 2
                && abs(f.width - ref.bounds.width) < 2 && abs(f.height - ref.bounds.height) < 2
        }
        if let target {
            AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        }
    }
}

// MARK: - 切换指示条

/// ⌘Tab 式浮动指示条：应用图标一排，高亮块随选择平滑滑动，下方显示当前窗口标题。
/// 仅主线程访问。
final class SwitcherHUD: ObservableObject {
    static let shared = SwitcherHUD()

    struct Item {
        let icon: NSImage?
        let title: String
    }

    @Published var items: [Item] = []
    @Published var index = 0

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(windows: [WindowSwitcher.WindowRef]) {
        hideWork?.cancel()
        hideWork = nil
        items = windows.map { ref in
            let app = NSRunningApplication(processIdentifier: ref.pid)
            let title = ref.title.isEmpty ? (app?.localizedName ?? "") : ref.title
            return Item(icon: app?.icon, title: title)
        }
        index = 0
        presentPanel()
    }

    func select(_ i: Int) {
        index = i
    }

    func hideSoon() {
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func presentPanel() {
        panel?.orderOut(nil)
        panel = nil

        let hosting = NSHostingView(rootView: SwitcherHUDView(model: self))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let p = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        // 系统窗口投影会给半透明浮窗描一圈亮色轮廓线，阴影改在 SwiftUI 里画。
        p.hasShadow = false
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .transient]
        p.contentView = hosting
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.midX - hosting.frame.width / 2, y: f.minY + 120))
        }
        p.alphaValue = 0
        p.orderFrontRegardless()
        panel = p
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 1
        }
    }

    private func dismiss() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            p.animator().alphaValue = 0
        }, completionHandler: {
            p.orderOut(nil)
            if self.panel === p { self.panel = nil }
        })
    }
}

private struct SwitcherHUDView: View {
    @ObservedObject var model: SwitcherHUD
    @Namespace private var selectionNS

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                ForEach(Array(model.items.enumerated()), id: \.offset) { i, item in
                    ZStack {
                        if i == model.index {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color.black.opacity(0.14))
                                .matchedGeometryEffect(id: "selection", in: selectionNS)
                        }
                        if let icon = item.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .frame(width: 58, height: 58)
                    .scaleEffect(i == model.index ? 1.12 : 1)
                }
            }
            Text(model.items.indices.contains(model.index) ? model.items[model.index].title : " ")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 360)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        // 浅色半透明底：可透视后方窗口；柔和扩散阴影，无轮廓线。
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.5))
                .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
        )
        .padding(26)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: model.index)
    }
}
