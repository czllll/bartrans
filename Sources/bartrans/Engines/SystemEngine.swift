import Foundation
import SwiftUI
import Translation

/// Translation framework（macOS 15）的编程式调用必须绑定在一个存活的 SwiftUI
/// 视图上（`.translationTask` modifier），因此每个需要系统翻译的界面（菜单栏面板、
/// 划词结果浮窗）都各自挂一个隐藏的 bridge view，把它包装成普通的 async 函数。
/// 挂在"用户正看着的那个窗口"上还有个好处：缺语言包时系统弹出的下载提示能正常显示。
@available(macOS 15.0, *)
@MainActor
final class SystemTranslationBridge: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?

    private struct Pending {
        let text: String
        let continuation: CheckedContinuation<String, Error>
    }

    private var pending: Pending?
    /// 串行化请求：上一次还没返回时新的请求排队，而不是互相覆盖 continuation。
    private var tail: Task<Void, Never>?

    private static let timeout: Duration = .seconds(20)

    func translate(text: String, source: Locale.Language?, target: Locale.Language) async throws -> String {
        let previous = tail
        let work = Task { @MainActor in
            await previous?.value
            return try await self.perform(text: text, source: source, target: target)
        }
        tail = Task { _ = try? await work.value }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }

    private func perform(text: String, source: Locale.Language?, target: Locale.Language) async throws -> String {
        try Task.checkCancellation()

        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.timeout)
            guard !Task.isCancelled else { return }
            self?.finish(with: .failure(TranslationError.unavailable("系统翻译无响应，请确认语言包已下载，或切换到 LLM 引擎")))
        }
        defer { timeoutTask.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            pending = Pending(text: text, continuation: continuation)
            // 同样的语言对重新赋一个"相等"的 Configuration 不会触发 .translationTask，
            // 必须调用 invalidate() 才会让它再跑一次。
            if let current = configuration, current.source == source, current.target == target {
                configuration?.invalidate()
            } else {
                configuration = TranslationSession.Configuration(source: source, target: target)
            }
        }
    }

    func handle(session: TranslationSession) async {
        guard let pending else { return }
        do {
            let response = try await session.translate(pending.text)
            finish(with: .success(response.targetText))
        } catch is CancellationError {
            finish(with: .failure(CancellationError()))
        } catch {
            finish(with: .failure(Self.map(error)))
        }
    }

    private func finish(with result: Result<String, Error>) {
        guard let pending else { return }
        self.pending = nil
        pending.continuation.resume(with: result)
    }

    private static func map(_ error: Error) -> Error {
        TranslationError.unavailable("系统翻译失败：\(error.localizedDescription)")
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

    func translate(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error> {
        let bridge = bridge
        return singleShot {
            let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw TranslationError.emptyInput }

            let source = request.languages.source.map { Locale.Language(identifier: $0) }
            let target = Locale.Language(identifier: request.languages.target)
            if let source {
                if source.minimalIdentifier == target.minimalIdentifier {
                    return trimmed
                }
                if await LanguageAvailability().status(from: source, to: target) == .unsupported {
                    throw TranslationError.unavailable("系统翻译不支持该语言组合，可切换到 LLM 引擎")
                }
            }
            return try await bridge.translate(text: trimmed, source: source, target: target)
        }
    }
}

/// 目标系统版本低于 Translation framework 要求时的降级占位引擎。
struct UnavailableEngine: TranslationEngine {
    let name: String
    let reason: String

    func translate(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error> {
        let reason = reason
        return singleShot { throw TranslationError.unavailable(reason) }
    }
}

/// 创建一个系统翻译引擎，以及必须挂进目标界面视图树里的隐藏 bridge 视图。
@MainActor
func makeSystemEngine() -> (engine: TranslationEngine, hostView: AnyView) {
    if #available(macOS 15.0, *) {
        let bridge = SystemTranslationBridge()
        return (SystemEngine(bridge: bridge), AnyView(SystemTranslationBridgeView(bridge: bridge)))
    }
    return (UnavailableEngine(name: "系统离线", reason: "系统翻译需要 macOS 15 或更高版本"), AnyView(EmptyView()))
}
