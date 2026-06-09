import SwiftUI

/// Discover, driven by the **stremio-core** engine (`CatalogWithFilters`): pick a type, catalog, and
/// genre, see the full grid. Each chip carries the engine's own `request`, dispatched back on tap.
struct DiscoverView: View {
    @EnvironmentObject private var core: CoreBridge
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var account: StremioAccount
    @StateObject private var focusModel = FocusedItemModel()
    private let columns = Array(repeating: GridItem(.fixed(kPosterWidth), spacing: Theme.Space.lg), count: 6)

    var body: some View {
        NavigationStack {
            ZStack {
                // The focused title's artwork + details show through the band between the chips
                // and the grid; the grid scrolls over them.
                BrowseHeroBackdrop(model: focusModel, detailsTop: 320)
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.md) {
                        Text("Discover").screenTitleStyle().padding(.horizontal, Theme.Space.screenEdge)
                        if let discover = core.discover {
                            typeChips(discover.selectable.types)
                            catalogChips(discover.selectable.catalogs)
                            genreChips(discover.selectable.extra)
                            Color.clear.frame(height: 380)
                            grid(discover.items)
                        } else if account.isSignedIn {
                            ProgressView().controlSize(.large).tint(Theme.Palette.accent)
                                .padding(Theme.Space.xxl).frame(maxWidth: .infinity)
                        } else {
                            CoreEmptyState.signedOut
                        }
                    }
                    .padding(.vertical, Theme.Space.xl)
                }
            }
            .background(Theme.Palette.canvas.ignoresSafeArea())
        }
        .onAppear { if core.discover == nil { core.loadDiscover() }; seed() }
        .onChange(of: core.discover?.items.first?.id) { seed() }
    }

    private func seed() {
        focusModel.seedIfEmpty(core.discover?.items.first?.focusedHero)
    }

    private func typeChips(_ types: [CoreSelectableType]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.sm) {
                ForEach(types) { type in
                    Button { core.selectDiscover(type.request) } label: { Text(type.type.capitalized) }
                        .buttonStyle(ChipButtonStyle(selected: type.selected))
                }
            }
            .padding(.horizontal, Theme.Space.screenEdge).padding(.vertical, Theme.Space.xs)
        }
    }

    private func catalogChips(_ catalogs: [CoreSelectableCatalog]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.sm) {
                ForEach(catalogs) { catalog in
                    Button { core.selectDiscover(catalog.request) } label: { Text(catalog.catalog).lineLimit(1) }
                        .buttonStyle(ChipButtonStyle(selected: catalog.selected))
                }
            }
            .padding(.horizontal, Theme.Space.screenEdge).padding(.vertical, Theme.Space.xs)
        }
    }

    /// Genre filter chips, only when the selected catalog declares a "genre" extra.
    @ViewBuilder private func genreChips(_ extra: [CoreSelectableExtra]) -> some View {
        if let genre = extra.first(where: { $0.name.caseInsensitiveCompare("genre") == .orderedSame }),
           !genre.options.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.sm) {
                    ForEach(genre.options) { option in
                        Button { core.selectDiscover(option.request) } label: { Text(option.label).lineLimit(1) }
                            .buttonStyle(ChipButtonStyle(selected: option.selected))
                    }
                }
                .padding(.horizontal, Theme.Space.screenEdge).padding(.vertical, Theme.Space.xs)
            }
        }
    }

    @ViewBuilder private func grid(_ items: [CoreMeta]) -> some View {
        if items.isEmpty {
            ProgressView().controlSize(.large).tint(Theme.Palette.accent)
                .padding(Theme.Space.xxl).frame(maxWidth: .infinity)
        } else {
            LazyVGrid(columns: columns, spacing: Theme.Space.xl) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    PosterCard(title: item.name, poster: item.poster, type: item.type, id: item.id,
                               menu: .catalog,
                               onFocus: { focusModel.focus(item.focusedHero, showsDetails: index < 6) })
                }
            }
            .padding(.horizontal, Theme.Space.screenEdge)
            .padding(.top, Theme.Space.sm)
        }
    }
}
