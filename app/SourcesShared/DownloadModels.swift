import Foundation

/// Offline downloads: the device-local data model. These types are OS-agnostic and compile on every
/// Apple target, and the UI now lives on every target too (iOS/Mac in SourcesiOS, Apple TV in
/// SourcesTV's DetailView Download button + TVDownloadsView). A download is a
/// physical file on ONE device plus a row in the local JSON index: it is NEVER E2E-synced and NEVER
/// written into a `libraryItem` document. Playback of a downloaded file still flows through the normal
/// engine progress path (via `PlaybackMeta`), so per-profile watch history / Continue Watching keep
/// working exactly as for a streamed source.

/// Lifecycle of one download. `queued` exists for a future concurrency-limited queue (P2); the v1
/// manager starts a task immediately, so a record normally moves queued -> downloading on creation.
enum DownloadState: String, Codable, Sendable {
    case queued
    case downloading
    case paused
    case completed
    case failed
}

/// One offline download. Identifiable + Codable so it both persists in `index.json` and drives the
/// SwiftUI list directly. All playback-relevant ids (`contentId`/`videoId`/`season`/`episode`) are the
/// SAME values the streaming play path uses, so `playbackMeta` rebuilds a byte-equivalent `PlaybackMeta`
/// and the engine records progress against the right library item.
struct DownloadRecord: Codable, Identifiable, Hashable {
    /// Stable id; also the on-disk filename stem (`<id>.<ext>`), so the file is found without a path
    /// being persisted (paths move between app-container relocations; a relative stem does not).
    let id: UUID

    /// `PlaybackMeta.libraryId` — the movie/series id (the libraryItem `_id`). For a movie this equals
    /// `videoId`; for an episode it is the series id.
    let contentId: String
    /// `PlaybackMeta.videoId` — the movie id, or `imdbId:season:episode` for an episode.
    let videoId: String
    /// "movie" | "series" (the `PlaybackMeta.type`; an episode download carries "series", matching the
    /// streaming episode play path).
    let type: String

    let name: String
    let poster: String?
    let season: Int?
    let episode: Int?

    /// The add-on / source label this download came from (`stream.name`), for display.
    let sourceName: String?
    /// Quality signature (StreamRanking.signature) shown on the row + re-recorded on play, so a CW
    /// resume of a downloaded title keeps quality continuity like a streamed one.
    let qualityText: String?

    /// True when this was a torrent-to-disk download (loopback `127.0.0.1:11470/{hash}/{fileIdx}` via
    /// the `.default` foreground session). Debrid/direct/HTTP are false (true `.background` session).
    /// NOTE: a *finished* download always plays from the LOCAL file with `isTorrent: false`; this flag
    /// only records HOW it was fetched.
    let isTorrent: Bool

    /// `behaviorHints.proxyHeaders.request` the source declared — applied to the download request, since
    /// some CDNs 403 without a specific Referer / User-Agent (the player applies the same headers).
    let headers: [String: String]?

    /// The resolved remote URL the download fetched (debrid/direct https, or the loopback torrent URL).
    /// Kept for diagnostics / a future re-download; playback never uses it once `state == .completed`.
    let remoteURL: String

    /// On-disk filename (`<id>.<ext>`), relative to the Downloads directory. The full `URL` is rebuilt
    /// from the current container path so a relocated container can't strand the file.
    let localFilename: String

    var bytesTotal: Int64
    var bytesDone: Int64
    var state: DownloadState
    let addedAt: Date
    /// Human-readable failure reason when `state == .failed`; nil otherwise.
    var errorText: String?

    init(id: UUID = UUID(), contentId: String, videoId: String, type: String, name: String,
         poster: String?, season: Int?, episode: Int?, sourceName: String?, qualityText: String?,
         isTorrent: Bool, headers: [String: String]?, remoteURL: String, localFilename: String,
         bytesTotal: Int64 = 0, bytesDone: Int64 = 0, state: DownloadState = .queued,
         addedAt: Date = Date(), errorText: String? = nil) {
        self.id = id
        self.contentId = contentId
        self.videoId = videoId
        self.type = type
        self.name = name
        self.poster = poster
        self.season = season
        self.episode = episode
        self.sourceName = sourceName
        self.qualityText = qualityText
        self.isTorrent = isTorrent
        self.headers = headers
        self.remoteURL = remoteURL
        self.localFilename = localFilename
        self.bytesTotal = bytesTotal
        self.bytesDone = bytesDone
        self.state = state
        self.addedAt = addedAt
        self.errorText = errorText
    }

    /// Rebuild the `PlaybackMeta` for play-from-local. Identical to the meta the streaming play path
    /// builds, so the engine + account record progress against the same library item — Continue
    /// Watching / resume keep working offline.
    var playbackMeta: PlaybackMeta {
        PlaybackMeta(libraryId: contentId, videoId: videoId, type: type,
                     name: name, poster: poster, season: season, episode: episode)
    }

    /// Display title, episode-aware (matches the streaming episode title format).
    var displayTitle: String {
        if type == "series", let s = season, let e = episode {
            return "\(name)  ·  S\(s)E\(e)"
        }
        return name
    }

    /// 0...1 download progress; 0 until a total is known (a torrent's total is unknown up front).
    var fractionComplete: Double {
        guard bytesTotal > 0 else { return 0 }
        return min(1, max(0, Double(bytesDone) / Double(bytesTotal)))
    }
}
