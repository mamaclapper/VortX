import Foundation
import CryptoKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Community trickplay: scrub-preview thumbnails SHARED across users, like Netflix / Plex storyboards.
///
/// Two halves, both 100% fail-soft (any miss / error / offline silently leaves the player on its existing
/// per-device local capture, today's behavior, so there is never a regression):
///
///   1. FETCH-FIRST (`fetch`): on opening a title, compute the content key and GET
///      `trickplay.vortx.tv/tp/{key}`. On a hit, download the sprite-sheet + WEBVTT index ONCE and serve
///      scrub previews by cropping the sprite sub-rect for the scrubbed time — so a title brand new to this
///      device shows previews immediately from the community, with no local generation.
///
///   2. UPLOAD-AFTER-GENERATE (`buildAndUpload`): after the device finishes generating its own local
///      trickplay set, pack the captured JPEG frames into one sprite-sheet, build a matching WEBVTT index,
///      and POST it (first-writer-wins; skipped when the fetch already returned a community set). Gated by a
///      setting and run off the main actor so it never blocks playback.
///
/// CONTENT KEY (computed identically by the Cloudflare Worker):
///   sha1("{imdb}:{season|0}:{episode|0}:{durationBucket}")  durationBucket = floor(duration/10)*10
/// Quality is deliberately NOT in the key (a 720p and 1080p of the same cut share previews); the duration
/// bucket keeps different cuts (theatrical vs extended, or a mismatched file) from colliding.
///
/// Privacy: uploads ONLY the generated sprite + vtt + the content key/metadata (imdb / season / episode /
/// duration-bucket). NEVER an account token, user id, or any PII — none is referenced here.
enum CommunityTrickplay {
    static let baseURL = "https://trickplay.vortx.tv"

    /// The setting gate (default on, like a normal feature). Mirrors the `stremiox.*` @AppStorage namespace
    /// the player already uses; the 0.4 rename seam (`stremiox.` -> `vortx.`) maps it via SettingsBackup.
    static let settingKey = "stremiox.communityTrickplay"

    static var isEnabled: Bool {
        // Absent default = true. UserDefaults returns false for an unset bool, so check object presence.
        if UserDefaults.standard.object(forKey: settingKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: settingKey)
    }

    /// floor(duration/10)*10, matching the Worker's durationBucket.
    static func durationBucket(_ duration: Double) -> Int {
        guard duration.isFinite, duration > 0 else { return 0 }
        return Int(floor(duration / 10) * 10)
    }

