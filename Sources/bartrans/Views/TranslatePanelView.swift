import SwiftUI

private struct FlipModifier: ViewModifier {
    let angle: Double
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0))
            .opacity(angle == 0 ? 1 : 0)
    }
}

private extension AnyTransition {
    static var flip: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FlipModifier(angle: -90), identity: FlipModifier(angle: 0)),
            removal: .modifier(active: FlipModifier(angle: 90), identity: FlipModifier(angle: 0))
        )
    }
}

struct TranslatePanelView: View {
    @ObservedObject var viewModel: TranslationViewModel
    @State private var showHistory = false
    @State private var justCopied = false
    var onOpenSettings: () -> Void

    var body: some View {
        Group {
            if showHistory {
                HistoryView(historyStore: viewModel.historyStore) {
                    withAnimation(.easeInOut(duration: 0.3)) { showHistory = false }
                } onSelect: { entry in
                    viewModel.inputText = entry.sourceText
                    viewModel.outputText = entry.translatedText
                    withAnimation(.easeInOut(duration: 0.3)) { showHistory = false }
                }
                .frame(width: 340)
                .transition(.flip)
            } else {
                translateContent
                    .transition(.flip)
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .focusTranslatorInput, object: nil)
            }
        }
    }

    private var translateContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            engineRow

            labeledCard(title: "输入", accent: false) {
                SubmitTextView(text: $viewModel.inputText) { viewModel.translate() }
                    .frame(height: 84)
            }

            directionDivider

            labeledCard(title: "翻译结果", accent: !viewModel.outputText.isEmpty) {
                resultContent
            }

            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            actionRow
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 8) {
            BarTransLogo(size: 24)
            Text("bartrans")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
            Spacer()
            iconButton("clock.arrow.circlepath", help: "历史记录") {
                withAnimation(.easeInOut(duration: 0.3)) { showHistory = true }
            }
            iconButton("gearshape", help: "设置") { onOpenSettings() }
        }
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(Color.secondary.opacity(0.001)) // 撑满可点击区域
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .help(help)
    }

    private var engineRow: some View {
        Picker("", selection: $viewModel.selectedEngine) {
            ForEach(EngineKind.allCases) { engine in
                Text(engine.label).tag(engine)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: viewModel.selectedEngine) { viewModel.retranslateIfNeeded() }
    }

    private var directionDivider: some View {
        HStack(spacing: 6) {
            Rectangle().fill(Color.secondary.opacity(0.15)).frame(height: 1)
            Button {
                viewModel.toggleDirection()
                viewModel.retranslateIfNeeded()
            } label: {
                Label(viewModel.directionLabel, systemImage: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Rectangle().fill(Color.secondary.opacity(0.15)).frame(height: 1)
        }
    }

    @ViewBuilder
    private func labeledCard<Content: View>(title: String, accent: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accent ? Color.accentColor.opacity(0.08) : Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(accent ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.2))
                )
        }
    }

    private var resultContent: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                Text(viewModel.outputText.isEmpty ? "翻译结果将显示在这里" : viewModel.outputText)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .foregroundStyle(viewModel.outputText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 28))
            }
            .frame(height: 84)

            if !viewModel.outputText.isEmpty {
                Button {
                    viewModel.copyResult()
                    flashCopied()
                } label: {
                    Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(justCopied ? .green : .secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .help("复制翻译结果")
            }
        }
    }

    private var actionRow: some View {
        HStack {
            if viewModel.isTranslating {
                ProgressView().controlSize(.small)
                Text("翻译中…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text(shortcutHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                viewModel.translate()
            } label: {
                Label("翻译", systemImage: "return")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var shortcutHint: String {
        let hotKey = viewModel.settings.hotKey
        let prefix = hotKey == .none ? "" : "\(hotKey.label.replacingOccurrences(of: " ", with: "")) 划词翻译 · "
        return prefix + "↩ 翻译 · ⇧↩ 换行"
    }

    private func flashCopied() {
        justCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            justCopied = false
        }
    }
}
