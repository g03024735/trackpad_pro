import AppKit
import SwiftUI

// MARK: - 设置界面

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var fingers: FingerPublisher
    @State private var launchAtLogin: Bool
    /// 鼠标悬停的手势行，示意图中对应热区高亮。
    @State private var hovered: Zone?

    init(store: SettingsStore, fingers: FingerPublisher) {
        self.store = store
        self.fingers = fingers
        _launchAtLogin = State(initialValue: store.launchAtLogin)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部：示意图 + 自定义提示。
            VStack(spacing: 8) {
                TrackpadDiagram(config: store.config, fingers: fingers.fingers, highlight: hovered)
                    .overlay(ZoneHandles(store: store))
                    .frame(height: 180)
                HStack(spacing: 5) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text(tr("拖动白色手柄可调整热区大小", "Drag the white handles to resize zones"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()

            // 经典表单：右对齐标签列 + 控件列。
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 12) {
                GridRow {
                    Text(tr("手势:", "Gestures:"))
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 16) {
                            gestureCheckbox(.close, isOn: $store.config.closeEnabled)
                            gestureCheckbox(.minimize, isOn: $store.config.minimizeEnabled)
                            gestureCheckbox(.move, isOn: $store.config.moveEnabled)
                        }
                        HStack(spacing: 16) {
                            gestureCheckbox(.resize, isOn: $store.config.resizeEnabled)
                            gestureCheckbox(.zoom, isOn: $store.config.cursorZoomEnabled)
                            gestureCheckbox(.switcher, isOn: $store.config.switcherEnabled)
                        }
                    }
                }
                GridRow {
                    Text(tr("切换方向:", "Switch direction:"))
                        .gridColumnAlignment(.trailing)
                    Picker("", selection: $store.config.switcherRightToNext) {
                        Text(tr("向右滑切换下一个窗口", "Swipe right for next window")).tag(true)
                        Text(tr("向左滑切换下一个窗口", "Swipe left for next window")).tag(false)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!store.config.switcherEnabled)
                    .opacity(store.config.switcherEnabled ? 1 : 0.5)
                }
                GridRow {
                    Text(tr("指针跟随:", "Pointer follow:"))
                        .gridColumnAlignment(.trailing)
                    Toggle(tr("切换后把指针移到所选窗口", "Move the pointer to the picked window"),
                           isOn: $store.config.switcherMovesPointer)
                        .toggleStyle(.checkbox)
                        .disabled(!store.config.switcherEnabled)
                        .opacity(store.config.switcherEnabled ? 1 : 0.5)
                }
                GridRow {
                    Text(tr("指针放大倍率:", "Cursor zoom:"))
                        .gridColumnAlignment(.trailing)
                    HStack(spacing: 8) {
                        Slider(value: Binding(
                            get: { store.config.cursorZoomScale },
                            set: { store.config.cursorZoomScale = (($0 * 2).rounded()) / 2 }
                        ), in: 1.5...4)
                            .frame(width: 180)
                        Text(String(format: "%.1f×", store.config.cursorZoomScale))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    .disabled(!store.config.cursorZoomEnabled)
                    .opacity(store.config.cursorZoomEnabled ? 1 : 0.5)
                }
                GridRow {
                    Text(tr("启动:", "Startup:"))
                        .gridColumnAlignment(.trailing)
                    Toggle(tr("开机自动启动", "Launch at login"), isOn: $launchAtLogin)
                        .toggleStyle(.checkbox)
                        .disabled(!store.canLaunchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in
                            store.launchAtLogin = newValue
                            launchAtLogin = store.launchAtLogin
                        }
                }
                GridRow {
                    Text(tr("引导教学:", "Tutorial:"))
                        .gridColumnAlignment(.trailing)
                    Button(tr("重新观看", "Show again")) { OnboardingWindowController.shared.show() }
                }
            }
            .padding(.leading, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)

            Spacer(minLength: 0)
        }
        .onAppear { fingers.attach() }
        .onDisappear { fingers.detach() }
    }

    /// 手势复选框；悬停时示意图对应热区高亮。
    private func gestureCheckbox(_ zone: Zone, isOn: Binding<Bool>) -> some View {
        Toggle(zone.name, isOn: isOn)
            .toggleStyle(.checkbox)
            .onHover { hovered = $0 ? zone : nil }
    }
}

// MARK: - 预览图上的尺寸拖柄

/// 把热区尺寸调整直接做在示意图上：每个可调边界一个拖柄，拖动实时生效，拖动中显示当前值。
private struct ZoneHandles: View {
    @ObservedObject var store: SettingsStore
    @State private var dragLabel: (text: String, x: CGFloat, y: CGFloat)?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let c = store.config
            let bandMidY = CGFloat(c.topEdgeHeight) * h / 2

