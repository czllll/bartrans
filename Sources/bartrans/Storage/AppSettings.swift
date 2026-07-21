import Foundation
import ServiceManagement

enum EngineKind: String, CaseIterable, Identifiable {
    case system
    case llm

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "系统离线"
        case .llm: return "LLM"
        }
    }
}

enum LLMProvider: String, CaseIterable, Identifiable {
    case anthropic
    case openAICompatible

    var id: String { rawValue }

    var label: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openAICompatible: return "OpenAI 兼容"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var defaultEngine: EngineKind {
        didSet { UserDefaults.standard.set(defaultEngine.rawValue, forKey: Keys.defaultEngine) }
    }

    @Published var llmProvider: LLMProvider {
        didSet { UserDefaults.standard.set(llmProvider.rawValue, forKey: Keys.llmProvider) }
    }

    @Published var openAIBaseURL: String {
        didSet { UserDefaults.standard.set(openAIBaseURL, forKey: Keys.openAIBaseURL) }
    }

    @Published var openAIModel: String {
        didSet { UserDefaults.standard.set(openAIModel, forKey: Keys.openAIModel) }
    }

    @Published var launchAtLogin: Bool {
        didSet { updateLaunchAtLogin(launchAtLogin) }
    }

    static let defaultOpenAIBaseURL = "https://api.openai.com/v1"
    static let defaultOpenAIModel = "gpt-4o-mini"

    private enum Keys {
        static let defaultEngine = "com.transpop.bartrans.defaultEngine"
        static let llmProvider = "com.transpop.bartrans.llmProvider"
        static let openAIBaseURL = "com.transpop.bartrans.openAIBaseURL"
        static let openAIModel = "com.transpop.bartrans.openAIModel"
    }

    private init() {
        let storedEngine = UserDefaults.standard.string(forKey: Keys.defaultEngine)
        defaultEngine = EngineKind(rawValue: storedEngine ?? "") ?? .system

        let storedProvider = UserDefaults.standard.string(forKey: Keys.llmProvider)
        llmProvider = LLMProvider(rawValue: storedProvider ?? "") ?? .anthropic

        openAIBaseURL = UserDefaults.standard.string(forKey: Keys.openAIBaseURL) ?? Self.defaultOpenAIBaseURL
        openAIModel = UserDefaults.standard.string(forKey: Keys.openAIModel) ?? Self.defaultOpenAIModel

        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            launchAtLogin = false
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            print("SMAppService 更新失败: \(error.localizedDescription)")
        }
    }
}