    /// sha1("{imdb}:{season|0}:{episode|0}:{durationBucket}") as lowercase hex. nil when the imdb id is not a
    /// real `tt…` id (ad-hoc paste-a-link plays have no shareable identity, so they never touch the service).
    static func contentKey(imdbId: String, season: Int?, episode: Int?, duration: Double) -> String? {
        guard imdbId.range(of: #"^tt\d{6,}$"#, options: .regularExpression) != nil else { return nil }
        let bucket = durationBucket(duration)
        guard bucket > 0 else { return nil }
        let raw = "\(imdbId):\(season ?? 0):\(episode ?? 0):\(bucket)"
        let digest = Insecure.SHA1.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Fetch-first (L1 community layer)

    /// A community sprite-sheet ready to crop. `tiles` maps a frame index to its (x,y) origin in the sheet;
    /// `tileW`/`tileH` are the per-tile size; `intervalS` the seconds between tiles.
    struct Sheet {
        let image: ScrubImage
        let cgImage: CGImage
        let tileW: Int
        let tileH: Int
        let intervalS: Double
        let frameCount: Int
        let cols: Int

        /// The cropped tile nearest `time`, drawn from the sheet sub-rect. nil if out of range.
        func crop(at time: Double) -> ScrubImage? {
            guard frameCount > 0, cols > 0, intervalS > 0 else { return nil }
            let idx = max(0, min(frameCount - 1, Int((time / intervalS).rounded(.down))))
            let col = idx % cols
            let row = idx / cols
            let rect = CGRect(x: col * tileW, y: row * tileH, width: tileW, height: tileH)
            guard let sub = cgImage.cropping(to: rect) else { return nil }
            #if canImport(AppKit)
            return NSImage(cgImage: sub, size: NSSize(width: tileW, height: tileH))
            #else
            return UIImage(cgImage: sub)
            #endif
        }
    }

    private struct FetchResponse: Decodable {
        let sprite: String
        let vtt: String?
        let tile_w: Int
        let tile_h: Int
        let interval_s: Double
        let frame_count: Int
        let cols: Int
    }

    /// GET the community set for `key` and, on a hit, download + decode the sprite. Returns nil on any miss /
    /// error (404, offline, decode failure) so the caller falls back to local generation. Never throws.
    static func fetch(key: String) async -> Sheet? {
        guard let url = URL(string: "\(baseURL)/tp/\(key)") else { return nil }
        do {
            var req = URLRequest(url: url, timeoutInterval: 8)
            req.setValue("application/json", forHTTPHeaderField: "accept")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let meta = try JSONDecoder().decode(FetchResponse.self, from: data)
            guard meta.frame_count > 0, meta.cols > 0, meta.tile_w > 0, meta.tile_h > 0,
                  meta.interval_s > 0, let spriteURL = URL(string: meta.sprite) else { return nil }

            let (imgData, imgResp) = try await URLSession.shared.data(
                for: URLRequest(url: spriteURL, timeoutInterval: 12))
            guard let imgHttp = imgResp as? HTTPURLResponse, imgHttp.statusCode == 200,
                  let image = ScrubImage(data: imgData), let cg = image.cgImageForCrop else { return nil }

            return Sheet(image: image, cgImage: cg, tileW: meta.tile_w, tileH: meta.tile_h,
                         intervalS: meta.interval_s, frameCount: meta.frame_count, cols: meta.cols)
        } catch {
            return nil
        }
    }

    // MARK: - Upload-after-generate (sprite-sheet build + POST)

    /// One captured local frame: its JPEG bytes and the playback time it was grabbed at.
    struct CapturedFrame {
        let time: Double
        let jpeg: Data
    }

    /// Build a sprite-sheet + WEBVTT index from the device's captured frames and POST it (first-writer-wins).
    /// Runs entirely off the main actor. Returns true only if the server stored a NEW set. Never throws.
    ///
    /// `intervalS` is the capture cadence the local pipeline uses (~10s). Frames are sorted by time, packed
    /// left-to-right / top-to-bottom into a grid, and each tile is downscaled to ~480x270 (16:9) so the
    /// sheet stays tiny. The WEBVTT maps each tile's time window to `sprite#xywh=x,y,w,h` (Jellyfin/Plex web
    /// convention); the app crops the sub-rect itself, so no native trickplay support is needed.
    static func buildAndUpload(
        key: String,
        imdbId: String,
        season: Int?,
        episode: Int?,
        durationBucket: Int,
        srcHeight: Int,
        intervalS: Double,
        frames: [CapturedFrame]
    ) async -> Bool {
        guard isEnabled else { return false }
        let sorted = frames.sorted { $0.time < $1.time }
        guard sorted.count >= 2, sorted.count <= 600 else { return false }

        // Tile size: 16:9 at 480 wide is the local capture's native shape (480px, aspect-preserved).
        let tileW = 480, tileH = 270
        let cols = Int(ceil(sqrt(Double(sorted.count))))   // roughly square sheet to bound max dimension
        let rows = Int(ceil(Double(sorted.count) / Double(cols)))

        guard let sheetJPEG = renderSheet(frames: sorted, tileW: tileW, tileH: tileH, cols: cols, rows: rows)
        else { return false }
        // Defensive: keep the upload under the worker's 3 MB cap.
        guard sheetJPEG.count <= 3 * 1024 * 1024 else { return false }

        let vtt = buildVTT(frameCount: sorted.count, cols: cols, tileW: tileW, tileH: tileH, intervalS: intervalS)

        let meta: [String: Any] = [
            "imdb": imdbId,
            "season": season ?? 0,
            "episode": episode ?? 0,
            "durationBucket": durationBucket,
            "frame_count": sorted.count,
            "tile_w": tileW,
            "tile_h": tileH,
            "interval_s": intervalS,
            "cols": cols,
            "src_height": srcHeight,
        ]
        return await post(key: key, sprite: sheetJPEG, vtt: vtt, meta: meta)
    }

    /// Compose the frames into one sheet bitmap and JPEG-encode it. Each frame is drawn scaled-to-fill into
    /// its tile cell. Returns nil on any drawing/encoding failure.
    private static func renderSheet(frames: [CapturedFrame], tileW: Int, tileH: Int, cols: Int, rows: Int) -> Data? {
        let sheetW = cols * tileW, sheetH = rows * tileH
        guard sheetW > 0, sheetH > 0 else { return nil }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: sheetW, height: sheetH, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))
        ctx.interpolationQuality = .medium

        for (i, frame) in frames.enumerated() {
            guard let src = ScrubImage(data: frame.jpeg)?.cgImageForCrop else { continue }
            let col = i % cols
            let row = i / cols
            // CGContext origin is bottom-left; lay tiles out top-to-bottom so the index order matches the vtt.
            let y = (rows - 1 - row) * tileH
            ctx.draw(src, in: CGRect(x: col * tileW, y: y, width: tileW, height: tileH))
        }
        guard let composed = ctx.makeImage() else { return nil }
        return composed.jpegData(quality: 0.7)
    }

