package com.stremiox.android.data

import com.stremiox.android.model.Catalog
import com.stremiox.android.model.MediaType
import com.stremiox.android.model.MetaItem

/// The seam between the UI and the engine. The Compose screens depend only on this interface, so the
/// real stremio-core-kotlin engine (Rust core over JNI, the same engine the iOS/tvOS apps use) lands
/// behind it in a later iteration with no UI churn. Functions are suspend/Result-shaped to match the
/// async, fallible nature of add-on requests.
interface CatalogRepository {
    /// Home rows: Continue Watching first, then the user's add-on catalogs as poster rails.
    suspend fun home(): Result<List<Catalog>>

    /// Discover rows filtered by type (Movie/Series/...), drawn from the installed add-ons.
    suspend fun discover(type: MediaType): Result<List<Catalog>>

    /// The user's saved Library (bookmarked titles).
    suspend fun library(): Result<List<MetaItem>>

    /// Full-text search across every add-on the user has installed.
    suspend fun search(query: String): Result<List<MetaItem>>
}

/// Offline preview data so the UI builds, runs, and is CI-verifiable before the engine is wired.
/// Every poster is null on purpose: the UI must look intentional without images, since real poster
/// URLs only arrive once the engine is connected. This is replaced, not extended, by the engine impl.
class PreviewCatalogRepository : CatalogRepository {

    private fun sample(prefix: String, type: MediaType, count: Int): List<MetaItem> =
        (1..count).map { i ->
            MetaItem(
                id = "$prefix-$i",
                type = type,
                name = "$prefix Title $i",
                year = "20${10 + (i % 15)}",
            )
        }

    override suspend fun home(): Result<List<Catalog>> = Result.success(
        listOf(
            Catalog("continue", "Continue Watching", sample("Resume", MediaType.SERIES, 6)),
            Catalog("popular-movies", "Popular Movies", sample("Movie", MediaType.MOVIE, 10)),
            Catalog("popular-series", "Popular Series", sample("Series", MediaType.SERIES, 10)),
            Catalog("trending", "Trending Now", sample("Trending", MediaType.MOVIE, 10)),
        )
    )

    override suspend fun discover(type: MediaType): Result<List<Catalog>> = Result.success(
        listOf(
            Catalog("top", "Top ${type.label}", sample(type.label, type, 10)),
            Catalog("new", "New ${type.label}", sample("New ${type.label}", type, 10)),
        )
    )

    override suspend fun library(): Result<List<MetaItem>> =
        Result.success(sample("Saved", MediaType.MOVIE, 8))

    override suspend fun search(query: String): Result<List<MetaItem>> =
        Result.success(if (query.isBlank()) emptyList() else sample(query, MediaType.MOVIE, 12))
}
