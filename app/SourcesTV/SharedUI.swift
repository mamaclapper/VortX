import SwiftUI

/// Shared, system-aligned building blocks: the poster artwork, the focusable poster card used by every
/// rail and grid, and the empty / not-signed-in state. See Theme.swift for the tokens these use.

/// Standard poster width across the app. Posters are 2:3, so height is `width * 1.5`.
let kPosterWidth: CGFloat = 200

/// Poster artwork with a warm placeholder and the system card radius. Not focusable on its own;
/// `PosterCard` wraps it in the focusable button.
struct PosterArt: View {
    let poster: String?
    var width: CGFloat = kPosterWidth
    init(_ poster: String?, width: CGFloat = kPosterWidth) { self.poster = poster; self.width = width }

    var body: some View {
        AsyncImage(url: poster.flatMap { URL(string: $0) }) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .empty:
                Theme.Palette.surface2.overlay(ProgressView().tint(Theme.Palette.textTertiary))
            default:
                Theme.Palette.surface2.overlay(
                    Image(systemName: "film").font(.system(size: 40)).foregroundStyle(Theme.Palette.textTertiary)
                )
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

/// The focusable poster + title used in every rail and grid. Navigates to the detail page; crafted
/// focus (scale + ember glow + lift) comes from `CardFocusStyle`. Optional progress stripe for
/// in-progress titles.
struct PosterCard: View {
    let title: String
    let poster: String?
    let type: String
    let id: String
    var progress: Double? = nil
    var width: CGFloat = kPosterWidth

    var body: some View {
        NavigationLink {
            DetailView(type: type, id: id)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                PosterArt(poster, width: width)
                    .overlay(alignment: .bottom) {
                        if let progress, progress > 0.01 {
                            ProgressStripe(value: progress).padding(Theme.Space.xs)
                        }
                    }
                Text(title)
                    .font(.system(size: 18, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: width, alignment: .leading)
            }
        }
        .buttonStyle(CardFocusStyle())
    }
}

/// A thin resume-progress bar that sits at the bottom of a poster.
struct ProgressStripe: View {
    let value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.55))
                Capsule().fill(Theme.Palette.accent).frame(width: max(6, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 6)
    }
}

/// A centered empty / not-signed-in / error state: an icon, a title, and a short line.
/// Used instead of an endless spinner when there is genuinely nothing to show.
struct CoreEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: systemImage)
                .font(.system(size: 60, weight: .regular))
                .foregroundStyle(Theme.Palette.accent)
            Text(title)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 760)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.screenEdge)
    }

    /// The standard "you are not signed in" state, shown on the main tabs.
    static var signedOut: CoreEmptyState {
        CoreEmptyState(
            systemImage: "person.crop.circle.badge.questionmark",
            title: "Sign in to get started",
            message: "Open the Settings tab and sign in to your Stremio account to load your library, catalogs, and add-ons."
        )
    }
}
