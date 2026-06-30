import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
typealias ScrubImage = NSImage
#elseif canImport(UIKit)
typealias ScrubImage = UIImage
#endif

/// Provides scrub-preview thumbnails from locally captured frames.
/// When no server storyboard is available the player captures a frame every ~10 s of playback
/// and stores it via `recordCapturedFrameData`. During scrubbing `show(time:)` serves the
/// nearest stored frame so the user gets a preview even without a network trickplay service.
@MainActor
final class ScrubThumbnailsStore: ObservableObject {
    @Published private(set) var image: ScrubImage?

    private var localCacheKey: String?
    private static let localFrameCache = LocalTrickplayFrameCache()

    // MARK: Community trickplay (shared across users; 100% fail-soft -> local capture)

    /// The downloaded community sheet, when this title had one. While present, `show(time:)` serves a crop
    /// from it instead of the local cache, so a title brand-new to this device shows previews immediately.
    private var communitySheet: CommunityTrickplay.Sheet?
    /// True when the L1 community fetch returned a set, so we skip the upload (first-writer already exists).
    private var communityAlreadyExists = false
    /// The shareable identity for the current title, set by `configureCommunity`. nil for ad-hoc plays.
    private var communityKey: String?
    private var communityImdb: String?
    private var communitySeason: Int?
    private var communityEpisode: Int?
    private var communityDurationBucket = 0
    private var communitySrcHeight = 0
    /// Raw JPEG frames captured THIS session, time-ordered build input for the upload sprite-sheet.
    private var sessionFrames: [CommunityTrickplay.CapturedFrame] = []
    /// Frame count at the last upload. Throttles progressive re-uploads and lets the teardown flush skip a
    /// re-send when no new coverage arrived. Replaces the old one-shot `didUpload` (which lost everything to a
    /// missing teardown).
    private var lastUploadedCount = 0
    /// Capture cadence the local pipeline records at (~every 10s); also the sheet/vtt tile interval.
    private static let captureInterval: Double = 10

    func configure(localCacheKey: String?) {
        guard self.localCacheKey != localCacheKey else { return }
        self.localCacheKey = localCacheKey
        image = nil
        // A new title: drop the previous community sheet + session frames.
        communitySheet = nil
        communityAlreadyExists = false
        communityKey = nil
        sessionFrames = []
        lastUploadedCount = 0
    }

    /// Plumb the shareable identity + kick off the L1 community fetch. Call ONCE per title after the duration
    /// is known (the content key needs it). Fully fail-soft: a miss / error / offline leaves the player on
    /// local capture. Safe to call repeatedly; it acts only the first time a real key resolves.
    func configureCommunity(imdbId: String?, season: Int?, episode: Int?, duration: Double, enabled: Bool = CommunityTrickplay.isEnabled) {
        guard enabled, communityKey == nil, let imdbId,
              let key = CommunityTrickplay.contentKey(imdbId: imdbId, season: season, episode: episode, duration: duration)
        else {
            // Diagnose an empty server table: log WHY we never key (the usual culprit is a non-`tt` libraryId,
            // e.g. a tmdb:/kitsu: id, so contentKey returns nil and nothing is ever captured for upload).
            if enabled, communityKey == nil {
                NSLog("[trickplay] community NOT keyed (need a tt-imdb id + duration): imdb=%@ dur=%.0f", imdbId ?? "nil", duration)
            }
            return
        }
        NSLog("[trickplay] community keyed: %@ (imdb=%@)", key, imdbId)
        communityKey = key
        communityImdb = imdbId
        communitySeason = season
        communityEpisode = episode
        communityDurationBucket = CommunityTrickplay.durationBucket(duration)
        Task { [weak self] in
            let sheet = await CommunityTrickplay.fetch(key: key)
            await MainActor.run {
                guard let self, self.communityKey == key else { return }   // title may have changed
                if let sheet {
                    self.communitySheet = sheet
                    self.communityAlreadyExists = true
                }
            }
        }
    }

    /// Shows the stored frame nearest to `time`. Call while the user is scrubbing. Community sheet first
    /// (shared), then the per-device local cache.
    func show(time: Double) {
        if let sheet = communitySheet, let crop = sheet.crop(at: time) {
            image = crop
            return
        }
        guard let key = localCacheKey,
              let local = Self.localFrameCache.image(for: key, time: time) else {
            image = nil
            return
        }
        image = local
    }

