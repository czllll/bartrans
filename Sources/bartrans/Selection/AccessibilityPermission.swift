import AppKit
import ApplicationServices

/// 划词依赖「辅助功能」权限：读取其它 App 的选中文字、模拟 ⌘C 都需要它。
@MainActor
final class AccessibilityPermission: ObservableObject {
    static let shared = AccessibilityPermission()

    @Published private(set) var isTrusted: Bool = AXIsProcessTrusted()

    private var pollTimer: Timer?

    /// 弹出系统的授权提示（只有未授权时才会弹）。
    func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        startPolling()
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startPolling()
    }

    func refresh() {
        isTrusted = AXIsProcessTrusted()
    }

    /// 系统没有"权限已变更"的通知，授权流程进行中时轮询一下，拿到后立即停止。
    private func startPolling() {
        guard !isTrusted, pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                self.refresh()
                if self.isTrusted {
                    timer.invalidate()
                    self.pollTimer = nil
                }
            }
        }
    }
}
