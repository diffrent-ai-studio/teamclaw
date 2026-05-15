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
            VStack(alignment: .leading, spacing: 24) {
                header

                credentialFields

                if let err = coordinator.errorMessage {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(Color.amux.cinnabarDeep)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                primaryButton

                toggleModeButton

                divider

                socialButtons

                magicLinkSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 72)
            .padding(.bottom, 36)
        }
        .background(Color.amux.mist)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(mode == .signIn ? "Sign in" : "Create account")
                .font(.amuxSerif(38, weight: .regular))
                .foregroundStyle(Color.amux.onyx)
            Text(mode == .signIn
                 ? "Return to your Teamclaw workspace."
                 : "Create a workspace for your AI digital employees.")
                .font(.body)
                .foregroundStyle(Color.amux.basalt)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var credentialFields: some View {
        VStack(spacing: 10) {
            authField {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("login.emailField")
            }

            authField {
                SecureField("Password", text: $password)
                    .textContentType(mode == .signIn ? .password : .newPassword)
                    .accessibilityIdentifier("login.passwordField")
            }
        }
    }

    private var primaryButton: some View {
        Button {
            Task {
                if mode == .signIn {
                    await coordinator.signIn(email: email, password: password)
                } else {
                    await coordinator.signUp(email: email, password: password)
                }
            }
        } label: {
            HStack(spacing: 8) {
                if coordinator.isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(hasCredentials ? Color.white : Color.amux.slate)
                }
                Text(mode == .signIn ? "Sign in" : "Create account")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(hasCredentials ? Color.white : Color.amux.slate)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(hasCredentials ? Color.amux.cinnabar : Color.amux.pebble.opacity(0.82))
                    .shadow(color: hasCredentials ? Color.amux.onyx.opacity(0.10) : .clear,
                            radius: 18,
                            x: 0,
                            y: 10)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .accessibilityIdentifier("login.submitButton")
    }

    private var toggleModeButton: some View {
        Button {
            mode = mode == .signIn ? .signUp : .signIn
            coordinator.errorMessage = nil
        } label: {
            Text(mode == .signIn
                 ? "New to Teamclaw? Create an account"
                 : "Already have a workspace? Sign in")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.amux.cinnabarDeep)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("login.toggleModeButton")
    }

    private var divider: some View {
        HStack(spacing: 14) {
            Rectangle().fill(Color.amux.hairline).frame(height: 0.5)
            Text("or")
                .font(.footnote)
                .foregroundStyle(Color.amux.slate)
            Rectangle().fill(Color.amux.hairline).frame(height: 0.5)
        }
    }

    private var socialButtons: some View {
        VStack(spacing: 10) {
            socialButton(title: "Sign in with Apple", icon: "applelogo") {
                Task { await coordinator.signInWithApple() }
            }

            socialButton(title: "Sign in with Google", icon: "globe") {
                Task { await coordinator.signInWithGoogle() }
            }
        }
    }

    @ViewBuilder
    private var magicLinkSection: some View {
        if showMagicLink {
            if let pendingEmail = coordinator.pendingMagicLinkEmail {
                VStack(spacing: 10) {
                    Image(systemName: "envelope.badge")
                        .font(.title2)
                        .foregroundStyle(Color.amux.cinnabar)
                    Text("Check your email")
                        .font(.headline)
                        .foregroundStyle(Color.amux.onyx)
                    Text("We sent a sign-in link to **\(pendingEmail)**. Tap it to continue.")
                        .font(.footnote)
                        .foregroundStyle(Color.amux.basalt)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.amux.paper)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.amux.hairline, lineWidth: 1)
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Email sign-in link")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.amux.onyx)
                    authField {
                        TextField("Email", text: $magicLinkEmail)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    Button {
                        Task { await coordinator.sendMagicLink(email: magicLinkEmail) }
                    } label: {
                        HStack(spacing: 8) {
                            if coordinator.isBusy {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(hasMagicLinkEmail ? Color.white : Color.amux.slate)
                            }
                            Text("Send link")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(hasMagicLinkEmail ? Color.white : Color.amux.slate)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(hasMagicLinkEmail ? Color.amux.cinnabar : Color.amux.pebble.opacity(0.82))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSendMagicLink)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.amux.paper)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.amux.hairline, lineWidth: 1)
                )
            }
        } else {
            Button("Email me a sign-in link") {
                showMagicLink = true
                magicLinkEmail = email
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.amux.basalt)
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
        }
    }

    private var canSubmit: Bool {
        !coordinator.isBusy && hasCredentials
    }

    private var canSendMagicLink: Bool {
        !coordinator.isBusy && hasMagicLinkEmail
    }

    private var hasCredentials: Bool {
        !email.isEmpty && !password.isEmpty
    }

    private var hasMagicLinkEmail: Bool {
        !magicLinkEmail.isEmpty
    }

    private func authField<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.body)
            .foregroundStyle(Color.amux.onyx)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.amux.paper)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.amux.hairline, lineWidth: 1)
            )
    }

    private func socialButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 24)
                Text(title)
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(Color.amux.onyx)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.amux.paper.opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.amux.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(coordinator.isBusy)
    }
}
