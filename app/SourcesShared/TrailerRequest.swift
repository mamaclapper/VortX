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

    /// The libmpv-playable URL: a direct (non-YouTube) trailer stream, or nil. YouTube trailers are NO
    /// longer playable through the embedded server's `/yt` route - tokenless InnerTube extraction now
    /// returns LOGIN_REQUIRED - so a YouTube-only trailer has no playable URL here. iOS/Mac play it through
    /// the WKWebView IFrame (`YouTubeEmbedView`) using `youTubeID` directly; tvOS (no web view) hides the
    /// clip/chip when this is nil. That nil-hides-on-tvOS behavior is exactly the old Lite-build path.
    var playableURL: URL? { directURL }

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
