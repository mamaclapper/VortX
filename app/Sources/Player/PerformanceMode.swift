import Foundation

/// One switch for a lighter UI and playback path on memory- and GPU-constrained Apple TVs.
///
/// The only weak device that runs current tvOS is the Apple TV HD (4th gen, A8, 2 GB RAM, no
/// dedicated HEVC decode). Every Apple TV 4K has 3 GB or more and an A10X or newer. So we split on
/// physical memory rather than a brittle model list: anything under ~2.5 GB takes the reduced path,
/// which also future-proofs against any new low-end device. Auto by default, overridable in Settings.
///
/// In reduced mode the app drops the living backdrop, trims animations, and slows the play-head
/// re-render so the remote stays responsive while a weak CPU is busy decoding and serving a torrent.
/// On every capable device this is always false and nothing changes.
enum PerformanceMode {
    /// UserDefaults override: "auto" (default), "reduced" (force on), "full" (force off).
    static let overrideKey = "stremiox.performanceMode"

    /// Memory-constrained device (Apple TV HD) or the user forced the reduced path.
    static var reduced: Bool {
        switch UserDefaults.standard.string(forKey: overrideKey) {
        case "reduced": return true
        case "full": return false
        default: return isConstrainedDevice   // "auto" / unset
        }
    }

    /// Apple TV HD (A8) reports ~2 GB; every Apple TV 4K reports 3 GB or more. 2.5 GB cleanly splits
    /// them. Computed once: the hardware does not change under us.
    static let isConstrainedDevice: Bool = ProcessInfo.processInfo.physicalMemory < 2_684_354_560
}
