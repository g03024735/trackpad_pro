import AppKit
import SwiftUI

// MARK: - 步骤

enum OnboardingStep: Int, CaseIterable {
    case welcome, move, resize, zoom, minimize, close

    var title: String {
        switch self {
        case .welcome: return tr("欢迎使用 trackpad_pro", "Welcome to trackpad_pro")
        case .move: return tr("移动窗口", "Move a Window")
        case .resize: return tr("调整窗口大小", "Resize a Window")
        case .zoom: return tr("找不到指针？放大它", "Lost the Pointer? Zoom It")
        case .minimize: return tr("最小化窗口", "Minimize a Window")
        case .close: return tr("恭喜，只差最后一步 🎉", "One Last Step 🎉")
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: return tr("接下来用这个窗口亲手试一遍，每步做对会自动进入下一步。",
                                 "Try each gesture on this very window — each step advances automatically once you get it right.")
        case .move: return tr("把指针放在这个窗口上，在触摸板上沿按下并拖动。",
                              "Put the pointer over this window, then press and drag along the top edge of the trackpad.")
        case .resize: return tr("把指针放在这个窗口上，在触摸板右上角按下并拖动。",
                                "Put the pointer over this window, then press and drag in the top-right corner of the trackpad.")
        case .zoom: return tr("单指从触摸板右边缘向内滑动，指针会放大；抬起手指即还原。",
                              "Swipe inward from the right edge of the trackpad with one finger; lift to restore.")
        case .minimize: return tr("把指针放在这个窗口上，在触摸板上沿左侧第二格按下、松开。\n窗口会收进 Dock，然后自己回来。",
                                  "Put the pointer over this window, then press and release the second zone from the top-left.\nThe window drops into the Dock — and comes right back.")
        case .close: return tr("前面的手势你都掌握了！把指针放在这个窗口上，\n在触摸板左上角按下、松开，关掉它——教学到此完成。",
                               "You've mastered every gesture! Put the pointer over this window,\nthen press and release the top-left corner to close it — that completes the tutorial.")
        }
    }

    var zone: Zone? {
        switch self {
        case .welcome: return nil
        case .move: return .move
        case .resize: return .resize
        case .zoom: return .zoom
        case .minimize: return .minimize
        case .close: return .close
        }
    }

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
}

// MARK: - 模型

final class OnboardingModel: ObservableObject {
    @Published var step: OnboardingStep = .welcome
    @Published var completed: Set<OnboardingStep> = []

    weak var window: NSWindow?
    private var observer: NSObjectProtocol?

    func start() {
        stop()
        step = .welcome
        completed = []
        observer = NotificationCenter.default.addObserver(forName: .gesturePerformed, object: nil, queue: .main) { [weak self] n in
            guard let self, let (kind, pid) = GestureEvents.parse(n) else { return }
            self.handle(kind: kind, pid: pid)
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func handle(kind: GestureKind, pid: pid_t?) {
        let mine = pid == ProcessInfo.processInfo.processIdentifier
        print("[教学] 手势事件 \(kind.rawValue) pid=\(pid.map(String.init) ?? "nil") mine=\(mine) step=\(step)")
        switch (kind, step) {
        case (.move, .move) where mine:
            complete(.move)
        case (.resize, .resize) where mine:
            complete(.resize)
        case (.zoom, .zoom):
            complete(.zoom)
        case (.minimize, _) where mine:
            // 无论在哪一步，被最小化后都自己回来，用户不会"丢失"教学窗口。
            let isTargetStep = step == .minimize
            if isTargetStep { completed.insert(.minimize) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, let window = self.window else { return }
                self.restoreFromDock(window, attempt: 1)
                if isTargetStep { self.advanceLater(from: .minimize) }
            }
        case (.close, .close) where mine:
            completed.insert(.close)
        default:
            break
        }
    }

    /// 从 Dock 还原教学窗口。个别系统版本上 deminiaturize 偶尔不生效，失败则重试（最多 3 次）。
    private func restoreFromDock(_ window: NSWindow, attempt: Int) {
        print("[教学] 还原窗口 第\(attempt)次 miniaturized=\(window.isMiniaturized) visible=\(window.isVisible)")
        NSApp.activate(ignoringOtherApps: true)
        window.deminiaturize(nil)
        activateAndFront(window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            if window.isMiniaturized || !window.isVisible {
                if attempt < 3 {
                    self.restoreFromDock(window, attempt: attempt + 1)
                } else {
                    print("[教学] 还原失败 miniaturized=\(window.isMiniaturized) visible=\(window.isVisible)")
                }
            }
        }
    }

    private func complete(_ s: OnboardingStep) {
        guard !completed.contains(s) else { return }
        completed.insert(s)
        advanceLater(from: s)
    }

    private func advanceLater(from s: OnboardingStep) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, self.step == s else { return }
            self.advance()
        }
    }

