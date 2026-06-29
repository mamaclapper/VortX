import Foundation

/// Minimal TMDB v3 client, used only when the user has set a TMDB key (see ApiKeys). It enriches the
/// engine's data; it is never required. Recommendations are returned as IMDb ids so they map straight
/// onto the engine's Cinemeta metas. Every call fails soft (returns nil / []), so a flaky or missing
/// key never breaks a screen.
enum TMDBClient {
    private static let host = "https://api.themoviedb.org/3"

    /// IMDb ids recommended for the given IMDb id. `type` is the stremio type ("movie" or "series").
    /// Recommendations whose ORIGIN/language matches the source are surfaced first, so a Korean drama
    /// suggests Korean, a Bollywood film suggests Bollywood, not just same-genre Hollywood.
    static func recommendations(imdbID: String, type: String) async -> [String] {
        guard let key = ApiKeys.tmdbKey(), imdbID.hasPrefix("tt") else { return [] }
        let media = (type == "series") ? "tv" : "movie"
        guard let found = await get("/find/\(imdbID)?external_source=imdb_id&api_key=\(key)"),
              let first = (found[media == "tv" ? "tv_results" : "movie_results"] as? [[String: Any]])?.first,
              let tmdbID = first["id"] as? Int else { return [] }
        let srcLang = first["original_language"] as? String
        guard let recs = await get("/\(media)/\(tmdbID)/recommendations?api_key=\(key)"),
              let results = recs["results"] as? [[String: Any]] else { return [] }
        // Stable sort: same-original-language first, otherwise keep TMDB's popularity order.
        let ranked = results.enumerated().sorted { a, b in
            let am = ((a.element["original_language"] as? String) == srcLang) ? 0 : 1
            let bm = ((b.element["original_language"] as? String) == srcLang) ? 0 : 1
            return am != bm ? am < bm : a.offset < b.offset
        }.map { $0.element }
        let ids = ranked.compactMap { $0["id"] as? Int }.prefix(12)
        // Map each TMDB id back to an IMDb id (concurrently, capped) so results play through the engine.
        return await withTaskGroup(of: (Int, String)?.self) { group in
            for (i, id) in ids.enumerated() {
                group.addTask {
                    guard let ext = await get("/\(media)/\(id)/external_ids?api_key=\(key)"),
                          let imdb = ext["imdb_id"] as? String, imdb.hasPrefix("tt") else { return nil }
                    return (i, imdb)
                }
            }
            var out: [(Int, String)] = []
            for await r in group { if let r { out.append(r) } }
            return out.sorted { $0.0 < $1.0 }.map { $0.1 }   // preserve the language-boosted order
        }
    }

    /// A streaming/rent/buy provider a title is available on, for the "Where to watch" row.
    struct WatchProvider: Identifiable, Hashable {
        let name: String
        let logoURL: String?
        var id: String { name }
    }

    /// Legal streaming availability for a title in the viewer's region, from TMDB's watch/providers
    /// (JustWatch data). `link` is the JustWatch page for the title. Nil when there's no TMDB key, the
    /// id is not an IMDb id, or nothing is listed for the region. Streaming (flatrate) is listed first.
    struct WatchAvailability {
        let link: String?
        let providers: [WatchProvider]
    }

    static var deviceRegion: String { Locale.current.region?.identifier ?? "US" }

