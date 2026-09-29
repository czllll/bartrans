import AppKit
import Carbon.HIToolbox

/// 用 Carbon `RegisterEventHotKey` 注册全局快捷键——这是系统级快捷键的标准做法，
/// 不需要辅助功能权限，也不需要监听所有键盘事件。
@MainActor
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    private static let signature: OSType = 0x4254_524E // "BTRN"

    func register(_ preset: HotKeyPreset, action: @escaping () -> Void) {
        unregister()
        guard let (keyCode, modifiers) = preset.carbon else { return }
        self.action = action

        installHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            print("注册快捷键失败（可能与其它 App 冲突）: \(status)")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated {
                manager.action?()
            }
            return noErr
        }, 1, &eventType, context, &handlerRef)
    }
}
