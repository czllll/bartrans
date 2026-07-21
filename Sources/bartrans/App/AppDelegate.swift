import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var eventMonitor: Any?

    private let historyStore = HistoryStore()
    private let settings = AppSettings.shared
    private lazy var systemTranslationBridge: Any? = {
        if #available(macOS 15.0, *) {
            return SystemTranslationBridge()
        }
        return nil
    }()

    private lazy var viewModel: TranslationViewModel = {
        let systemEngine: TranslationEngine
        if #available(macOS 15.0, *), let bridge = systemTranslationBridge as? SystemTranslationBridge {
            systemEngine = SystemEngine(bridge: bridge)
        } else {
            systemEngine = UnavailableEngine(name: "系统离线", reason: "系统翻译需要 macOS 15 或更高版本")
        }
        let llmEngine = LLMEngine(settings: settings)
        return TranslationViewModel(systemEngine: systemEngine, llmEngine: llmEngine, historyStore: historyStore, settings: settings)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setUpMainMenu()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = Self.renderStatusBarIcon()
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = statusItem

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 340, height: 430)

        var rootView: AnyView {
            let panel = TranslatePanelView(viewModel: viewModel) { [weak self] in
                self?.openSettings()
            }
            if #available(macOS 15.0, *), let bridge = systemTranslationBridge as? SystemTranslationBridge {
                return AnyView(
                    panel.background(SystemTranslationBridgeView(bridge: bridge))
                )
            }
            return AnyView(panel)
        }

        popover.contentViewController = NSHostingController(rootView: rootView)
        self.popover = popover
    }

    /// 用 SwiftUI 矢量图形渲染菜单栏图标，作为 template image
    /// （单色轮廓）随浅色/深色菜单栏自动适配，不需要外部图片资源。
    private static func renderStatusBarIcon() -> NSImage {
        let mark = BarTransMark(color: .black)
            .frame(width: 18, height: 18)
        let renderer = ImageRenderer(content: mark)
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        image.accessibilityDescription = "bartrans"
        return image
    }

    /// Accessory (无 Dock 图标) 应用默认没有主菜单，Cmd+C/V/X/A 这类
    /// 快捷键依赖 Edit 菜单的 key equivalent 才能路由到当前输入框，
    /// 所以这里手动搭一个最小可用的菜单栏。
    private func setUpMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 bartrans", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showStatusMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(settingsMenuAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 bartrans", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func settingsMenuAction() {
        openSettings()
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(sender)
            removeEventMonitor()
        } else {
            viewModel.prefillFromClipboard()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            addEventMonitor()
        }
    }

    private func addEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover?.performClose(nil)
            self?.removeEventMonitor()
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }

    private func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(settings: settings))
        let window = NSWindow(contentViewController: hosting)
        window.title = "设置"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// 目标系统版本低于 Translation framework 要求时的降级占位引擎。
private struct UnavailableEngine: TranslationEngine {
    let name: String
    let reason: String

    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        throw TranslationError.network(reason)
    }
}
