package com.stremiox.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Subtitles
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.stremiox.android.data.CatalogRepository
import com.stremiox.android.model.Catalog
import com.stremiox.android.model.MediaType
import com.stremiox.android.model.MetaItem
import com.stremiox.android.ui.components.PosterCard
import com.stremiox.android.ui.components.PosterRail

/// Discover: a type filter (Movie/Series/...) over add-on catalog rails for that type.
@Composable
fun DiscoverScreen(repo: CatalogRepository, onItem: (MetaItem) -> Unit, modifier: Modifier = Modifier) {
    var type by remember { mutableStateOf(MediaType.MOVIE) }
    val catalogs by produceState(initialValue = emptyList<Catalog>(), type) {
        value = repo.discover(type).getOrDefault(emptyList())
    }
    Column(modifier = modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            MediaType.entries.forEach { t ->
                FilterChip(
                    selected = t == type,
                    onClick = { type = t },
                    label = { Text(t.label) },
                )
            }
        }
        LazyColumn(
            contentPadding = PaddingValues(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            items(catalogs, key = { it.id }) { catalog -> PosterRail(catalog = catalog, onItem = onItem) }
        }
    }
}

/// Library: the user's saved titles in a poster grid.
@Composable
fun LibraryScreen(repo: CatalogRepository, onItem: (MetaItem) -> Unit, modifier: Modifier = Modifier) {
    val items by produceState(initialValue = emptyList<MetaItem>(), repo) {
        value = repo.library().getOrDefault(emptyList())
    }
    PosterGrid(items = items, onItem = onItem, modifier = modifier, emptyHint = "Titles you save appear here.")
}

/// Search: a query field over a poster grid of matches across every installed add-on.
@Composable
fun SearchScreen(repo: CatalogRepository, onItem: (MetaItem) -> Unit, modifier: Modifier = Modifier) {
    var query by remember { mutableStateOf("") }
    val results by produceState(initialValue = emptyList<MetaItem>(), query) {
        value = repo.search(query).getOrDefault(emptyList())
    }
    Column(modifier = modifier.fillMaxSize()) {
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
            placeholder = { Text("Search movies, series, channels") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(16.dp),
        )
        PosterGrid(
            items = results,
            onItem = onItem,
            emptyHint = if (query.isBlank()) "Type to search across your add-ons." else "No matches.",
        )
    }
}

/// Settings: the same controls the iOS app exposes. Values are placeholders until the engine and
/// preferences are wired; the structure is final.
@Composable
fun SettingsScreen(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        SettingRow(Icons.Filled.Person, "Account", "Not signed in")
        SettingRow(Icons.Filled.GraphicEq, "Audio output", "Auto")
        SettingRow(Icons.Filled.Subtitles, "Subtitle size", "Medium")
    }
}

@Composable
private fun SettingRow(icon: ImageVector, title: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        Text(title, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onBackground, modifier = Modifier.fillMaxWidth(0.6f))
        Text(value, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun PosterGrid(items: List<MetaItem>, onItem: (MetaItem) -> Unit, modifier: Modifier = Modifier, emptyHint: String) {
    if (items.isEmpty()) {
        Column(modifier = modifier.fillMaxSize().padding(32.dp)) {
            Text(emptyHint, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        return
    }
    LazyVerticalGrid(
        columns = GridCells.Adaptive(minSize = 112.dp),
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        items(items, key = { it.id }) { item -> PosterCard(item = item, onClick = { onItem(item) }) }
    }
}
