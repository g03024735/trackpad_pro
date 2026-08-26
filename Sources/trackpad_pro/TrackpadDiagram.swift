import SwiftUI

/// 手势区域的统一配色与名称。
enum Zone: CaseIterable, Hashable {
    case close, minimize, move, resize, zoom, switcher

    var color: Color {
        switch self {
        case .close: return .red
        case .minimize: return .orange
        case .move: return .blue
        case .resize: return .green
        case .zoom: return .purple
        case .switcher: return .teal
        }
    }

    var name: String {
        switch self {
        case .close: return tr("关闭", "Close")
        case .minimize: return tr("最小化", "Minimize")
        case .move: return tr("移动", "Move")
        case .resize: return tr("调整大小", "Resize")
        case .zoom: return tr("放大指针", "Zoom cursor")
        case .switcher: return tr("窗口切换", "Switch windows")
        }
    }

    var symbol: String {
        switch self {
        case .close: return "xmark.circle"
        case .minimize: return "arrow.down.right.and.arrow.up.left"
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .resize: return "arrow.up.left.and.arrow.down.right"
        case .zoom: return "cursorarrow.motionlines"
        case .switcher: return "rectangle.stack"
        }
    }

    func isEnabled(in c: Config) -> Bool {
        switch self {
        case .close: return c.closeEnabled
        case .minimize: return c.minimizeEnabled
        case .move: return c.moveEnabled
        case .resize: return c.resizeEnabled
        case .zoom: return c.cursorZoomEnabled
        case .switcher: return c.switcherEnabled
        }
    }

    /// 在单位正方形（原点左上，y 向下）中的区域。
    func rect(in c: Config) -> CGRect {
        let corner = CGFloat(c.cornerSize)
        let top = CGFloat(c.topEdgeHeight)
        switch self {
        case .close:
            return CGRect(x: 0, y: 0, width: CGFloat(c.closeZoneWidth), height: top)
        case .minimize:
            return CGRect(x: CGFloat(c.minimizeZoneStart), y: 0, width: CGFloat(c.minimizeZoneWidth), height: top)
        case .move:
            let start = c.minimizeEnabled ? CGFloat(c.minimizeZoneStart + c.minimizeZoneWidth)
                : (c.closeEnabled ? CGFloat(c.closeZoneWidth) : 0)
            let end = c.resizeEnabled ? 1 - corner : 1
            return CGRect(x: start, y: 0, width: max(0, end - start), height: top)
        case .resize:
            return CGRect(x: 1 - corner, y: 0, width: corner, height: top)
        case .zoom:
            let zoneTop = c.resizeEnabled ? top : 0
            return CGRect(x: 1 - CGFloat(c.rightEdgeWidth), y: zoneTop, width: CGFloat(c.rightEdgeWidth), height: 1 - zoneTop)
        case .switcher:
            let h = CGFloat(c.bottomEdgeHeight)
            let end = c.cursorZoomEnabled ? 1 - CGFloat(c.rightEdgeWidth) : 1
            return CGRect(x: 0, y: 1 - h, width: end, height: h)
        }
    }
}

/// 触摸板示意图：圆角面板 + 各功能区着色 + 可选的手指位置点。
struct TrackpadDiagram: View {
    var config: Config
    /// 归一化手指坐标（x 0~1，y 0 下 ~ 1 上，与触摸板数据一致）。
    var fingers: [CGPoint] = []
    /// 仅突出显示某个区域（其余变淡）。
    var highlight: Zone? = nil
    var showLabels = true

    /// 实体触摸板约 16:11.5。
    static let aspectRatio: CGFloat = 16 / 11.5

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let zones = Zone.allCases.filter { $0.isEnabled(in: config) }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)

                // 实色色块，无边框；按真实判定区域绘制：彼此相邻无间隔，贴满触摸板边缘，
                // 仅靠颜色区分。外缘圆角由整体 clipShape 裁出。
                ForEach(zones, id: \.self) { zone in
                    let f = frame(of: zone, in: size)
                    Rectangle()
                        .fill(zone.color.opacity(highlight == zone ? 0.85 : 0.45))
                        .frame(width: max(0, f.width), height: max(0, f.height))
                        .position(x: f.midX, y: f.midY)
                        .opacity(dimmed(zone) ? 0.22 : 1)
                        .animation(.easeInOut(duration: 0.2), value: highlight)
                }

                if showLabels {
                    ForEach(zones, id: \.self) { zone in
                        let f = frame(of: zone, in: size)
                        if f.width > 44, f.height > 20 {
                            Text(zone.name)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .position(x: f.midX, y: f.midY)
                                .opacity(dimmed(zone) ? 0.3 : 1)
                        }
                    }
                }

                ForEach(Array(fingers.enumerated()), id: \.offset) { _, p in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .position(x: p.x * size.width, y: (1 - p.y) * size.height)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
    }

    private func dimmed(_ zone: Zone) -> Bool { highlight != nil && highlight != zone }

    private func frame(of zone: Zone, in size: CGSize) -> CGRect {
        let r = zone.rect(in: config)
        return CGRect(
            x: r.minX * size.width,
            y: r.minY * size.height,
            width: r.width * size.width,
            height: r.height * size.height
        )
    }
}

/// 把触摸板数据线程上的手指位置以 ≤30Hz 发布到主线程，供 UI 显示。
final class FingerPublisher: ObservableObject {
    static let shared = FingerPublisher()
    @Published var fingers: [CGPoint] = []

    private var lastPublish: TimeInterval = 0
    private var subscribers = 0

    /// UI 出现时调用；没有订阅者时不做任何事。
    func attach() { subscribers += 1 }
    func detach() { subscribers = max(0, subscribers - 1); if subscribers == 0 { fingers = [] } }

    func push(_ fingers: [Finger]) {
        guard subscribers > 0 else { return }
        let now = Date().timeIntervalSince1970
        guard now - lastPublish > 1.0 / 30 else { return }
        lastPublish = now
        let points = fingers.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        DispatchQueue.main.async { self.fingers = points }
    }
}
