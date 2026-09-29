import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// 全局划词的总调度：监听选词手势 → 读取选中文字 → 弹出工具条 / 翻译浮窗。
@MainActor
final class SelectionController {
    /// 快捷键触发但没有选中任何文字时，交给菜单栏面板手动输入
    var onRequestMainPanel: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private let settings: AppSettings
    private let monitor = SelectionMonitor()
    private let hotKeys = HotKeyManager()
    private let viewModel: TranslationViewModel
    private let panelState = ResultPanelState()

    private lazy var actionBar = FloatingPanel(
        rootView: ActionBarView(
            onAction: { [weak self] action in self?.perform(action) },
            onHover: { [weak self] hovering in self?.actionBarHovered(hovering) }
        ),
        allowsKey: false
    )
    private let resultPanel: FloatingPanel

    private var current: SelectedText?
    private var anchor: Anchor?
    /// 每次手势递增，异步读取选区回来时用来丢弃过期结果
    private var gestureSerial = 0
    private var actionBarHideTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    /// 选区在屏幕上的参考位置（Cocoa 坐标）
    private struct Anchor {
        var x: CGFloat
        var top: CGFloat
        var bottom: CGFloat
    }

    init(settings: AppSettings, historyStore: HistoryStore, llmEngine: TranslationEngine) {
        self.settings = settings
        let system = makeSystemEngine()
        let viewModel = TranslationViewModel(
            systemEngine: system.engine, llmEngine: llmEngine, historyStore: historyStore, settings: settings
        )
        self.viewModel = viewModel

        var closeHandler: () -> Void = {}
        var replaceHandler: () -> Void = {}
        var settingsHandler: () -> Void = {}
        resultPanel = FloatingPanel(
            rootView: ResultPanelView(
                viewModel: viewModel,
                state: panelState,
                systemBridgeView: system.hostView,
                onClose: { closeHandler() },
                onReplace: { replaceHandler() },
                onOpenSettings: { settingsHandler() }
            ),
            allowsKey: true
        )
        closeHandler = { [weak self] in self?.hideResult() }
        replaceHandler = { [weak self] in self?.replaceSelection() }
        settingsHandler = { [weak self] in
            self?.hideResult()
            self?.onOpenSettings?()
        }
    }

