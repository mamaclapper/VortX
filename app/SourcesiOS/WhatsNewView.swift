import SwiftUI

/// "What's new" sheet shown once after an app update (see `WhatsNew`). A short, branded highlights list with
/// a single dismiss action. iOS/Mac only (SourcesiOS); tvOS has its own surfaces.
struct WhatsNewView: View {
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("What's new")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("VortX \(WhatsNew.version)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.accent)
                }

                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    ForEach(WhatsNew.highlights, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                            Image(systemName: "sparkle")
                                .font(.footnote)
                                .foregroundStyle(Theme.Palette.accent)
                            Text(line)
                                .font(.body)
                                .foregroundStyle(Theme.Palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Palette.canvas)
        // Pin the dismiss button so it is always visible regardless of scroll position,
        // and let the safe area inset keep it clear of the home indicator.
        .safeAreaInset(edge: .bottom) {
            Button { onDone() } label: {
                Text("Got it").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionStyle())
            .padding(.horizontal, Theme.Space.xl)
            .padding(.top, Theme.Space.sm)
            .padding(.bottom, Theme.Space.md)
            .background(Theme.Palette.canvas)
        }
        .presentationDetents([.large])
    }
}
