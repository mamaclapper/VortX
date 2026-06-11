import Foundation

/// The exact stream each title last played, per profile, so Continue Watching can
/// resume the same link directly instead of routing through the detail page and
/// re-resolving sources. Links can expire (debrid URLs are time-limited); the
/// player's existing load-failure overlay is the fallback when one has.
enum LastStreamStore {
    struct Entry: Codable {
        var videoId: String
        var url: String
        var title: String
        var season: Int?
        var episode: Int?
        var name: String
        var poster: String?
        var type: String
        var qualityText: String?
        var savedAt: Date
    }

    private static func key(_ profileID: UUID) -> String { "stremiox.lastStream.\(profileID.uuidString)" }

    private static func load(_ profileID: UUID) -> [String: Entry] {
        guard let data = UserDefaults.standard.data(forKey: key(profileID)),
              let dict = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return dict
    }

    static func entry(for libraryId: String, profileID: UUID?) -> Entry? {
        guard let profileID else { return nil }
        return load(profileID)[libraryId]
    }

    static func record(libraryId: String, entry: Entry, profileID: UUID?) {
        guard let profileID else { return }
        var dict = load(profileID)
        dict[libraryId] = entry
        if dict.count > 60 {   // cap per profile, oldest out
            dict = Dictionary(uniqueKeysWithValues:
                dict.sorted { $0.value.savedAt > $1.value.savedAt }.prefix(50).map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: key(profileID))
        }
    }
}
