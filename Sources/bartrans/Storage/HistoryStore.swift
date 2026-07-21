import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let sourceText: String
    let translatedText: String
    let engineName: String
    let date: Date

    init(sourceText: String, translatedText: String, engineName: String, date: Date = Date()) {
        self.id = UUID()
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.engineName = engineName
        self.date = date
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    static let maxEntries = 50

    @Published private(set) var entries: [HistoryEntry] = []

    private let defaultsKey = "com.transpop.bartrans.history"

    init() {
        load()
    }

    func add(sourceText: String, translatedText: String, engineName: String) {
        let entry = HistoryEntry(sourceText: sourceText, translatedText: translatedText, engineName: engineName)
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        entries = (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