    func clear() {
        image = nil
    }

    /// Stores a captured frame for future scrub previews.
    func recordCapturedFrameData(_ data: Data, at time: Double) {
        guard let key = localCacheKey, !key.isEmpty else { return }
        guard let decoded = ScrubImage(data: data) else {
            NSLog("[trickplay] dropping frame at %.0fs: JPEG decode failed", time)
            return
        }
        #if canImport(AppKit)
        if let cgImage = decoded.cgImage(forProposedRect: nil, context: nil, hints: nil),
           Self.isBlackImage(cgImage) {
            return
        }
        #endif
        Self.localFrameCache.store(image: decoded, data: data, for: key, time: time)
        // Keep the raw JPEG for a possible community upload (bounded; the worker caps at 600 tiles anyway).
        if communityKey != nil, !communityAlreadyExists, sessionFrames.count < 600 {
            sessionFrames.append(CommunityTrickplay.CapturedFrame(time: time, jpeg: data))
            maybeUploadProgressively()   // upload DURING playback, not only at a teardown that may never fire
        }
    }

    /// Upload DURING playback so trickplay is never lost to a missing teardown (movie ends -> home, sleep,
    /// auto-advance, or jetsam all skip the teardown flush below). Pushes once we have a useful set (~5 min in)
    /// then again as coverage roughly doubles; the worker is overwrite-wins, so the fullest capture survives.
    private func maybeUploadProgressively() {
        // Push every ~1 MINUTE of new coverage so a watch never loses its tail no matter where it ends. The
        // worker is overwrite-wins, so each push just improves the stored set; capture is ~every 10s, so a
        // minute is ~6 frames.
        let perMinute = max(1, Int(60.0 / Self.captureInterval))
        guard !communityAlreadyExists, CommunityTrickplay.isEnabled,
              sessionFrames.count >= lastUploadedCount + perMinute,
              let key = communityKey, let imdb = communityImdb else { return }
        pushUpload(key: key, imdb: imdb)
    }

    /// Teardown flush: send the FULL session set if it grew since the last progressive push. No-op when
    /// disabled / no key / the community already had a set / no new coverage since the last upload.
    func finishAndUploadIfNeeded(srcHeight: Int = 0) {
        if srcHeight > 0 { communitySrcHeight = srcHeight }
        guard !communityAlreadyExists, CommunityTrickplay.isEnabled,
              let key = communityKey, let imdb = communityImdb,
              sessionFrames.count >= 2, sessionFrames.count > lastUploadedCount else { return }
        pushUpload(key: key, imdb: imdb)
    }

    /// Build + POST the current session frames off the main actor (fail-soft). Records the uploaded count so
    /// the progressive throttle + teardown flush never re-send the same coverage. Logs the result so an empty
    /// server table can be traced (capture vs key vs POST) from the device log.
    private func pushUpload(key: String, imdb: String) {
        lastUploadedCount = sessionFrames.count
        let frames = sessionFrames
        let season = communitySeason, episode = communityEpisode
        let bucket = communityDurationBucket, height = communitySrcHeight
        Task.detached(priority: .utility) {
            let ok = await CommunityTrickplay.buildAndUpload(
                key: key, imdbId: imdb, season: season, episode: episode,
                durationBucket: bucket, srcHeight: height,
                intervalS: Self.captureInterval, frames: frames)
            NSLog("[trickplay] upload key=%@ frames=%d -> %@", key, frames.count, ok ? "stored" : "failed")
        }
    }

    /// Samples five points; considers the frame black (unrendered) if four or more are near-black.
    #if canImport(AppKit)
    private static func isBlackImage(_ cgImage: CGImage) -> Bool {
        guard cgImage.width > 0, cgImage.height > 0 else { return true }
        let w = cgImage.width, h = cgImage.height
        guard let data = cgImage.dataProvider?.data else { return false }
        let bytes = CFDataGetBytePtr(data)
        let bpr = cgImage.bytesPerRow
        let len = CFDataGetLength(data)
        let points = [(w/4, h/4), (3*w/4, h/4), (w/2, h/2), (w/4, 3*h/4), (3*w/4, 3*h/4)]
        let blackCount = points.filter { x, y in
            let off = y * bpr + x * 4
            guard off + 3 < len else { return false }
            return (bytes?[off] ?? 0) < 30 && (bytes?[off+1] ?? 0) < 30 && (bytes?[off+2] ?? 0) < 30
        }.count
        return blackCount >= 4
    }
    #endif
}

