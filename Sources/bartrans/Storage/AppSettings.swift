import AppKit
import Carbon.HIToolbox
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

/// 划词（选中文字）之后的行为。
enum SelectionBehavior: String, CaseIterable, Identifiable {
    /// 像 PopClip 一样先弹出一个小工具条
    case toolbar
    /// 直接弹出翻译结果
    case translate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .toolbar: return "显示工具条"
        case .translate: return "直接翻译"
        }
    }
}

enum SearchEngine: String, CaseIterable, Identifiable {
    case google, bing, baidu

    var id: String { rawValue }

    var label: String {
        switch self {
        case .google: return "Google"
        case .bing: return "Bing"
        case .baidu: return "百度"
        }
    }

    func url(for query: String) -> URL? {
        var components: URLComponents
        switch self {
        case .google:
            components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        case .bing:
            components = URLComponents(string: "https://www.bing.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        case .baidu:
            components = URLComponents(string: "https://www.baidu.com/s")!
            components.queryItems = [URLQueryItem(name: "wd", value: query)]
        }
        return components.url
    }
}

/// 可选的"翻译选中文字"全局快捷键。用预设而不是自由录制，保持实现简单。
enum HotKeyPreset: String, CaseIterable, Identifiable {
    case none
    case optionD
    case optionCommandT
    case controlOptionD

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "不使用"
        case .optionD: return "⌥ D"
        case .optionCommandT: return "⌥ ⌘ T"
        case .controlOptionD: return "⌃ ⌥ D"
        }
    }

    /// Carbon 的虚拟键码与修饰键
    var carbon: (keyCode: UInt32, modifiers: UInt32)? {
        switch self {
        case .none: return nil
        case .optionD: return (UInt32(kVK_ANSI_D), UInt32(optionKey))
        case .optionCommandT: return (UInt32(kVK_ANSI_T), UInt32(optionKey | cmdKey))
        case .controlOptionD: return (UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey))
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var defaultEngine: EngineKind {
        didSet { defaults.set(defaultEngine.rawValue, forKey: Keys.defaultEngine) }
    }

    @Published var llmProvider: LLMProvider {
        didSet { defaults.set(llmProvider.rawValue, forKey: Keys.llmProvider) }
    }

    @Published var anthropicModel: String {
        didSet { defaults.set(anthropicModel, forKey: Keys.anthropicModel) }
    }

    @Published var openAIBaseURL: String {
        didSet { defaults.set(openAIBaseURL, forKey: Keys.openAIBaseURL) }
    }

    @Published var openAIModel: String {
        didSet { defaults.set(openAIModel, forKey: Keys.openAIModel) }
    }

    @Published var primaryLanguage: String {
        didSet { defaults.set(primaryLanguage, forKey: Keys.primaryLanguage) }
    }

    @Published var secondaryLanguage: String {
        didSet { defaults.set(secondaryLanguage, forKey: Keys.secondaryLanguage) }
    }

    @Published var selectionEnabled: Bool {
        didSet { defaults.set(selectionEnabled, forKey: Keys.selectionEnabled) }
    }

    @Published var selectionBehavior: SelectionBehavior {
        didSet { defaults.set(selectionBehavior.rawValue, forKey: Keys.selectionBehavior) }
    }

    /// 读不到辅助功能里的选中文字时，是否模拟 ⌘C 从剪贴板取（取完会恢复剪贴板）。
    @Published var clipboardFallback: Bool {
        didSet { defaults.set(clipboardFallback, forKey: Keys.clipboardFallback) }
    }

    @Published var hotKey: HotKeyPreset {
        didSet { defaults.set(hotKey.rawValue, forKey: Keys.hotKey) }
    }

    @Published var searchEngine: SearchEngine {
        didSet { defaults.set(searchEngine.rawValue, forKey: Keys.searchEngine) }
    }

    /// 不触发划词的 App（bundle identifier）
    @Published var excludedApps: [String] {
        didSet { defaults.set(excludedApps, forKey: Keys.excludedApps) }
    }

    @Published var launchAtLogin: Bool {
        didSet { updateLaunchAtLogin(launchAtLogin) }
    }

    static let defaultOpenAIBaseURL = "https://api.openai.com/v1"
    static let defaultOpenAIModel = "gpt-4o-mini"
    nonisolated static let defaultAnthropicModel = "claude-sonnet-4-6"

    var primary: AppLanguage { AppLanguage.named(primaryLanguage) }
    var secondary: AppLanguage { AppLanguage.named(secondaryLanguage) }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let defaultEngine = "com.transpop.bartrans.defaultEngine"
        static let llmProvider = "com.transpop.bartrans.llmProvider"
        static let anthropicModel = "com.transpop.bartrans.anthropicModel"
        static let openAIBaseURL = "com.transpop.bartrans.openAIBaseURL"
        static let openAIModel = "com.transpop.bartrans.openAIModel"
        static let primaryLanguage = "com.transpop.bartrans.primaryLanguage"
        static let secondaryLanguage = "com.transpop.bartrans.secondaryLanguage"
        static let selectionEnabled = "com.transpop.bartrans.selectionEnabled"
        static let selectionBehavior = "com.transpop.bartrans.selectionBehavior"
        static let clipboardFallback = "com.transpop.bartrans.clipboardFallback"
        static let hotKey = "com.transpop.bartrans.hotKey"
        static let searchEngine = "com.transpop.bartrans.searchEngine"
        static let excludedApps = "com.transpop.bartrans.excludedApps"
        static let migratedFromSandbox = "com.transpop.bartrans.migratedFromSandbox"
    }

    private init() {

        let defaults = UserDefaults.standard

        defaultEngine = EngineKind(rawValue: defaults.string(forKey: Keys.defaultEngine) ?? "") ?? .system
        llmProvider = LLMProvider(rawValue: defaults.string(forKey: Keys.llmProvider) ?? "") ?? .anthropic
        anthropicModel = defaults.string(forKey: Keys.anthropicModel) ?? Self.defaultAnthropicModel
        openAIBaseURL = defaults.string(forKey: Keys.openAIBaseURL) ?? Self.defaultOpenAIBaseURL
        openAIModel = defaults.string(forKey: Keys.openAIModel) ?? Self.defaultOpenAIModel
        primaryLanguage = defaults.string(forKey: Keys.primaryLanguage) ?? "zh-Hans"
        secondaryLanguage = defaults.string(forKey: Keys.secondaryLanguage) ?? "en"
        selectionEnabled = defaults.object(forKey: Keys.selectionEnabled) as? Bool ?? true
        selectionBehavior = SelectionBehavior(rawValue: defaults.string(forKey: Keys.selectionBehavior) ?? "") ?? .toolbar
        clipboardFallback = defaults.object(forKey: Keys.clipboardFallback) as? Bool ?? true
        hotKey = HotKeyPreset(rawValue: defaults.string(forKey: Keys.hotKey) ?? "") ?? .optionD
        searchEngine = SearchEngine(rawValue: defaults.string(forKey: Keys.searchEngine) ?? "") ?? .google
        excludedApps = defaults.stringArray(forKey: Keys.excludedApps) ?? []
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func isExcluded(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedApps.contains(bundleID)
    }

    func setExcluded(_ excluded: Bool, bundleID: String) {
        if excluded {
            if !excludedApps.contains(bundleID) { excludedApps.append(bundleID) }
        } else {
            excludedApps.removeAll { $0 == bundleID }
        }
    }

    /// 1.x 版本开着 App Sandbox，设置和历史都存在沙盒容器里；
    /// 2.0 为了读取其它 App 的选中文字关掉了沙盒，这里把旧数据搬过来，只做一次。
    static func migrateSandboxDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Keys.migratedFromSandbox) else { return }
        defaults.set(true, forKey: Keys.migratedFromSandbox)

        let bundleID = Bundle.main.bundleIdentifier ?? "com.transpop.bartrans"
        let containerPlist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(bundleID)/Data/Library/Preferences/\(bundleID).plist")
        guard let legacy = NSDictionary(contentsOf: containerPlist) as? [String: Any] else { return }

        for (key, value) in legacy where key.hasPrefix("com.transpop.") && defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
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
