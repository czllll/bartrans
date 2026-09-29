import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var permission: AccessibilityPermission

    @State private var anthropicKeyInput: String = ""
    @State private var openAIKeyInput: String = ""
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                selectionSection

                languageSection

                sectionCard(title: "LLM 引擎", icon: "sparkles") {
                    Picker("", selection: $settings.llmProvider) {
                        ForEach(LLMProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    switch settings.llmProvider {
                    case .anthropic:
                        fieldRow(title: "API Key") {
                            SecureField("Anthropic API Key", text: $anthropicKeyInput)
                                .textFieldStyle(.roundedBorder)
                        }
                        saveClearRow(
                            disabled: anthropicKeyInput.isEmpty,
                            onSave: {
                                KeychainHelper.shared.save(anthropicKeyInput, for: .anthropicAPIKey)
                                showStatus("已保存到 Keychain")
                            },
                            onClear: {
                                KeychainHelper.shared.delete(for: .anthropicAPIKey)
                                anthropicKeyInput = ""
                                showStatus("已清除")
                            }
                        )
                        fieldRow(title: "模型名称") {
                            TextField(AppSettings.defaultAnthropicModel, text: $settings.anthropicModel)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        hint("划词翻译追求速度，可以改用 claude-haiku-4-5；译文会流式逐字显示")

                    case .openAICompatible:
                        fieldRow(title: "Base URL") {
                            TextField("https://api.openai.com/v1", text: $settings.openAIBaseURL)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        fieldRow(title: "模型名称") {
                            TextField("gpt-4o-mini", text: $settings.openAIModel)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        fieldRow(title: "API Key") {
                            SecureField("API Key", text: $openAIKeyInput)
                                .textFieldStyle(.roundedBorder)
                        }
                        saveClearRow(
                            disabled: openAIKeyInput.isEmpty,
                            onSave: {
                                KeychainHelper.shared.save(openAIKeyInput, for: .openAICompatibleAPIKey)
                                showStatus("已保存到 Keychain")
                            },
                            onClear: {
                                KeychainHelper.shared.delete(for: .openAICompatibleAPIKey)
                                openAIKeyInput = ""
                                showStatus("已清除")
                            }
                        )
                        hint("兼容任何 OpenAI Chat Completions 接口：OpenAI 官方、Azure OpenAI、DeepSeek、Ollama/LM Studio 本地代理等")
                    }
                }

                sectionCard(title: "通用", icon: "gearshape") {
                    HStack {
                        Text("默认引擎")
                            .font(.system(size: 12))
                        Spacer()
                        Picker("", selection: $settings.defaultEngine) {
                            ForEach(EngineKind.allCases) { engine in
                                Text(engine.label).tag(engine)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }

                    Divider()

                    HStack {
                        Text("工具条搜索引擎")
                            .font(.system(size: 12))
                        Spacer()
                        Picker("", selection: $settings.searchEngine) {
                            ForEach(SearchEngine.allCases) { engine in
                                Text(engine.label).tag(engine)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }

                    Divider()

                    HStack {
                        Text("登录时启动")
                            .font(.system(size: 12))
                        Spacer()
                        Toggle("", isOn: $settings.launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                if let statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }
            .padding(16)
        }
        .frame(width: 440, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            permission.refresh()
            anthropicKeyInput = KeychainHelper.shared.load(for: .anthropicAPIKey) ?? ""
            openAIKeyInput = KeychainHelper.shared.load(for: .openAICompatibleAPIKey) ?? ""
        }
    }

    // MARK: - 划词

    private var selectionSection: some View {
        sectionCard(title: "划词翻译", icon: "text.cursor") {
            if !permission.isTrusted {
                VStack(alignment: .leading, spacing: 8) {
                    Label("需要「辅助功能」权限才能读取其它 App 中选中的文字", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                    hint("在「系统设置 → 隐私与安全性 → 辅助功能」中打开 bartrans。如果列表里已经有 bartrans 但仍不生效，先用「−」删掉再重新添加。")
                    HStack {
                        Spacer()
                        Button("打开系统设置") {
                            permission.request()
                            permission.openSystemSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                Divider()
            } else {
                Label("辅助功能权限已开启", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
                Divider()
            }

            toggleRow("选中文字后自动弹出", isOn: $settings.selectionEnabled)

            HStack {
                Text("弹出内容")
                    .font(.system(size: 12))
                Spacer()
                Picker("", selection: $settings.selectionBehavior) {
                    ForEach(SelectionBehavior.allCases) { behavior in
                        Text(behavior.label).tag(behavior)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }
            .disabled(!settings.selectionEnabled)

            HStack {
                Text("快捷键翻译选中文字")
                    .font(.system(size: 12))
                Spacer()
                Picker("", selection: $settings.hotKey) {
                    ForEach(HotKeyPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            toggleRow("兼容模式（模拟 ⌘C 读取选中文字）", isOn: $settings.clipboardFallback)
            hint("Chrome、VS Code 等 App 不通过辅助功能暴露选中文字，开启后会短暂借用剪贴板，读取完立即恢复原内容。")

            if !settings.excludedApps.isEmpty {
                Divider()
                Text("已停用划词的 App")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                ForEach(settings.excludedApps, id: \.self) { bundleID in
                    HStack {
                        Text(Self.appName(for: bundleID))
                            .font(.system(size: 12))
                        Text(bundleID)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
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
            hint("右键点击菜单栏图标，可以在当前 App 中停用 / 恢复划词。")
        }
    }

    private var languageSection: some View {
        sectionCard(title: "语言", icon: "globe") {
            languagePicker("母语", selection: $settings.primaryLanguage)
            languagePicker("常用外语", selection: $settings.secondaryLanguage)
            hint("自动识别时：外文译成母语，母语译成常用外语。")
        }
    }

    private func languagePicker(_ title: String, selection: Binding<String>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
            Spacer()
            Picker("", selection: selection) {
                ForEach(AppLanguage.all) { language in
                    Text(language.name).tag(language.code)
                }
            }
            .labelsHidden()
            .frame(width: 140)
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
        }
    }

    @ViewBuilder
    private func fieldRow<Field: View>(title: String, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            field()
        }
    }

    private func saveClearRow(disabled: Bool, onSave: @escaping () -> Void, onClear: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button("清除", action: onClear)
                .controlSize(.small)
            Button("保存", action: onSave)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(disabled)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func showStatus(_ message: String) {
        withAnimation { statusMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if statusMessage == message {
                withAnimation { statusMessage = nil }
            }
        }
    }
}
