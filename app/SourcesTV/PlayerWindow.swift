import SwiftUI
import UIKit

/// Presents a SwiftUI view in a dedicated **key** `UIWindow` above the app's main window.
///
/// On tvOS the focus engine only evaluates the key window, so this gives the player a focus environment
/// the `TabView` / tab bar cannot leak into: the player's catcher becomes the only focusable item in the
/// only focus window, so every remote press falls through to it. This is the canonical tvOS pattern for a
/// full-takeover player and avoids all focus-trap hacks.
@MainActor
final class PlayerWindow {
    static let shared = PlayerWindow()
    private var window: UIWindow?

    private var foregroundScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    func present(_ content: AnyView) {
        guard window == nil, let scene = foregroundScene else { return }
        let w = UIWindow(windowScene: scene)
        w.rootViewController = UIHostingController(rootView: content)
        w.windowLevel = .normal + 1          // sit above the TabView's window
        w.makeKeyAndVisible()
        window = w
    }

    func dismiss() {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        // Hand key status back to the app's main window so the shell regains the remote.
        foregroundScene?.windows.first { $0.windowLevel == .normal }?.makeKeyAndVisible()
    }
}
