import SwiftUI
import AMUXSharedUI
import AMUXCore

struct LoginView: View {
    @Bindable var coordinator: AppOnboardingCoordinator
    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode = .signIn
    @State private var showMagicLink = false
    @State private var magicLinkEmail = ""

    enum Mode { case signIn, signUp }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(mode == .signIn ? "Sign In" : "Create Account")
                        .font(.largeTitle.bold())
                    Text(mode == .signIn ? "Welcome back." : "Start monitoring your agents.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 16)

                // Email + Password
                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("login.emailField")

                    SecureField("Password", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("login.passwordField")
                }

                if let err = coordinator.errorMessage {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(Color.amux.cinnabarDeep)
                }

                // Primary action
                Button {
                    Task {
                        if mode == .signIn {
                            await coordinator.signIn(email: email, password: password)
                        } else {
                            await coordinator.signUp(email: email, password: password)
                        }
                    }
                } label: {
                    HStack {
                        if coordinator.isBusy { ProgressView().progressViewStyle(.circular).tint(.white) }
                        Text(mode == .signIn ? "Sign In" : "Create Account").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .glassProminentButtonStyle()
                .disabled(coordinator.isBusy || email.isEmpty || password.isEmpty)
                .accessibilityIdentifier("login.submitButton")

                // Toggle sign in / sign up
                Button(mode == .signIn ? "Don't have an account? Create one" : "Already have an account? Sign in") {
                    mode = mode == .signIn ? .signUp : .signIn
                    coordinator.errorMessage = nil
                }
                .font(.footnote)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("login.toggleModeButton")

                // Divider
                HStack {
                    Rectangle().frame(height: 1).foregroundStyle(.separator)
                    Text("or").font(.footnote).foregroundStyle(.secondary)
                    Rectangle().frame(height: 1).foregroundStyle(.separator)
                }

                // Social sign-in
                VStack(spacing: 12) {
                    Button {
                        Task { await coordinator.signInWithApple() }
                    } label: {
                        Label("Sign in with Apple", systemImage: "applelogo")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .glassButtonStyle()
                    .disabled(coordinator.isBusy)

                    Button {
                        Task { await coordinator.signInWithGoogle() }
                    } label: {
                        Label("Sign in with Google", systemImage: "globe")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .glassButtonStyle()
                    .disabled(coordinator.isBusy)
                }

                // Magic link section
                if showMagicLink {
                    if let pendingEmail = coordinator.pendingMagicLinkEmail {
                        VStack(spacing: 8) {
                            Image(systemName: "envelope.badge")
                                .font(.largeTitle)
                                .foregroundStyle(.tint)
                            Text("Check your email")
                                .font(.headline)
                            Text("We sent a sign-in link to **\(pendingEmail)**. Tap it to continue.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Email sign-in link")
                                .font(.headline)
                            TextField("Email", text: $magicLinkEmail)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                            Button {
                                Task { await coordinator.sendMagicLink(email: magicLinkEmail) }
                            } label: {
                                HStack {
                                    if coordinator.isBusy { ProgressView().progressViewStyle(.circular).tint(.white) }
                                    Text("Send Link").fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                            .glassProminentButtonStyle()
                            .disabled(coordinator.isBusy || magicLinkEmail.isEmpty)
                        }
                    }
                } else {
                    Button("Email me a sign-in link instead") {
                        showMagicLink = true
                        magicLinkEmail = email
                    }
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}
