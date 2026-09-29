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

    /// 完整语言名，例如"英文 → 简体中文"
    var directionFullLabel: String {
        if let resolvedLanguages, !inputText.isEmpty {
            let source = resolvedLanguages.source.map { AppLanguage.named($0).name } ?? "自动"
            return "\(source) → \(AppLanguage.named(resolvedLanguages.target).name)"
        }
        return direction.menuLabel(primary: settings.primary, secondary: settings.secondary)
    }

    /// 引擎的简短说明：Apple 离线，或 LLM 的模型名
    var engineCaption: String {
        switch selectedEngine {
        case .system:
            return "Apple 离线"
        case .llm:
            let model = settings.llmProvider == .anthropic ? settings.anthropicModel : settings.openAIModel
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? settings.llmProvider.label : trimmed
        }
    }

    /// 查词模式下 LLM 输出的结构化结果（音标 / 义项 / 例句）
    var wordEntry: WordEntry? {
        guard isWordMode, selectedEngine == .llm, !outputText.isEmpty else { return nil }
        return WordEntry.parse(outputText)
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

/// 把 LLM 的词典式输出拆成音标、义项、例句，方便排版。
/// 解析是尽力而为的：认不出的行都当作普通义项，流式输出到一半时也能正常显示。
struct WordEntry {
    struct Sense: Hashable {
        var partOfSpeech: String?
        var meaning: String
    }

    var phonetic: String?
    var senses: [Sense] = []
    var example: (sentence: String, translation: String?)?

    private static let posPattern = try! NSRegularExpression(
        pattern: "^((?:[a-zA-Z]{1,6}\\.\\s*)+|[名动形副介连代数量助叹][词]?\\.?)\\s*(.+)$"
    )

    static func parse(_ text: String) -> WordEntry {
        var entry = WordEntry()
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.replacingOccurrences(of: "**", with: "")
            if index == 0, isPhonetic(line) {
                entry.phonetic = line
                continue
            }
            if let dash = line.range(of: " — ") ?? line.range(of: " - ") ?? line.range(of: "——") {
                let sentence = String(line[..<dash.lowerBound]).trimmingCharacters(in: .whitespaces)
                let translation = String(line[dash.upperBound...]).trimmingCharacters(in: .whitespaces)
                entry.example = (strip(sentence), translation.isEmpty ? nil : translation)
                continue
            }
            let range = NSRange(line.startIndex..., in: line)
            if let match = posPattern.firstMatch(in: line, range: range),
               let posRange = Range(match.range(at: 1), in: line),
               let meaningRange = Range(match.range(at: 2), in: line) {
                entry.senses.append(Sense(
                    partOfSpeech: line[posRange].trimmingCharacters(in: .whitespaces),
                    meaning: String(line[meaningRange])
                ))
            } else {
                entry.senses.append(Sense(partOfSpeech: nil, meaning: line))
            }
        }
        return entry
    }

    private static func isPhonetic(_ line: String) -> Bool {
        guard line.count <= 60 else { return false }
        return line.contains("/") || line.contains("[") || line.hasPrefix("音标") || line.hasPrefix("读音")
            || line.unicodeScalars.contains { (0x0250...0x02AF).contains($0.value) }
    }

    private static func strip(_ text: String) -> String {
        var result = text
        for prefix in ["例句：", "例句:", "例：", "例:", "Example:"] where result.hasPrefix(prefix) {
            result = String(result.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return result
    }
}