    func advance() {
        if let next = step.next {
            withAnimation(.easeInOut(duration: 0.25)) { step = next }
        }
    }
}

// MARK: - 界面

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var store: SettingsStore
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(model.step.title)
                    .font(.system(size: 22, weight: .bold))
                Text(model.step.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 38, alignment: .top)
            }
            .padding(.top, 34)
            .padding(.horizontal, 40)

            Group {
                if let zone = model.step.zone {
                    GestureDemoView(zone: zone, config: store.config)
                } else {
                    TrackpadDiagram(config: store.config)
                        .frame(height: 170)
                }
            }
            .frame(height: 190)
            .padding(.top, 22)
            .id(model.step)
            .transition(.opacity)

            Spacer(minLength: 0)

            HStack {
                stepDots
                Spacer()
                if model.step != .welcome && model.step != .close {
                    Button(tr("跳过", "Skip")) { model.advance() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .keyboardShortcut(.rightArrow, modifiers: .command)
                }
                primaryButton
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(minWidth: 560, maxWidth: .infinity, minHeight: 470, maxHeight: .infinity)
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                if model.step == .close { ConfettiView() }
            }
        }
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { s in
                Circle()
                    .fill(s == model.step ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: 7, height: 7)
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch model.step {
        case .welcome:
            Button(tr("开始", "Start")) { model.advance() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        case .close:
            Button(tr("跳过，直接完成", "Skip and finish")) { onFinish() }
                .buttonStyle(.bordered)
        default:
            EmptyView()
        }
    }
}

// MARK: - 手势动画

/// 左：触摸板上的手指动画；右：屏幕上的效果动画。按时间循环播放。
struct GestureDemoView: View {
    let zone: Zone
    let config: Config

    private static let cycle: Double = 2.8

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.cycle) / Self.cycle
            HStack(spacing: 28) {
                ZStack {
                    TrackpadDiagram(config: config, highlight: zone, showLabels: false)
                    FingerOverlay(zone: zone, config: config, t: t)
                }
                .frame(width: 250)
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tertiary)
                ScreenMock(zone: zone, t: t)
                    .frame(width: 170, height: 120)
            }
        }
    }
}

private func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double {
    min(1, max(0, (t - a) / (b - a)))
}

private func easeInOut(_ x: Double) -> Double {
    x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
}

/// 触摸板上的手指：触摸为实心点，按下时多一圈扩散环。
private struct FingerOverlay: View {
    let zone: Zone
    let config: Config
    let t: Double

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let (pos, touching, pressing) = state()
            let x = pos.x * size.width
            let y = (1 - pos.y) * size.height
            let fade = min(ramp(t, 0.02, 0.12), 1 - ramp(t, 0.86, 0.96))
            ZStack {
                if pressing > 0 {
                    Circle()
                        .stroke(zone.color.opacity(0.8 * (1 - pressing)), lineWidth: 2)
                        .frame(width: 18 + 26 * pressing, height: 18 + 26 * pressing)
                        .position(x: x, y: y)
                }
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .position(x: x, y: y)
                    .opacity(touching ? fade : 0)
            }
        }
    }

    /// 返回：归一化位置（y 向上）、是否接触、按下环进度(0 无)。
    private func state() -> (CGPoint, Bool, Double) {
        let topEdge = Double(config.topEdgeHeight)
        switch zone {
        case .move:
            let r = Zone.move.rect(in: config)
            let x = Double(r.midX) + 0.22 * easeInOut(ramp(t, 0.3, 0.7))
            return (CGPoint(x: x, y: 1 - topEdge / 2), true, pressRing(down: 0.18, up: 0.76))
        case .zoom:
            let x = 0.985 - 0.38 * easeInOut(ramp(t, 0.2, 0.7))
            return (CGPoint(x: x, y: 0.5), true, 0)
        case .minimize:
            let r = Zone.minimize.rect(in: config)
            return (CGPoint(x: r.midX, y: 1 - topEdge / 2), t < 0.62, pressRing(down: 0.25, up: 0.55))
        case .close:
            let r = Zone.close.rect(in: config)
            return (CGPoint(x: r.midX, y: 1 - topEdge / 2), t < 0.62, pressRing(down: 0.25, up: 0.55))
        case .resize:
            let x = 1 - Double(config.cornerSize) / 2 + 0.1 * easeInOut(ramp(t, 0.3, 0.7))
            return (CGPoint(x: x, y: 1 - topEdge / 2), true, pressRing(down: 0.18, up: 0.76))
        }
    }

    /// 按下瞬间的扩散环：down 时刻开始 0.3 秒内从 0 → 1。
    private func pressRing(down: Double, up: Double) -> Double {
        let p = ramp(t, down, down + 0.12)
        return p >= 1 ? 0 : p
    }
}

