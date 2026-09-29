import SwiftUI

/// PopClip 风格的划词工具条：选中文字后浮在选区上方的一排小按钮。
struct ActionBarView: View {
    enum Action: CaseIterable {
        case translate, copy, search, speak

        var title: String {
            switch self {
            case .translate: return "翻译"
            case .copy: return "复制"
            case .search: return "搜索"
            case .speak: return "朗读"
            }
        }

        var icon: String {
            switch self {
            case .translate: return "character.bubble"
            case .copy: return "doc.on.doc"
            case .search: return "magnifyingglass"
            case .speak: return "speaker.wave.2"
            }
        }
    }

    var onAction: (Action) -> Void
    var onHover: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Action.allCases.enumerated()), id: \.offset) { index, action in
                if index > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 1, height: 16)
                }
                ActionBarButton(action: action, isPrimary: action == .translate) {
                    onAction(action)
                }
            }
        }
        .padding(3)
        .background(
            Capsule(style: .continuous)
                .fill(Color(white: 0.12).opacity(0.94))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .environment(\.colorScheme, .dark)
        .padding(6) // 给窗口阴影留出空间
        .onHover(perform: onHover)
    }
}

private struct ActionBarButton: View {
    let action: ActionBarView.Action
    let isPrimary: Bool
    let perform: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 4) {
                Image(systemName: action.icon)
                    .font(.system(size: 11, weight: .semibold))
                if isPrimary {
                    Text(action.title)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, isPrimary ? 10 : 8)
            .frame(height: 24)
            .background(
                Capsule(style: .continuous)
                    .fill(hovering ? Color.white.opacity(0.2) : (isPrimary ? BarTransLogo.brandColor.opacity(0.9) : .clear))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(action.title)
    }
}
