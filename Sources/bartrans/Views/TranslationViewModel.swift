import AppKit
import SwiftUI

/// 一个翻译界面（菜单栏面板 / 划词浮窗）的状态。两个界面各持有一个实例，互不干扰。
@MainActor
final class TranslationViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var outputText: String = ""
    @Published var direction: TranslationDirection = .auto
    @Published var selectedEngine: EngineKind
    @Published private(set) var isTranslating: Bool = false
    @Published var errorMessage: String?
    /// 本次翻译实际使用的语言对（界面上显示"英 → 中"）
    @Published private(set) var resolvedLanguages: TranslationRequest.Languages?
    /// 查词模式下来自系统词典的释义
    @Published private(set) var dictionaryDefinition: String?
    @Published private(set) var isWordMode: Bool = false

    let historyStore: HistoryStore
    let settings: AppSettings

    private let systemEngine: TranslationEngine
    private let llmEngine: TranslationEngine
    private var currentTask: Task<Void, Never>?
    private var lastClipboardChangeCount: Int?

    init(systemEngine: TranslationEngine, llmEngine: TranslationEngine, historyStore: HistoryStore, settings: AppSettings) {
        self.systemEngine = systemEngine
        self.llmEngine = llmEngine
        self.historyStore = historyStore
        self.settings = settings
        self.selectedEngine = settings.defaultEngine
    }

    var directionLabel: String {
        if direction == .auto, let resolvedLanguages {
            let source = resolvedLanguages.source.map { AppLanguage.named($0).shortName } ?? "?"
            return "\(source) → \(AppLanguage.named(resolvedLanguages.target).shortName)"
        }
        return direction.label(primary: settings.primary, secondary: settings.secondary)
    }

    /// 打开面板时用剪贴板内容预填输入框。
    /// 只有剪贴板自上次以来变过才覆盖，避免把用户正在编辑的内容冲掉。
    func prefillFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastClipboardChangeCount else { return }
        lastClipboardChangeCount = pasteboard.changeCount

        if let clipboardText = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !clipboardText.isEmpty, clipboardText != inputText {
            inputText = clipboardText
            outputText = ""
            errorMessage = nil
        }
    }

    /// 划词浮窗：载入新的选中文字并立即翻译。
    func load(_ text: String) {
        cancel()
        inputText = text
        outputText = ""
        errorMessage = nil
        direction = .auto
        translate()
    }

    func toggleDirection() {
        direction.cycle()
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isTranslating = false
    }

    func translate() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = TranslationError.emptyInput.localizedDescription
            return
        }

        cancel()
        errorMessage = nil
        outputText = ""
        isTranslating = true

        let languages = direction.resolve(for: text, primary: settings.primary, secondary: settings.secondary)
        resolvedLanguages = languages

        let wordMode = DictionaryLookup.isWordLike(text)
        isWordMode = wordMode
        dictionaryDefinition = wordMode ? DictionaryLookup.definition(for: text) : nil

        let engine = selectedEngine == .system ? systemEngine : llmEngine
        // 系统翻译只会逐字翻译，查词的释义格式只对 LLM 有意义
        let mode: TranslationRequest.Mode = (wordMode && selectedEngine == .llm) ? .word : .text
        let request = TranslationRequest(text: text, languages: languages, mode: mode)
        let engineName = engine.name

        currentTask = Task { [weak self] in
            do {
                for try await partial in engine.translate(request) {
                    guard let self, !Task.isCancelled else { return }
                    self.outputText = partial
                }
                guard let self, !Task.isCancelled else { return }
                self.isTranslating = false
                if !self.outputText.isEmpty {
                    self.historyStore.add(sourceText: text, translatedText: self.outputText, engineName: engineName)
                }
            } catch {
                guard let self, !Task.isCancelled, !(error is CancellationError) else { return }
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.isTranslating = false
            }
        }
    }

    /// 切换引擎 / 方向后，如果已经翻过一次就自动重新翻译
    func retranslateIfNeeded() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !outputText.isEmpty || errorMessage != nil || isTranslating
        else { return }
        translate()
    }

    func copyResult() {
        guard !outputText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputText, forType: .string)
        lastClipboardChangeCount = NSPasteboard.general.changeCount
    }

    func speakSource() {
        Speaker.shared.speak(inputText, language: resolvedLanguages?.source)
    }

    func speakResult() {
        guard !outputText.isEmpty else { return }
        Speaker.shared.speak(outputText, language: resolvedLanguages?.target)
    }
}
