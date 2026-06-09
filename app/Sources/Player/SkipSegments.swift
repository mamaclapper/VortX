import Foundation

/// One entry from mpv's `chapter-list` (a title and its start time, in seconds).
struct MPVChapter: Equatable {
    let title: String
    let start: Double
}

/// An intro or outro span the player can offer to skip past.
struct SkipSegment: Equatable, Identifiable {
    enum Kind { case intro, outro }
    let kind: Kind
    let start: Double
    let end: Double
    var id: String { "\(kind == .intro ? "intro" : "outro")-\(Int(start))" }
    var label: String { kind == .intro ? "Skip Intro" : "Skip Outro" }
}

/// Derives skip segments from named media chapters, the universal (no-network) baseline that desktop
/// players use: a chapter whose title reads like an opening/recap becomes an intro, an ending/credits
/// chapter becomes an outro, and the segment runs to the next chapter's start (or the end of the file).
/// Crowd-sourced anime timings (AniSkip) can layer on top later by feeding the same `SkipSegment` model.
enum SkipSegments {
    /// `(token, requiresWholeWord)`. Short ambiguous tokens (anime "OP"/"ED") need a word boundary so
    /// they don't match inside longer words ("op" must not fire on "Opening" or "Stop").
    private static let introTokens: [(String, Bool)] = [
        ("opening", false), ("intro", false), ("recap", false), ("previously", false), ("op", true),
    ]
    private static let outroTokens: [(String, Bool)] = [
        ("ending", false), ("outro", false), ("credits", false), ("closing", false),
        ("preview", false), ("next episode", false), ("ed", true),
    ]

    /// Intro is checked before outro so "opening credits" reads as an intro, not an outro.
    static func detect(chapters: [MPVChapter], duration: Double) -> [SkipSegment] {
        guard !chapters.isEmpty, duration > 0 else { return [] }
        let sorted = chapters.sorted { $0.start < $1.start }
        var segments: [SkipSegment] = []
        for (i, chapter) in sorted.enumerated() {
            let title = chapter.title.lowercased()
            let kind: SkipSegment.Kind?
            if introTokens.contains(where: { matches(title, $0.0, wholeWord: $0.1) }) {
                kind = .intro
            } else if outroTokens.contains(where: { matches(title, $0.0, wholeWord: $0.1) }) {
                kind = .outro
            } else {
                kind = nil
            }
            guard let kind else { continue }
            let end = i + 1 < sorted.count ? sorted[i + 1].start : duration
            guard end > chapter.start + 1 else { continue }   // ignore degenerate / zero-length spans
            segments.append(SkipSegment(kind: kind, start: chapter.start, end: end))
        }
        return segments
    }

    private static func matches(_ title: String, _ token: String, wholeWord: Bool) -> Bool {
        guard let range = title.range(of: token) else { return false }
        guard wholeWord else { return true }
        let before = range.lowerBound == title.startIndex ? nil : title[title.index(before: range.lowerBound)]
        let after = range.upperBound == title.endIndex ? nil : title[range.upperBound]
        func isBoundary(_ c: Character?) -> Bool { c == nil || !c!.isLetter }
        return isBoundary(before) && isBoundary(after)
    }
}