    func start() {
        monitor.onSelectionGesture = { [weak self] gesture in self?.handle(gesture) }
        monitor.onUserActivity = { [weak self] event in self?.handleUserActivity(event) }

        settings.$selectionEnabled
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.monitor.start()
                } else {
                    self.monitor.stop()
                    self.hideActionBar()
                }
            }
            .store(in: &cancellables)

        settings.$hotKey
            .sink { [weak self] preset in
                self?.hotKeys.register(preset) { [weak self] in self?.translateSelectionFromHotKey() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Gesture → selection

    private func handle(_ gesture: SelectionMonitor.Gesture) {
        guard settings.selectionEnabled, AXIsProcessTrusted() else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        guard !settings.isExcluded(bundleID: frontmost?.bundleIdentifier) else { return }

        gestureSerial += 1
        let serial = gestureSerial

        Task {
            // 给目标 App 一点时间更新选区（双击选词尤其需要）
            try? await Task.sleep(for: .milliseconds(80))
            guard serial == self.gestureSerial else { return }

            let selection = await SelectionReader.read(allowClipboardFallback: self.settings.clipboardFallback)
            guard serial == self.gestureSerial, let selection else { return }

            self.current = selection
            self.anchor = Self.anchor(for: selection, gesture: gesture)

            switch self.settings.selectionBehavior {
            case .toolbar:
                self.showActionBar()
            case .translate:
                self.showResult(for: selection.text)
            }
        }
    }

    private func translateSelectionFromHotKey() {
        gestureSerial += 1
        let serial = gestureSerial
        hideActionBar()

        Task {
            let selection = await SelectionReader.read(allowClipboardFallback: true)
            guard serial == self.gestureSerial else { return }
            guard let selection else {
                self.onRequestMainPanel?()
                return
            }
            let mouse = NSEvent.mouseLocation
            self.current = selection
            self.anchor = Self.anchor(for: selection, gesture: .init(start: mouse, end: mouse))
            self.showResult(for: selection.text)
        }
    }

    private static func anchor(for selection: SelectedText, gesture: SelectionMonitor.Gesture) -> Anchor {
        let sameLine = abs(gesture.start.y - gesture.end.y) < 8
        let x = sameLine ? (gesture.start.x + gesture.end.x) / 2 : gesture.end.x

        // 辅助功能给出的选区矩形在部分 App 里不可靠（例如返回整个文本框），
        // 只在它看起来像"几行文字"并且离鼠标不远时才采用。
        if let bounds = selection.bounds,
           bounds.height < 160,
           abs(bounds.midY - gesture.end.y) < 200,
           bounds.minX - 50 < gesture.end.x, gesture.end.x < bounds.maxX + 50 {
            return Anchor(x: sameLine && bounds.width < 600 ? bounds.midX : x, top: bounds.maxY, bottom: bounds.minY)
        }
        return Anchor(
            x: x,
            top: max(gesture.start.y, gesture.end.y) + 10,
            bottom: min(gesture.start.y, gesture.end.y) - 12
        )
    }

    // MARK: - Action bar

    private func showActionBar() {
        guard let anchor else { return }
        let height = actionBar.contentView?.fittingSize.height ?? 42
        let visibleTop = ScreenGeometry.screen(containing: NSPoint(x: anchor.x, y: anchor.top))?.visibleFrame.maxY ?? .greatestFiniteMagnitude

        // 默认在选区上方；上方放不下时放到选区下方
        let top = anchor.top + height < visibleTop ? anchor.top + height : anchor.bottom
        actionBar.show(centeredAt: anchor.x, top: top, makeKey: false)
        scheduleActionBarHide()
    }

    private func hideActionBar() {
        actionBarHideTimer?.invalidate()
        actionBarHideTimer = nil
        actionBar.orderOut(nil)
    }

    private func scheduleActionBarHide() {
        actionBarHideTimer?.invalidate()
        actionBarHideTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideActionBar() }
        }
    }

    private func actionBarHovered(_ hovering: Bool) {
        if hovering {
            actionBarHideTimer?.invalidate()
        } else if actionBar.isVisible {
            scheduleActionBarHide()
        }
    }

    private func perform(_ action: ActionBarView.Action) {
        guard let current else { return }
        hideActionBar()

        switch action {
        case .translate:
            showResult(for: current.text)
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(current.text, forType: .string)
        case .search:
            if let url = settings.searchEngine.url(for: current.text) {
                NSWorkspace.shared.open(url)
            }
        case .speak:
            Speaker.shared.speak(current.text, language: nil)
        }
    }

    // MARK: - Result panel

    private func showResult(for text: String) {
        hideActionBar()
        panelState.canReplace = current?.isEditable ?? false
        viewModel.load(text)

        let anchor = anchor ?? {
            let mouse = NSEvent.mouseLocation
            return Anchor(x: mouse.x, top: mouse.y + 10, bottom: mouse.y - 12)
        }()

        // 默认放在选区下方；下方空间不够时放到选区上方
        let visibleBottom = ScreenGeometry.screen(containing: NSPoint(x: anchor.x, y: anchor.bottom))?.visibleFrame.minY ?? 0
        let estimatedHeight: CGFloat = 220
        let top = anchor.bottom - estimatedHeight > visibleBottom ? anchor.bottom - 4 : anchor.top + estimatedHeight

        // 已固定的浮窗保持原位，只更新内容
        if resultPanel.isVisible && panelState.isPinned { return }
        resultPanel.show(centeredAt: anchor.x, top: top, makeKey: false)
    }

    private func hideResult() {
        viewModel.cancel()
        resultPanel.orderOut(nil)
    }

    private func handleUserActivity(_ event: NSEvent) {
        hideActionBar()

        guard resultPanel.isVisible else { return }
        switch event.type {
        case .keyDown where event.keyCode == UInt16(kVK_Escape):
            hideResult()
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            // 全局监听只收得到别的 App 的点击，也就是点在了浮窗外面
            if !panelState.isPinned { hideResult() }
        default:
            break
        }
    }

    /// 用译文替换原文：切回原 App，借剪贴板粘贴，再把剪贴板恢复原样。
    private func replaceSelection() {
        let translation = viewModel.outputText
        guard !translation.isEmpty, let app = current?.app else { return }
        hideResult()

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(translation, forType: .string)

        app.activate()
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            KeyboardSimulator.press(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
            try? await Task.sleep(for: .milliseconds(400))
            snapshot.restore(to: pasteboard)
        }
    }
}
