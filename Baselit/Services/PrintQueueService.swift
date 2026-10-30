import Foundation
import SwiftData

/// Tracks items and containers the user wants to print labels for.
/// Persists queued identifiers in UserDefaults so the queue survives app restarts.
@Observable
final class PrintQueueService {
    /// Each queued entry stores enough info to display in the queue list and generate a label.
    struct QueueEntry: Identifiable, Codable, Equatable {
        var id: String { identifier }
        let name: String
        let identifier: String
        /// "item" or "container"
        let type: String
    }

    private(set) var entries: [QueueEntry] = []

    private let defaultsKey = "printQueueEntries"

    init() {
        loadFromDefaults()
    }

    var count: Int { entries.count }
    var isEmpty: Bool { entries.isEmpty }

    func add(_ entry: QueueEntry) {
        guard !entries.contains(where: { $0.identifier == entry.identifier }) else { return }
        entries.append(entry)
        saveToDefaults()
    }

    func remove(_ entry: QueueEntry) {
        entries.removeAll { $0.identifier == entry.identifier }
        saveToDefaults()
    }

    func removeAll() {
        entries.removeAll()
        saveToDefaults()
    }

    func contains(identifier: String) -> Bool {
        entries.contains { $0.identifier == identifier }
    }

    // MARK: - Persistence

    private func saveToDefaults() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func loadFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([QueueEntry].self, from: data) else {
            return
        }
        entries = decoded
    }
}