    static func watchProviders(imdbID: String, type: String, region: String = TMDBClient.deviceRegion) async -> WatchAvailability? {
        guard let key = ApiKeys.tmdbKey(), imdbID.hasPrefix("tt") else { return nil }
        let media = (type == "series") ? "tv" : "movie"
        guard let found = await get("/find/\(imdbID)?external_source=imdb_id&api_key=\(key)"),
              let first = (found[media == "tv" ? "tv_results" : "movie_results"] as? [[String: Any]])?.first,
              let tmdbID = first["id"] as? Int,
              let prov = await get("/\(media)/\(tmdbID)/watch/providers?api_key=\(key)"),
              let results = prov["results"] as? [String: Any],
              let here = results[region] as? [String: Any] else { return nil }
        let link = here["link"] as? String
        func read(_ bucket: String) -> [WatchProvider] {
            ((here[bucket] as? [[String: Any]]) ?? [])
                .sorted { ($0["display_priority"] as? Int ?? 99) < ($1["display_priority"] as? Int ?? 99) }
                .compactMap { p in
                    guard let name = p["provider_name"] as? String else { return nil }
                    let logo = (p["logo_path"] as? String).map { "https://image.tmdb.org/t/p/w92\($0)" }
                    return WatchProvider(name: name, logoURL: logo)
                }
        }
        // Streaming first, then rent, then buy; dedupe by provider name.
        var seen = Set<String>()
        let merged = (read("flatrate") + read("rent") + read("buy")).filter { seen.insert($0.name).inserted }
        guard !merged.isEmpty else { return nil }
        return WatchAvailability(link: link, providers: merged)
    }

    /// The official YouTube trailer id for a title from TMDB's /videos (the source Stremio trailer add-ons
    /// use). Accepts an IMDb id (tt...) via /find or a `tmdb:[type:]id`. Requires a TMDB key; nil on no key,
    /// no match, or no trailer. Prefers an official Trailer, then any YouTube Trailer/Teaser/Clip.
    static func trailerYouTubeID(metaID: String, type: String) async -> String? {
        guard let key = ApiKeys.tmdbKey() else { return nil }
        let media = (type == "series") ? "tv" : "movie"
        var tmdbID: Int?
        if metaID.hasPrefix("tt") {
            guard let found = await get("/find/\(metaID)?external_source=imdb_id&api_key=\(key)"),
                  let first = (found[media == "tv" ? "tv_results" : "movie_results"] as? [[String: Any]])?.first else { return nil }
            tmdbID = first["id"] as? Int
        } else if metaID.hasPrefix("tmdb:") {
            tmdbID = metaID.split(separator: ":").last.flatMap { Int($0) }
        }
        guard let id = tmdbID,
              let vids = await get("/\(media)/\(id)/videos?api_key=\(key)"),
              let results = vids["results"] as? [[String: Any]] else { return nil }
        let youtube = results.filter { ($0["site"] as? String)?.lowercased() == "youtube" && $0["key"] is String }
        func firstKey(where pred: ([String: Any]) -> Bool) -> String? {
            youtube.first(where: pred).flatMap { $0["key"] as? String }
        }
        if let k = firstKey(where: { ($0["type"] as? String) == "Trailer" && ($0["official"] as? Bool == true) }) { return k }
        if let k = firstKey(where: { ($0["type"] as? String) == "Trailer" }) { return k }
        if let k = firstKey(where: { ["Teaser", "Clip"].contains(($0["type"] as? String) ?? "") }) { return k }
        return youtube.first.flatMap { $0["key"] as? String }
    }

