import SwiftUI

/// 菜单栏面板当前显示哪一面。翻译是正面，历史 / 设置翻到背面。
@MainActor
final class PanelNavigation: ObservableObject {
    static let shared = PanelNavigation()

    enum Page { case translate, history, settings }

    @Published var page: Page = .translate

    func show(_ page: Page, animated: Bool = true) {
        guard page != self.page else { return }
        if animated {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { self.page = page }
        } else {
            self.page = page
        }
    }
}

/// 以 Y 轴翻转。只旋转内容本身、不带任何底色，
/// 看起来就是整块面板在翻面，而不是面板里另有一张卡片在转。
private struct FlipModifier: ViewModifier {
    let angle: Double
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
            .opacity(abs(angle) < 90 ? 1 : 0)
    }
}

private extension AnyTransition {
    static var flipFront: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FlipModifier(angle: 90), identity: FlipModifier(angle: 0))
                .animation(.spring(response: 0.45, dampingFraction: 0.86).delay(0.12)),
            removal: .modifier(active: FlipModifier(angle: -90), identity: FlipModifier(angle: 0))
                .combined(with: .opacity)
        )
    }

    static var flipBack: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FlipModifier(angle: -90), identity: FlipModifier(angle: 0))
                .animation(.spring(response: 0.45, dampingFraction: 0.86).delay(0.12)),
            removal: .modifier(active: FlipModifier(angle: 90), identity: FlipModifier(angle: 0))
                .combined(with: .opacity)
        )
    }
}

/// 菜单栏弹出的翻译面板：手动输入 / 粘贴翻译；背面是历史记录和设置。
///
/// 版式是上下两块通栏区域而不是嵌套卡片：上半原文、下半译文，
/// 中间一条语言栏把两者分开——像一张对照的便笺。
struct TranslatePanelView: View {
    static let size = CGSize(width: 400, height: 520)

    @ObservedObject var viewModel: TranslationViewModel
    @ObservedObject var navigation = PanelNavigation.shared
    let permission: AccessibilityPermission

    @State private var justCopied = false

    var body: some View {
        ZStack {
            switch navigation.page {
            case .translate:
                translateContent
                    .transition(.flipBack)
            case .history:
                HistoryView(historyStore: viewModel.historyStore) {
                    navigation.show(.translate)
                } onSelect: { entry in
                    viewModel.inputText = entry.sourceText
                    viewModel.outputText = entry.translatedText
                    viewModel.errorMessage = nil
                    navigation.show(.translate)
                }
                .transition(.flipFront)
            case .settings:
                SettingsView(settings: viewModel.settings, permission: permission) {
                    navigation.show(.translate)
                }
                .transition(.flipFront)
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
        VStack(spacing: 0) {
            header
            inputArea
            languageBar
            outputArea
            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 7) {
            BarTransLogo(size: 18)
            Text("bartrans")
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Spacer()
            IconButton(systemName: "clock.arrow.circlepath", help: "历史记录", size: 11.5) {
                navigation.show(.history)
            }
            IconButton(systemName: "gearshape", help: "设置", size: 11.5) {
                navigation.show(.settings)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 42)
    }

    // MARK: - Input

    private var inputArea: some View {
        ZStack(alignment: .topLeading) {
            SubmitTextView(
                text: $viewModel.inputText,
                fontSize: 15,
                inset: NSSize(width: 16, height: 6)
            ) { viewModel.translate() }

            if viewModel.inputText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("输入或粘贴文字")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                    Text("↩ 翻译  ·  ⇧↩ 换行")
                        .font(.system(size: 11))
                        .foregroundStyle(.quaternary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .allowsHitTesting(false)
            }
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 2) {
                if !viewModel.inputText.isEmpty {
                    Text("\(viewModel.inputText.count)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.quaternary)
                        .padding(.trailing, 4)
                    IconButton(systemName: "speaker.wave.2", help: "朗读原文", size: 11) { viewModel.speakSource() }
                    IconButton(systemName: "xmark", help: "清空", size: 10) {
                        viewModel.inputText = ""
                        viewModel.outputText = ""
                        viewModel.errorMessage = nil
                        NotificationCenter.default.post(name: .focusTranslatorInput, object: nil)
                    }
                } else {
                    IconButton(systemName: "doc.on.clipboard", help: "粘贴并翻译", size: 11) {
                        if let text = NSPasteboard.general.string(forType: .string) {
                            viewModel.inputText = text
                            viewModel.translate()
                        }
                    }
                }
            }
            .padding(.trailing, 10)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Language bar

    private var languageBar: some View {
        let preview = viewModel.languagePreview
        return HStack(spacing: 0) {
            languageButton(preview.source)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Button {
                viewModel.swapDirection()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.inkText)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("互换翻译方向")
            .padding(.horizontal, 6)
            languageButton(preview.target)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 34)
        .padding(.horizontal, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
        }
    }

    private func languageButton(_ title: String) -> some View {
        PopUpMenuButton(items: {
            TranslationDirection.allCases.map { direction in
                PopUpMenuItem(
                    title: direction.menuLabel(primary: viewModel.settings.primary, secondary: viewModel.settings.secondary),
                    isOn: viewModel.direction == direction
                ) {
                    viewModel.direction = direction
                    viewModel.retranslateIfNeeded()
                }
            }
        }) {
            Text(title)
                .lineLimit(1)
        }
    }

    // MARK: - Output

    private var outputArea: some View {
        Group {
            if let error = viewModel.errorMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .font(.system(size: 12.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if viewModel.isTranslating && viewModel.outputText.isEmpty {
                ShimmerLines(widths: [0.92, 0.7, 0.45], lineHeight: 11)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else if viewModel.outputText.isEmpty {
                Text("译文")
                    .font(.system(size: 15))
                    .foregroundStyle(.quaternary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    Text(viewModel.outputText)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.inkText)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 30)
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            if !viewModel.outputText.isEmpty && viewModel.errorMessage == nil {
                HStack(spacing: 2) {
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
                .padding(.trailing, 10)
                .padding(.bottom, 6)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            EngineMenu(viewModel: viewModel) { navigation.show(.settings) }
                .padding(.leading, -6)

            Spacer()

            if viewModel.settings.hotKey != .none {
                Text("\(viewModel.settings.hotKey.label.replacingOccurrences(of: " ", with: "")) 划词")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                    .help("在任意 App 中选中文字后按此快捷键翻译")
            }

            Button {
                viewModel.translate()
            } label: {
                HStack(spacing: 5) {
                    if viewModel.isTranslating {
                        ProgressView().controlSize(.mini).tint(.white)
                    }
                    Text("翻译")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 26)
                .background(Capsule().fill(Theme.ink))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
        }
    }
}
