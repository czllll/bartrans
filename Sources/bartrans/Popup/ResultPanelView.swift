import SwiftUI

/// 划词翻译的结果浮窗。
struct ResultPanelView: View {
    @ObservedObject var viewModel: TranslationViewModel
    @ObservedObject var state: ResultPanelState
    /// 系统翻译需要挂在视图树里的隐藏 bridge 视图
    let systemBridgeView: AnyView

    var onClose: () -> Void
    var onReplace: () -> Void
    var onOpenSettings: () -> Void

    @State private var sourceExpanded = false
    @State private var dictionaryExpanded = false
    @State private var justCopied = false

    private static let width: CGFloat = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 11)
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 12) {
                source
                result
                if let definition = viewModel.dictionaryDefinition {
                    dictionary(definition)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            footer
        }
        .frame(width: Self.width, alignment: .leading)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .background(systemBridgeView)
        .padding(10) // 给窗口阴影留出空间
        .onChange(of: viewModel.inputText) {
            sourceExpanded = false
            dictionaryExpanded = false
        }
    }

    private var panelBackground: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(.regularMaterial)
            LinearGradient(colors: [Theme.ink.opacity(0.07), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.35))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            BarTransLogo(size: 16)
            DirectionMenu(viewModel: viewModel)

            Spacer(minLength: 4)

            EngineMenu(viewModel: viewModel, onOpenSettings: onOpenSettings)

            HStack(spacing: 0) {
                IconButton(
                    systemName: state.isPinned ? "pin.fill" : "pin",
                    help: state.isPinned ? "取消固定" : "固定浮窗（点击别处不关闭）",
                    size: 11,
                    isActive: state.isPinned
                ) { state.isPinned.toggle() }
                IconButton(systemName: "xmark", help: "关闭 (Esc)", size: 11) { onClose() }
            }
        }
    }

    // MARK: - Source

    @ViewBuilder
    private var source: some View {
        if viewModel.isWordMode {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(viewModel.inputText)
                        .font(.system(size: 26, weight: .semibold, design: .serif))
                        .highlighterMark()
                        .textSelection(.enabled)
                    IconButton(systemName: "speaker.wave.2", help: "朗读", size: 11) { viewModel.speakSource() }
                }
                if let phonetic = viewModel.wordEntry?.phonetic {
                    Text(Self.cleanPhonetic(phonetic))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.highlighter)
                    .frame(width: 2.5)
                Text(viewModel.inputText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .lineLimit(sourceExpanded ? 14 : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { sourceExpanded.toggle() } }
                    .help(sourceExpanded ? "收起原文" : "展开原文")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func cleanPhonetic(_ text: String) -> String {
        var result = text
        for prefix in ["音标：", "音标:", "读音：", "读音:"] where result.hasPrefix(prefix) {
            result = String(result.dropFirst(prefix.count))
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Result

    @ViewBuilder
    private var result: some View {
        if let error = viewModel.errorMessage {
            errorCard(error)
        } else if viewModel.outputText.isEmpty {
            ShimmerLines(widths: viewModel.isWordMode ? [0.5, 0.8] : [1, 0.86, 0.6])
                .padding(.vertical, 4)
        } else if let entry = viewModel.wordEntry {
            wordEntryView(entry)
        } else {
            CappedScrollView(maxHeight: 300) {
                Text(viewModel.outputText)
                    .font(.system(size: viewModel.isWordMode ? 18 : 15, weight: viewModel.isWordMode ? .medium : .regular))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func wordEntryView(_ entry: WordEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(entry.senses, id: \.self) { sense in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let pos = sense.partOfSpeech {
                        Text(pos)
                            .font(.system(size: 10.5, weight: .semibold, design: .serif))
                            .italic()
                            .foregroundStyle(Theme.inkText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.inkText.opacity(0.12)))
                    }
                    Text(sense.meaning)
                        .font(.system(size: 14))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let example = entry.example {
                VStack(alignment: .leading, spacing: 2) {
                    Text(example.sentence)
                        .font(.system(size: 12.5, design: .serif))
                        .italic()
                    if let translation = example.translation {
                        Text(translation)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.primary.opacity(0.15)).frame(width: 2)
                }
                .padding(.top, 2)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("重试") { viewModel.translate() }
                    if viewModel.selectedEngine == .llm {
                        Button("打开设置", action: onOpenSettings)
                    }
                }
                .buttonStyle(.link)
                .font(.system(size: 11, weight: .medium))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Color.orange.opacity(0.1)))
    }

    private func dictionary(_ definition: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { dictionaryExpanded.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .rotationEffect(.degrees(dictionaryExpanded ? 90 : 0))
                        Text("系统词典")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    DictionaryLookup.openInDictionaryApp(viewModel.inputText)
                    onClose()
                } label: {
                    HStack(spacing: 2) {
                        Text("在词典中打开")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if dictionaryExpanded {
                CappedScrollView(maxHeight: 180) {
                    Text(definition)
                        .font(.system(size: 12))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 2) {
            if viewModel.isTranslating {
                ProgressView().controlSize(.mini)
                Text(viewModel.outputText.isEmpty ? "翻译中" : "生成中")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            } else {
                IconButton(systemName: "gearshape", help: "设置", size: 11) { onOpenSettings() }
            }

            Spacer()

            if !viewModel.outputText.isEmpty && viewModel.errorMessage == nil {
                IconButton(systemName: "speaker.wave.2", help: "朗读译文", size: 11) { viewModel.speakResult() }
                if state.canReplace {
                    IconButton(systemName: "text.insert", help: "用译文替换原文", size: 11) { onReplace() }
                        .disabled(viewModel.isTranslating)
                }
                copyButton
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(Color.primary.opacity(0.035))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5)
        }
    }

    private var copyButton: some View {
        Button {
            viewModel.copyResult()
            withAnimation(.easeOut(duration: 0.15)) { justCopied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                withAnimation(.easeOut(duration: 0.15)) { justCopied = false }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(justCopied ? "已复制" : "复制")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Capsule().fill(justCopied ? Color.green : Theme.ink))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("c", modifiers: [.command, .shift])
        .help("复制译文 (⇧⌘C)")
        .padding(.leading, 4)
    }
}

/// 浮窗自身的 UI 状态（与翻译内容无关的部分）。
@MainActor
final class ResultPanelState: ObservableObject {
    @Published var isPinned = false
    /// 原文所在位置可编辑时才显示"替换"
    @Published var canReplace = false
}