    /// CLEAN landscape artwork for the cinematic cards: a textless 16:9 backdrop + a PNG clearlogo from
    /// TMDB, with NO rating/quality overlay (distinct from the ERDB rating-bake path, which stays opt-in for
    /// posters). Requires a TMDB key; accepts an IMDb id (tt..., via /find) or a `tmdb:[type:]id`. Either URL
    /// is nil when absent. The card layer caches the result so each title resolves once.
    static func landscapeImages(metaID: String, type: String) async -> (backdrop: String?, logo: String?) {
        guard let key = ApiKeys.tmdbKey() else { return (nil, nil) }
        let media = (type == "series") ? "tv" : "movie"
        var tmdbID: Int?
        if metaID.hasPrefix("tt") {
            guard let found = await get("/find/\(metaID)?external_source=imdb_id&api_key=\(key)"),
                  let first = (found[media == "tv" ? "tv_results" : "movie_results"] as? [[String: Any]])?.first else { return (nil, nil) }
            tmdbID = first["id"] as? Int
        } else if metaID.hasPrefix("tmdb:") {
            tmdbID = metaID.split(separator: ":").last.flatMap { Int($0) }
        }
        guard let id = tmdbID,
              let imgs = await get("/\(media)/\(id)/images?api_key=\(key)&include_image_language=en,null") else { return (nil, nil) }
        // Prefer a TEXTLESS backdrop (iso_639_1 == null) for a clean card, else the first available.
        let backdrops = (imgs["backdrops"] as? [[String: Any]]) ?? []
        let bd = ((backdrops.first { ($0["iso_639_1"] as? String) == nil }) ?? backdrops.first)?["file_path"] as? String
        // Prefer a PNG clearlogo (transparent), else the first.
        let logos = (imgs["logos"] as? [[String: Any]]) ?? []
        let lg = ((logos.first { ($0["file_path"] as? String)?.lowercased().hasSuffix(".png") == true }) ?? logos.first)?["file_path"] as? String
        return (bd.map { "https://image.tmdb.org/t/p/w780\($0)" }, lg.map { "https://image.tmdb.org/t/p/w500\($0)" })
    }

    /// A streaming service for a "what's on {service}" Home rail (TMDB watch-provider id + display label).
    struct StreamingService: Identifiable, Hashable {
        let providerID: Int
        let name: String
        var id: Int { providerID }
    }

    /// The major flatrate streaming services, by TMDB watch-provider id (JustWatch). A service with nothing
    /// available in the viewer's region resolves to an empty rail and is dropped, so users outside the US
    /// simply see fewer rails rather than blank rows. Order here is the on-screen order.
    static let majorStreamingServices: [StreamingService] = [
        .init(providerID: 8, name: "Netflix"),
        .init(providerID: 337, name: "Disney+"),
        .init(providerID: 9, name: "Prime Video"),
        .init(providerID: 1899, name: "Max"),
        .init(providerID: 350, name: "Apple TV+"),
        .init(providerID: 531, name: "Paramount+"),
        .init(providerID: 15, name: "Hulu"),
        .init(providerID: 386, name: "Peacock"),
        .init(providerID: 283, name: "Crunchyroll"),
    ]

    /// Titles available on a streaming service in the region (TMDB /discover with_watch_providers, flatrate,
    /// most-popular first), resolved to engine-playable Cinemeta (tt) previews so a tapped card plays through
    /// the engine like any other card. Movie + TV are merged. Returns [] when no TMDB key is set or nothing
    /// is available in-region; titles with no IMDb id are dropped (they would dead-tap without a TMDB meta
    /// add-on). Name + poster come from the discover row itself, so this is one discover call + one
    /// external_ids call per title (capped), not a full meta fetch per card.
    static func streamingProviderTitles(providerID: Int, region: String = deviceRegion, limit: Int = 18) async -> [MetaPreview] {
        guard let key = ApiKeys.tmdbKey() else { return [] }
        async let movieRows = discoverProviderPage(media: "movie", providerID: providerID, region: region, key: key)
        async let tvRows = discoverProviderPage(media: "tv", providerID: providerID, region: region, key: key)
        let movies = await movieRows, series = await tvRows
        // Interleave movie + tv (each already popularity-ordered) so a rail blends both.
        var rows: [(tmdbID: Int, media: String, name: String, poster: String?)] = []
        for i in 0..<max(movies.count, series.count) {
            if i < movies.count { rows.append(movies[i]) }
            if i < series.count { rows.append(series[i]) }
        }
        // Over-fetch (some drop for a missing IMDb id), resolve each TMDB id -> tt concurrently, preserve order.
        let slice = Array(rows.prefix(limit * 2))
        // Resolve external_ids in CAPPED chunks (~6 in flight) instead of spawning all ~36 at once, so the
        // 9 rails together never burst hundreds of concurrent requests at TMDB (429s silently thin the rails)
        // and the in-flight count tracks URLSession's per-host socket budget. Order preserved by row index.
        var resolved: [(Int, MetaPreview)] = []
        for start in stride(from: 0, to: slice.count, by: 6) {
            if resolved.count >= limit { break }   // enough resolved; stop the over-fetch early
            let batch = Array(slice[start..<min(start + 6, slice.count)])
            let part: [(Int, MetaPreview)] = await withTaskGroup(of: (Int, MetaPreview)?.self) { group in
                for (offset, row) in batch.enumerated() {
                    let i = start + offset
                    group.addTask {
                        guard let ext = await get("/\(row.media)/\(row.tmdbID)/external_ids?api_key=\(key)"),
                              let imdb = ext["imdb_id"] as? String, imdb.hasPrefix("tt"),
                              row.poster?.isEmpty == false else { return nil }
                        let type = row.media == "tv" ? "series" : "movie"
                        return (i, MetaPreview(id: imdb, type: type, name: row.name, poster: row.poster, posterShape: nil, popularity: nil))
                    }
                }
                var out: [(Int, MetaPreview)] = []
                for await r in group { if let r { out.append(r) } }
                return out
            }
            resolved.append(contentsOf: part)
        }
        var seen = Set<String>()
        let ordered = resolved.sorted { $0.0 < $1.0 }.map(\.1).filter { seen.insert($0.id).inserted }
        return Array(ordered.prefix(limit))
    }

