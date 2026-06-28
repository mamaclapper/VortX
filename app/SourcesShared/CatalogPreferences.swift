import SwiftUI

/// Per-device catalog customization (#0.3.8 add-on manager): which catalog rows show on Home and in
/// what order. Keyed by the same `base|type|id` string CoreBridge.catalogKey builds. The read helpers
/// are plain static UserDefaults reads so `buildBoardRows` can call them off the main actor; the
/// ObservableObject drives the editor UI and asks CoreBridge to rebuild the board on a change.
enum CatalogPrefsStore {
    static let hiddenKey = "stremiox.catalog.hidden"
    static let orderKey = "stremiox.catalog.order"
    static let landscapeKey = "stremiox.catalog.landscapeCards"

    static func hidden() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? []) }
    static func order() -> [String] { UserDefaults.standard.stringArray(forKey: orderKey) ?? [] }
    /// Cinematic landscape (16:9) catalog cards vs the legacy portrait (2:3) posters. Defaults to ON
    /// (the key unset reads true), so a fresh install gets the cinematic look; the Appearance toggle
    /// lets anyone fall back to portrait. Read as a plain static so card views can size off-main.
    static func landscapeCards() -> Bool {
        UserDefaults.standard.object(forKey: landscapeKey) == nil ? true : UserDefaults.standard.bool(forKey: landscapeKey)
    }
    static func setLandscapeCards(_ value: Bool) { UserDefaults.standard.set(value, forKey: landscapeKey) }
    static func isHidden(_ key: String) -> Bool { hidden().contains(key) }
    /// Position in the user's order, or `.max` so unlisted catalogs keep the engine's relative order after the listed ones.
    static func rank(_ key: String) -> Int { order().firstIndex(of: key) ?? Int.max }

    static func setHidden(_ key: String, _ value: Bool) {
        var h = hidden()
        if value { h.insert(key) } else { h.remove(key) }
        UserDefaults.standard.set(Array(h), forKey: hiddenKey)
    }
    static func setOrder(_ keys: [String]) { UserDefaults.standard.set(keys, forKey: orderKey) }
}

@MainActor
final class CatalogPreferences: ObservableObject {
    static let shared = CatalogPreferences()
    @Published private(set) var hidden: Set<String> = CatalogPrefsStore.hidden()
    @Published private(set) var order: [String] = CatalogPrefsStore.order()
    /// Drives whether catalog cards render as cinematic 16:9 landscape pills (TMDB backdrop) or
    /// legacy portrait posters. Two-way bound by the Appearance toggle; persists on change.
    @Published var landscapeCards: Bool = CatalogPrefsStore.landscapeCards() {
        didSet { CatalogPrefsStore.setLandscapeCards(landscapeCards) }
    }
    private init() {}

    func isHidden(_ key: String) -> Bool { hidden.contains(key) }

    func setHidden(_ key: String, _ value: Bool) {
        CatalogPrefsStore.setHidden(key, value)
        hidden = CatalogPrefsStore.hidden()
        CoreBridge.shared.rebuildBoardRows()
    }

    /// Move a catalog up/down within the full ordered list (rebuilds the persisted order from `keys`).
    func reorder(_ keys: [String]) {
        order = keys
        CatalogPrefsStore.setOrder(keys)
        CoreBridge.shared.rebuildBoardRows()
    }
}

/// Editor: every catalog the installed add-ons provide, with a show/hide toggle and move up/down
/// (cross-platform; tvOS has no drag-to-reorder, so explicit buttons work on every target).
struct CatalogManagerView: View {
    @EnvironmentObject private var core: CoreBridge
    @ObservedObject private var prefs = CatalogPreferences.shared