// MARK: - Local frame cache

private final class LocalTrickplayFrameCache {
    private let bucketSeconds: Double = 2
    private let maxLookbackBuckets = 180        // ~6 min back at 2 s per bucket
    private let ttl: TimeInterval = 48 * 3600
    private let maxDiskBytes: Int64 = 256 * 1024 * 1024
    private let ioQueue = DispatchQueue(label: "com.stremiox.trickplay.localcache", qos: .utility)
    /// Bounded in-memory layer of decoded thumbnails. NSCache caps the resident count AND auto-evicts
    /// under memory pressure (it observes the system memory warning) — important on iOS, where this runs
    /// in-process alongside the embedded streaming server and mpv's 4K decode buffers, so an UNBOUNDED
    /// frame map (the original [String:[Int:ScrubImage]], which neither store nor image(for:) ever pruned)
    /// would add straight onto the jetsam pressure. Anything evicted stays on disk and re-decodes on demand.
    private let memory: NSCache<NSString, ScrubImage> = {
        let cache = NSCache<NSString, ScrubImage>()
        #if os(iOS) || os(tvOS)
        cache.countLimit = 40    // ~40 resident thumbnails; the embedded server shares this app's budget
        #else
        cache.countLimit = 240   // macOS server is a separate process, so the app can hold more
        #endif
        return cache
    }()
    private var lastPrune = Date.distantPast

    /// Composite NSCache key for one stream's time bucket (`#` never appears in the base64 stream prefix).
    private func memKey(_ key: String, _ bucket: Int) -> NSString { "\(key)#\(bucket)" as NSString }

    private lazy var cacheDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = base.appendingPathComponent("trickplay-local", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {
        ioQueue.async { _ = self.cacheDirectory }
    }

    func hasFrames(for key: String?) -> Bool {
        guard let key, !key.isEmpty else { return false }
        return ioQueue.sync {
            // NSCache isn't enumerable by prefix; the on-disk presence is the source of truth here.
            let prefix = filePrefix(for: key) + "-"
            let files = (try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
            return files.contains { $0.lastPathComponent.hasPrefix(prefix) }
        }
    }

    func store(image: ScrubImage, data: Data, for key: String, time: Double) {
        let bucket = bucketFor(time)
        ioQueue.async {
            self.memory.setObject(image, forKey: self.memKey(key, bucket))
            try? data.write(to: self.fileURL(for: key, bucket: bucket), options: .atomic)
            self.pruneIfNeeded()
        }
    }

    func image(for key: String, time: Double) -> ScrubImage? {
        let target = bucketFor(time)
        return ioQueue.sync {
            let minBucket = max(0, target - maxLookbackBuckets)
            for bucket in stride(from: target, through: minBucket, by: -1) {
                if let cached = memory.object(forKey: memKey(key, bucket)) { return cached }
                let url = fileURL(for: key, bucket: bucket)
                guard let data = try? Data(contentsOf: url),
                      let decoded = ScrubImage(data: data) else { continue }
                memory.setObject(decoded, forKey: memKey(key, bucket))
                return decoded
            }
            return nil
        }
    }

    private func bucketFor(_ time: Double) -> Int { Int(max(0, floor(time / bucketSeconds))) }

    private func fileURL(for key: String, bucket: Int) -> URL {
        cacheDirectory.appendingPathComponent("\(filePrefix(for: key))-\(bucket).jpg")
    }

    private func filePrefix(for key: String) -> String {
        Data(key.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    private func pruneIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastPrune) > 600 else { return }
        lastPrune = now
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return }
        var retained: [(url: URL, date: Date, size: Int64)] = []
        var total: Int64 = 0
        for file in files {
            guard let vals = try? file.resourceValues(forKeys: Set(keys)),
                  vals.isRegularFile == true else { continue }
            let modified = vals.contentModificationDate ?? .distantPast
            let size = Int64(vals.fileSize ?? 0)
            if now.timeIntervalSince(modified) > ttl { try? FileManager.default.removeItem(at: file); continue }
            total += size
            retained.append((file, modified, size))
        }
        if total > maxDiskBytes {
            for item in retained.sorted(by: { $0.date < $1.date }) {
                if total <= maxDiskBytes { break }
                try? FileManager.default.removeItem(at: item.url)
                total -= item.size
            }
        }
    }

}
