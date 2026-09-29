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
        .frame(width: 520, height: 600)
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
                        .font(.system(size: 12, design: .monospaced))
                    TextField("备选模型", text: $settings.anthropicExtraModels, prompt: Text("多个用逗号分隔"))
                        .font(.system(size: 12, design: .monospaced))
                    keyRow(input: $anthropicKeyInput, account: .anthropicAPIKey, provider: .anthropic)
                case .openAICompatible:
                    TextField("Base URL", text: $settings.openAIBaseURL, prompt: Text(AppSettings.defaultOpenAIBaseURL))
                        .font(.system(size: 12, design: .monospaced))
                    TextField("当前模型", text: $settings.openAIModel, prompt: Text(AppSettings.defaultOpenAIModel))
                        .font(.system(size: 12, design: .monospaced))
                    TextField("备选模型", text: $settings.openAIExtraModels, prompt: Text("如 deepseek-chat, deepseek-reasoner"))
                        .font(.system(size: 12, design: .monospaced))
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
