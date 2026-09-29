import AppKit

/// 监听全局鼠标事件，识别"用户刚刚选中了一段文字"的手势：
/// 拖选、双击选词、三击选段、Shift+点击扩展选区。
///
/// 只用 `NSEvent` 全局监听（不装 CGEventTap），不拦截、不修改任何事件；
/// 自己 App 窗口里的事件不会进全局监听，所以在结果浮窗里选字不会误触发。
@MainActor
final class SelectionMonitor {
    struct Gesture {
        /// 鼠标按下 / 抬起的位置（Cocoa 坐标）
        let start: NSPoint
        let end: NSPoint
    }

    /// 检测到可能的选词手势
    var onSelectionGesture: ((Gesture) -> Void)?
    /// 用户开始做别的事（点击、打字、滚动）——该收起浮层了
    var onUserActivity: ((NSEvent) -> Void)?

    private var monitors: [Any] = []
    private var mouseDownLocation: NSPoint = .zero
    private var dragged = false

    private static let minDragDistance: CGFloat = 6

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }

        add(.leftMouseDown) { [weak self] event in
            guard let self else { return }
            self.mouseDownLocation = NSEvent.mouseLocation
            self.dragged = false
            self.onUserActivity?(event)
        }
        add(.leftMouseDragged) { [weak self] _ in
            self?.dragged = true
        }
        add(.leftMouseUp) { [weak self] event in
            self?.handleMouseUp(event)
        }
        add([.rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            self?.onUserActivity?(event)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func add(_ mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { handler(event) }
        }) {
            monitors.append(monitor)
        }
    }

    private func handleMouseUp(_ event: NSEvent) {
        let end = NSEvent.mouseLocation
        let distance = hypot(end.x - mouseDownLocation.x, end.y - mouseDownLocation.y)

        let isDragSelect = dragged && distance >= Self.minDragDistance
        let isMultiClick = event.clickCount >= 2
        let isShiftExtend = event.modifierFlags.contains(.shift) && event.clickCount == 1

        guard isDragSelect || isMultiClick || isShiftExtend else { return }
        // 按住 ⌘ / ⌃ 拖动一般是在搬东西或者做别的操作，不当作选字
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) { return }

        onSelectionGesture?(Gesture(start: isDragSelect ? mouseDownLocation : end, end: end))
    }
}
