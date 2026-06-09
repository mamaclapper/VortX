import SwiftUI

/// Native tvOS Home, driven by the **stremio-core** engine (via `CoreBridge`): a "Continue Watching"
/// rail plus every catalog of every installed addon, on the StremioX design system (Theme.swift).
struct HomeView: View {
    @EnvironmentObject private var core: CoreBridge
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var account: StremioAccount

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.xl) {
                    header
                    if !core.continueWatching.isEmpty {
                        CoreContinueWatchingRow(items: core.continueWatching)
                    }
                    ForEach(core.boardRows) { row in
                        CoreCatalogRowView(row: row)
                    }
                    if core.continueWatching.isEmpty && core.boardRows.isEmpty {
                        if account.isSignedIn { LoadingRail() } else { CoreEmptyState.signedOut }
                    }
                }
                .padding(.vertical, Theme.Space.xl)
            }
            .background(Theme.Palette.canvas.ignoresSafeArea())
        }
    }

    /// Serif wordmark, the editorial signature: warm-white "Stremio" with an ember "X".
    private var header: some View {
        HStack(spacing: 0) {
            Text("Stremio").foregroundStyle(Theme.Palette.textPrimary)
            Text("X").foregroundStyle(Theme.Palette.accent)
            Spacer()
        }
        .font(Theme.Typography.wordmark)
        .padding(.horizontal, Theme.Space.screenEdge)
    }
}

/// Eyebrow kicker + section title, the shared header for every rail.
struct RailHeader: View {
    var eyebrow: String? = nil
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow { Text(eyebrow).eyebrowStyle() }
            Text(title).sectionTitleStyle()
        }
        .padding(.horizontal, Theme.Space.screenEdge)
    }
}

/// "Continue Watching" rail from the engine (`continue_watching_preview`), newest first, with a
/// resume-progress stripe on each poster.
struct CoreContinueWatchingRow: View {
    let items: [CoreCWItem]
    @EnvironmentObject private var theme: ThemeManager   // observe so the rail's cards repaint on a theme change

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            RailHeader(eyebrow: "Pick up where you left off", title: "Continue Watching")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.Space.lg) {
                    ForEach(items) { item in
                        PosterCard(title: item.name, poster: item.poster,
                                   type: item.type, id: item.id, progress: item.progress,
                                   menu: .continueWatching)
                    }
                }
                .padding(.horizontal, Theme.Space.screenEdge)
                .padding(.vertical, Theme.Space.md)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One engine catalog row from the board (all installed-addon catalogs).
struct CoreCatalogRowView: View {
    let row: CoreBoardRow
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            RailHeader(title: row.title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.Space.lg) {
                    ForEach(row.items) { item in
                        PosterCard(title: item.name, poster: item.poster, type: item.type, id: item.id,
                                   menu: .catalog)
                    }
                }
                .padding(.horizontal, Theme.Space.screenEdge)
                .padding(.vertical, Theme.Space.md)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Skeleton rail shown while the engine is still loading (signed in). Calmer than a spinner.
struct LoadingRail: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            RailHeader(title: "Loading your library")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Space.lg) {
                    ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .fill(Theme.Palette.surface1)
                            .frame(width: kPosterWidth, height: kPosterWidth * 1.5)
                    }
                }
                .padding(.horizontal, Theme.Space.screenEdge)
                .padding(.vertical, Theme.Space.md)
            }
        }
    }
}