    // MARK: - Nested-collection Home rails (genres, Top New, Just New)

    /// A TMDB genre for a "Genres" Home rail: a stable movie-genre id, an optional matching TV-genre id
    /// (nil = movies-only for this rail), and a display label. A genre rail blends its movie + TV buckets.
    /// Order in `homeGenres` is the on-screen order.
    struct Genre: Identifiable, Hashable {
        let movieGenreID: Int
        let tvGenreID: Int?
        let name: String
        var id: Int { movieGenreID }
    }

    /// A handful of broad, populated genres for the "Genres" group, in display order. TMDB splits a few
    /// genres between movie and TV (Action vs Action & Adventure, Sci-Fi vs Sci-Fi & Fantasy), so each
    /// carries the matching TV id where it differs; a nil TV id means "movies only for this rail".
    static let homeGenres: [Genre] = [
        .init(movieGenreID: 28, tvGenreID: 10759, name: "Action"),       // TV: Action & Adventure
        .init(movieGenreID: 35, tvGenreID: 35, name: "Comedy"),
        .init(movieGenreID: 18, tvGenreID: 18, name: "Drama"),
        .init(movieGenreID: 53, tvGenreID: nil, name: "Thriller"),       // no direct TV genre
        .init(movieGenreID: 878, tvGenreID: 10765, name: "Sci-Fi"),      // TV: Sci-Fi & Fantasy
        .init(movieGenreID: 27, tvGenreID: nil, name: "Horror"),
        .init(movieGenreID: 16, tvGenreID: 16, name: "Animation"),
        .init(movieGenreID: 10749, tvGenreID: nil, name: "Romance"),
    ]

    /// "How recent counts as new" for the Top New / Just New groups: titles released within this many
    /// months back from today. Keeps both groups to genuinely-current releases, not the all-time catalog.
    static let newWindowMonths = 6

    /// Titles for one genre rail (TMDB /discover by genre, popularity-desc), movie + TV merged, resolved to
    /// engine-playable Cinemeta (tt) previews. [] with no TMDB key or nothing found; the caller then falls
    /// back to Cinemeta genre catalogs (which need no key) so the Genres group still fills.
    static func genreTitles(_ genre: Genre, region: String = deviceRegion, limit: Int = 18) async -> [MetaPreview] {
        guard let key = ApiKeys.tmdbKey() else { return [] }
        async let movieRows = discoverGenrePage(media: "movie", genreID: genre.movieGenreID, key: key)
        // Only fetch a TV bucket for genres that map to a TMDB TV genre (Thriller / Horror / Romance are
        // movie-only here); otherwise the rail is movies-only.
        async let tvRows = tvGenrePageIfAvailable(genre.tvGenreID, key: key)
        return await resolveRows(interleave(await movieRows, await tvRows), key: key, limit: limit)
    }

