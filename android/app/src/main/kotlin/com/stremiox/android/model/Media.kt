package com.stremiox.android.model

/// Domain models for the Android + Android TV client. These mirror the shapes the shared
/// stremio-core engine returns (and the iOS/tvOS apps already render), so the Compose UI is built
/// against them now and the real engine plugs in behind [com.stremiox.android.data.CatalogRepository]
/// without any UI changes.

enum class MediaType(val label: String) {
    MOVIE("Movie"),
    SERIES("Series"),
    CHANNEL("Channel"),
    TV("TV");

    companion object {
        fun fromId(id: String): MediaType = when (id.lowercase()) {
            "movie" -> MOVIE
            "series" -> SERIES
            "channel" -> CHANNEL
            "tv" -> TV
            else -> MOVIE
        }
    }
}

/// A single catalog entry (movie, series, etc.). [poster] is a URL once the engine is wired; until
/// then it is null and the UI renders a typographic placeholder card.
data class MetaItem(
    val id: String,
    val type: MediaType,
    val name: String,
    val poster: String? = null,
    val year: String? = null,
    val description: String? = null,
)

/// A named row of items, e.g. "Continue Watching" or an add-on catalog like "Cinemeta - Popular".
data class Catalog(
    val id: String,
    val title: String,
    val items: List<MetaItem>,
)
