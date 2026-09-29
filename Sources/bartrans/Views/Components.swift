import SwiftUI

/// 只有图标的小按钮：悬停时出现圆角底色。
struct IconButton: View {
    let systemName: String
    var help: String
    var size: CGFloat = 12
    var tint: Color = .secondary
    var isActive: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(isActive ? Theme.inkText : (hovering ? .primary : tint))
                .frame(width: size + 14, height: size + 12)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hovering || isActive ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// 荧光笔效果：文字下半部分垫一道琥珀色高亮，呼应"划词"。
struct HighlighterMark: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.highlighterSoft)
                    .frame(height: 11)
                    .padding(.horizontal, -3)
                    .offset(y: -3)
            }
    }
}

extension View {
    func highlighterMark() -> some View { modifier(HighlighterMark()) }
}

/// 译文未到达时的骨架占位：几条带流光的圆角条。
struct ShimmerLines: View {
    var widths: [CGFloat] = [1.0, 0.82, 0.55]
    var lineHeight: CGFloat = 10

    @State private var phase: CGFloat = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, fraction in
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.primary.opacity(0.07))
                        .overlay(
                            LinearGradient(
                                colors: [.clear, Color.primary.opacity(0.08), .clear],
                                startPoint: .leading, endPoint: .trailing
                            )
                            .frame(width: geo.size.width * 0.5)
                            .offset(x: phase * geo.size.width)
                        )
                        .clipShape(Capsule())
                        .frame(width: geo.size.width * fraction)
                }
                .frame(height: lineHeight)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                phase = 1.5
            }
        }
    }
}

/// 下拉菜单里的一项。
struct PopUpMenuItem {
    var title: String
    var systemImage: String?
    var isOn: Bool = false
    var isSeparator = false
    var isHeader = false
    var action: () -> Void = {}

    static var separator: PopUpMenuItem { PopUpMenuItem(title: "", isSeparator: true) }
    static func header(_ title: String) -> PopUpMenuItem { PopUpMenuItem(title: title, isHeader: true) }
}

/// 一个带自定义外观的下拉菜单按钮。
///
/// SwiftUI `Menu` 在 macOS 上会被渲染成 NSPopUpButton，自定义字号、图标都会被忽略，
/// 所以这里用普通按钮 + 在鼠标位置弹出 NSMenu 来实现。
struct PopUpMenuButton<Label: View>: View {
    let items: () -> [PopUpMenuItem]
    @ViewBuilder var label: Label

    @State private var hovering = false

    var body: some View {
        Button {
            let menu = NSMenu()
            for item in items() {
                if item.isSeparator {
                    menu.addItem(.separator())
                    continue
                }
                if item.isHeader {
                    menu.addItem(.sectionHeader(title: item.title))
                    continue
                }
                let menuItem = ClosureMenuItem(title: item.title, action: item.action)
                menuItem.state = item.isOn ? .on : .off
                if let systemImage = item.systemImage {
                    menuItem.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
                }
                menu.addItem(menuItem)
            }
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        } label: {
            HStack(spacing: 4) {
                label
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .opacity(0.55)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(hovering ? .primary : .secondary)
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.07 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .fixedSize()
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func fire() { handler() }
}

/// 方向选择：显示实际语言对，点开可强制方向。
struct DirectionMenu: View {
    @ObservedObject var viewModel: TranslationViewModel

    var body: some View {
        PopUpMenuButton(items: {
            TranslationDirection.allCases.map { direction in
                .init(
                    title: direction.menuLabel(primary: viewModel.settings.primary, secondary: viewModel.settings.secondary),
                    isOn: viewModel.direction == direction
                ) {
                    viewModel.direction = direction
                    viewModel.retranslateIfNeeded()
                }
            }
        }) {
            Text(viewModel.directionFullLabel)
        }
        .help("翻译方向")
    }
}

/// 引擎选择：Apple 离线，或者某个 LLM 服务下的某个模型。
/// 选模型会同时切换全局的 LLM 服务与模型设置。
struct EngineMenu: View {
    @ObservedObject var viewModel: TranslationViewModel
    var onOpenSettings: (() -> Void)?

    var body: some View {
        PopUpMenuButton(items: menuItems) {
            HStack(spacing: 4) {
                if let icon = viewModel.selectedEngine.icon {
                    Image(systemName: icon)
                        .font(.system(size: 9.5, weight: .semibold))
                }
                Text(viewModel.engineCaption)
                    .lineLimit(1)
                    .frame(maxWidth: 150)
                    .fixedSize()
            }
        }
        .help("切换翻译引擎 / 模型")
    }

    func menuItems() -> [PopUpMenuItem] {
        let settings = viewModel.settings
        var items: [PopUpMenuItem] = [
            .init(title: EngineKind.system.label, systemImage: EngineKind.system.icon, isOn: viewModel.selectedEngine == .system) {
                select(.system)
            }
        ]
        for provider in LLMProvider.allCases {
            items.append(.separator)
            items.append(.header(provider.label))
            for model in settings.models(for: provider) {
                let isOn = viewModel.selectedEngine == .llm && settings.llmProvider == provider && settings.currentModel(for: provider) == model
                items.append(.init(title: model, isOn: isOn) {
                    settings.llmProvider = provider
                    settings.setCurrentModel(model, for: provider)
                    select(.llm)
                })
            }
        }
        if let onOpenSettings {
            items.append(.separator)
            items.append(.init(title: "管理模型…", systemImage: "slider.horizontal.3") {
                SettingsNavigation.shared.tab = .translation
                onOpenSettings()
            })
        }
        return items
    }

    private func select(_ engine: EngineKind) {
        viewModel.selectedEngine = engine
        // 切换模型时即便引擎没变也要重新翻译
        viewModel.retranslateIfNeeded()
    }
}

extension EngineKind {
    var icon: String? {
        switch self {
        case .system: return "apple.logo"
        case .llm: return nil
        }
    }
}

extension TranslationDirection {
    func menuLabel(primary: AppLanguage, secondary: AppLanguage) -> String {
        switch self {
        case .auto: return "自动识别"
        case .toSecondary: return "\(primary.name) → \(secondary.name)"
        case .toPrimary: return "其它语言 → \(primary.name)"
        }
    }
}

/// 内容较少时高度贴合内容，超过 `maxHeight` 后变成可滚动区域。
/// （浮窗整体是 fixedSize 布局，裸 ScrollView 在这种布局下没有合理的理想高度。）
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