    /// The TV discover-by-genre page when a TV genre id exists, else []. Keeps `genreTitles`' `async let`
    /// clean (a `.map` closure over an async call won't type-check).
    private static func tvGenrePageIfAvailable(_ tvGenreID: Int?, key: String) async -> [DiscoverRow] {
        guard let tvGenreID else { return [] }
        return await discoverGenrePage(media: "tv", genreID: tvGenreID, key: key)
    }

    /// "Top New": the most popular movies + shows released in the last `newWindowMonths`, merged and
    /// resolved to tt previews. Sorted by popularity (what's hot right now among recent releases).
    static func topNewTitles(region: String = deviceRegion, limit: Int = 24) async -> [MetaPreview] {
        guard let key = ApiKeys.tmdbKey() else { return [] }
        let (from, to) = newWindow()
        async let movieRows = discoverRecentPage(media: "movie", sort: "popularity.desc", from: from, to: to, region: region, key: key)
        async let tvRows = discoverRecentPage(media: "tv", sort: "popularity.desc", from: from, to: to, region: region, key: key)
        return await resolveRows(interleave(await movieRows, await tvRows), key: key, limit: limit)
    }

    /// "New": the freshest movies + shows by release / air date (newest first) within the last
    /// `newWindowMonths`, merged and resolved to tt previews. This is the "just landed" rail.
    static func justNewTitles(region: String = deviceRegion, limit: Int = 24) async -> [MetaPreview] {
        guard let key = ApiKeys.tmdbKey() else { return [] }
        let (from, to) = newWindow()
        async let movieRows = discoverRecentPage(media: "movie", sort: "primary_release_date.desc", from: from, to: to, region: region, key: key)
        async let tvRows = discoverRecentPage(media: "tv", sort: "first_air_date.desc", from: from, to: to, region: region, key: key)
        return await resolveRows(interleave(await movieRows, await tvRows), key: key, limit: limit)
    }

