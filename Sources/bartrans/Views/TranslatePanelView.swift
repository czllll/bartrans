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

/// 菜单栏弹出的翻译面板：手动输入 / 粘贴翻译。
struct TranslatePanelView: View {
    static let size = CGSize(width: 360, height: 480)

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
                .transition(.flip)
            } else {
                translateContent
                    .transition(.flip)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onAppear {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .focusTranslatorInput, object: nil)
            }
        }
    }

    private var translateContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            VStack(spacing: 8) {
                inputCard
                directionRow
                outputCard
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            BarTransLogo(size: 22)
            Text("bartrans")
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Spacer()
            IconButton(systemName: "clock.arrow.circlepath", help: "历史记录") {
                withAnimation(.easeInOut(duration: 0.3)) { showHistory = true }
            }
            IconButton(systemName: "gearshape", help: "设置") { onOpenSettings() }
        }
    }

    // MARK: - Input

    private var inputCard: some View {
        ZStack(alignment: .topLeading) {
            SubmitTextView(text: $viewModel.inputText) { viewModel.translate() }
            if viewModel.inputText.isEmpty {
                Text("输入或粘贴要翻译的文字…")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 130)
        .overlay(alignment: .bottomTrailing) {
            if !viewModel.inputText.isEmpty {
                IconButton(systemName: "xmark.circle.fill", help: "清空", size: 11, tint: Color.secondary.opacity(0.6)) {
                    viewModel.inputText = ""
                    viewModel.outputText = ""
                    viewModel.errorMessage = nil
                    NotificationCenter.default.post(name: .focusTranslatorInput, object: nil)
                }
                .padding(4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    private var directionRow: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
            DirectionMenu(viewModel: viewModel)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
        }
        .frame(height: 18)
    }

    // MARK: - Output

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if viewModel.isTranslating && viewModel.outputText.isEmpty {
                    ShimmerLines()
                        .frame(maxHeight: .infinity, alignment: .top)
                } else if viewModel.outputText.isEmpty {
                    Text("译文会显示在这里")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    ScrollView {
                        Text(viewModel.outputText)
                            .font(.system(size: 14))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 11)
            .padding(.top, 9)

            if !viewModel.outputText.isEmpty && viewModel.errorMessage == nil {
                HStack(spacing: 0) {
                    Spacer()
                    IconButton(systemName: "speaker.wave.2", help: "朗读译文", size: 11) { viewModel.speakResult() }
                    IconButton(
                        systemName: justCopied ? "checkmark" : "doc.on.doc",
                        help: "复制译文",
                        size: 11,
                        tint: justCopied ? .green : .secondary
                    ) {
                        viewModel.copyResult()
                        justCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { justCopied = false }
                    }
                }
                .padding(4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.ink.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.ink.opacity(0.12), lineWidth: 0.5)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            EngineMenu(viewModel: viewModel, onOpenSettings: onOpenSettings)

            Spacer()

            Text(shortcutHint)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Button {
                viewModel.translate()
            } label: {
                HStack(spacing: 4) {
                    Text("翻译")
                    Image(systemName: "return")
                        .font(.system(size: 9, weight: .bold))
                        .opacity(0.7)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Capsule().fill(Theme.ink))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Color.primary.opacity(0.035))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5)
        }
    }

    private var shortcutHint: String {
        let hotKey = viewModel.settings.hotKey
        guard hotKey != .none else { return "⇧↩ 换行" }
        return "\(hotKey.label.replacingOccurrences(of: " ", with: "")) 划词翻译"
    }
}
