import UIKit

/// Hand the playing stream off to another installed player app via its URL scheme.
///
/// tvOS supports custom URL schemes the same way iOS does (UIApplication.open +
/// LSApplicationQueriesSchemes in Info.plist). The menu prefers the players it can
/// actually detect as installed (canOpenURL, which needs the scheme declared in
/// Info-tvOS.plist), but if it detects none it falls back to showing the whole
/// curated list so the user is never stuck with an empty menu and can try whichever
/// player they have. Torrent playback is excluded by the caller: its URL points at
/// this app's embedded server, which suspends with the app, so a handed-off torrent
/// would die seconds after the switch.
enum ExternalPlayers {
    struct Player: Identifiable {
        let name: String
        let scheme: String                       // bare scheme for the canOpenURL probe
        let launch: (String) -> String           // percent-encoded stream URL -> open URL
        var id: String { name }
    }

    /// Curated tvOS players that expose a URL-scheme handoff, preferred order. Keep the
    /// scheme list in sync with LSApplicationQueriesSchemes in Info-tvOS.plist or
    /// canOpenURL silently reports them as not installed.
    static let candidates: [Player] = [
        Player(name: "Infuse", scheme: "infuse",
               launch: { "infuse://x-callback-url/play?url=\($0)" }),
        Player(name: "VLC", scheme: "vlc-x-callback",
               launch: { "vlc-x-callback://x-callback-url/stream?url=\($0)" }),
        Player(name: "Sen Player", scheme: "senplayer",
               launch: { "senplayer://x-callback-url/play?url=\($0)" }),
        Player(name: "OutPlayer", scheme: "outplayer",
               launch: { "outplayer://\($0)" }),
        Player(name: "nPlayer", scheme: "nplayer-stremiox",
               launch: { "nplayer-stremiox://weblink?action=addotgo&url=\($0)" }),
        Player(name: "MX Player", scheme: "mxplayer",
               launch: { "mxplayer://\($0)" }),
    ]

    /// Players detected as installed via canOpenURL.
    static func detected() -> [Player] {
        candidates.filter {
            guard let url = URL(string: "\($0.scheme)://") else { return false }
            return UIApplication.shared.canOpenURL(url)
        }
    }

    /// What the player menu should list: the installed players if any are detected,
    /// otherwise the full curated list (so the menu is never empty and the user can
    /// pick whichever they have, even when detection is blocked).
    static func menu() -> [Player] {
        let installed = detected()
        return installed.isEmpty ? candidates : installed
    }

    /// True when this player is detected as installed (so the menu can mark untested rows).
    static func isInstalled(_ player: Player) -> Bool {
        guard let url = URL(string: "\(player.scheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Open `streamURL` in `player`. Returns false when the URL cannot be encoded.
    @discardableResult
    static func open(_ streamURL: URL, in player: Player) -> Bool {
        guard let encoded = streamURL.absoluteString.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics) else { return false }
        guard let url = URL(string: player.launch(encoded)) else { return false }
        UIApplication.shared.open(url)
        return true
    }
}
