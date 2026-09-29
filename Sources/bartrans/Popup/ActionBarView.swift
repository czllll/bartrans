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
        HStack(spacing: 2) {
            TranslateChip { onAction(.translate) }
            ForEach([Action.copy, .search, .speak], id: \.self) { action in
                ActionBarIconButton(action: action) { onAction(action) }
            }
        }
        .padding(3)
        .background(
            Capsule(style: .continuous)
                .fill(Color(red: 0.09, green: 0.10, blue: 0.16).opacity(0.92))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.5
                )
        )
        .environment(\.colorScheme, .dark)
        .padding(8) // 给窗口阴影留出空间
        .onHover(perform: onHover)
    }
}

/// 主操作：荧光笔琥珀色的"译"
private struct TranslateChip: View {
    let perform: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 5) {
                Text("译")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.highlighter)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Theme.inkDeep))
                Text("翻译")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkDeep)
            }
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .frame(height: 26)
            .background(
                Capsule(style: .continuous)
                    .fill(Theme.highlighter.opacity(hovering ? 1 : 0.92))
            )
            .scaleEffect(hovering ? 1.03 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("翻译")
    }
}

private struct ActionBarIconButton: View {
    let action: ActionBarView.Action
    let perform: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: perform) {
            Image(systemName: action.icon)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.78))
                .frame(width: 30, height: 26)
                .background(Capsule(style: .continuous).fill(Color.white.opacity(hovering ? 0.14 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(action.title)
    }
}
