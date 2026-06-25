import SwiftUI

/// ERDB (Easy Ratings Database, easyratingsdb.com, open-source at github.com/realbestia1/erdb) renders
/// posters, backdrops, LOGOS, and episode thumbnails with rating badges and quality overlays baked in. It
/// is token-based: the user pastes their `Tk-...` token (which carries their saved providers, layout, and
/// rating placement server-side), and the renderer URL is simply `{base}/{token}/{type}/{id}.jpg` with NO
/// query string. The base URL is configurable so VortX can later point at a self-hosted instance (e.g. a
/// Cloudflare Worker) instead of easyratingsdb.com.
///
/// Unlike the per-image XRDB transformer, ERDB is the only one of our art providers that also serves a
/// rating-baked LOGO by id, which is exactly what add-on authors asked for.
enum ERDB {
    static let enabledKey = "stremiox.erdb.enabled"   // absent = on (only takes effect once a token is set)
    static let tokenKey = "stremiox.erdb.token"
    static let baseKey = "stremiox.erdb.baseURL"
    static let defaultBase = "https://erdb.vortx.tv"

    static var token: String {
        (UserDefaults.standard.string(forKey: tokenKey) ?? "").trimmingCharacters(in: .whitespaces)
    }

    /// ERDB drives artwork only when the toggle is on AND a token is set (no token = nothing to resolve).
    static var isActive: Bool {
        (UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true) && !token.isEmpty
    }

    /// The renderer URL for a title, or the `fallback` art when inactive or the id is not renderable. `type`
    /// is "poster", "backdrop", "logo", or "thumbnail". The id keeps its scheme (ERDB accepts the colons in
    /// `tmdb:movie:603` / `tt0944947:1:1` directly in the path), so it is inserted raw.
    static func imageURL(_ type: String, id: String, fallback: String?) -> String? {
        guard isActive, let rid = renderableID(id) else { return fallback }
        return "\(normalizedBase())/\(token)/\(type)/\(rid).jpg"
    }

    /// ERDB resolves IMDb, TMDB, TVDB, and the anime id schemes. A custom add-on id it cannot map keeps its
    /// original artwork (return nil so the caller uses the fallback).
    private static func renderableID(_ id: String) -> String? {
        if id.hasPrefix("tt") { return id }
        for scheme in ["tmdb:", "tvdb:", "kitsu:", "anilist:", "mal:", "anidb:", "realimdb:"] where id.hasPrefix(scheme) {
            return id
        }
        return nil
    }

    /// Trimmed base URL, http(s) only, trailing slashes removed; defaults to easyratingsdb.com (or a future
    /// VortX-hosted instance) when the user has not set a custom one.
    private static func normalizedBase() -> String {
        var s = (UserDefaults.standard.string(forKey: baseKey) ?? "").trimmingCharacters(in: .whitespaces)
        if s.isEmpty || !(s.hasPrefix("http://") || s.hasPrefix("https://")) { return defaultBase }
        while s.hasSuffix("/") { s.removeLast() }
        return s.isEmpty ? defaultBase : s
    }
}

/// The single place every poster / backdrop / logo URL is resolved, so the active art provider is chosen
/// once. Precedence: ERDB (when the user set a token) wins, then the VortX / XRDB poster service, then the
/// original add-on artwork. Keeps the three poster call sites and the two logo slots from each re-deciding.
enum PosterArtwork {
    /// True when an art provider bakes ratings onto the image, so the app must NOT also draw its own rating
    /// badge (avoids a double badge).
    static var bakesRatings: Bool { ERDB.isActive || XRDB.isEnabled }

    /// Poster image URL for a title id. ERDB token wins, then VortX / XRDB, then the original poster.
    static func poster(id: String, fallback: String?) -> String? {
        if ERDB.isActive { return ERDB.imageURL("poster", id: id, fallback: fallback) }
        return XRDB.imageURL(id: id, fallback: fallback)
    }

    /// Backdrop image URL. ERDB when active (it bakes ratings/quality on backdrops too), else the original.
    static func backdrop(id: String, fallback: String?) -> String? {
        ERDB.isActive ? ERDB.imageURL("backdrop", id: id, fallback: fallback) : fallback
    }

    /// Title clearart LOGO URL. ERDB serves a rating-baked logo by id when active; otherwise the caller's
    /// existing logo (the add-on `meta.logo` or the metahub clearart) is used unchanged.
    static func logo(id: String?, fallback: String?) -> String? {
        if ERDB.isActive, let id, let url = ERDB.imageURL("logo", id: id, fallback: nil) { return url }
        return fallback
    }
}