    /// WEBVTT mapping each tile window [t, t+interval) to `sprite#xywh=x,y,w,h`. Matches the worker's expected
    /// layout (row-major, cols per row).
    private static func buildVTT(frameCount: Int, cols: Int, tileW: Int, tileH: Int, intervalS: Double) -> String {
        var lines = ["WEBVTT", ""]
        for i in 0..<frameCount {
            let start = Double(i) * intervalS
            let end = Double(i + 1) * intervalS
            let col = i % cols
            let row = i / cols
            let x = col * tileW, y = row * tileH
            lines.append("\(vttTime(start)) --> \(vttTime(end))")
            lines.append("sprite#xywh=\(x),\(y),\(tileW),\(tileH)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func vttTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let ms = Int((seconds - Double(total)) * 1000)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }

    /// POST the multipart body. Returns true only on `{ ok:true, stored:true }`. Never throws.
    private static func post(key: String, sprite: Data, vtt: String, meta: [String: Any]) async -> Bool {
        guard let url = URL(string: "\(baseURL)/tp/\(key)"),
              let metaJSON = try? JSONSerialization.data(withJSONObject: meta),
              let metaString = String(data: metaJSON, encoding: .utf8) else { return false }

        let boundary = "vortx-tp-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        // sprite file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"sprite\"; filename=\"sprite.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(sprite)
        body.append("\r\n".data(using: .utf8)!)
        // vtt file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"vtt\"; filename=\"index.vtt\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/vtt\r\n\r\n".data(using: .utf8)!)
        body.append(vtt.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        // meta field
        field("meta", metaString)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "content-type")
        req.httpBody = body
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return (obj["stored"] as? Bool) == true
        } catch {
            return false
        }
    }
}

// MARK: - Cross-platform image helpers

extension ScrubImage {
    /// A CGImage suitable for cropping/drawing, on both AppKit and UIKit.
    var cgImageForCrop: CGImage? {
        #if canImport(AppKit)
        return cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return cgImage
        #endif
    }
}

extension CGImage {
    /// JPEG-encode a CGImage at the given quality, on both platforms.
    func jpegData(quality: CGFloat) -> Data? {
        #if canImport(AppKit)
        let rep = NSBitmapImageRep(cgImage: self)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        #else
        return UIImage(cgImage: self).jpegData(compressionQuality: quality)
        #endif
    }
}
