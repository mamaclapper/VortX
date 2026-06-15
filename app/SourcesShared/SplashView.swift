import SwiftUI

/// Animated launch splash: the VortX vortex-X winds in over obsidian, the center
/// dot pops with an ember shockwave ring, the VortX wordmark rises, and a
/// "StremioX is now VortX" line names the handoff so a returning StremioX user
/// is never left wondering what changed. It covers the engine and embedded-server
/// boot moment, and honors Reduce Motion with a static beat instead of movement.
///
/// Colors are the fixed VortX brand palette (gold on obsidian), NOT Theme.Palette:
/// this is the brand moment, so it reads as VortX regardless of the accent the
/// viewer has chosen, and it already matches once the default palette flips.
struct SplashView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowIn = false
    @State private var barsIn = false
    @State private var dotIn = false
    @State private var ringOut = false
    @State private var nameIn = false
    @State private var subIn = false
    @State private var fadingOut = false

    // VortX brand palette (gold / obsidian), fixed for the brand moment.
    private static let canvas = Color(red: 0x0F / 255, green: 0x0D / 255, blue: 0x0A / 255)
    private static let accent = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x06 / 255)
    private static let accentBright = Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255)
    private static let ember = Color(red: 0xC2 / 255, green: 0x44 / 255, blue: 0x0F / 255)
    private static let cream = Color(red: 0xFD / 255, green: 0xF6 / 255, blue: 0xE3 / 255)
    private static let muted = Color(red: 0xC4 / 255, green: 0xA8 / 255, blue: 0x82 / 255)

    var body: some View {
        ZStack {
            Self.canvas.ignoresSafeArea()

            VStack(spacing: 44) {
                mark
                VStack(spacing: 14) {
                    HStack(spacing: 0) {
                        Text("Vort").foregroundStyle(Self.cream)
                        Text("X").foregroundStyle(Self.accentBright)
                    }
                    .font(.system(size: 64, weight: .heavy))
                    .opacity(nameIn ? 1 : 0)
                    .offset(y: nameIn || reduceMotion ? 0 : 16)

                    Text("StremioX is now VortX")
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Self.muted)
                        .opacity(subIn ? 1 : 0)
                }
            }
        }
        .opacity(fadingOut ? 0 : 1)
        .onAppear(perform: run)
    }

    private var mark: some View {
        ZStack {
            // Ember glow behind the mark, scales+fades in.
            RadialGradient(
                colors: [Self.ember.opacity(0.55), Self.ember.opacity(0)],
                center: .center, startRadius: 4, endRadius: 150
            )
            .frame(width: 320, height: 320)
            .scaleEffect(glowIn ? 1 : 0.6)
            .opacity(glowIn ? 1 : 0)

            // Single vortex shockwave ring that expands once and fades.
            Circle()
                .stroke(Self.accent.opacity(0.7), lineWidth: 3)
                .frame(width: 150, height: 150)
                .scaleEffect(ringOut ? 1.7 : 0.4)
                .opacity(ringOut ? 0 : 0.7)

            // The X: two crossed ribbons (kept from the StremioX mark, now gold).
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Self.accent)
                .frame(width: 250, height: 56)
                .rotationEffect(.degrees(45))
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Self.accentBright)
                .frame(width: 250, height: 56)
                .rotationEffect(.degrees(-45))
            Circle()
                .fill(Self.cream)
                .frame(width: 34, height: 34)
                .scaleEffect(dotIn ? 1 : 0.01)
        }
        .frame(width: 220, height: 220)
        .scaleEffect(barsIn ? 1 : (reduceMotion ? 1 : 0.4))
        .opacity(barsIn ? 1 : 0)
        // Wind-up spin: a near-full rotation into place reads as a vortex forming.
        .rotationEffect(.degrees(barsIn || reduceMotion ? 0 : -300))
    }

    private func run() {
        if reduceMotion {
            glowIn = true; barsIn = true; dotIn = true; ringOut = true; nameIn = true; subIn = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { finish() }
            return
        }
        withAnimation(.easeOut(duration: 0.5)) { glowIn = true }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) { barsIn = true }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.55).delay(0.4)) { dotIn = true }
        withAnimation(.easeOut(duration: 0.7).delay(0.45)) { ringOut = true }
        withAnimation(.easeOut(duration: 0.45).delay(0.7)) { nameIn = true }
        withAnimation(.easeOut(duration: 0.4).delay(1.15)) { subIn = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { finish() }
    }

    private func finish() {
        withAnimation(.easeIn(duration: 0.35)) { fadingOut = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.37) { onFinished() }
    }
}
