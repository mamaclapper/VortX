import Foundation

/// Cross-platform "resolve a trailer to a playable URL" type, compiled into every target
/// (SourcesShared is in all of them). A meta's trailer is either a direct (non-YouTube) stream
/// URL or a YouTube id; this collapses both into one `playableURL` the players can hand to libmpv.
///
/// YouTube trailers are played through the embedded server's `/yt/:id` route (server.js: a 301
/// redirect to a direct media URL resolved by ytdl-core), so they need `StremioServer.canProxy`.
/// On the Lite build (no embedded server) a YouTube-only trailer has no `playableURL`, which is
/// what lets the tvOS Trailer button auto-hide there. `watchURL` is the public youtube.com link
/// for surfaces that can open a browser/external player instead (e.g. iOS/macOS).
struct TrailerRequest: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let youTubeID: String?
    /// A non-YouTube `trailerStreams` url, if the meta carried a direct stream.
    let directURL: URL?

    /// Prefer a direct stream; else the embedded server's `/yt` redirect. Nil when neither a
    /// direct URL nor a (proxiable) YouTube id is available.
    var playableURL: URL? {
        if let directURL { return directURL }
        guard let youTubeID, StremioServer.canProxy else { return nil }
        return URL(string: "\(StremioServer.base)/yt/\(youTubeID)")
    }

    /// The public YouTube watch link, for surfaces that open trailers externally.
    var watchURL: URL? {
        youTubeID.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0)") }
    }

    /// Build from a resolved meta: prefer a direct (non-YouTube) trailer stream url, else fall
    /// back to the YouTube id (`trailerStreams` ytId, or a "Trailer" link). Nil when neither exists.
    static func from(meta: CoreMetaItem) -> TrailerRequest? {
        let direct = (meta.trailerStreams ?? [])
            .compactMap { $0.ytId == nil ? $0.url : nil }
            .compactMap { URL(string: $0) }
            .first
        let yt = meta.trailerYouTubeID
        guard direct != nil || yt != nil else { return nil }
        return TrailerRequest(title: meta.name, youTubeID: yt, directURL: direct)
    }
}
