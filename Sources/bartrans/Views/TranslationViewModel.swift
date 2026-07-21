import Foundation
import SwiftUI

@MainActor
final class TranslationViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var outputText: String = ""
    @Published var direction: TranslationDirection = .auto
    @Published var selectedEngine: EngineKind
    @Published var isTranslating: Bool = false
    @Published var errorMessage: String?

    let historyStore: HistoryStore
    private let settings: AppSettings

    private let systemEngine: TranslationEngine
    private let llmEngine: TranslationEngine

    init(systemEngine: TranslationEngine, llmEngine: TranslationEngine, historyStore: HistoryStore, settings: AppSettings) {
        self.systemEngine = systemEngine
        self.llmEngine = llmEngine
        self.historyStore = historyStore
        self.settings = settings
        self.selectedEngine = settings.defaultEngine
    }

    func prefillFromClipboard() {
        if let clipboardText = NSPasteboard.general.string(forType: .string), !clipboardText.isEmpty {
            inputText = clipboardText
        }
        outputText = ""
        errorMessage = nil
    }

    func toggleDirection() {
        direction.cycle()
    }

    func translate() {
        let text = inputText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = TranslationError.emptyInput.localizedDescription
            return
        }

        errorMessage = nil
        isTranslating = true

        let engine = selectedEngine == .system ? systemEngine : llmEngine
        let (source, target) = direction.resolve(for: text)

        Task {
            do {
                let result = try await engine.translate(text, from: source, to: target)
                self.outputText = result
                self.historyStore.add(sourceText: text, translatedText: result, engineName: engine.name)
            } catch {
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            self.isTranslating = false
        }
    }

    func copyResult() {
        guard !outputText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputText, forType: .string)
    }
}
