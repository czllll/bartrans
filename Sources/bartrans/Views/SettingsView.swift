import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var permission: AccessibilityPermission

    @ObservedObject private var navigation = SettingsNavigation.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $navigation.tab) {
                SelectionSettings(settings: settings, permission: permission)
                    .tabItem { Label("划词", systemImage: "text.cursor") }
                    .tag(SettingsNavigation.Tab.selection)
                TranslationSettings(settings: settings)
                    .tabItem { Label("翻译", systemImage: "character.bubble") }
                    .tag(SettingsNavigation.Tab.translation)
                GeneralSettings(settings: settings)
                    .tabItem { Label("通用", systemImage: "gearshape") }
                    .tag(SettingsNavigation.Tab.general)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 520, height: 660)
        .onAppear { permission.refresh() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            BarTransLogo(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("bartrans")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("划词翻译 · 查词 · 版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            PermissionBadge(isTrusted: permission.isTrusted)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
}

/// 让别处（例如引擎菜单里的"管理模型…"）可以直接打开设置的某个标签页。
@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    enum Tab: Hashable { case selection, translation, general }
    @Published var tab: Tab = .selection
}

private struct PermissionBadge: View {
    let isTrusted: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isTrusted ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(isTrusted ? "划词已就绪" : "需要辅助功能权限")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

// MARK: - 划词

private struct SelectionSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var permission: AccessibilityPermission

    var body: some View {
        Form {
            if !permission.isTrusted {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("开启「辅助功能」权限")
                                .font(.system(size: 13, weight: .semibold))
                            Text("读取其它 App 中选中的文字需要这项权限。在「系统设置 → 隐私与安全性 → 辅助功能」中打开 bartrans；若已在列表中但不生效，先用「−」删除再重新添加。")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Button("去开启") {
                            permission.request()
                            permission.openSystemSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.ink)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                Toggle("选中文字后自动弹出", isOn: $settings.selectionEnabled)
                Picker("弹出内容", selection: $settings.selectionBehavior) {
                    ForEach(SelectionBehavior.allCases) { behavior in
                        Text(behavior.label).tag(behavior)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!settings.selectionEnabled)
                Picker("翻译选中文字的快捷键", selection: $settings.hotKey) {
                    ForEach(HotKeyPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
            } footer: {
                Text("拖选、双击、三击或 Shift+点击都会触发。没有选中文字时按快捷键，会打开菜单栏面板。")
                    .settingsFootnote()
            }

            Section {
                Toggle("兼容模式（模拟 ⌘C 读取）", isOn: $settings.clipboardFallback)
            } footer: {
                Text("Chrome、VS Code 等 App 不通过辅助功能提供选中文字。开启后会短暂借用剪贴板，读完立即还原。")
                    .settingsFootnote()
            }

            Section {
                if settings.excludedApps.isEmpty {
                    Text("暂无")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settings.excludedApps, id: \.self) { bundleID in
                        HStack(spacing: 8) {
                            AppIconView(bundleID: bundleID)
                            Text(AppIconView.name(for: bundleID))
                            Spacer()
                            Button {
                                settings.setExcluded(false, bundleID: bundleID)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("恢复划词")
                        }
                    }
                }
            } header: {
                Text("已停用划词的 App")
            } footer: {
                Text("在某个 App 中右键点击菜单栏图标，可以停用 / 恢复该 App 的划词。")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 翻译

private struct TranslationSettings: View {
    @ObservedObject var settings: AppSettings

    @State private var anthropicKeyInput = ""
    @State private var openAIKeyInput = ""
    @State private var savedFlash: LLMProvider?

    var body: some View {
        Form {
            Section {
                languagePicker("母语", selection: $settings.primaryLanguage)
                languagePicker("常用外语", selection: $settings.secondaryLanguage)
                Picker("默认引擎", selection: $settings.defaultEngine) {
                    ForEach(EngineKind.allCases) { engine in
                        Label(engine.label, systemImage: engine.icon).tag(engine)
                    }
                }
            } footer: {
                Text("自动识别时：外文译成母语，母语译成常用外语。")
                    .settingsFootnote()
            }

            Section {
                Picker("服务", selection: $settings.llmProvider) {
                    ForEach(LLMProvider.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                switch settings.llmProvider {
                case .anthropic:
                    TextField("当前模型", text: $settings.anthropicModel, prompt: Text(AppSettings.defaultAnthropicModel))
                    TextField("备选模型", text: $settings.anthropicExtraModels, prompt: Text("多个用逗号分隔"))
                    keyRow(input: $anthropicKeyInput, account: .anthropicAPIKey, provider: .anthropic)
                case .openAICompatible:
                    TextField("Base URL", text: $settings.openAIBaseURL, prompt: Text(AppSettings.defaultOpenAIBaseURL))
                    TextField("当前模型", text: $settings.openAIModel, prompt: Text(AppSettings.defaultOpenAIModel))
                    TextField("备选模型", text: $settings.openAIExtraModels, prompt: Text("如 deepseek-chat, deepseek-reasoner"))
                    keyRow(input: $openAIKeyInput, account: .openAICompatibleAPIKey, provider: .openAICompatible)
                }
            } header: {
                Text("LLM 引擎")
            } footer: {
                Text(settings.llmProvider == .anthropic
                     ? "备选模型会出现在翻译面板的引擎菜单里，一键切换。划词追求速度可以用 claude-haiku-4-5。API Key 保存在钥匙串中。"
                     : "兼容 OpenAI、DeepSeek、Ollama、LM Studio 等；本地地址可不填 Key。备选模型会出现在翻译面板的引擎菜单里，一键切换。")
                    .settingsFootnote()
            }

            LLMTestSection(
                settings: settings,
                apiKey: settings.llmProvider == .anthropic ? anthropicKeyInput : openAIKeyInput
            )
        }
        .formStyle(.grouped)
        .onAppear {
            anthropicKeyInput = KeychainHelper.shared.load(for: .anthropicAPIKey) ?? ""
            openAIKeyInput = KeychainHelper.shared.load(for: .openAICompatibleAPIKey) ?? ""
        }
    }

    private func languagePicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(AppLanguage.all) { language in
                Text(language.name).tag(language.code)
            }
        }
    }

    private func keyRow(input: Binding<String>, account: KeychainAccount, provider: LLMProvider) -> some View {
        LabeledContent("API Key") {
            HStack(spacing: 6) {
                SecureField("", text: input, prompt: Text("sk-…"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                if savedFlash == provider {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }
                Button("保存") {
                    KeychainHelper.shared.save(input.wrappedValue, for: account)
                    withAnimation { savedFlash = provider }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { if savedFlash == provider { savedFlash = nil } }
                    }
                }
                .disabled(input.wrappedValue.isEmpty)
                Button {
                    KeychainHelper.shared.delete(for: account)
                    input.wrappedValue = ""
                } label: {
                    Image(systemName: "trash")
                }
                .help("清除")
                .disabled(input.wrappedValue.isEmpty)
            }
        }
    }
}

// MARK: - LLM 测试

/// 用输入框里当前的配置（包括还没保存的 Key）实际请求一次，检查是否可用、速度如何。
private struct LLMTestSection: View {
    @ObservedObject var settings: AppSettings
    let apiKey: String

    private enum Outcome {
        case running
        case success(LLMConnectionTester.Report)
        case failure(String)
    }

    @State private var results: [String: Outcome] = [:]
    @State private var order: [String] = []
    @State private var task: Task<Void, Never>?

    private var models: [String] { settings.models(for: settings.llmProvider) }
    private var isRunning: Bool { task != nil }

    var body: some View {
        Section {
            HStack {
                Text("用一句英文实际请求一次，检查 Key、地址和模型是否可用")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                Spacer()
                if isRunning {
                    Button("停止") { stop() }
                } else {
                    Button("测试当前模型") { run([settings.currentModel(for: settings.llmProvider)]) }
                    if models.count > 1 {
                        Button("测试全部") { run(models) }
                    }
                }
            }

            ForEach(order, id: \.self) { model in
                if let outcome = results[model] {
                    resultRow(model: model, outcome: outcome)
                }
            }
        } header: {
            Text("连接测试")
        }
        .onChange(of: settings.llmProvider) { stop(); results = [:]; order = [] }
    }

    @ViewBuilder
    private func resultRow(model: String, outcome: Outcome) -> some View {
        HStack(alignment: .top, spacing: 8) {
            switch outcome {
            case .running:
                ProgressView().controlSize(.small).frame(width: 16)
            case .success:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).frame(width: 16)
            case .failure:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red).frame(width: 16)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(model)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                    Spacer()
                    if case .success(let report) = outcome {
                        Text("首字 \(Self.format(report.firstTokenLatency)) · 共 \(Self.format(report.totalLatency))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Self.speedColor(report.firstTokenLatency))
                    }
                }
                switch outcome {
                case .running:
                    Text("请求中…").font(.system(size: 11)).foregroundStyle(.secondary)
                case .success(let report):
                    Text("“\(report.output)”")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                case .failure(let message):
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func run(_ models: [String]) {
        stop()
        order = models
        results = Dictionary(uniqueKeysWithValues: models.map { ($0, Outcome.running) })
        let provider = settings.llmProvider
        let key = apiKey
        task = Task {
            // 逐个测，避免并发请求触发限流，结果也更可比
            for model in models {
                guard !Task.isCancelled else { break }
                do {
                    let report = try await LLMConnectionTester.run(provider: provider, model: model, apiKey: key, settings: settings)
                    results[model] = .success(report)
                } catch is CancellationError {
                    break
                } catch {
                    results[model] = .failure((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                }
            }
            task = nil
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
        for (model, outcome) in results {
            if case .running = outcome { results[model] = .failure("已停止") }
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        seconds < 1 ? "\(Int(seconds * 1000))ms" : String(format: "%.1fs", seconds)
    }

    private static func speedColor(_ firstToken: TimeInterval) -> Color {
        switch firstToken {
        case ..<1.5: return .green
        case ..<4: return .orange
        default: return .red
        }
    }
}

// MARK: - 通用

private struct GeneralSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("登录时启动", isOn: $settings.launchAtLogin)
                Picker("工具条搜索引擎", selection: $settings.searchEngine) {
                    ForEach(SearchEngine.allCases) { engine in
                        Text(engine.label).tag(engine)
                    }
                }
            }

            Section {
                LabeledContent("划词") { Text("选中文字").foregroundStyle(.secondary) }
                LabeledContent("翻译选中文字") { Text(settings.hotKey.label).foregroundStyle(.secondary) }
                LabeledContent("面板内翻译 / 换行") { Text("↩  /  ⇧↩").foregroundStyle(.secondary) }
                LabeledContent("复制译文") { Text("⇧⌘C").foregroundStyle(.secondary) }
                LabeledContent("关闭浮窗") { Text("Esc").foregroundStyle(.secondary) }
            } header: {
                Text("快捷操作")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Helpers

private struct AppIconView: View {
    let bundleID: String

    var body: some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 18, height: 18)
    }

    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

private extension Text {
    func settingsFootnote() -> some View {
        self.font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
