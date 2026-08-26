import AppKit
import ApplicationServices
import Foundation

// 供等待授权时的子进程探测使用：已授权返回 0，否则返回 1。放在最前面，不做任何初始化。
if CommandLine.arguments.contains("--check-ax") {
    exit(AXIsProcessTrusted() ? 0 : 1)
}

setlinebuf(stdout)

// 以 .app 方式（open / 双击）启动时没有终端，把输出写到日志文件。
if isatty(1) == 0 {
    let logPath = NSHomeDirectory() + "/Library/Logs/trackpad_pro.log"
    freopen(logPath, "a", stdout)
    freopen(logPath, "a", stderr)
    setlinebuf(stdout)
    print("---- 启动 \(Date()) ----")
}

// ---- AppKit（反馈覆盖层需要 NSApplication）----
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// ---- 参数 ----
var debugFlag = false
let store = SettingsStore.shared
for arg in CommandLine.arguments.dropFirst() {
    switch arg {
    case "--debug", "-d":
        debugFlag = true
    case "--reset-onboarding":
        store.config.hasCompletedOnboarding = false
    case "--show-settings":
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { SettingsWindowController.shared.show() }
    case "--show-onboarding":
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { OnboardingWindowController.shared.show() }
    case "--overlay-demo":
        // 仅用于预览反馈覆盖层的外观，不需要任何权限。
        let demoFrame = CGRect(x: 240, y: 160, width: 900, height: 560)
        if let dir = ProcessInfo.processInfo.environment["OVERLAY_PREVIEW_DIR"] {
            FeedbackOverlay.shared.renderPreview(style: .close, size: demoFrame.size, to: dir + "/overlay_close.png")
            FeedbackOverlay.shared.renderPreview(style: .drag, size: demoFrame.size, to: dir + "/overlay_drag.png")
            exit(0)
        }
        FeedbackOverlay.shared.show(axFrame: demoFrame, style: .close)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            FeedbackOverlay.shared.show(axFrame: demoFrame, style: .drag)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { exit(0) }
        app.run()
    case "--help", "-h":
        print(tr("""
        trackpad_pro — 触摸板增强
          左上角按下、松开      关闭当前窗口（按住时移动手指可取消）
          左上角右侧按下、松开  最小化当前窗口（同上）
          上沿按下并拖动        拖动当前窗口
          右上角按下并拖动      调整当前窗口大小
          右边缘起手向内滑动    放大指针，抬起还原

        选项:
          --debug, -d         打印手指坐标与手势触发日志（用于调阈值）
          --reset-onboarding  下次启动重新显示引导教学
        """, """
        trackpad_pro — trackpad window control
          Press & release the top-left corner    close the window under the cursor (slide to cancel)
          Press & release the zone next to it    minimize the window (same cancel)
          Press & drag along the top edge        move the window
          Press & drag the top-right corner      resize the window
          Swipe in from the right edge           zoom the cursor, lift to restore

        Options:
          --debug, -d         print finger coordinates and gesture logs (for tuning)
          --reset-onboarding  show the tutorial again on next launch
        """))
        exit(0)
    default:
        print(tr("未知参数: \(arg)（--help 查看用法）", "Unknown argument: \(arg) (see --help)"))
        exit(1)
    }
}

/// 当前生效的配置（持久化配置 + 命令行 debug 标志）。
func effectiveConfig() -> Config {
    var c = store.config
    c.debug = debugFlag
    return c
}

// ---- 指针放大（不需要权限）----
CursorZoom.shared.recoverIfNeeded()
let edgeSwipe = EdgeSwipeDetector(edgeWidth: store.config.rightEdgeWidth, activationDistance: store.config.edgeSwipeActivationDistance)
edgeSwipe.topExclusion = store.config.resizeEnabled ? store.config.topEdgeHeight : 0
edgeSwipe.onBegan = {
    DispatchQueue.main.async {
        guard store.config.cursorZoomEnabled, !store.isPaused, !GestureController.shared.isMidGesture else { return }
        CursorZoom.shared.zoom(to: store.config.cursorZoomScale)
        GestureEvents.post(.zoom)
        if debugFlag { print("[gesture] 右边缘向内滑动 → 放大指针") }
    }
}
edgeSwipe.onEnded = {
    DispatchQueue.main.async {
        guard CursorZoom.shared.isZoomed else { return }
        CursorZoom.shared.restore()
        if debugFlag { print("[gesture] 手指抬起 → 指针还原") }
    }
}
// ---- 下沿滑动切换窗口（不需要权限；置前其他应用窗口用到 AX，仅在已授权时有效果）----
let windowSwitcher = WindowSwitcher()
windowSwitcher.enabled = store.config.switcherEnabled
windowSwitcher.bandHeight = store.config.bottomEdgeHeight
windowSwitcher.stepDistance = store.config.switcherStepDistance
windowSwitcher.rightExclusion = store.config.cursorZoomEnabled ? store.config.rightEdgeWidth : 0
windowSwitcher.rightToNext = store.config.switcherRightToNext
windowSwitcher.debug = debugFlag

TouchTracker.shared.onFrame = { fingers in
    edgeSwipe.update(fingers)
    if !store.isPaused { windowSwitcher.update(fingers) }
    FingerPublisher.shared.push(fingers)
}

