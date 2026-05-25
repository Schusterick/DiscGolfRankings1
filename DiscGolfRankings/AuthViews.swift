import SwiftUI
import AuthenticationServices

// MARK: - SignInView

struct SignInView: View {
    @EnvironmentObject var auth: AuthService
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var showSignUp = false
    @State private var showForgotPassword = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.homeGradient.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    Image(systemName: "figure.disc.sports")
                        .font(.system(size: 80))
                        .foregroundStyle(Theme.accent)
                        .shadow(color: Theme.accent.opacity(0.4), radius: 20)

                    VStack(spacing: 8) {
                        Text("DiscGolfRankings")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Own Your Rank")
                            .font(.title3.bold())
                            .foregroundStyle(Theme.gold)
                    }

                    Spacer()

                    VStack(spacing: 14) {
                        // Email field
                        HStack(spacing: 10) {
                            Image(systemName: "envelope").foregroundStyle(Theme.textSecondary)
                            TextField("Email", text: $email)
                                .foregroundStyle(Theme.textPrimary)
                                .textContentType(.emailAddress)
                                .autocapitalization(.none)
                                .keyboardType(.emailAddress)
                        }
                        .padding(14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.divider, lineWidth: 1))

                        // Password field — with show/hide toggle
                        HStack(spacing: 10) {
                            Image(systemName: "lock").foregroundStyle(Theme.textSecondary)
                            Group {
                                if showPassword {
                                    TextField("Password", text: $password)
                                        .textContentType(.password)
                                } else {
                                    SecureField("Password", text: $password)
                                        .textContentType(.password)
                                }
                            }
                            .foregroundStyle(Theme.textPrimary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                            Button { showPassword.toggle() } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                        }
                        .padding(14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.divider, lineWidth: 1))

                        if let error = auth.errorMessage {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            Task { await auth.signIn(email: email, password: password) }
                        } label: {
                            Group {
                                if auth.isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Sign In")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(email.isEmpty || password.isEmpty || auth.isLoading)

                        // — OR — divider
                        HStack(spacing: 10) {
                            Rectangle().fill(Theme.divider).frame(height: 1)
                            Text("OR").font(.caption).foregroundStyle(Theme.textSecondary)
                            Rectangle().fill(Theme.divider).frame(height: 1)
                        }
                        .padding(.vertical, 4)

                        // Sign in with Apple
                        SignInWithAppleButton(.signIn,
                            onRequest: { auth.makeAppleSignInRequest($0) },
                            onCompletion: { result in
                                Task { await auth.handleAppleSignInResult(result) }
                            }
                        )
                        .signInWithAppleButtonStyle(.white)   // matches the dark-on-light card look on top of our dark gradient
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal)

                    HStack {
                        Button("Forgot password?") { showForgotPassword = true }
                            .font(.footnote)
                            .foregroundStyle(Theme.accent)
                        Spacer()
                        Button("Create account") { showSignUp = true }
                            .font(.footnote)
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal)

                    Spacer()
                }
                .padding()
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showSignUp) {
                SignUpView().environmentObject(auth)
            }
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordView().environmentObject(auth)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - SignUpView

struct SignUpView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) var dismiss
    @State private var firstName = ""
    @State private var lastName  = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false

    private var passwordsMatch: Bool { password == confirmPassword }
    private var canSubmit: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !email.isEmpty && password.count >= 6 && passwordsMatch && !auth.isLoading
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                Form {
                    Section("Your Name") {
                        TextField("First Name", text: $firstName)
                            .foregroundStyle(Theme.textPrimary)
                            .textContentType(.givenName)
                            .autocorrectionDisabled()
                        TextField("Last Name", text: $lastName)
                            .foregroundStyle(Theme.textPrimary)
                            .textContentType(.familyName)
                            .autocorrectionDisabled()
                    }
                    .listRowBackground(Theme.card)

                    Section("Credentials") {
                        TextField("Email", text: $email)
                            .foregroundStyle(Theme.textPrimary)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                        HStack {
                            Group {
                                if showPassword {
                                    TextField("Password (6+ characters)", text: $password)
                                } else {
                                    SecureField("Password (6+ characters)", text: $password)
                                }
                            }
                            .foregroundStyle(Theme.textPrimary)
                            .textContentType(.newPassword)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            Button { showPassword.toggle() } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                        }
                        HStack {
                            Group {
                                if showConfirmPassword {
                                    TextField("Confirm Password", text: $confirmPassword)
                                } else {
                                    SecureField("Confirm Password", text: $confirmPassword)
                                }
                            }
                            .foregroundStyle(Theme.textPrimary)
                            .textContentType(.newPassword)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            Button { showConfirmPassword.toggle() } label: {
                                Image(systemName: showConfirmPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .accessibilityLabel(showConfirmPassword ? "Hide password" : "Show password")
                        }
                    }
                    .listRowBackground(Theme.card)

                    // Heads-up notice before they finish signing up
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(Theme.gold)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Heads up")
                                    .font(.caption.bold())
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Once you join a club, the club admin may contact you about leagues, tournaments, and other events. Your email is only visible to club admins of clubs you join — never to other players.")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(Theme.card)

                    if !passwordsMatch && !confirmPassword.isEmpty {
                        Section {
                            Text("Passwords do not match").foregroundStyle(.red).font(.caption)
                        }
                        .listRowBackground(Theme.card)
                    }

                    if let error = auth.errorMessage {
                        Section {
                            Text(error).foregroundStyle(.red).font(.caption)
                        }
                        .listRowBackground(Theme.card)
                    }

                    Section {
                        Button {
                            Task {
                                let fullName = "\(firstName.trimmingCharacters(in: .whitespaces)) \(lastName.trimmingCharacters(in: .whitespaces))"
                                await auth.signUp(email: email, password: password, displayName: fullName)
                                if auth.errorMessage == nil { dismiss() }
                            }
                        } label: {
                            Group {
                                if auth.isLoading { ProgressView().tint(.white) }
                                else { Text("Create Account").fontWeight(.semibold).foregroundStyle(.white) }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .disabled(!canSubmit)
                    }
                    .listRowBackground(Theme.accent.opacity(canSubmit ? 0.85 : 0.4))
                }
                .darkListStyle()
            }
            .navigationTitle("Create Account")
            .navigationBarTitleDisplayMode(.inline)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - ForgotPasswordView

struct ForgotPasswordView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var sent = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                Form {
                    Section(footer: Text("We'll send a reset link to your email address.")
                                .foregroundStyle(Theme.textSecondary)) {
                        TextField("Email", text: $email)
                            .foregroundStyle(Theme.textPrimary)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                    }
                    .listRowBackground(Theme.card)

                    if sent {
                        Section {
                            Label("Reset email sent!", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Theme.success)
                        }
                        .listRowBackground(Theme.card)
                    }

                    if let error = auth.errorMessage {
                        Section {
                            Text(error).foregroundStyle(.red).font(.caption)
                        }
                        .listRowBackground(Theme.card)
                    }

                    Section {
                        Button {
                            Task {
                                await auth.resetPassword(email: email)
                                sent = auth.errorMessage == nil
                            }
                        } label: {
                            Group {
                                if auth.isLoading { ProgressView().tint(.white) }
                                else { Text("Send Reset Link").fontWeight(.semibold).foregroundStyle(.white) }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .disabled(email.isEmpty || auth.isLoading)
                    }
                    .listRowBackground(Theme.accent.opacity(email.isEmpty ? 0.4 : 0.85))
                }
                .darkListStyle()
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
