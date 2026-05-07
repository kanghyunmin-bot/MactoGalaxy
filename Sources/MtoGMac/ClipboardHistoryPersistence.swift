import Foundation

final class ClipboardHistoryPersistence {
    private let historyURL: URL

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = appSupport.appendingPathComponent("MtoG", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        historyURL = directory.appendingPathComponent("clipboard-history.json")
    }

    func load() -> [ClipboardHistoryItem]? {
        guard let data = try? Data(contentsOf: historyURL) else { return nil }
        return try? JSONDecoder().decode([ClipboardHistoryItem].self, from: data)
    }

    func save(_ items: [ClipboardHistoryItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: historyURL, options: [.atomic])
    }
}
