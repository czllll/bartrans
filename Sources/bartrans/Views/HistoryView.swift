import SwiftUI

struct HistoryView: View {
    @ObservedObject var historyStore: HistoryStore
    var onClose: () -> Void
    var onSelect: (HistoryEntry) -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                .help("返回")

                Label("历史记录", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                Button("清空", role: .destructive) {
                    historyStore.clear()
                }
                .disabled(historyStore.entries.isEmpty)
                .controlSize(.small)
            }
            .padding()

            Divider()

            if historyStore.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("暂无历史记录")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(historyStore.entries) { entry in
                    Button {
                        onSelect(entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Text(entry.sourceText)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                Text(entry.translatedText)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                            }
                            Text("\(entry.engineName) · \(Self.dateFormatter.string(from: entry.date))")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 340, height: 430)
    }
}
