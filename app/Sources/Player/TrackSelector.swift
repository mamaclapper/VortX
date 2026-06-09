import Foundation

/// Picks the audio and subtitle track to auto-select from the available tracks and the user's
/// preferences. Pure and side-effect free, so it is unit-testable. Shared by both players.
enum TrackSelector {
    /// The audio and subtitle track ids to select. A subtitle id of -1 means "off"; a nil audio id
    /// means "leave mpv's default" (no preferred-language match was found).
    static func select(audio: [MPVTrack], subtitles: [MPVTrack], preferences p: TrackPreferences) -> (audio: Int?, subtitle: Int?) {
        let audioPick = firstMatch(audio, languages: p.audioLanguages, reject: p.rejectTerms)
        let subtitle = selectSubtitle(subtitles, preferences: p, gotPreferredAudio: audioPick != nil)
        return (audioPick?.id, subtitle)
    }

    /// First track whose language matches the priority list and whose title isn't rejected.
    private static func firstMatch(_ tracks: [MPVTrack], languages: [String], reject: [String]) -> MPVTrack? {
        for lang in languages {
            if let t = tracks.first(where: { matches($0.lang, lang) && !isRejected($0, reject) }) { return t }
        }
        return nil
    }

    private static func selectSubtitle(_ subs: [MPVTrack], preferences p: TrackPreferences, gotPreferredAudio: Bool) -> Int? {
        guard !subs.isEmpty else { return -1 }
        // Foreign-language content (no preferred audio matched): show full subtitles so you can follow.
        if !gotPreferredAudio {
            return firstMatch(subs, languages: p.subtitleLanguages, reject: p.rejectTerms)?.id ?? -1
        }
        switch p.forcedPolicy {
        case .off:
            return -1
        case .always:
            return firstMatch(subs, languages: p.subtitleLanguages, reject: p.rejectTerms)?.id ?? -1
        case .forced:
            for lang in p.subtitleLanguages {
                if let t = subs.first(where: { matches($0.lang, lang) && $0.title.lowercased().contains("forced") && !isRejected($0, p.rejectTerms) }) {
                    return t.id
                }
            }
            return -1
        }
    }

    private static func isRejected(_ track: MPVTrack, _ reject: [String]) -> Bool {
        let title = track.title.lowercased()
        return reject.contains { !$0.isEmpty && title.contains($0.lowercased()) }
    }

    /// Language match, tolerant of 2- vs 3-letter ISO codes (en/eng) and region suffixes (en-US).
    static func matches(_ a: String, _ b: String) -> Bool {
        let ca = canonical(a)
        return !ca.isEmpty && ca == canonical(b)
    }

    /// Reduce a language code to a canonical 2-letter form (eng → en, en-US → en, ja → ja).
    static func canonical(_ code: String) -> String {
        let base = code.lowercased().split(separator: "-").first.map(String.init) ?? ""
        if base.count == 3, let two = alpha3to2[base] { return two }
        return String(base.prefix(2))
    }

    private static let alpha3to2: [String: String] = [
        "eng": "en", "spa": "es", "fra": "fr", "fre": "fr", "deu": "de", "ger": "de",
        "ita": "it", "por": "pt", "rus": "ru", "jpn": "ja", "kor": "ko", "zho": "zh",
        "chi": "zh", "ara": "ar", "hin": "hi", "nld": "nl", "dut": "nl", "swe": "sv",
        "nor": "no", "dan": "da", "fin": "fi", "pol": "pl", "tur": "tr", "tha": "th",
        "vie": "vi", "ind": "id", "heb": "he", "ell": "el", "gre": "el", "ces": "cs", "cze": "cs",
    ]
}
