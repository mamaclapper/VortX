import SwiftUI

/// The app shell: Home · Discover · Library · Add-ons · Search · Settings. The player is presented in a
/// dedicated key window (see `PlayerWindow`), not here, so the tvOS focus engine cannot leak focus to the
/// tab bar while the player is up.
struct RootTabView: View {
    @EnvironmentObject private var account: StremioAccount

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "safari.fill") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
            AddonsView()
                .tabItem { Label("Add-ons", systemImage: "puzzlepiece.extension.fill") }
            NavigationStack { SearchView() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(Theme.Palette.accent)
    }
}
