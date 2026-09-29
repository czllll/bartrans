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

    private static let width: CGFloat = 380

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            source
            Divider().opacity(0.6)
            result
            if let definition = viewModel.dictionaryDefinition {
                dictionary(definition)
            }
            footer
        }
        .padding(12)
        .frame(width: Self.width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .background(systemBridgeView)
        .padding(8) // 给窗口阴影留出空间
        .onChange(of: viewModel.inputText) {
            sourceExpanded = false
            dictionaryExpanded = false
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            BarTransLogo(size: 18)

            Button {
                viewModel.toggleDirection()
                viewModel.retranslateIfNeeded()
            } label: {
                HStack(spacing: 3) {
                    Text(viewModel.directionLabel)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help("切换翻译方向（\(viewModel.direction.label(primary: viewModel.settings.primary, secondary: viewModel.settings.secondary))）")

            Picker("", selection: $viewModel.selectedEngine) {
                ForEach(EngineKind.allCases) { engine in
                    Text(engine.label).tag(engine)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 118)
            .onChange(of: viewModel.selectedEngine) { viewModel.retranslateIfNeeded() }

            Spacer(minLength: 0)

            iconButton(state.isPinned ? "pin.fill" : "pin", help: state.isPinned ? "取消固定" : "固定浮窗（点击别处不关闭）", tint: state.isPinned ? .accentColor : .secondary) {
                state.isPinned.toggle()
            }
            iconButton("gearshape", help: "设置") { onOpenSettings() }
            iconButton("xmark", help: "关闭 (Esc)") { onClose() }
        }
    }

    // MARK: - Source

    @ViewBuilder
    private var source: some View {
        if viewModel.isWordMode {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(viewModel.inputText)
                    .font(.system(size: 20, weight: .semibold))
                    .textSelection(.enabled)
                speakButton { viewModel.speakSource() }
            }
        } else {
            HStack(alignment: .top, spacing: 4) {
                Text(viewModel.inputText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(sourceExpanded ? 12 : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture { sourceExpanded.toggle() }
                    .help(sourceExpanded ? "收起原文" : "展开原文")
                speakButton { viewModel.speakSource() }
            }
        }
    }

    // MARK: - Result

    @ViewBuilder
    private var result: some View {
        if let error = viewModel.errorMessage {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(error)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                    if viewModel.selectedEngine == .llm || error.contains("Key") {
                        Button("打开设置", action: onOpenSettings)
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                    }
                }
            }
        } else if viewModel.outputText.isEmpty {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("翻译中…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 22)
        } else {
            CappedScrollView(maxHeight: 280) {
                Text(viewModel.outputText)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func dictionary(_ definition: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { dictionaryExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(dictionaryExpanded ? 90 : 0))
                        Image(systemName: "book.closed")
                        Text("系统词典")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button("在词典中打开") {
                    DictionaryLookup.openInDictionaryApp(viewModel.inputText)
                    onClose()
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }

            if dictionaryExpanded {
                CappedScrollView(maxHeight: 180) {
                    Text(definition)
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Text(engineCaption)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer()

            if !viewModel.outputText.isEmpty {
                footerButton("speaker.wave.2", title: "朗读") { viewModel.speakResult() }
                if state.canReplace {
                    footerButton("arrow.2.squarepath", title: "替换") { onReplace() }
                        .disabled(viewModel.isTranslating)
                        .help("用译文替换原文中选中的内容")
                }
                footerButton(justCopied ? "checkmark" : "doc.on.doc", title: justCopied ? "已复制" : "复制") {
                    viewModel.copyResult()
                    justCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { justCopied = false }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
    }

    private var engineCaption: String {
        if viewModel.isTranslating && !viewModel.outputText.isEmpty { return "生成中…" }
        return viewModel.selectedEngine == .system ? "Apple 离线翻译" : "LLM · \(viewModel.settings.llmProvider.label)"
    }

    // MARK: - Pieces

    private func iconButton(_ systemName: String, help: String, tint: Color = .secondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func speakButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("朗读原文")
    }

    private func footerButton(_ systemName: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// 浮窗自身的 UI 状态（与翻译内容无关的部分）。
@MainActor
final class ResultPanelState: ObservableObject {
    @Published var isPinned = false
    /// 原文所在位置可编辑时才显示"替换"
    @Published var canReplace = false
}

/// 内容较少时高度贴合内容，超过 `maxHeight` 后变成可滚动区域。
/// （面板整体是 fixedSize 布局，裸 ScrollView 在这种布局下没有合理的理想高度。）
struct CappedScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            content
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollIndicators(contentHeight > maxHeight ? .automatic : .never)
        .frame(height: min(max(contentHeight, 16), maxHeight))
    }
}
