import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    @State private var anthropicKeyInput: String = ""
    @State private var openAIKeyInput: String = ""
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
                        hint("模型固定为 claude-sonnet-4-6")

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
        .frame(width: 420, height: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            anthropicKeyInput = KeychainHelper.shared.load(for: .anthropicAPIKey) ?? ""
            openAIKeyInput = KeychainHelper.shared.load(for: .openAICompatibleAPIKey) ?? ""
        }
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
