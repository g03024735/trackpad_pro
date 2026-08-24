import AppKit
import Combine

/// 菜单栏图标：左键切换手势暂停/恢复，右键弹出菜单（仅设置与退出）。
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private var item: NSStatusItem!
    private let menu = NSMenu()
    private var cancellables: Set<AnyCancellable> = []

    func install() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = Self.trackpadIcon()
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 trackpad_pro", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.delegate = self

        let store = SettingsStore.shared
        store.$isPaused.combineLatest(store.$isTrusted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.refresh() }
            .store(in: &cancellables)
        refresh()
    }

    /// 左键：暂停/恢复手势；右键或 ⌃左键：菜单。未授权时没有手势可切，一律弹菜单。
    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        let isMenuClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isMenuClick || !SettingsStore.shared.isTrusted {
            showMenu()
        } else {
            SettingsStore.shared.isPaused.toggle()
        }
    }

    /// 临时把菜单挂到状态栏项上再模拟一次点击；收起后在 menuDidClose 里摘掉，
    /// 否则之后的左键会直接弹菜单而不走 action。
    private func showMenu() {
        item.menu = menu
        item.button?.performClick(nil)
    }

    private func refresh() {
        let store = SettingsStore.shared
        item.button?.appearsDisabled = store.isPaused || !store.isTrusted
        if !store.isTrusted {
            item.button?.toolTip = "trackpad_pro — 等待辅助功能权限"
        } else if store.isPaused {
            item.button?.toolTip = "手势已暂停 — 左键恢复，右键菜单"
        } else {
            item.button?.toolTip = "手势运行中 — 左键暂停，右键菜单"
        }
    }

    /// 菜单栏图标：触摸板轮廓 + 左上角触点。模板图，随系统明暗与状态自动着色。
    static func trackpadIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let outline = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 3.5, width: 15, height: 11.5), xRadius: 3, yRadius: 3)
            outline.lineWidth = 1.4
            NSColor.black.setStroke()
            outline.stroke()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 4, y: 9.8, width: 3.4, height: 3.4)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// 把自己激活到前台并让窗口成为 key。刚启动时系统可能拒绝一次，所以稍后再试一次。
func activateAndFront(_ window: NSWindow) {
    func attempt() {
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    attempt()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
        if !NSApp.isActive || !window.isKeyWindow { attempt() }
    }
}

extension StatusBarController: NSMenuDelegate {
    func menuDidClose(_ menu: NSMenu) {
        item.menu = nil
    }
}
