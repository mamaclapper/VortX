import SwiftUI

/// Minimal touch sign-in: email + password into the shared StremioAccount, which seeds the engine
/// (add-ons + library). QR sign-in and Sign in with Apple come in later 0.3.0 iterations.
struct iOSSignInView: View {
    @EnvironmentObject private var account: StremioAccount
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Stremio account") {
                    TextField("Email", text: $email)
                        .textContentType(.username).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password).textContentType(.password)
                }
                if let error {
                    Text(error).font(Theme.Typography.label).foregroundStyle(Theme.Palette.danger)
                }
                Section {
                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack { if busy { ProgressView() }; Text("Sign In") }
                    }
                    .disabled(busy || email.isEmpty || password.isEmpty)
                }
                Section {
                    Text("Signing in pulls your add-ons and library into the app. QR sign-in is coming.")
                        .font(Theme.Typography.label).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        }
    }

    private func signIn() async {
        busy = true; error = nil
        await account.signIn(email: email, password: password)
        busy = false
        if account.isSignedIn {
            account.reloadForActiveProfile()
            dismiss()
        } else {
            error = "Sign in failed. Check your email and password."
        }
    }
}