/// 屏幕效果：一个小窗口（移动/最小化/关闭）或指针（放大）。
private struct ScreenMock: View {
    let zone: Zone
    let t: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            // Dock 底线
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(0.12))
                .frame(width: 90, height: 5)
                .offset(y: 48)

            switch zone {
            case .zoom:
                let s = 1 + 1.3 * easeInOut(ramp(t, 0.35, 0.6)) * (1 - ramp(t, 0.9, 0.98))
                Image(systemName: "cursorarrow")
                    .font(.system(size: 22, weight: .medium))
                    .scaleEffect(s, anchor: .topLeading)
                    .offset(x: -6, y: -8)
            case .move:
                let dx = 36 * easeInOut(ramp(t, 0.3, 0.7))
                MiniWindow(color: zone.color).offset(x: -18 + dx, y: -4)
            case .minimize:
                let p = easeInOut(ramp(t, 0.58, 0.88))
                MiniWindow(color: zone.color)
                    .scaleEffect(1 - 0.85 * p, anchor: .bottom)
                    .offset(y: -4 + 42 * p)
                    .opacity(1 - 0.7 * p)
            case .close:
                let p = easeInOut(ramp(t, 0.58, 0.8))
                MiniWindow(color: zone.color)
                    .scaleEffect(1 - 0.15 * p)
                    .opacity(1 - p)
                    .offset(y: -4)
            case .resize:
                let p = easeInOut(ramp(t, 0.3, 0.7))
                MiniWindow(color: zone.color, width: 84 + 30 * p, height: 54 + 18 * p).offset(y: -4)
            }
        }
    }
}

private struct MiniWindow: View {
    let color: Color
    var width: CGFloat = 92
    var height: CGFloat = 58

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(color.opacity(0.9), lineWidth: 2)
            HStack(spacing: 4) {
                Circle().fill(.red).frame(width: 6, height: 6)
                Circle().fill(.yellow).frame(width: 6, height: 6)
                Circle().fill(.green).frame(width: 6, height: 6)
            }
            .padding(7)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: width * (i == 1 ? 0.45 : 0.65), height: 5)
                }
            }
            .padding(.top, 22)
            .padding(.leading, 10)
        }
        .frame(width: width, height: height)
    }
}

// MARK: - 窗口

final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?
    private let model = OnboardingModel()

    /// 教学窗口是否打开（含教学过程中被最小化、等待还原的间隙）。
    var isTeaching: Bool {
        guard let window else { return false }
        return window.isVisible || window.isMiniaturized
    }

    func show() {
        if window == nil {
            let view = OnboardingView(model: model, store: SettingsStore.shared) { [weak self] in
                self?.window?.close()
            }
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.contentMinSize = NSSize(width: 560, height: 470)
            win.title = tr("trackpad_pro 引导教学", "trackpad_pro Tutorial")
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.contentView = NSHostingView(rootView: view)
            win.isReleasedWhenClosed = false
            win.isMovableByWindowBackground = true
            win.delegate = self
            win.center()
            window = win
            model.window = win
        }
        model.start()
        if let window { activateAndFront(window) }
    }

    func windowWillClose(_ notification: Notification) {
        print("[教学] 窗口关闭 step=\(model.step) completedClose=\(model.completed.contains(.close))")
        model.stop()
        SettingsStore.shared.config.hasCompletedOnboarding = true
    }
}

// MARK: - 彩带

/// 最后一步的庆祝氛围：彩色小纸片在窗口内缓缓飘落。位置由索引伪随机生成，循环播放。
private struct ConfettiView: View {
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]
                for i in 0..<26 {
                    let seed = Double(i)
                    let speed = 26 + 20 * pseudo(seed, 1)
                    let x = pseudo(seed, 2) * size.width + 16 * sin(t * (0.7 + pseudo(seed, 3)) + seed)
                    let y = (t * speed + pseudo(seed, 4) * (size.height + 24)).truncatingRemainder(dividingBy: size.height + 24) - 12
                    let w = 5 + 3 * pseudo(seed, 5)
                    let h = 3 + 2 * pseudo(seed, 6)
                    var c = canvas
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(t * (0.8 + pseudo(seed, 7)) + seed))
                    c.opacity = 0.5
                    c.fill(Path(CGRect(x: -w / 2, y: -h / 2, width: w, height: h)), with: .color(colors[i % colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// [0,1) 的确定性伪随机数：同一索引每帧结果一致，动画才连贯。
    private func pseudo(_ seed: Double, _ salt: Double) -> Double {
        let v = sin(seed * 127.1 + salt * 311.7) * 43758.5453
        return v - v.rounded(.down)
    }
}
