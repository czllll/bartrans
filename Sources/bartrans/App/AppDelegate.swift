import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var eventMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    private let historyStore = HistoryStore()
    private let settings = AppSettings.shared
    private let permission = AccessibilityPermission.shared
    private lazy var llmEngine = LLMEngine(settings: settings)

    /// 菜单栏面板：手动输入 / 粘贴翻译
    private lazy var panelSystemEngine = makeSystemEngine()
    private lazy var viewModel = TranslationViewModel(
        systemEngine: panelSystemEngine.engine,
        llmEngine: llmEngine,
        historyStore: historyStore,
        settings: settings
    )

    /// 全局划词
    private lazy var selectionController = SelectionController(
        settings: settings, historyStore: historyStore, llmEngine: llmEngine
    )

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
        popover.contentSize = TranslatePanelView.size
        let panel = TranslatePanelView(viewModel: viewModel) { [weak self] in
            self?.openSettings()
        }
        popover.contentViewController = NSHostingController(
            rootView: panel.background(panelSystemEngine.hostView)
        )
        self.popover = popover

        selectionController.onRequestMainPanel = { [weak self] in self?.showPopover() }
        selectionController.onOpenSettings = { [weak self] in self?.openSettings() }
        selectionController.start()

        // 划词需要辅助功能权限：首次启动时请求一次，之后在设置/菜单里提示
        if settings.selectionEnabled && !permission.isTrusted {
            permission.request()
        }
        permission.$isTrusted
            .sink { [weak self] trusted in self?.updateStatusIcon(needsAttention: !trusted) }
            .store(in: &cancellables)
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

    private func updateStatusIcon(needsAttention: Bool) {
        statusItem?.button?.appearsDisabled = needsAttention && settings.selectionEnabled
        statusItem?.button?.toolTip = needsAttention ? "bartrans：划词需要开启辅助功能权限" : "bartrans"
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
            togglePopover()
        }
    }

    // MARK: - Status menu

    private func showStatusMenu() {
        let menu = NSMenu()

        if !permission.isTrusted {
            let item = NSMenuItem(title: "⚠︎ 开启辅助功能权限以使用划词…", action: #selector(requestPermission), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let toggle = NSMenuItem(title: "划词翻译", action: #selector(toggleSelection), keyEquivalent: "")
        toggle.target = self
        toggle.state = settings.selectionEnabled ? .on : .off
        menu.addItem(toggle)

        // 右键菜单弹出时，前台 App 仍然是用户正在用的那个
        if let app = NSWorkspace.shared.frontmostApplication,
           let bundleID = app.bundleIdentifier,
           bundleID != Bundle.main.bundleIdentifier {
            let name = app.localizedName ?? bundleID
            let excluded = settings.isExcluded(bundleID: bundleID)
            let item = NSMenuItem(
                title: excluded ? "在「\(name)」中恢复划词" : "在「\(name)」中停用划词",
                action: #selector(toggleExcludedApp(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = bundleID
            item.isEnabled = settings.selectionEnabled
            menu.addItem(item)
        }

        menu.addItem(.separator())

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

    @objc private func requestPermission() {
        permission.request()
        permission.openSystemSettings()
    }

    @objc private func toggleSelection() {
        settings.selectionEnabled.toggle()
        updateStatusIcon(needsAttention: !permission.isTrusted)
    }

    @objc private func toggleExcludedApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        settings.setExcluded(!settings.isExcluded(bundleID: bundleID), bundleID: bundleID)
    }

    @objc private func settingsMenuAction() {
        openSettings()
    }

    // MARK: - Popover

    private func togglePopover() {
        if popover?.isShown == true {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let popover, let button = statusItem?.button, !popover.isShown else { return }
        viewModel.prefillFromClipboard()
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NotificationCenter.default.post(name: .focusTranslatorInput, object: nil)
        addEventMonitor()
    }

    private func closePopover() {
        popover?.performClose(nil)
        removeEventMonitor()
    }

    private func addEventMonitor() {
        removeEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePopover() }
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }

    // MARK: - Settings

    private func openSettings() {
        closePopover()
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(settings: settings, permission: permission))
        let window = NSWindow(contentViewController: hosting)
        window.title = "bartrans 设置"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
