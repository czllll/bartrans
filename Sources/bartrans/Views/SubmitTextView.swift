import SwiftUI
import AppKit

extension Notification.Name {
    static let focusTranslatorInput = Notification.Name("com.transpop.bartrans.focusInput")
}

/// 支持"回车触发 / Shift+回车换行"的多行输入框。
/// SwiftUI 的 TextEditor 无法区分这两种按键，因此用 NSTextView 包一层。
struct SubmitTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 13
    var inset = NSSize(width: 6, height: 6)
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        // `NSTextView()` 的裸初始化 frame 为 .zero，且缺少滚动所需的
        // 尺寸配置；用 `scrollableTextView()` 拿到官方配好的一整套，
        // 避免因为 frame/textContainer 没配置好导致内容不可见。
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = .systemFont(ofSize: fontSize)
        textView.textContainerInset = inset
        textView.textContainer?.lineFragmentPadding = 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes[.paragraphStyle] = paragraph
        textView.typingAttributes[.font] = NSFont.systemFont(ofSize: fontSize)
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.string = text

        context.coordinator.textView = textView
        context.coordinator.observeFocusRequests()
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: SubmitTextView
        weak var textView: NSTextView?

        init(_ parent: SubmitTextView) {
            self.parent = parent
        }

        func observeFocusRequests() {
            NotificationCenter.default.addObserver(
                forName: .focusTranslatorInput, object: nil, queue: .main
            ) { [weak self] _ in
                guard let textView = self?.textView else { return }
                textView.window?.makeFirstResponder(textView)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }

            let shiftPressed = NSEvent.modifierFlags.contains(.shift)
            if shiftPressed {
                return false // 让系统插入换行
            }
            parent.onSubmit()
            return true // 拦截回车，不插入换行
        }
    }
}
