import Foundation

/// How the player drives audio output, the escape hatch for soundbars and receivers that
/// mis-negotiate audio over HDMI-ARC. The recurring "no sound through my soundbar, but the same
/// Apple TV plays fine straight to the TV, and official Stremio plays it" reports are an ARC
/// format/layout mismatch: the audio path the player hands the bar is one it silently drops.
/// Channel count alone cannot detect this (a 2.1 bar and a TV both report ~2 channels yet one is
/// silent), so the viewer gets an explicit switch.
///
/// Device-scoped: it describes the audio hardware attached to THIS Apple TV, not the viewer, so it
/// stays global (like the HDR tonemap and performance-mode toggles), never per-profile.
enum AudioOutputMode: String, CaseIterable {
    /// Match the route: a multichannel receiver gets native surround, anything stereo gets a clean
    /// downmix. The right default for most setups.
    case auto
    /// Force a guaranteed stereo (2.0) downmix and the most compatible session mode. The reliable
    /// fix when a soundbar or receiver plays no sound, because every endpoint can render 2.0.
    case stereo
    /// Force multichannel even when the route reports stereo, for a receiver that under-reports.
    case surround

    static let key = "stremiox.audioOutputMode"

    static var current: AudioOutputMode {
        AudioOutputMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .auto
    }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .stereo: return "Stereo"
        case .surround: return "Surround"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "Matches your TV or receiver. Best for most setups."
        case .stereo: return "Forces a stereo downmix. Choose this if a soundbar or receiver plays no sound."
        case .surround: return "Forces multichannel for a receiver that supports it but reports stereo."
        }
    }
}
