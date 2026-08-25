import AppKit

/// 覆盖在目标窗口上的高亮反馈层：彩色描边 + 顶部提示文字。不响应鼠标，不抢焦点。
final class FeedbackOverlay {
    static let shared = FeedbackOverlay()

    enum Style {
        case close     // 待关闭：红色
        case minimize  // 待最小化：橙黄色
        case drag      // 拖动中：蓝色
        case resize    // 调整大小：绿色

        var color: NSColor {
            switch self {
            case .close: return .systemRed
            case .minimize: return .systemOrange
            case .drag: return .systemBlue
            case .resize: return .systemGreen
            }
        }

        var text: String {
            switch self {
            case .close: return tr("松开关闭窗口 · 移动手指取消", "Release to close · move finger to cancel")
            case .minimize: return tr("松开最小化窗口 · 移动手指取消", "Release to minimize · move finger to cancel")
            case .drag: return tr("正在拖动窗口", "Moving window")
            case .resize: return tr("正在调整窗口大小", "Resizing window")
            }
        }
    }

    private let window: NSWindow
    private let view: OverlayView

    private init() {
        view = OverlayView(frame: .zero)
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView = view
        window.alphaValue = 0
    }

    /// axFrame: Accessibility 坐标系（原点在主屏左上角，y 向下）。
    func show(axFrame: CGRect, style: Style) {
        view.style = style
        window.setFrame(Self.toAppKit(axFrame), display: true)
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            window.animator().alphaValue = 1
        }
    }

    func move(axFrame: CGRect) {
        window.setFrame(Self.toAppKit(axFrame), display: true)
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            window.animator().alphaValue = 0
        }, completionHandler: { [window] in
            if window.alphaValue == 0 { window.orderOut(nil) }
        })
    }

    /// 离屏渲染一张预览图（仅用于开发时检查外观）。
    func renderPreview(style: Style, size: CGSize, to path: String) {
        let v = OverlayView(frame: CGRect(origin: .zero, size: size))
        v.style = style
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    /// AX 坐标（左上原点）→ AppKit 坐标（主屏左下原点）。
    private static func toAppKit(_ r: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: r.origin.x, y: primaryHeight - r.origin.y - r.height, width: r.width, height: r.height)
    }
}

private final class OverlayView: NSView {
    var style: FeedbackOverlay.Style = .close { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let color = style.color
        let lineWidth: CGFloat = 4
        let rect = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)

        color.withAlphaComponent(0.10).setFill()
        path.fill()
        color.withAlphaComponent(0.9).setStroke()
        path.lineWidth = lineWidth
        path.stroke()

        // 顶部居中的提示胶囊
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let text = NSAttributedString(string: style.text, attributes: attrs)
        let textSize = text.size()
        let padding = NSSize(width: 16, height: 8)
        let pillSize = NSSize(width: textSize.width + padding.width * 2, height: textSize.height + padding.height * 2)
        let pillRect = NSRect(
            x: bounds.midX - pillSize.width / 2,
            y: bounds.maxY - pillSize.height - 24,
            width: pillSize.width,
            height: pillSize.height
        )
        let pill = NSBezierPath(roundedRect: pillRect, xRadius: pillSize.height / 2, yRadius: pillSize.height / 2)
        color.withAlphaComponent(0.92).setFill()
        pill.fill()
        text.draw(at: NSPoint(x: pillRect.minX + padding.width, y: pillRect.minY + padding.height))
    }
}
