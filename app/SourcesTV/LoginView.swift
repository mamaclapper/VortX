import SwiftUI
import Combine

/// tvOS sign-in for a Stremio account. Pulls the user's addons (AIOStreams etc.) so their
/// real streams play. The token and addon URLs stay on-device.
struct LoginView: View {
    @ObservedObject var account: StremioAccount
    @EnvironmentObject private var core: CoreBridge
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false

    var body: some View {
        ZStack {
            Theme.Palette.canvas.ignoresSafeArea()
            VStack(spacing: Theme.Space.lg) {
                HStack(spacing: 0) {
                    Text("Stremio").foregroundStyle(Theme.Palette.textPrimary)
                    Text("X").foregroundStyle(Theme.Palette.accent)
                }
                .font(Theme.Typography.hero)

                Text("Sign in to your Stremio account to load your addons and streams.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)

                VStack(spacing: Theme.Space.md) {
                    field { TextField("Email", text: $email)
                        .textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled() }
                    field { SecureField("Password", text: $password).textContentType(.password) }
                }
                .frame(width: 700)

                if let err = account.signInError {
                    Text(err).font(Theme.Typography.label).foregroundStyle(Theme.Palette.danger)
                }

                Button {
                    busy = true
                    Task { await account.signIn(email: email, password: password); busy = false }
                } label: {
                    Text(busy ? "Signing in…" : "Sign In").frame(width: 280)
                }
                .buttonStyle(PrimaryActionStyle())
                .disabled(busy || email.isEmpty || password.isEmpty)
            }
            .padding(Theme.Space.screenEdge)
        }
        // Login is pushed via NavigationLink; pop back the moment the token is saved, otherwise a
        // successful sign-in leaves the user staring at this same screen.
        .onReceive(account.$isSignedIn) { signedIn in
            if signedIn {
                core.signedInWithLegacyAuthKey()   // seed the engine now, not on next launch
                dismiss()
            }
        }
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.sm)
            .background(Theme.Palette.surface1, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }
}
