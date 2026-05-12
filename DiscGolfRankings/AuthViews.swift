import SwiftUI

// MARK: - SignInView

struct SignInView: View {
    @EnvironmentObject var auth: AuthService
    @State private var email = ""
    @State private var password = ""
    @State private var showSignUp = false
    @State private var showForgotPassword = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "figure.disc.sports")
                    .font(.system(size: 72))
                    .foregroundStyle(.green)

                Text("DiscGolf Rankings")
                    .font(.largeTitle.bold())

                Text("Tag Match System")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)

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
                                ProgressView()
                            } else {
                                Text("Sign In")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(email.isEmpty || password.isEmpty || auth.isLoading)
                }
                .padding(.horizontal)

                HStack(spacing: 4) {
                    Button("Forgot password?") { showForgotPassword = true }
                        .font(.footnote)
                    Spacer()
                    Button("Create account") { showSignUp = true }
                        .font(.footnote)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .navigationBarHidden(true)
            .sheet(isPresented: $showSignUp) { SignUpView() }
            .sheet(isPresented: $showForgotPassword) { ForgotPasswordView() }
        }
    }
}

// MARK: - SignUpView

struct SignUpView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) var dismiss
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    private var passwordsMatch: Bool { password == confirmPassword }
    private var canSubmit: Bool {
        !displayName.isEmpty && !email.isEmpty && password.count >= 6 && passwordsMatch && !auth.isLoading
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Display Name", text: $displayName)
                        .textContentType(.name)
                }

                Section("Credentials") {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                    SecureField("Password (6+ characters)", text: $password)
                        .textContentType(.newPassword)
                    SecureField("Confirm Password", text: $confirmPassword)
                        .textContentType(.newPassword)
                }

                if let error = auth.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }

                Section {
                    Button("Create Account") {
                        Task {
                            await auth.signUp(email: email, password: password, displayName: displayName)
                            if auth.errorMessage == nil { dismiss() }
                        }
                    }
                    .disabled(!canSubmit)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Create Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if auth.isLoading { ProgressView() }
            }
        }
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
            Form {
                Section(footer: Text("We'll send a reset link to your email address.")) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                }

                if sent {
                    Section {
                        Label("Reset email sent!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Section {
                    Button("Send Reset Link") {
                        Task {
                            await auth.resetPassword(email: email)
                            sent = auth.errorMessage == nil
                        }
                    }
                    .disabled(email.isEmpty || auth.isLoading)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
