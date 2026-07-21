import Foundation
import SwiftUI
import Translation

/// Translation framework 的编程式调用必须绑定在一个存活的 SwiftUI 视图上
/// （`.translationTask` modifier），因此用一个常驻的隐藏 view + bridge
/// 把它包装成普通的 async 函数，供 `SystemEngine` 以协议方式调用。
@available(macOS 15.0, *)
@MainActor
final class SystemTranslationBridge: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?

    private var pendingText: String = ""
    private var continuation: CheckedContinuation<String, Error>?

    func translate(text: String, source: Locale.Language, target: Locale.Language) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.pendingText = text
            // 修改 configuration 会触发挂载中的 .translationTask 重新执行
            self.configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }

    func handle(session: TranslationSession) async {
        guard let continuation else { return }
        self.continuation = nil
        do {
            let response = try await session.translate(pendingText)
            continuation.resume(returning: response.targetText)
        } catch {
            continuation.resume(throwing: TranslationError.unsupportedLanguagePack)
        }
    }
}

/// 挂在视图树里、不可见的桥接视图，负责持有 .translationTask。
@available(macOS 15.0, *)
struct SystemTranslationBridgeView: View {
    @ObservedObject var bridge: SystemTranslationBridge

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(bridge.configuration) { session in
                await bridge.handle(session: session)
            }
    }
}

@available(macOS 15.0, *)
final class SystemEngine: TranslationEngine {
    let name = "系统离线"

    private let bridge: SystemTranslationBridge

    init(bridge: SystemTranslationBridge) {
        self.bridge = bridge
    }

    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyInput }

        let sourceLang = Self.language(for: source)
        let targetLang = Self.language(for: target)

        return try await bridge.translate(text: trimmed, source: sourceLang, target: targetLang)
    }

    private static func language(for label: String) -> Locale.Language {
        label == "中文" ? Locale.Language(identifier: "zh") : Locale.Language(identifier: "en")
    }
}