// ---- 配置变更同步到各模块 ----
var configCancellable = store.$config.sink { c in
    GestureController.shared.config = { var x = c; x.debug = debugFlag; return x }()
    edgeSwipe.edgeWidth = c.rightEdgeWidth
    edgeSwipe.activationDistance = c.edgeSwipeActivationDistance
    edgeSwipe.topExclusion = c.resizeEnabled ? c.topEdgeHeight : 0
    windowSwitcher.enabled = c.switcherEnabled
    windowSwitcher.bandHeight = c.bottomEdgeHeight
    windowSwitcher.stepDistance = c.switcherStepDistance
    windowSwitcher.rightExclusion = c.cursorZoomEnabled ? c.rightEdgeWidth : 0
    windowSwitcher.rightToNext = c.switcherRightToNext
}

// ---- 单实例 ----
// 两个实例会各装一个事件监听，同一手势被执行两次（例如教学窗口被最小化两次、还原互相打架）。
// O_CLOEXEC 让 execv 自动重启时先释放锁，新进程能重新拿到。
let lockPath = NSHomeDirectory() + "/Library/Application Support/trackpad_pro.lock"
try? FileManager.default.createDirectory(
    atPath: (lockPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
let lockFD = open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
if lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    print(tr("已有另一个 trackpad_pro 实例在运行，本实例退出。",
             "Another trackpad_pro instance is already running; exiting."))
    exit(1)
}

// ---- 开机自启 ----
// 首次以 .app 方式运行时默认注册开机自启；只做一次，之后以设置面板里的开关为准。
if store.canLaunchAtLogin, !store.config.hasSetupLaunchAtLogin {
    store.launchAtLogin = true
    store.config.hasSetupLaunchAtLogin = true
    print(tr("已默认开启开机自启动（可在设置中关闭）。",
             "Launch at login enabled by default (can be turned off in Settings)."))
}

// ---- 菜单栏 ----
StatusBarController.shared.install()

// ---- 触摸板（不需要权限）----
TouchTracker.shared.debug = debugFlag
let deviceCount = TouchTracker.shared.start()
guard deviceCount > 0 else {
    print(tr("未找到多点触控设备（MTDeviceCreateList 为空）。",
             "No multitouch device found (MTDeviceCreateList is empty)."))
    exit(1)
}
print(tr("已监听 \(deviceCount) 个触摸板设备。", "Listening on \(deviceCount) trackpad device(s)."))

// ---- 辅助功能权限 ----
// 不用系统的授权弹窗（kAXTrustedCheckOptionPrompt），改用自己的引导面板，避免对话框堆在屏幕上。
func startGestures() {
    GestureController.shared.config = effectiveConfig()
    guard GestureController.shared.start() else {
        print(tr("创建事件监听 (CGEventTap) 失败，通常是辅助功能权限未生效，请重新勾选后重启程序。",
                 "Failed to create the event tap (CGEventTap) — usually a stale Accessibility grant. Re-enable it and relaunch."))
        exit(1)
    }
    store.isTrusted = true
    print(tr("trackpad_pro 运行中：左上角=关闭，其右侧=最小化，上沿拖动=移动，右上角拖动=调整大小，右边缘滑入=放大指针。",
             "trackpad_pro running: top-left = close, next to it = minimize, top-edge drag = move, top-right drag = resize, right-edge swipe = zoom cursor."))
    if !store.config.hasCompletedOnboarding {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { OnboardingWindowController.shared.show() }
    }
}

func relaunchSelf() -> Never {
    let exePath = CommandLine.arguments[0]
    print(tr("检测到已授权，重新启动…", "Permission granted — relaunching…"))
    fflush(stdout)
    // 用 execv 以同样的参数替换当前进程，获得干净的授权状态。
    let cArgs = CommandLine.arguments.map { strdup($0) } + [nil]
    execv(exePath, cArgs)
    print(tr("自动重启失败，请手动重新启动程序。", "Automatic relaunch failed; please restart the app manually."))
    exit(1)
}

/// 系统对已在运行的进程会缓存"未授权"结果，用一个新进程探测真实状态。
func probeTrusted() -> Bool {
    let probe = Process()
    probe.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    probe.arguments = ["--check-ax"]
    probe.standardOutput = FileHandle.nullDevice
    probe.standardError = FileHandle.nullDevice
    guard (try? probe.run()) != nil else { return false }
    probe.waitUntilExit()
    return probe.terminationStatus == 0
}

if AXIsProcessTrusted() {
    startGestures()
} else {
    print(tr("需要「辅助功能」权限：系统设置 → 隐私与安全性 → 辅助功能，打开 trackpad_pro 的开关。等待授权中（授权后会自动重启）…",
             "Accessibility permission required: System Settings → Privacy & Security → Accessibility, enable trackpad_pro. Waiting for the grant (the app relaunches automatically)…"))
    let appPath = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main.bundlePath : CommandLine.arguments[0]
    PermissionWindow.shared.show(appPath: appPath)
    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
        if AXIsProcessTrusted() || probeTrusted() {
            PermissionWindow.shared.close()
            relaunchSelf()
        }
    }
}

// 退出时务必还原指针倍率。
atexit { CursorZoom.shared.restore() }
signal(SIGINT) { _ in
    TouchTracker.shared.stop()
    CursorZoom.shared.restore()
    print("\n已退出。")
    exit(0)
}
signal(SIGTERM) { _ in
    TouchTracker.shared.stop()
    CursorZoom.shared.restore()
    exit(0)
}

app.run()
