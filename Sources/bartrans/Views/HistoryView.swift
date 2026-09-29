import SwiftUI

struct HistoryView: View {
    @ObservedObject var historyStore: HistoryStore
    var onClose: () -> Void
    var onSelect: (HistoryEntry) -> Void

    @State private var query = ""

    private var filtered: [HistoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return historyStore.entries }
        return historyStore.entries.filter {
            $0.sourceText.localizedCaseInsensitiveContains(trimmed) || $0.translatedText.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                IconButton(systemName: "chevron.left", help: "返回") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Text("历史记录")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Button("清空") { historyStore.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(historyStore.entries.isEmpty ? Color.secondary.opacity(0.4) : Color.red.opacity(0.85))
                    .disabled(historyStore.entries.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if !historyStore.entries.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    TextField("搜索", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: historyStore.entries.isEmpty ? "clock" : "magnifyingglass")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(historyStore.entries.isEmpty ? "还没有翻译记录" : "没有匹配的记录")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { entry in
                            HistoryRow(entry: entry) { onSelect(entry) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let action: () -> Void

    @State private var hovering = false

    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh-Hans")
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.sourceText)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Self.formatter.localizedString(for: entry.date, relativeTo: Date()))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Text(entry.translatedText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
