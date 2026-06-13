import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// SwiftUI's controller-representable protocol differs by platform; alias it so the struct body is
// shared and only the make/update/dismantle methods (whose names differ) branch below.
#if canImport(UIKit)
typealias PlatformViewControllerRepresentable = UIViewControllerRepresentable
#elseif canImport(AppKit)
typealias PlatformViewControllerRepresentable = NSViewControllerRepresentable
#endif

struct MPVMetalPlayerView: PlatformViewControllerRepresentable {
    @ObservedObject var coordinator: Coordinator

    /// Shared construction + wiring of the player controller (identical on every platform).
    private func makeController(_ context: Context) -> MPVMetalViewController {
        let mpv = MPVMetalViewController()
        mpv.playDelegate = coordinator
        mpv.playUrl = coordinator.playUrl
        mpv.playHeaders = coordinator.playHeaders
        mpv.playUrlLive = coordinator.playLive
        let coord = context.coordinator
        mpv.onSingleTap = { [weak coord] in coord?.onTap?() }
        context.coordinator.player = mpv
        return mpv
    }

    #if canImport(UIKit)
    func makeUIViewController(context: Context) -> MPVMetalViewController { makeController(context) }
    func updateUIViewController(_ controller: MPVMetalViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: MPVMetalViewController, coordinator: Coordinator) {
        controller.stop()
    }
    #elseif canImport(AppKit)
    func makeNSViewController(context: Context) -> MPVMetalViewController { makeController(context) }
    func updateNSViewController(_ controller: MPVMetalViewController, context: Context) {}
    static func dismantleNSViewController(_ controller: MPVMetalViewController, coordinator: Coordinator) {
        controller.stop()
    }
    #endif

    public func makeCoordinator() -> Coordinator {
        coordinator
    }

    func play(_ url: URL, headers: [String: String]? = nil) -> Self {
        coordinator.playUrl = url
        coordinator.playHeaders = headers
        return self
    }

    func live(_ live: Bool) -> Self {
        coordinator.playLive = live
        return self
    }

    func onPropertyChange(_ handler: @escaping (MPVMetalViewController, String, Any?) -> Void) -> Self {
        coordinator.onPropertyChange = handler
        return self
    }

    func onTap(_ handler: @escaping () -> Void) -> Self {
        coordinator.onTap = handler
        return self
    }

    @MainActor
    public final class Coordinator: MPVPlayerDelegate, ObservableObject {
        weak var player: MPVMetalViewController?

        var playUrl : URL?
        var playHeaders: [String: String]?
        var playLive = false
        var onPropertyChange: ((MPVMetalViewController, String, Any?) -> Void)?
        var onTap: (() -> Void)?

        func play(_ url: URL) {
            player?.loadFile(url, headers: playHeaders, live: playLive)
        }

        func propertyChange(mpv: OpaquePointer, propertyName: String, data: Any?) {
            guard let player else { return }

            self.onPropertyChange?(player, propertyName, data)
        }
    }
}
