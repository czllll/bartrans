import AppKit
import ApplicationServices
import Carbon.HIToolbox

struct SelectedText {
    let text: String
    /// 选区在屏幕上的位置（Cocoa 坐标，原点在主屏左下角）。拿不到时为 nil。
    let bounds: NSRect?
    /// 选中文字所在的 App，"替换原文"时要切回去粘贴
    let app: NSRunningApplication?
    /// 选区是否可编辑（决定是否提供"替换"）。走剪贴板兜底时无从得知，按不可编辑处理。
    var isEditable: Bool = false
}

/// 读取当前前台 App 里被选中的文字。
///
/// 优先走辅助功能 API（`kAXSelectedTextAttribute`），对原生 App 最准确、零副作用；
/// 读不到时（Chrome、Electron 等自绘文字的 App 常见）退回到"模拟 ⌘C → 读剪贴板
/// → 恢复剪贴板"，这也是 PopClip 的做法。
@MainActor
enum SelectionReader {
    /// 模拟 ⌘C 容易误伤的 App：Finder 里 ⌘C 会复制文件
    private static let noClipboardFallbackApps: Set<String> = ["com.apple.finder"]

    static func read(allowClipboardFallback: Bool) async -> SelectedText? {
        let app = NSWorkspace.shared.frontmostApplication
        if let app, app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return nil
        }
        // 密码框等安全输入状态下什么都不做
        if IsSecureEventInputEnabled() { return nil }

        if let result = readViaAccessibility(pid: app?.processIdentifier), let text = normalized(result.text) {
            return SelectedText(text: text, bounds: result.bounds, app: app, isEditable: result.isEditable)
        }

        guard allowClipboardFallback, AXIsProcessTrusted() else { return nil }
        if let bundleID = app?.bundleIdentifier, noClipboardFallbackApps.contains(bundleID) { return nil }

        guard let text = await readViaClipboard(), let text = normalized(text) else { return nil }
        return SelectedText(text: text, bounds: nil, app: app)
    }

    private static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // 超长选区（整页全选之类）截断，避免把一整本书丢给翻译引擎
        return trimmed.count > 5000 ? String(trimmed.prefix(5000)) : trimmed
    }

    // MARK: - Accessibility

    private static func readViaAccessibility(pid: pid_t?) -> (text: String, bounds: NSRect?, isEditable: Bool)? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        // 目标 App 卡死时 AX 调用会一直阻塞主线程，限制一下
        AXUIElementSetMessagingTimeout(systemWide, 0.3)

        var focused: AnyObject?
        var element: AXUIElement?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            element = (focused as! AXUIElement)
        } else if let pid {
            // 有些 App 的系统级焦点查询会失败，改从 App 元素本身取焦点
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, 0.3)
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
               let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
                element = (focused as! AXUIElement)
            }
        }
        guard let element else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.3)

        var selected: AnyObject?
        guard
            AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
            let text = selected as? String,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        var settable = DarwinBoolean(false)
        let isEditable = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success
            && settable.boolValue

        return (text, selectionBounds(of: element), isEditable)
    }

    private static func selectionBounds(of element: AXUIElement) -> NSRect? {
        var rangeValue: AnyObject?
        guard
            AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
            let rangeValue
        else { return nil }

        var boundsValue: AnyObject?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsValue
            ) == .success,
            let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID()
        else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect), rect.width > 0 || rect.height > 0 else {
            return nil
        }
        return ScreenGeometry.cocoaRect(fromAXRect: rect)
    }

    // MARK: - Clipboard fallback

    private static func readViaClipboard() async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let before = pasteboard.changeCount

        KeyboardSimulator.press(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)

        // 等目标 App 把选中内容写进剪贴板，最多 400ms
        var text: String?
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(20))
            if pasteboard.changeCount != before {
                // 部分 App 会分两次写入，稍等一下再读
                try? await Task.sleep(for: .milliseconds(20))
                text = pasteboard.string(forType: .string)
                break
            }
        }

        if pasteboard.changeCount != before {
            snapshot.restore(to: pasteboard)
        }
        return text
    }
}

/// 剪贴板内容快照：模拟 ⌘C / ⌘V 之前保存，用完原样写回，尽量不打扰用户的剪贴板。
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type] = data
                }
            }
            return entry
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}

enum KeyboardSimulator {
    static func press(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        // 显式覆盖 flags，避免用户此刻按着的修饰键（比如 Shift）混进来
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

enum ScreenGeometry {
    /// AX / CoreGraphics 使用左上角为原点的全局坐标，Cocoa 使用主屏左下角为原点。
    static func cocoaRect(fromAXRect rect: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }
}
