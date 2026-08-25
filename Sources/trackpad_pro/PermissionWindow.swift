import AppKit
import SwiftUI

/// 未获得辅助功能权限时显示的引导面板（代替系统自带的授权弹窗）。
struct PermissionView: View {
    let appPath: String

    var body: some View {
        VStack(spacing: 0) {
            PrivacyIconTile()
                .padding(.top, 38)

            Text(tr("开启辅助功能权限", "Enable Accessibility Permission"))
                .font(.system(size: 20, weight: .bold))
                .padding(.top, 18)

            Text(tr("用于读取窗口的位置与大小，并执行移动、缩放、最小化和关闭",
                    "Needed to read window positions and to move, resize, minimize and close windows"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.horizontal, 48)

            ToggleHeroCard()
                .padding(.top, 36)

            Button {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            } label: {
                Text(tr("打开系统设置", "Open System Settings"))
            }
            .buttonStyle(ProminentCTAStyle())
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 46)
            .padding(.top, 34)

            Button(tr("退出", "Quit")) { exit(0) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.top, 12)
                .padding(.bottom, 26)
        }
        .frame(width: 440)
    }
}

/// 不随窗口激活态变灰的主按钮：权限面板失焦时（用户去了系统设置）CTA 仍保持醒目。
private struct ProminentCTAStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
    }
}

/// macOS 系统设置「隐私与安全性」同款图标：蓝色渐变圆角方块 + 白色手掌。
private struct PrivacyIconTile: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14.5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.38, green: 0.66, blue: 0.99), Color(red: 0.10, green: 0.43, blue: 0.94)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 64, height: 64)
                .shadow(color: Color(red: 0.10, green: 0.43, blue: 0.94).opacity(0.3), radius: 12, y: 6)
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 33, weight: .regular))
                .foregroundStyle(.white)
        }
    }
}

/// 主视觉：一行"设置项"卡片，指针移入点击，开关打开，循环播放。
private struct ToggleHeroCard: View {
    private static let cycle: Double = 3.4

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.cycle) / Self.cycle
            let on = clamp((t - 0.34) / 0.10)
            let cursorIn = easeInOut(clamp((t - 0.05) / 0.22))
            let click = clamp((t - 0.30) / 0.12)
            let fade = min(1, (1 - t) / 0.06)

            ZStack {
                HStack(spacing: 12) {
                    MiniAppIcon()
                    Text("trackpad_pro")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    SwitchShape(progress: on)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.10), radius: 16, y: 8)
                .frame(width: 330)

                // 指针
                GeometryReader { geo in
                    let target = CGPoint(x: geo.size.width / 2 + 136, y: geo.size.height / 2 + 12)
                    let start = CGPoint(x: geo.size.width / 2 - 60, y: geo.size.height + 26)
                    let pos = CGPoint(
                        x: start.x + (target.x - start.x) * cursorIn,
                        y: start.y + (target.y - start.y) * cursorIn
                    )
                    ZStack {
                        if click > 0 && click < 1 {
                            Circle()
                                .stroke(Color.accentColor.opacity(0.8 * (1 - click)), lineWidth: 2)
                                .frame(width: 14 + 26 * click, height: 14 + 26 * click)
                                .position(x: pos.x + 2, y: pos.y + 2)
                        }
                        Image(systemName: "cursorarrow")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                            .shadow(color: Color(nsColor: .windowBackgroundColor), radius: 1)
                            .position(pos)
                    }
                }
            }
            .frame(height: 96)
            .opacity(Double(fade))
        }
    }

    private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private func easeInOut(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
}

/// 卡片里的小应用图标：蓝紫渐变方块 + 白色触摸板轮廓。
private struct MiniAppIcon: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.35, green: 0.55, blue: 1.0), Color(red: 0.25, green: 0.32, blue: 0.9)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 30, height: 30)
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .strokeBorder(.white, lineWidth: 1.6)
                .frame(width: 17, height: 12.5)
                .offset(x: 6.5, y: 9)
            Circle()
                .fill(.white)
                .frame(width: 3.2, height: 3.2)
                .offset(x: 9.3, y: 11.5)
        }
        .frame(width: 30, height: 30)
    }
}

/// 一个模拟的 macOS 开关。progress 0 = 关，1 = 开。
private struct SwitchShape: View {
    let progress: Double

    var body: some View {
        let width: CGFloat = 42
        let height: CGFloat = 25
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.primary.opacity(0.2))
            Capsule()
                .fill(Color.accentColor)
                .opacity(progress)
            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                .padding(2)
                .offset(x: (width - height) * progress)
                .frame(width: height, height: height)
        }
        .frame(width: width, height: height)
    }
}

final class PermissionWindow {
    static let shared = PermissionWindow()
    private var window: NSWindow?

    private init() {}

    func show(appPath: String) {
        if window == nil {
            let hosting = NSHostingView(rootView: PermissionView(appPath: appPath))
            let win = NSWindow(
                contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.title = "trackpad_pro"
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.contentView = hosting
            win.isReleasedWhenClosed = false
            win.isMovableByWindowBackground = true
            win.level = .floating
            win.center()
            window = win
        }
        if let window { activateAndFront(window) }
    }

    func close() {
        window?.orderOut(nil)
    }
}