    private var ordered: [CoreBridge.CatalogInfo] {
        // Fall back to the LIVE Home order (boardRows) when the user hasn't set an explicit order, so the
        // editor reflects how catalogs currently appear instead of an arbitrary alphabetical list (Bug 10).
        var boardIndex: [String: Int] = [:]
        for (i, row) in core.boardRows.enumerated() where boardIndex[row.id] == nil { boardIndex[row.id] = i }
        return core.allCatalogs.sorted { a, b in
            let ra = CatalogPrefsStore.rank(a.key), rb = CatalogPrefsStore.rank(b.key)
            if ra != rb { return ra < rb }
            let ba = boardIndex[a.key] ?? Int.max, bb = boardIndex[b.key] ?? Int.max
            if ba != bb { return ba < bb }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    var body: some View {
        #if os(tvOS)
        scrollBody   // focus-driven; reorder via the buttons (no drag gesture on tvOS)
        #else
        listBody     // iPhone / iPad / Mac: drag-to-reorder + the buttons
        #endif
    }

    /// Header shared by both layouts: title, blurb, and the group-by-add-on shortcut.
    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("Customize catalogs")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("Choose which rows appear on Home and the order they show in.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
            if !ordered.isEmpty {
                // One-tap: group every add-on's catalogs together, in add-on (priority) order.
                Button { groupByAddonOrder() } label: {
                    Label("Group by add-on order", systemImage: "rectangle.3.group")
                }
                .buttonStyle(ChipButtonStyle(selected: false))
                .fixedSize()
            }
        }
    }

    private var scrollBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                header
                let items = ordered
                if items.isEmpty {
                    Text("No catalogs yet. Install an add-on that provides catalogs first.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                ForEach(Array(items.enumerated()), id: \.element.key) { index, info in
                    row(info, index: index, total: items.count, keys: items.map(\.key))
                }
            }
            .padding(.horizontal, Theme.Space.screenInset)
            .padding(.vertical, Theme.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Palette.canvas.ignoresSafeArea())
    }

    #if !os(tvOS)
    /// A List so rows can be DRAG-reordered (macOS drags directly; iPhone/iPad use the Edit button). The
    /// per-row move buttons stay as a fallback and for move-to-top/bottom. `.onMove` rewrites the order.
    private var listBody: some View {
        let items = ordered
        return List {
            header
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            if items.isEmpty {
                Text("No catalogs yet. Install an add-on that provides catalogs first.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.key) { index, info in
                    row(info, index: index, total: items.count, keys: items.map(\.key))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: Theme.Space.screenInset, bottom: 4, trailing: Theme.Space.screenInset))
                }
                .onMove { source, dest in
                    var keys = items.map(\.key)
                    keys.move(fromOffsets: source, toOffset: dest)
                    prefs.reorder(keys)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.canvas.ignoresSafeArea())
        #if os(iOS)
        .toolbar { EditButton() }
        #endif
    }
    #endif

    @ViewBuilder
    private func row(_ info: CoreBridge.CatalogInfo, index: Int, total: Int, keys: [String]) -> some View {
        let isHidden = prefs.isHidden(info.key)
        HStack(spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(info.title)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(isHidden ? Theme.Palette.textTertiary : Theme.Palette.textPrimary)
                    .lineLimit(1)
                Text(info.addonName)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Space.sm)
            // Move to top -> up -> down -> bottom, then the show/hide eye. Send-to-top / send-to-bottom
            // are the fast path on a long catalog list (and the only practical reorder on Apple TV).
            Button { move(keys, from: index, to: 0) } label: { Image(systemName: "arrow.up.to.line") }
                .buttonStyle(ChipButtonStyle(selected: false))
                .disabled(index == 0)
            Button { move(keys, from: index, to: index - 1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(ChipButtonStyle(selected: false))
                .disabled(index == 0)
            Button { move(keys, from: index, to: index + 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(ChipButtonStyle(selected: false))
                .disabled(index == total - 1)
            Button { move(keys, from: index, to: total - 1) } label: { Image(systemName: "arrow.down.to.line") }
                .buttonStyle(ChipButtonStyle(selected: false))
                .disabled(index == total - 1)
            Button { prefs.setHidden(info.key, !isHidden) } label: {
                Image(systemName: isHidden ? "eye.slash" : "eye")
            }
            .buttonStyle(ChipButtonStyle(selected: !isHidden))
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func move(_ keys: [String], from: Int, to: Int) {
        guard to >= 0, to < keys.count else { return }
        var next = keys
        let item = next.remove(at: from)
        next.insert(item, at: to)
        prefs.reorder(next)
    }

    /// Reorder every catalog grouped by its add-on, in the add-on (priority) order, so each add-on's
    /// catalogs sit together. Catalogs of an add-on not currently installed keep their relative order at
    /// the end. (Owner request: rearrange catalogs based on add-on order.)
    private func groupByAddonOrder() {
        var addonIndex: [String: Int] = [:]
        for (i, addon) in core.addons.enumerated() { addonIndex[addon.transportUrl] = i }
        let sorted = ordered.enumerated().sorted { a, b in
            let ia = addonIndex[Self.base(of: a.element.key)] ?? Int.max
            let ib = addonIndex[Self.base(of: b.element.key)] ?? Int.max
            return ia != ib ? ia < ib : a.offset < b.offset
        }.map(\.element.key)
        prefs.reorder(sorted)
    }

    /// The add-on transport URL embedded in a catalog key (`base|type|id`).
    private static func base(of key: String) -> String {
        key.components(separatedBy: "|").first ?? key
    }
}