    /// The (from, to) ISO date strings bounding the "new" window: `newWindowMonths` ago through today, so a
    /// "release date desc" sort can't surface far-future scheduled titles with no real release yet.
    private static func newWindow() -> (from: String, to: String) {
        let now = Date()
        let from = Calendar.current.date(byAdding: .month, value: -newWindowMonths, to: now) ?? now
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .iso8601)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return (fmt.string(from: from), fmt.string(from: now))
    }

    /// Interleave two already-ordered row lists (movie + tv) so a rail blends both, movie-first per pair.
    private static func interleave(_ a: [DiscoverRow], _ b: [DiscoverRow]) -> [DiscoverRow] {
        var rows: [DiscoverRow] = []
        for i in 0..<max(a.count, b.count) {
            if i < a.count { rows.append(a[i]) }
            if i < b.count { rows.append(b[i]) }
        }
        return rows
    }

    /// Resolve discover rows to engine-playable tt previews: over-fetch (some drop for a missing IMDb id),
    /// resolve each tmdb id -> tt in CAPPED chunks (~6 in flight) so several rails don't burst hundreds of
    /// concurrent requests at TMDB (429s silently thin rails), preserve order, de-dup, and cap at `limit`.
    /// This is the exact resolve path `streamingProviderTitles` uses, factored out for the new rails.
    private static func resolveRows(_ rows: [DiscoverRow], key: String, limit: Int) async -> [MetaPreview] {
        let slice = Array(rows.prefix(limit * 2))
        var resolved: [(Int, MetaPreview)] = []
        for start in stride(from: 0, to: slice.count, by: 6) {
            if resolved.count >= limit { break }
            let batch = Array(slice[start..<min(start + 6, slice.count)])
            let part: [(Int, MetaPreview)] = await withTaskGroup(of: (Int, MetaPreview)?.self) { group in
                for (offset, row) in batch.enumerated() {
                    let i = start + offset
                    group.addTask {
                        guard let ext = await get("/\(row.media)/\(row.tmdbID)/external_ids?api_key=\(key)"),
                              let imdb = ext["imdb_id"] as? String, imdb.hasPrefix("tt"),
                              row.poster?.isEmpty == false else { return nil }
                        let type = row.media == "tv" ? "series" : "movie"
                        return (i, MetaPreview(id: imdb, type: type, name: row.name, poster: row.poster, posterShape: nil, popularity: nil))
                    }
                }
                var out: [(Int, MetaPreview)] = []
                for await r in group { if let r { out.append(r) } }
                return out
            }
            resolved.append(contentsOf: part)
        }
        var seen = Set<String>()
        let ordered = resolved.sorted { $0.0 < $1.0 }.map(\.1).filter { seen.insert($0.id).inserted }
        return Array(ordered.prefix(limit))
    }

    /// A discover-result row, shared by the genre / recent / provider pages: (tmdb id, media, title, poster).
    private typealias DiscoverRow = (tmdbID: Int, media: String, name: String, poster: String?)

    /// One TMDB discover-by-genre page, popularity-desc, US-English titles.
    private static func discoverGenrePage(media: String, genreID: Int, key: String) async -> [DiscoverRow] {
        let path = "/discover/\(media)?api_key=\(key)&with_genres=\(genreID)"
            + "&sort_by=popularity.desc&vote_count.gte=50&language=en-US&page=1"
        return parseDiscover(await get(path), media: media)
    }

    /// One TMDB discover page bounded by a release/air-date window, with the given sort (popularity for Top
    /// New, release-date for Just New). The date field differs by media (`primary_release_date` vs
    /// `first_air_date`), so bound on the matching `.gte`/`.lte` for each.
    private static func discoverRecentPage(media: String, sort: String, from: String, to: String, region: String, key: String) async -> [DiscoverRow] {
        let dateField = media == "tv" ? "first_air_date" : "primary_release_date"
        let path = "/discover/\(media)?api_key=\(key)&sort_by=\(sort)&\(dateField).gte=\(from)&\(dateField).lte=\(to)"
            + "&vote_count.gte=20&watch_region=\(region)&language=en-US&page=1"
        return parseDiscover(await get(path), media: media)
    }

    /// Decode a TMDB discover/results payload into `DiscoverRow`s (id + title/name + poster).
    private static func parseDiscover(_ obj: [String: Any]?, media: String) -> [DiscoverRow] {
        guard let obj, let results = obj["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { r in
            guard let id = r["id"] as? Int else { return nil }
            let name = (r["title"] as? String) ?? (r["name"] as? String) ?? ""
            let poster = (r["poster_path"] as? String).map { "https://image.tmdb.org/t/p/w342\($0)" }
            return (id, media, name, poster)
        }
    }

    /// One TMDB discover-by-provider page: (tmdb id, media, title, poster URL) rows, flatrate + most popular.
    private static func discoverProviderPage(media: String, providerID: Int, region: String, key: String)
        async -> [(tmdbID: Int, media: String, name: String, poster: String?)] {
        let path = "/discover/\(media)?api_key=\(key)&watch_region=\(region)&with_watch_providers=\(providerID)"
            + "&with_watch_monetization_types=flatrate&sort_by=popularity.desc&language=en-US&page=1"
        guard let obj = await get(path), let results = obj["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { r in
            guard let id = r["id"] as? Int else { return nil }
            let name = (r["title"] as? String) ?? (r["name"] as? String) ?? ""
            let poster = (r["poster_path"] as? String).map { "https://image.tmdb.org/t/p/w342\($0)" }
            return (id, media, name, poster)
        }
    }

    private static func get(_ path: String) async -> [String: Any]? {
        guard let url = URL(string: host + path) else { return nil }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        } catch { return nil }
    }
}
