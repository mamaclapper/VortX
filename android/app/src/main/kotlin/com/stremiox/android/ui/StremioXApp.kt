package com.stremiox.android.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import com.stremiox.android.data.CatalogRepository
import com.stremiox.android.data.PreviewCatalogRepository
import com.stremiox.android.model.MetaItem
import com.stremiox.android.ui.screens.DetailScreen
import com.stremiox.android.ui.screens.DiscoverScreen
import com.stremiox.android.ui.screens.HomeScreen
import com.stremiox.android.ui.screens.LibraryScreen
import com.stremiox.android.ui.screens.SearchScreen
import com.stremiox.android.ui.screens.SettingsScreen
import com.stremiox.android.ui.theme.StremioXTheme

private enum class Tab(val label: String, val icon: ImageVector) {
    HOME("Home", Icons.Filled.Home),
    DISCOVER("Discover", Icons.Filled.Explore),
    LIBRARY("Library", Icons.Filled.VideoLibrary),
    SEARCH("Search", Icons.Filled.Search),
    SETTINGS("Settings", Icons.Filled.Settings),
}

/// The whole app: a five-tab shell matching the iOS and Apple TV structure, with a detail overlay.
/// [repo] defaults to the offline preview source; the real stremio-core engine is injected here once
/// the JNI binding lands, with no change to any screen.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StremioXApp(repo: CatalogRepository = PreviewCatalogRepository()) {
    StremioXTheme {
        var tab by remember { mutableStateOf(Tab.HOME) }
        var detail by remember { mutableStateOf<MetaItem?>(null) }
        val onItem: (MetaItem) -> Unit = { detail = it }

        val current = detail
        if (current != null) {
            DetailScreen(item = current, onBack = { detail = null })
            return@StremioXTheme
        }

        Scaffold(
            topBar = { TopAppBar(title = { Text(tab.label) }) },
            bottomBar = {
                NavigationBar {
                    Tab.entries.forEach { t ->
                        NavigationBarItem(
                            selected = t == tab,
                            onClick = { tab = t },
                            icon = { Icon(t.icon, contentDescription = t.label) },
                            label = { Text(t.label) },
                        )
                    }
                }
            },
        ) { padding ->
            val content = Modifier.padding(padding)
            when (tab) {
                Tab.HOME -> HomeScreen(repo, onItem, content)
                Tab.DISCOVER -> DiscoverScreen(repo, onItem, content)
                Tab.LIBRARY -> LibraryScreen(repo, onItem, content)
                Tab.SEARCH -> SearchScreen(repo, onItem, content)
                Tab.SETTINGS -> SettingsScreen(content)
            }
        }
    }
}
