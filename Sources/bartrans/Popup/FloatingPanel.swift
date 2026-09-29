import AppKit
import SwiftUI

/// 划词工具条和结果浮窗共用的无边框浮动面板。
///
/// `.nonactivatingPanel`：显示、甚至成为 key window 时都不会把 bartrans 切到前台，
/// 用户原来的 App 保持激活状态——这是 PopClip / Spotlight 这类浮层的关键。
///
/// 面板尺寸由 SwiftUI 内容通过 `SizeReportingView` 上报，再由 `fit(to:)` 调整，
/// 并保持**顶边不动**（内容变多时向下长），这样流式输出译文时浮窗不会往上跳。
final class FloatingPanel: NSPanel {
    private let allowsKey: Bool
    private var contentSizeKnown = false

    init<Content: View>(rootView: Content, allowsKey: Bool) {
        self.allowsKey = allowsKey
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        isMovableByWindowBackground = allowsKey

        let hosting = FirstMouseHostingView(rootView: SizeReportingView(content: rootView) { [weak self] size in
            // 推迟到本轮布局结束后再改窗口尺寸，避免在 SwiftUI 布局过程中重入
            DispatchQueue.main.async { self?.fit(to: size) }
        })
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    /// 以某个点为参考摆放面板：水平居中于 `x`，顶边位于 `top`。
    func show(centeredAt x: CGFloat, top: CGFloat, makeKey: Bool) {
        let size = contentSizeKnown ? frame.size : (contentView?.fittingSize ?? frame.size)
        setFrame(clamped(NSRect(x: x - size.width / 2, y: top - size.height, width: size.width, height: size.height)), display: true)
        if makeKey {
            makeKeyAndOrderFront(nil)
        } else {
            orderFrontRegardless()
        }
    }

    private func fit(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        contentSizeKnown = true
        let top = frame.maxY
        let rect = NSRect(x: frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
        setFrame(clamped(rect), display: true)
    }

    /// 始终完整留在屏幕可见区域内。
    private func clamped(_ rect: NSRect) -> NSRect {
        var rect = rect
        let screen = ScreenGeometry.screen(containing: NSPoint(x: rect.midX, y: rect.maxY)) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            rect.origin.x = min(max(rect.minX, visible.minX + 4), visible.maxX - rect.width - 4)
            if rect.minY < visible.minY + 4 {
                rect.origin.y = visible.minY + 4
            }
            if rect.maxY > visible.maxY - 4 {
                rect.origin.y = visible.maxY - 4 - rect.height
            }
        }
        return rect
    }

    /// Esc 关闭
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

/// 浮层不是 key window，默认第一次点击只会"激活窗口"而不会触发按钮；
/// 这里让第一次点击直接生效。
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 把 SwiftUI 内容的理想尺寸上报给宿主面板。
private struct SizeReportingView<Content: View>: View {
    let content: Content
    let onSizeChange: (CGSize) -> Void

    var body: some View {
        content
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                onSizeChange(size)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