            ZStack(alignment: .topLeading) {
                if c.closeEnabled {
                    handle(vertical: true, help: tr("拖动调整关闭热区宽度", "Drag to adjust the close zone width"))
                        .position(x: CGFloat(c.closeZoneWidth) * w, y: bandMidY)
                        .gesture(drag { v in
                            let nv = Self.clamp(Float(v.location.x / w), 0.05...0.30)
                            store.config.closeZoneWidth = nv
                            dragLabel = (Self.pct(nv), CGFloat(nv) * w, bandMidY)
                        })
                }
                if c.minimizeEnabled {
                    let start = CGFloat(c.minimizeZoneStart)
                    handle(vertical: true, help: tr("拖动调整最小化热区宽度", "Drag to adjust the minimize zone width"))
                        .position(x: (start + CGFloat(c.minimizeZoneWidth)) * w, y: bandMidY)
                        .gesture(drag { v in
                            let nv = Self.clamp(Float(v.location.x / w - start), 0.05...0.30)
                            store.config.minimizeZoneWidth = nv
                            dragLabel = (Self.pct(nv), (start + CGFloat(nv)) * w, bandMidY)
                        })
                }
                if c.resizeEnabled {
                    handle(vertical: true, help: tr("拖动调整「调整大小」热区宽度", "Drag to adjust the resize zone width"))
                        .position(x: (1 - CGFloat(c.cornerSize)) * w, y: bandMidY)
                        .gesture(drag { v in
                            let nv = Self.clamp(1 - Float(v.location.x / w), 0.08...0.30)
                            store.config.cornerSize = nv
                            dragLabel = (Self.pct(nv), (1 - CGFloat(nv)) * w, bandMidY)
                        })
                }
                if c.cursorZoomEnabled {
                    let midY = (CGFloat(c.topEdgeHeight) + 1) / 2
                    handle(vertical: true, help: tr("拖动调整右边缘触发区宽度", "Drag to adjust the right-edge zone width"))
                        .position(x: (1 - CGFloat(c.rightEdgeWidth)) * w, y: midY * h)
                        .gesture(drag { v in
                            let nv = Self.clamp(1 - Float(v.location.x / w), 0.03...0.15)
                            store.config.rightEdgeWidth = nv
                            dragLabel = (Self.pct(nv), (1 - CGFloat(nv)) * w, midY * h)
                        })
                }
                if c.moveEnabled {
                    let midX = Zone.move.rect(in: c).midX
                    handle(vertical: false, help: tr("拖动调整上沿热区高度", "Drag to adjust the top strip height"))
                        .position(x: midX * w, y: CGFloat(c.topEdgeHeight) * h)
                        .gesture(drag { v in
                            let nv = Self.clamp(Float(v.location.y / h), 0.05...0.25)
                            store.config.topEdgeHeight = nv
                            dragLabel = (Self.pct(nv), midX * w, CGFloat(nv) * h)
                        })
                }
                if c.switcherEnabled {
                    let midX = Zone.switcher.rect(in: c).midX
                    handle(vertical: false, help: tr("拖动调整下沿热区高度", "Drag to adjust the bottom strip height"))
                        .position(x: midX * w, y: (1 - CGFloat(c.bottomEdgeHeight)) * h)
                        .gesture(drag { v in
                            let nv = Self.clamp(1 - Float(v.location.y / h), 0.05...0.15)
                            store.config.bottomEdgeHeight = nv
                            dragLabel = (Self.pct(nv), midX * w, (1 - CGFloat(nv)) * h)
                        })
                }

                if let dragLabel {
                    Text(dragLabel.text)
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                        .position(x: dragLabel.x, y: dragLabel.y + 24)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func drag(_ onChanged: @escaping (DragGesture.Value) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged(onChanged)
            .onEnded { _ in dragLabel = nil }
    }

    /// 白色小拖柄；透明外框扩大点按范围。
    private func handle(vertical: Bool, help: String) -> some View {
        Color.clear
            .frame(width: vertical ? 16 : 26, height: vertical ? 26 : 16)
            .overlay(
                Capsule()
                    .fill(.white)
                    .frame(width: vertical ? 5 : 16, height: vertical ? 16 : 5)
                    .overlay(Capsule().strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
            )
            .contentShape(Rectangle())
            .help(help)
            .onHover { inside in
                if inside {
                    (vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private static func clamp(_ v: Float, _ r: ClosedRange<Float>) -> Float {
        min(max((v * 100).rounded() / 100, r.lowerBound), r.upperBound)
    }

    private static func pct(_ v: Float) -> String {
        "\(Int((v * 100).rounded()))%"
    }
}

// MARK: - 窗口

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let view = SettingsView(store: SettingsStore.shared, fingers: FingerPublisher.shared)
            let hosting = NSHostingView(rootView: view)
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 470, height: 430),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = tr("trackpad_pro 设置", "trackpad_pro Settings")
            win.contentView = hosting
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        if let window { activateAndFront(window) }
    }
}
